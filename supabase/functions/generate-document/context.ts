/**
 * Κατασκευή του «περιβάλλοντος εγγράφου»: όλα τα δεδομένα που μπορεί να
 * χρησιμοποιήσει ένα πρότυπο, διαβασμένα ΜΕ ΤΑ ΔΙΚΑΙΩΜΑΤΑ ΤΟΥ ΧΡΗΣΤΗ
 * (ο πελάτης φέρει το JWT του καλούντος, άρα ισχύουν τα RLS policies).
 *
 * Δεν εκτελείται ποτέ αυθαίρετο SQL από τα πρότυπα: το source_path είναι
 * απλή διαδρομή μέσα σε αυτό το αντικείμενο.
 */
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2'
import { addDays, addMonths, formatValue } from './format.ts'

export interface BuildOptions {
  projectId: string
  docCode: string
  entityId?: string | null
}

/** Ποια οντότητα συνοδεύει κάθε τύπο εγγράφου. */
export const ENTITY_BY_DOC: Record<string, string> = {
  PPAE: 'hidden_work_notices',
  ANAL_EPIMETRISI: 'measurements',
  TELIKH_EPIMETRISI: 'measurements',
  PRAXH_MEIWSHS_EGG: 'guarantees',
  PRAXH_APODESMEVSHS: 'guarantees',
  LOGARIASMOS: 'payment_certificates',
  TELIKOS_LOGARIASMOS: 'payment_certificates',
  APE: 'ape',
  BEBAIOSI_PERATOSIS: 'completions',
  EKTHESI_PERAIWSHS: 'completions',
  EGKRISI_XRONOD: 'schedules',
  XRONODIAGRAMMA: 'schedules',
}

export async function buildContext(sb: SupabaseClient, opts: BuildOptions) {
  const { projectId, docCode, entityId } = opts

  const { data: project, error: pErr } = await sb
    .from('projects')
    .select('*, organizations(*)')
    .eq('id', projectId)
    .single()
  if (pErr || !project) {
    throw new Error(`Το έργο δεν βρέθηκε ή δεν έχετε πρόσβαση: ${pErr?.message ?? projectId}`)
  }

  const { data: contract } = await sb
    .from('contracts')
    .select('*, contractors(*)')
    .eq('project_id', projectId)
    .maybeSingle()

  const { data: assignments } = await sb
    .from('project_assignments')
    .select('role, decision_no, decision_ada, decision_date, profiles(full_name, specialty, email)')
    .eq('project_id', projectId)
    .is('valid_to', null)

  const pick = (role: string) =>
    (assignments ?? []).find(a => a.role === role)?.profiles as
      | { full_name: string; specialty: string | null; email: string }
      | undefined

  const { data: financials } = await sb
    .from('v_project_financials').select('*').eq('project_id', projectId).maybeSingle()

  const ctx: Record<string, unknown> = {
    // Φορέας
    organizations: project.organizations ?? {},
    foreas: project.organizations ?? {},
    // Έργο
    projects: project,
    ergo: {
      titlos: project.title,
      kodikos: project.code,
      thesi: project.location,
      xrimatodotisi: project.funding_source,
      proypologismos_meletis: project.study_budget_net,
    },
    // Σύμβαση & ανάδοχος
    contracts: contract ?? {},
    contractors: contract?.contractors ?? {},
    symvasi: contract
      ? {
          arithmos: contract.contract_no,
          imerominia_ypografis: contract.signed_at,
          aksia: contract.initial_value_net,
          ekptosi: contract.discount_pct,
          apravlepta: contract.contingency_amount,
          prothesmia_imeres: contract.total_duration_days,
          lixi_prothesmias: contract.current_end_date,
          mines_syntirisis: contract.maintenance_months,
        }
      : {},
    anadoxos: contract?.contractors
      ? {
          epwnymia: (contract.contractors as { name: string }).name,
          afm: (contract.contractors as { afm: string }).afm,
          ekprosopos: (contract.contractors as { legal_rep_name: string | null }).legal_rep_name,
          dieuthynsi: (contract.contractors as { address: string | null }).address,
        }
      : {},
    // Πρόσωπα
    supervisor: pick('epivlepon') ?? {},
    epivlepon: pick('epivlepon') ?? {},
    head: pick('proistamenos_dy') ?? {},
    proistamenos: pick('proistamenos_dy') ?? {},
    // Οικονομικά
    v_project_financials: financials ?? {},
    oikonomika: financials ?? {},
  }

  // ---- Οντότητα του εγγράφου -------------------------------------
  const table = ENTITY_BY_DOC[docCode]
  if (table) {
    let row: Record<string, unknown> | null = null

    if (entityId) {
      const { data } = await sb.from(table).select('*').eq('id', entityId).maybeSingle()
      row = data
    } else if (table === 'completions') {
      const { data } = await sb.from(table).select('*').eq('project_id', projectId).maybeSingle()
      row = data
    } else if (table === 'schedules') {
      const { data } = await sb.from(table).select('*').eq('project_id', projectId)
        .order('version_no', { ascending: false }).limit(1)
      row = data?.[0] ?? null
    }

    if (row) {
      ctx[table] = row
      ctx.entity = row
      ctx.entity_type = table

      if (table === 'hidden_work_notices') {
        ctx.afaneis = {
          aa: row.serial_no,
          perigrafi: row.work_description,
          thesi: row.location,
          imerominia_prosklisis: row.invitation_sent_at,
          prothesmia_elegxou: row.inspection_due,
          imerominia_elegxou: row.inspected_at,
          imerominia_elegxou_pliris: formatValue(row.inspected_at, 'date_long'),
          plithos_fotografion: row.photos_count,
        }
      }

      if (table === 'measurements') {
        const { data: lines } = await sb
          .from('measurement_lines')
          .select('quantity_period, quantity_cumul, unit_price, amount_cumul, budget_items(line_no, item_code, description, unit)')
          .eq('measurement_id', row.id)
        ctx.grammes = (lines ?? []).map((l, i) => {
          const bi = l.budget_items as
            | { line_no: number; item_code: string; description: string; unit: string }
            | null
          return {
            aa: bi?.line_no ?? i + 1,
            arthro: bi?.item_code ?? '—',
            perigrafi: bi?.description ?? '—',
            monada: bi?.unit ?? '',
            timi: formatValue(l.unit_price, 'currency'),
            posotita: formatValue(l.quantity_cumul, 'quantity'),
            dapani: formatValue(l.amount_cumul, 'currency'),
          }
        })
        ctx.epimetrisi = {
          aa: row.serial_no,
          periodos:
            row.period_from && row.period_to
              ? `${formatValue(row.period_from, 'date')} – ${formatValue(row.period_to, 'date')}`
              : '—',
          tmima: row.work_section,
          imerominia_ypovolis: row.submitted_at,
          synolo_symvatikwn: row.contractual_amount,
          synolo_ektos: row.extra_amount,
          geniko_synolo: row.total_amount,
        }
      }

      if (table === 'guarantees') {
        const before = Number(row.current_amount ?? 0)
        ctx.eggyisi = {
          arithmos: row.guarantee_no,
          ekdotis: row.issuer,
          arxiko_poso: before,
          poso_meiosis: Math.round(before * 0.7 * 100) / 100,
          ypoloipo: Math.round(before * 0.3 * 100) / 100,
        }
        const { data: fm } = await sb.from('final_measurement').select('*')
          .eq('project_id', projectId).maybeSingle()
        ctx.final_measurement = fm ?? {}
        ctx.teliki = { imerominia_egkrisis: fm?.approved_at ?? null }
      }

      if (table === 'completions') {
        const issued = (row.certificate_issued_at as string | null) ?? null
        ctx.peraiosi = {
          egkekrimenos_xronos: row.approved_completion_date,
          ekthesi_epivleponta: row.supervisor_report_at,
          pragmatiki_imerominia: row.actual_completion_date ?? row.approved_completion_date,
          enarksi_syntirisis: issued ? addDays(issued, 1) : null,
          lixi_syntirisis:
            issued && contract
              ? addMonths(addDays(issued, 1), Number(contract.maintenance_months ?? 15))
              : null,
        }
      }

      if (table === 'schedules') {
        ctx.xronodiagramma = {
          imerominia_ypovolis: row.submitted_at,
          imerominia_egkrisis: row.approved_at,
          methodos: row.method === 'diktyoti_analysi' ? 'δικτυωτή ανάλυση' : 'γραμμικό διάγραμμα',
        }
      }

      if (table === 'ape') {
        const { data: lines } = await sb.from('ape_lines').select('*').eq('ape_id', row.id)
        ctx.ape_grammes = (lines ?? []).map(l => ({
          arthro: l.item_code,
          perigrafi: l.description,
          monada: l.unit,
          timi: formatValue(l.unit_price, 'currency'),
          pos_arxiki: formatValue(l.qty_initial, 'quantity'),
          pos_nea: formatValue(l.qty_new, 'quantity'),
          dap_arxiki: formatValue(l.amount_initial, 'currency'),
          dap_nea: formatValue(l.amount_new, 'currency'),
          metavoli: formatValue(l.delta_amount, 'currency'),
        }))
      }

      if (table === 'payment_certificates') {
        const { data: lines } = await sb.from('payment_certificate_lines').select('*')
          .eq('certificate_id', row.id)
        ctx.logariasmos_grammes = (lines ?? []).map(l => ({
          arthro: l.item_code,
          perigrafi: l.description,
          monada: l.unit,
          timi: formatValue(l.unit_price, 'currency'),
          posotita: formatValue(l.qty_cumulative, 'quantity'),
          dapani: formatValue(l.amount_cumulative, 'currency'),
        }))
      }
    }
  }

  // ---- Υπολογιζόμενες τιμές --------------------------------------
  const issued = (ctx.completions as { certificate_issued_at?: string } | undefined)?.certificate_issued_at
  ctx.computed = {
    maintenance_start: issued ? addDays(issued, 1) : null,
    inspection_date_long: formatValue(
      (ctx.hidden_work_notices as { inspected_at?: string } | undefined)?.inspected_at,
      'date_long',
    ),
    guarantee_reduction: (ctx.eggyisi as { poso_meiosis?: number } | undefined)?.poso_meiosis ?? null,
    guarantee_remaining: (ctx.eggyisi as { ypoloipo?: number } | undefined)?.ypoloipo ?? null,
    measurement_period: (ctx.epimetrisi as { periodos?: string } | undefined)?.periodos ?? null,
  }
  ctx.measurement_lines = ctx.grammes ?? []

  return ctx
}

/** Ανάγνωση τιμής με διαδρομή τελείας, π.χ. "contracts.signed_at". */
export function resolvePath(ctx: unknown, path: string): unknown {
  return path.split('.').reduce<unknown>((acc, key) => {
    if (acc === null || acc === undefined) return undefined
    return (acc as Record<string, unknown>)[key]
  }, ctx)
}
