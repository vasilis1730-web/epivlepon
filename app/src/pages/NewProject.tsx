/**
 * Έναρξη επίβλεψης νέου έργου.
 *
 * Η οθόνη αυτή είναι το σημείο εισόδου του οδηγού: μία φόρμα που
 * καταχωρίζει τη σύμβαση όπως υπογράφηκε και, με βάση αυτήν, στήνει
 * ολόκληρη τη ροή των σταδίων με τις προθεσμίες τους. Ό,τι συμπληρώνεται
 * εδώ καθορίζει τα εμπόδια που θα εμφανιστούν αργότερα — γι' αυτό κάθε
 * πεδίο φέρει τη διάταξη από την οποία απορρέει.
 */
import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import * as api from '@/lib/api'
import { useQuery } from '@/hooks/useQuery'
import { useToast } from '@/hooks/useToast'
import {
  Badge, Button, Card, CardHeader, Field, Input, LegalRef, Select, Spinner, Textarea,
} from '@/components/ui'
import { CATEGORY, ROLE } from '@/lib/labels'
import { cx, date, eur, pct } from '@/lib/format'
import { derive, emptyInput, validate, type NewProjectInput } from '@/lib/newProject'
import type { ProjectCategory } from '@/lib/types'

export default function NewProject() {
  const nav = useNavigate()
  const { push } = useToast()
  const { data: me, loading: loadingMe } = useQuery(() => api.getProfile().catch(() => null), [])
  const { data: people } = useQuery(() => api.getOrgPeople().catch(() => []), [])
  const { data: contractors } = useQuery(() => api.getContractors().catch(() => []), [])

  const [v, setV] = useState<NewProjectInput>(emptyInput)
  const [busy, setBusy] = useState(false)
  const [errors, setErrors] = useState<string[]>([])

  const d = useMemo(() => derive(v.contract), [v.contract])

  // Επιμέρους ενημερωτές — κρατούν τον τύπο, ώστε τα λάθη να πιάνονται στη μεταγλώττιση.
  const setP = <K extends keyof NewProjectInput['project']>(k: K, val: NewProjectInput['project'][K]) =>
    setV(s => ({ ...s, project: { ...s.project, [k]: val } }))
  const setC = <K extends keyof NewProjectInput['contract']>(k: K, val: NewProjectInput['contract'][K]) =>
    setV(s => ({ ...s, contract: { ...s.contract, [k]: val } }))
  const setA = <K extends keyof NewProjectInput['assignments']>(k: K, val: NewProjectInput['assignments'][K]) =>
    setV(s => ({ ...s, assignments: { ...s.assignments, [k]: val } }))
  const setK = <K extends keyof NewProjectInput['contractor']>(k: K, val: NewProjectInput['contractor'][K]) =>
    setV(s => ({ ...s, contractor: { ...s.contractor, [k]: val } }))
  const setG = <K extends keyof NewProjectInput['guarantee']>(k: K, val: NewProjectInput['guarantee'][K]) =>
    setV(s => ({ ...s, guarantee: { ...s.guarantee, [k]: val } }))

  if (loadingMe) return <Spinner />

  if (!api.canCreateProject(me)) return <NotPermitted roles={me?.roles ?? []} />

  async function submit() {
    const errs = validate(v)
    setErrors(errs)
    if (errs.length) {
      window.scrollTo({ top: 0, behavior: 'smooth' })
      return
    }
    setBusy(true)
    try {
      const res = await api.createProject(v)
      push('success', `Το έργο ${res.code} καταχωρίστηκε.`,
        `Δημιουργήθηκαν ${res.stagesCreated} στάδια του οδηγού με τις προθεσμίες τους.`)
      nav(`/erga/${res.projectId}/odigos`)
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e)
      setErrors([msg])
      push('error', 'Η καταχώριση δεν ολοκληρώθηκε.', msg)
      window.scrollTo({ top: 0, behavior: 'smooth' })
    } finally {
      setBusy(false)
    }
  }

  const engineers = people ?? []
  const helpers = engineers.filter(p => p.id !== v.assignments.epivlepon)

  return (
    <div className="space-y-6">
      <header>
        <div className="label-xs">Έναρξη επίβλεψης</div>
        <h1 className="mt-1 font-serif text-3xl font-bold tracking-tight">Νέο έργο</h1>
        <p className="mt-2 max-w-3xl text-sm text-ink2">
          Καταχωρίστε τη σύμβαση όπως υπογράφηκε. Από τα στοιχεία αυτά παράγονται
          αυτόματα τα στάδια του οδηγού, οι προθεσμίες τους και οι έλεγχοι που θα
          εμποδίσουν τη μετάβαση σε επόμενο στάδιο όσο εκκρεμούν υποχρεώσεις.
        </p>
      </header>

      {errors.length > 0 && (
        <div className="rounded border border-oxide bg-oxide-soft px-4 py-3">
          <p className="text-sm font-semibold text-oxide">
            {errors.length === 1 ? 'Η φόρμα δεν μπορεί να υποβληθεί:' : `${errors.length} σημεία χρειάζονται διόρθωση:`}
          </p>
          <ul className="mt-1.5 list-disc space-y-1 pl-5 text-sm text-ink">
            {errors.map((e, i) => <li key={i}>{e}</li>)}
          </ul>
        </div>
      )}

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_22rem]">
        <div className="min-w-0 space-y-5">

          {/* ---------------------------------------------------------- */}
          <Card>
            <CardHeader title="1. Το έργο" subtitle="Ταυτότητα και χρηματοδότηση" />
            <div className="grid gap-4 px-4 py-4 sm:grid-cols-2">
              <Field label="Κωδικός έργου" hint="Μοναδικός στον φορέα σας — π.χ. ΕΡΓ-2026-004">
                <Input value={v.project.code} onChange={e => setP('code', e.target.value)}
                  placeholder="ΕΡΓ-2026-004" />
              </Field>
              <Field label="Κατηγορία">
                <Select value={v.project.category}
                  onChange={e => setP('category', e.target.value as ProjectCategory)}>
                  {Object.entries(CATEGORY).map(([k, label]) => (
                    <option key={k} value={k}>{label}</option>
                  ))}
                </Select>
              </Field>
              <div className="sm:col-span-2">
                <Field label="Τίτλος έργου">
                  <Textarea value={v.project.title} onChange={e => setP('title', e.target.value)}
                    className="min-h-[60px]"
                    placeholder="Ασφαλτοστρώσεις οδών Δ.Ε. …" />
                </Field>
              </div>
              <Field label="Τόπος εκτέλεσης">
                <Input value={v.project.location} onChange={e => setP('location', e.target.value)} />
              </Field>
              <Field label="Πηγή χρηματοδότησης">
                <Input value={v.project.funding_source}
                  onChange={e => setP('funding_source', e.target.value)}
                  placeholder="ΣΑΤΑ / ΠΔΕ / Πρόγραμμα…" />
              </Field>
              <Field label="Κ.Α. προϋπολογισμού">
                <Input value={v.project.ka_budget_code}
                  onChange={e => setP('ka_budget_code', e.target.value)} />
              </Field>
              <Field label="Κωδικός CPV">
                <Input value={v.project.cpv} onChange={e => setP('cpv', e.target.value)} />
              </Field>
              <Field label="ΑΔΑΜ διακήρυξης" legalRef="N4727/2020">
                <Input value={v.project.adam_tender} onChange={e => setP('adam_tender', e.target.value)} />
              </Field>
              <Field label="ΑΔΑ απόφασης κατακύρωσης" legalRef="N4727/2020">
                <Input value={v.project.award_decision_ada}
                  onChange={e => setP('award_decision_ada', e.target.value)} />
              </Field>
            </div>
          </Card>

          {/* ---------------------------------------------------------- */}
          <Card>
            <CardHeader
              title="2. Ο ανάδοχος"
              subtitle="Το ηλεκτρονικό ταχυδρομείο χρησιμοποιείται για τις κοινοποιήσεις"
              legalRef="N4412/138"
            />
            <div className="px-4 py-4">
              {(contractors?.length ?? 0) > 0 && (
                <div className="mb-4">
                  <Field label="Υπάρχων ανάδοχος του μητρώου">
                    <Select
                      value={v.contractor.id ?? ''}
                      onChange={e => {
                        const id = e.target.value || null
                        const found = contractors?.find(c => c.id === id)
                        setV(s => ({
                          ...s,
                          contractor: found
                            ? {
                                ...s.contractor, id, name: found.name, afm: found.afm,
                                doy: found.doy ?? '', email: found.email ?? '',
                                phone: found.phone ?? '', legal_rep_name: found.legal_rep_name ?? '',
                              }
                            : { ...s.contractor, id: null },
                        }))
                      }}
                    >
                      <option value="">— Νέος ανάδοχος —</option>
                      {contractors?.map(c => (
                        <option key={c.id} value={c.id}>{c.name} · ΑΦΜ {c.afm}</option>
                      ))}
                    </Select>
                  </Field>
                </div>
              )}

              <fieldset disabled={Boolean(v.contractor.id)}
                className={cx('grid gap-4 sm:grid-cols-2', v.contractor.id && 'opacity-60')}>
                <div className="sm:col-span-2">
                  <Field label="Επωνυμία">
                    <Input value={v.contractor.name} onChange={e => setK('name', e.target.value)} />
                  </Field>
                </div>
                <Field label="Α.Φ.Μ." hint="Ακριβώς 9 ψηφία">
                  <Input value={v.contractor.afm} inputMode="numeric" maxLength={9}
                    onChange={e => setK('afm', e.target.value.replace(/\D/g, ''))} />
                </Field>
                <Field label="Δ.Ο.Υ.">
                  <Input value={v.contractor.doy} onChange={e => setK('doy', e.target.value)} />
                </Field>
                <Field label="Νομική μορφή">
                  <Input value={v.contractor.legal_form} onChange={e => setK('legal_form', e.target.value)}
                    placeholder="Α.Ε. / Ε.Π.Ε. / Ο.Ε. / ατομική" />
                </Field>
                <Field label="ΜΕΕΠ / ΜΗ.Ε.Ε.Δ.Ε.">
                  <Input value={v.contractor.meep_mieedde}
                    onChange={e => setK('meep_mieedde', e.target.value)} />
                </Field>
                <Field label="Νόμιμος εκπρόσωπος">
                  <Input value={v.contractor.legal_rep_name}
                    onChange={e => setK('legal_rep_name', e.target.value)} />
                </Field>
                <Field label="Τηλέφωνο">
                  <Input value={v.contractor.phone} onChange={e => setK('phone', e.target.value)} />
                </Field>
                <div className="sm:col-span-2">
                  <Field label="Ηλεκτρονικό ταχυδρομείο" legalRef="N4412/138"
                    hint="Σε αυτή τη διεύθυνση κοινοποιούνται τα έγγραφα της επίβλεψης.">
                    <Input type="email" value={v.contractor.email}
                      onChange={e => setK('email', e.target.value)} />
                  </Field>
                </div>
                <div className="sm:col-span-2">
                  <Field label="Έδρα">
                    <Input value={v.contractor.address} onChange={e => setK('address', e.target.value)} />
                  </Field>
                </div>
              </fieldset>
            </div>
          </Card>

          {/* ---------------------------------------------------------- */}
          <Card>
            <CardHeader title="3. Η σύμβαση" subtitle="Στοιχεία και οικονομικά μεγέθη" />
            <div className="grid gap-4 px-4 py-4 sm:grid-cols-2">
              <Field label="Αριθμός σύμβασης">
                <Input value={v.contract.contract_no} onChange={e => setC('contract_no', e.target.value)} />
              </Field>
              <Field label="Ημερομηνία υπογραφής" legalRef="N4412/147/2"
                hint="Από την ημερομηνία αυτή αρχίζουν όλες οι προθεσμίες.">
                <Input type="date" value={v.contract.signed_at}
                  onChange={e => setC('signed_at', e.target.value)} />
              </Field>
              <Field label="ΑΔΑ σύμβασης" legalRef="N4727/2020">
                <Input value={v.contract.ada_contract} onChange={e => setC('ada_contract', e.target.value)} />
              </Field>
              <Field label="ΑΔΑΜ σύμβασης">
                <Input value={v.contract.adam_contract} onChange={e => setC('adam_contract', e.target.value)} />
              </Field>

              <div className="sm:col-span-2 border-t border-rule pt-4">
                <div className="label-xs mb-3">Οικονομικά μεγέθη</div>
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label="Δαπάνη εργασιών κατά τη μελέτη (€)"
                    hint="Χωρίς ΓΕ & ΟΕ, απρόβλεπτα, αναθεώρηση και ΦΠΑ.">
                    <Input type="number" min={0} step={0.01} value={v.contract.budget_works_net || ''}
                      onChange={e => setC('budget_works_net', Number(e.target.value))} />
                  </Field>
                  <Field label="Έκπτωση (%)" hint="Η μέση τεκμαρτή έκπτωση της προσφοράς.">
                    <Input type="number" min={0} max={99.99} step={0.01} value={v.contract.discount_pct || ''}
                      onChange={e => setC('discount_pct', Number(e.target.value))} />
                  </Field>
                  <Field label="ΓΕ & ΟΕ (%)">
                    <Input type="number" min={0} max={30} step={0.01} value={v.contract.ge_oe_pct}
                      onChange={e => setC('ge_oe_pct', Number(e.target.value))} />
                  </Field>
                  <Field label="Απρόβλεπτα (%)" legalRef="N4412/156/3b"
                    hint="9% για έργα ίσα ή άνω των ορίων του άρθρου 5, 15% για τα μικρότερα.">
                    <Select value={String(v.contract.contingency_pct)}
                      onChange={e => setC('contingency_pct', Number(e.target.value) as 9 | 15)}>
                      <option value="15">15% — κάτω των ορίων</option>
                      <option value="9">9% — ίσα ή άνω των ορίων</option>
                    </Select>
                  </Field>
                  <Field label="Αναθεώρηση (€)" legalRef="N4412/153">
                    <Input type="number" min={0} step={0.01} value={v.contract.revision_amount || ''}
                      onChange={e => setC('revision_amount', Number(e.target.value))} />
                  </Field>
                  <Field label="ΦΠΑ (%)">
                    <Input type="number" min={0} max={30} step={0.5} value={v.contract.vat_rate}
                      onChange={e => setC('vat_rate', Number(e.target.value))} />
                  </Field>
                </div>
              </div>
            </div>
          </Card>

          {/* ---------------------------------------------------------- */}
          <Card>
            <CardHeader title="4. Προθεσμίες και ημερολόγιο" legalRef="N4412/147/1" />
            <div className="grid gap-4 px-4 py-4 sm:grid-cols-2">
              <Field label="Συνολική προθεσμία (ημερολογιακές ημέρες)" legalRef="N4412/147/1">
                <Input type="number" min={1} value={v.contract.total_duration_days || ''}
                  onChange={e => setC('total_duration_days', Number(e.target.value))} />
              </Field>
              <Field label="Υποβολή χρονοδιαγράμματος (ημέρες)" legalRef="N4412/145/1"
                hint="Από 15 έως 30 ημέρες από την υπογραφή.">
                <Input type="number" min={15} max={30} value={v.contract.schedule_submit_days}
                  onChange={e => setC('schedule_submit_days', Number(e.target.value))} />
              </Field>
              <Field label="Χρόνος υποχρεωτικής συντήρησης (μήνες)" legalRef="N4412/171">
                <Input type="number" min={0} max={60} value={v.contract.maintenance_months}
                  onChange={e => setC('maintenance_months', Number(e.target.value))} />
              </Field>
              <Field label="Τρόπος τήρησης ημερολογίου" legalRef="N4412/146">
                <Select value={v.contract.diary_mode}
                  onChange={e => setC('diary_mode', e.target.value as NewProjectInput['contract']['diary_mode'])}>
                  <option value="imerisio">Ημερήσιο</option>
                  <option value="evdomadiaio">Εβδομαδιαίο</option>
                  <option value="apallagi">Απαλλαγή από την τήρηση</option>
                </Select>
              </Field>
              {v.contract.diary_mode !== 'apallagi' && (
                <Field label="Ειδική ποινική ρήτρα ημερολογίου (€/ημέρα)" legalRef="N4412/146"
                  hint="Ορίζεται στα συμβατικά τεύχη, από 100 έως 500 €.">
                  <Input type="number" min={100} max={500} step={10}
                    value={v.contract.diary_penalty_per_day}
                    onChange={e => setC('diary_penalty_per_day', Number(e.target.value))} />
                </Field>
              )}
              <Field label="Νομικό καθεστώς σύμβασης">
                <Select value={v.contract.regime}
                  onChange={e => setC('regime', e.target.value as NewProjectInput['contract']['regime'])}>
                  <option value="n4412_meta_n4782">ν. 4412/2016 όπως ισχύει μετά τον ν. 4782/2021</option>
                  <option value="n4412_pro_n4782">ν. 4412/2016 πριν από τον ν. 4782/2021</option>
                </Select>
              </Field>
            </div>
          </Card>

          {/* ---------------------------------------------------------- */}
          <Card>
            <CardHeader
              title="5. Ομάδα επίβλεψης"
              subtitle="Ο ορισμός γίνεται με απόφαση της Διευθύνουσας Υπηρεσίας"
              legalRef="N4412/136/2"
            />
            <div className="grid gap-4 px-4 py-4 sm:grid-cols-2">
              <Field label="Επιβλέπων μηχανικός" legalRef="N4412/136/2">
                <Select value={v.assignments.epivlepon}
                  onChange={e => setA('epivlepon', e.target.value)}>
                  <option value="">— Επιλέξτε —</option>
                  {engineers.map(p => (
                    <option key={p.id} value={p.id}>
                      {p.full_name}{p.specialty ? ` — ${p.specialty}` : ''}
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="Προϊστάμενος Διευθύνουσας Υπηρεσίας">
                <Select value={v.assignments.proistamenos_dy}
                  onChange={e => setA('proistamenos_dy', e.target.value)}>
                  <option value="">— Επιλέξτε —</option>
                  {engineers.map(p => (
                    <option key={p.id} value={p.id}>
                      {p.full_name}
                      {p.roles.length ? ` — ${p.roles.map(r => ROLE[r as keyof typeof ROLE] ?? r).join(', ')}` : ''}
                    </option>
                  ))}
                </Select>
              </Field>

              <div className="sm:col-span-2">
                <span className="label-xs mb-1 flex items-center gap-2">
                  Βοηθοί επιβλέποντος <LegalRef id="N4412/136/2" />
                </span>
                {helpers.length === 0 ? (
                  <p className="text-xs text-ink3">Δεν υπάρχει άλλο διαθέσιμο προσωπικό στον φορέα.</p>
                ) : (
                  <div className="flex flex-wrap gap-2">
                    {helpers.map(p => {
                      const on = v.assignments.voithoi.includes(p.id)
                      return (
                        <button
                          key={p.id}
                          type="button"
                          onClick={() => setA('voithoi', on
                            ? v.assignments.voithoi.filter(x => x !== p.id)
                            : [...v.assignments.voithoi, p.id])}
                          className={cx(
                            'rounded border px-2.5 py-1 text-xs transition-colors',
                            on ? 'border-accent bg-accent-soft text-accent'
                               : 'border-rule2 bg-paper text-ink2 hover:border-accent',
                          )}
                        >
                          {on ? '✓ ' : ''}{p.full_name}
                        </button>
                      )
                    })}
                  </div>
                )}
                <label className="mt-3 flex items-center gap-2 text-xs text-ink2">
                  <input type="checkbox" checked={v.assignments.epivlepon_is_coordinator}
                    onChange={e => setA('epivlepon_is_coordinator', e.target.checked)} />
                  Ο επιβλέπων ορίζεται και συντονιστής της ομάδας επίβλεψης
                </label>
              </div>

              <Field label="Αριθμός απόφασης ορισμού">
                <Input value={v.assignments.decision_no} onChange={e => setA('decision_no', e.target.value)} />
              </Field>
              <Field label="Ημερομηνία απόφασης">
                <Input type="date" value={v.assignments.decision_date}
                  onChange={e => setA('decision_date', e.target.value)} />
              </Field>
              <Field label="ΑΔΑ απόφασης ορισμού" legalRef="N4727/2020">
                <Input value={v.assignments.decision_ada}
                  onChange={e => setA('decision_ada', e.target.value)} />
              </Field>
              <div className="sm:col-span-2">
                <Field label="Ειδικότερα καθήκοντα"
                  hint="Προαιρετικά: κατανομή αρμοδιοτήτων εντός της ομάδας επίβλεψης.">
                  <Textarea value={v.assignments.duties} onChange={e => setA('duties', e.target.value)} />
                </Field>
              </div>
            </div>
          </Card>

          {/* ---------------------------------------------------------- */}
          <Card>
            <CardHeader
              title="6. Εγγύηση καλής εκτέλεσης"
              subtitle="Αν δεν έχει κατατεθεί ακόμη, αφήστε τα πεδία κενά — το στάδιο εγκατάστασης θα παραμείνει φραγμένο."
              legalRef="N4412/72/4"
            />
            <div className="grid gap-4 px-4 py-4 sm:grid-cols-2">
              <Field label="Εκδότης">
                <Input value={v.guarantee.issuer} onChange={e => setG('issuer', e.target.value)}
                  placeholder="Τράπεζα / Τ.Μ.Ε.Δ.Ε." />
              </Field>
              <Field label="Αριθμός εγγυητικής">
                <Input value={v.guarantee.guarantee_no} onChange={e => setG('guarantee_no', e.target.value)} />
              </Field>
              <Field label="Ημερομηνία έκδοσης">
                <Input type="date" value={v.guarantee.issued_at}
                  onChange={e => setG('issued_at', e.target.value)} />
              </Field>
              <Field label="Ημερομηνία λήξης (αν ορίζεται)">
                <Input type="date" value={v.guarantee.valid_to}
                  onChange={e => setG('valid_to', e.target.value)} />
              </Field>
              <div className="sm:col-span-2">
                <Field label="Ποσό (€)" legalRef="N4412/72/4"
                  hint={`Το 5% της αρχικής συμβατικής αξίας αντιστοιχεί σε ${eur(d.guaranteeExpected)}.`}>
                  <div className="flex gap-2">
                    <Input type="number" min={0} step={0.01} value={v.guarantee.original_amount || ''}
                      onChange={e => setG('original_amount', Number(e.target.value))} />
                    <Button type="button" onClick={() => setG('original_amount', d.guaranteeExpected)}
                      disabled={!d.guaranteeExpected}>
                      Συμπλήρωση 5%
                    </Button>
                  </div>
                </Field>
              </div>
            </div>
          </Card>

          <div className="flex flex-wrap justify-end gap-3 pb-8">
            <Button onClick={() => nav('/')} disabled={busy}>Ακύρωση</Button>
            <Button variant="primary" onClick={submit} disabled={busy}>
              {busy ? 'Καταχώριση…' : 'Δημιουργία έργου και έναρξη οδηγού'}
            </Button>
          </div>
        </div>

        {/* ------------------------- Σύνοψη ------------------------- */}
        <aside className="xl:sticky xl:top-4 xl:self-start">
          <Card>
            <CardHeader title="Τι θα καταχωριστεί" subtitle="Ενημερώνεται καθώς συμπληρώνετε" />
            <div className="space-y-4 px-4 py-4 text-sm">
              <section>
                <div className="label-xs mb-1.5">Οικονομικά</div>
                <dl className="space-y-1">
                  <Row k="Εργασίες μετά την έκπτωση" v={eur(d.worksAfterDiscount)} />
                  <Row k={`ΓΕ & ΟΕ ${pct(v.contract.ge_oe_pct)}`} v={eur(d.geOe)} />
                  <Row k={`Απρόβλεπτα ${pct(v.contract.contingency_pct)}`} v={eur(d.contingency)} />
                  {v.contract.revision_amount > 0 && (
                    <Row k="Αναθεώρηση" v={eur(v.contract.revision_amount)} />
                  )}
                  <Row k="Αρχική συμβατική αξία" v={eur(d.initialValueNet)} strong />
                  <Row k={`ΦΠΑ ${pct(v.contract.vat_rate)}`} v={eur(d.vatAmount)} />
                  <Row k="Σύνολο με ΦΠΑ" v={eur(d.totalWithVat)} strong />
                </dl>
                <p className="mt-2 text-xs text-ink3">
                  Προϋπολογισμός μελέτης (χωρίς έκπτωση): {eur(d.studyBudgetNet)}
                </p>
              </section>

              <section className="border-t border-rule pt-3">
                <div className="label-xs mb-1.5">Προθεσμίες που θα οριστούν</div>
                <dl className="space-y-1">
                  <Row k="Υποβολή χρονοδιαγράμματος" v={date(d.scheduleDueDate)} ref_="N4412/145/1" />
                  <Row k="Έγκριση ή τεκμήριο" v={date(d.scheduleApprovalDue)} ref_="N4412/145/2" />
                  <Row k="Έναρξη εργασιών" v={date(d.worksStartDue)} ref_="N4412/145/2" />
                  <Row k="Λήξη συνολικής προθεσμίας" v={date(d.originalEndDate)} ref_="N4412/147/1" strong />
                  <Row k="Οριακή προθεσμία" v={date(d.oriakiEndDate)} ref_="N4412/147/4" />
                </dl>
                <p className="mt-2 text-xs text-ink3">
                  Συντήρηση: {d.maintenanceUntilNote}.
                </p>
              </section>

              <section className="border-t border-rule pt-3">
                <div className="label-xs mb-1.5">Θα δημιουργηθούν</div>
                <ul className="space-y-1 text-xs text-ink2">
                  <li>· Ο φάκελος του έργου και η σύμβαση</li>
                  <li>· Τα στάδια του οδηγού με τις προθεσμίες τους</li>
                  <li>· Οι ορισμοί επίβλεψης
                    {v.assignments.voithoi.length > 0 &&
                      ` (+${v.assignments.voithoi.length} βοηθοί)`}</li>
                  {v.guarantee.guarantee_no.trim() && <li>· Η εγγύηση καλής εκτέλεσης</li>}
                </ul>
                {v.contract.diary_mode === 'imerisio' && (
                  <p className="mt-2 flex items-start gap-1.5 text-xs text-brass">
                    <Badge tone="brass">146</Badge>
                    <span>
                      Ημερήσιο ημερολόγιο: κάθε εργάσιμη χωρίς καταχώριση προσμετράται
                      στην ειδική ποινική ρήτρα των {eur(v.contract.diary_penalty_per_day)}.
                    </span>
                  </p>
                )}
              </section>
            </div>
          </Card>
        </aside>
      </div>
    </div>
  )
}

function Row({ k, v, strong, ref_ }: {
  k: string; v: string; strong?: boolean; ref_?: string
}) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <dt className={cx('text-xs', strong ? 'text-ink' : 'text-ink3')}>
        {k}{ref_ && <LegalRef id={ref_} className="ml-1" />}
      </dt>
      <dd className={cx('tnum shrink-0 font-mono text-xs', strong ? 'font-semibold text-ink' : 'text-ink2')}>
        {v}
      </dd>
    </div>
  )
}

function NotPermitted({ roles }: { roles: string[] }) {
  return (
    <Card className="mx-auto max-w-2xl">
      <CardHeader title="Η δημιουργία έργου ανήκει στη Διευθύνουσα Υπηρεσία"
        legalRef="N4412/136/2" />
      <div className="space-y-3 px-4 py-4 text-sm text-ink2">
        <p>
          Ο φάκελος ενός έργου ανοίγεται από τη Διευθύνουσα Υπηρεσία, η οποία με
          απόφασή της ορίζει και τον επιβλέποντα μηχανικό. Ο επιβλέπων δεν
          αυτο-ορίζεται· γι' αυτό η οθόνη αυτή απαιτεί ρόλο υπηρεσιακής εμβέλειας
          (Προϊστάμενος Δ.Υ., Προϊσταμένη Αρχή ή διαχειριστής).
        </p>
        <p>
          Ο λογαριασμός σας φέρει σήμερα:{' '}
          {roles.length
            ? roles.map(r => ROLE[r as keyof typeof ROLE] ?? r).join(', ')
            : 'κανέναν υπηρεσιακό ρόλο'}.
        </p>
        <p className="text-ink3">
          Μόλις η Υπηρεσία καταχωρίσει το έργο και σας ορίσει επιβλέποντα, θα το
          δείτε αυτόματα στον πίνακα των έργων σας με όλα τα στάδια του οδηγού.
        </p>
      </div>
    </Card>
  )
}
