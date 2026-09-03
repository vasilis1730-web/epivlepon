-- =====================================================================
-- Migration 0011 : Ειδικοί κανόνες σταδίων (guard functions),
--                  κανόνας μείωσης εγγυήσεων, όψεις παρακολούθησης
-- =====================================================================

-- Βάση υπολογισμού της εγγύησης καλής εκτέλεσης (άρθρο 72 §4)
alter table public.contracts
  add column if not exists estimated_guarantee_base numeric(14,2);

comment on column public.contracts.estimated_guarantee_base is
  'Βάση υπολογισμού της εγγύησης καλής εκτέλεσης (εκτιμώμενη αξία σύμβασης χωρίς '
  'δικαιώματα προαίρεσης και ΦΠΑ) — άρθρο 72 §4 ν.4412/2016.';

-- ---------------------------------------------------------------------
-- 11.1 GUARD: Εγγυητικές επιστολές (άρθρο 72 §4)
-- ---------------------------------------------------------------------
create or replace function app.guard_guarantees(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; c public.contracts%rowtype; v_sum numeric;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;
  select * into c from public.contracts where project_id = v_pid;
  if not found then
    return next ('NO_CONTRACT','Δεν έχει καταχωρηθεί σύμβαση για το έργο.','hard','N4412/135')::app.blocker;
    return;
  end if;

  select coalesce(sum(g.current_amount),0) into v_sum
  from public.guarantees g
  where g.project_id = v_pid
    and g.gtype in ('kalis_ektelesis','prosthetti')
    and g.status in ('energi','meiomeni_70');

  if v_sum = 0 then
    return next ('GUAR_MISSING',
      'Δεν έχει καταχωρηθεί ενεργή εγγυητική επιστολή καλής εκτέλεσης.',
      'hard','N4412/72/4')::app.blocker;
  elsif v_sum < c.estimated_guarantee_base * 0.05 - 0.01 then
    return next ('GUAR_UNDER_5PCT',
      format('Η κατατεθειμένη εγγύηση (%s €) υπολείπεται του 5%% της εκτιμώμενης αξίας.',
             to_char(v_sum,'FM999G999G990D00')),
      'hard','N4412/72/4')::app.blocker;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.2 GUARD: Χρονοδιάγραμμα (άρθρο 145)
-- ---------------------------------------------------------------------
create or replace function app.guard_schedule(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; s public.schedules%rowtype; c public.contracts%rowtype;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;
  select * into c from public.contracts where project_id = v_pid;
  select * into s from public.schedules
   where project_id = v_pid order by version_no desc limit 1;

  if not found then
    return next ('SCHED_MISSING',
      'Δεν έχει υποβληθεί χρονοδιάγραμμα κατασκευής.','hard','N4412/145/1')::app.blocker;
    return;
  end if;

  if s.submitted_at is null then
    return next ('SCHED_NOT_SUBMITTED',
      'Το χρονοδιάγραμμα δεν έχει υποβληθεί από τον ανάδοχο.','hard','N4412/145/1')::app.blocker;
  elsif c.signed_at is not null and s.submitted_at > c.signed_at + 30 then
    return next ('SCHED_LATE',
      format('Εκπρόθεσμη υποβολή χρονοδιαγράμματος (%s) — η προθεσμία δεν μπορεί να υπερβαίνει τις 30 ημέρες από την υπογραφή.',
             to_char(s.submitted_at,'DD/MM/YYYY')),
      'soft','N4412/145/2')::app.blocker;
  end if;

  if s.approved_at is null and not s.deemed_approved then
    if s.approval_due is not null and current_date > s.approval_due then
      return next ('SCHED_TACIT',
        'Παρήλθε η 15ήμερη προθεσμία έγκρισης: το χρονοδιάγραμμα ΤΕΚΜΑΙΡΕΤΑΙ ΕΓΚΕΚΡΙΜΕΝΟ. Καταχωρίστε τη σιωπηρή έγκριση.',
        'hard','N4412/145/2')::app.blocker;
    else
      return next ('SCHED_PENDING',
        'Εκκρεμεί η έγκριση του χρονοδιαγράμματος από τη Διευθύνουσα Υπηρεσία (προθεσμία 15 ημερών).',
        'hard','N4412/145/2')::app.blocker;
    end if;
  end if;

  if c.initial_value_net > 1000000 and s.method <> 'diktyoti_analysi' then
    return next ('SCHED_METHOD',
      'Για έργα άνω του 1.000.000 € η μέθοδος δικτυωτής ανάλυσης είναι ΥΠΟΧΡΕΩΤΙΚΗ.',
      'hard','N4412/145/3')::app.blocker;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.3 GUARD: Ημερολόγιο (άρθρο 146)
-- ---------------------------------------------------------------------
create or replace function app.guard_diary(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; v_missing integer; v_unreviewed integer;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;

  select count(*) into v_missing from public.v_diary_missing_days d where d.project_id = v_pid;
  if v_missing > 0 then
    return next ('DIARY_MISSING',
      format('Λείπουν %s ημέρες ημερολογίου. Η παράλειψη επισύρει ειδική ποινική ρήτρα 100-500 € ανά ημέρα.',
             v_missing),
      'hard','N4412/146')::app.blocker;
  end if;

  select count(*) into v_unreviewed
  from public.diary_entries e
  where e.project_id = v_pid
    and e.status = 'submitted'
    and e.submitted_at < now() - interval '2 days';
  if v_unreviewed > 0 then
    return next ('DIARY_UNREVIEWED',
      format('%s εγγραφές ημερολογίου δεν ελέγχθηκαν από τον επιβλέποντα εντός δύο (2) εργασίμων ημερών.',
             v_unreviewed),
      'soft','N4412/146')::app.blocker;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.4 GUARD: Αφανείς εργασίες (άρθρο 151 §7)
-- ---------------------------------------------------------------------
create or replace function app.guard_hidden_works(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; v_overdue integer; v_covered integer;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;

  select count(*) into v_overdue
  from public.hidden_work_notices h
  where h.project_id = v_pid and h.inspected_at is null and h.inspection_due < current_date;
  if v_overdue > 0 then
    return next ('HW_OVERDUE',
      format('%s δηλώσεις αφανών εργασιών δεν ελέγχθηκαν εντός της 3ήμερης προθεσμίας — ΥΠΕΡΗΜΕΡΙΑ ΚΥΡΙΟΥ ΤΟΥ ΕΡΓΟΥ.',
             v_overdue),
      'hard','N4412/151/7')::app.blocker;
  end if;

  select count(*) into v_covered
  from public.hidden_work_notices h
  where h.project_id = v_pid and h.covered_at is not null and h.inspected_at is null;
  if v_covered > 0 then
    return next ('HW_COVERED_UNCHECKED',
      format('%s αφανείς εργασίες επικαλύφθηκαν χωρίς προηγούμενο έλεγχο του επιβλέποντος.',
             v_covered),
      'hard','N4412/151/7')::app.blocker;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.5 GUARD: Επιμετρήσεις — δειγματοληψία 40% (άρθρο 151 §3)
-- ---------------------------------------------------------------------
create or replace function app.guard_measurements(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; v_required integer; v_done integer; v_overdue integer;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;

  v_required := public.required_audit_count(v_pid);
  select count(distinct ma.measurement_id) into v_done
  from public.measurement_audits ma
  join public.measurements m on m.id = ma.measurement_id
  where m.project_id = v_pid and ma.performed_at is not null;

  if v_done < v_required then
    return next ('MEAS_AUDIT_SHORTFALL',
      format('Ο υποχρεωτικός δειγματοληπτικός έλεγχος δεν καλύφθηκε: απαιτούνται %s, διενεργήθηκαν %s.',
             v_required, v_done),
      'hard','N4412/151/3')::app.blocker;
  end if;

  select count(*) into v_overdue
  from public.measurements m
  where m.project_id = v_pid
    and m.status not in ('approved','deemed_approved','rejected')
    and m.approval_due is not null and m.approval_due < current_date;
  if v_overdue > 0 then
    return next ('MEAS_OVERDUE',
      format('%s επιμετρήσεις εκκρεμούν πέραν της 30ήμερης προθεσμίας εγκριτικής πράξης.', v_overdue),
      'soft','N4412/151/7')::app.blocker;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.6 GUARD: Ανακεφαλαιωτικοί Πίνακες
-- ---------------------------------------------------------------------
create or replace function app.guard_ape_stage(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; r record;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;
  for r in select id, serial_no from public.ape
           where project_id = v_pid and status <> 'approved' loop
    return query
      select 'APE' || r.serial_no || '_' || b.code, format('%sος ΑΠΕ: %s', r.serial_no, b.message),
             b.severity, b.legal_ref
      from app.ape_validation(r.id) b;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 11.7 GUARD: Βεβαίωση Περάτωσης (άρθρο 168)
-- ---------------------------------------------------------------------
create or replace function app.guard_completion(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; cm public.completions%rowtype; v_defects integer;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;
  select * into cm from public.completions where project_id = v_pid;

  if not found or cm.supervisor_report_at is null then
    return next ('COMP_NO_REPORT',
      'Δεν έχει συνταχθεί η έγγραφη αναφορά του επιβλέποντος περί περαίωσης (προθεσμία 30 ημερών από τη λήξη του εγκεκριμένου χρόνου).',
      'hard','N4412/168/1')::app.blocker;
    return;
  end if;

  if not cm.tests_completed then
    return next ('COMP_NO_TESTS',
      'Δεν βεβαιώνεται η ολοκλήρωση των προβλεπόμενων από τη σύμβαση δοκιμών.',
      'hard','N4412/168/1')::app.blocker;
  end if;

  select count(*) into v_defects from public.defects d
  where d.project_id = v_pid and d.source = 'peraiosi' and d.remedied_at is null;
  if v_defects > 0 then
    if cm.defects_severity = 'ousiodes' then
      return next ('COMP_MAJOR_DEFECTS',
        'Υφίστανται ΟΥΣΙΩΔΗ ελαττώματα: εφαρμόζονται τα άρθρα 159 και 160 (ακαταλληλότητα/έκπτωση) και δεν εκδίδεται Βεβαίωση Περάτωσης.',
        'hard','N4412/168/4')::app.blocker;
    else
      return next ('COMP_MINOR_DEFECTS',
        format('Εκκρεμεί η αποκατάσταση %s επουσιωδών ελαττωμάτων εντός της ταχθείσας προθεσμίας.', v_defects),
        'hard','N4412/168/3')::app.blocker;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.8 GUARD + TRIGGER: ΜΕΙΩΣΗ ΕΓΓΥΗΣΕΩΝ (άρθρο 72 §14 περ. β΄)
--      Η μείωση 70% προϋποθέτει ΕΓΚΕΚΡΙΜΕΝΗ ΤΕΛΙΚΗ ΕΠΙΜΕΤΡΗΣΗ.
--      Η ολική αποδέσμευση προϋποθέτει ΠΑΡΑΛΑΒΗ + ΤΕΛΙΚΟ ΛΟΓΑΡΙΑΣΜΟ.
-- ---------------------------------------------------------------------
create or replace function app.guard_guarantee_event()
returns trigger language plpgsql security definer set search_path = public, app as $$
declare v_pid uuid; g public.guarantees%rowtype;
begin
  select * into g from public.guarantees where id = new.guarantee_id;
  v_pid := g.project_id;

  if new.event_type = 'meiosi_70' then
    if not exists (select 1 from public.final_measurement fm
                   where fm.project_id = v_pid and fm.approved_at is not null) then
      raise exception
        'ΑΠΑΓΟΡΕΥΕΤΑΙ η μείωση της εγγύησης κατά 70%%: δεν υπάρχει ΕΓΚΕΚΡΙΜΕΝΗ ΤΕΛΙΚΗ ΕΠΙΜΕΤΡΗΣΗ (άρθρο 72 §14 περ. β΄ σε συνδυασμό με άρθρο 151 §9 ν.4412/2016).'
        using errcode = 'check_violation';
    end if;
    if abs(new.amount_after - new.amount_before * 0.30) > 0.05 then
      raise exception
        'Η μείωση πρέπει να ανέρχεται σε 70%% της εγγύησης: αναμενόμενο υπόλοιπο %s €.',
        to_char(new.amount_before * 0.30,'FM999G999G990D00')
        using errcode = 'check_violation';
    end if;
  end if;

  if new.event_type = 'apodesmevsi' then
    if not exists (select 1 from public.acceptances a
                   where a.project_id = v_pid
                     and a.status in ('completed','auto_completed')
                     and a.approved_at is not null) then
      raise exception
        'ΑΠΑΓΟΡΕΥΕΤΑΙ η επιστροφή της εγγύησης: δεν έχει εγκριθεί το πρωτόκολλο παραλαβής (άρθρα 72 §14, 172 ν.4412/2016).'
        using errcode = 'check_violation';
    end if;
    if not exists (select 1 from public.payment_certificates pc
                   where pc.project_id = v_pid and pc.ptype = 'telikos'
                     and pc.status in ('approved','deemed_approved','paid')) then
      raise exception
        'ΑΠΑΓΟΡΕΥΕΤΑΙ η επιστροφή της εγγύησης: δεν έχει εγκριθεί ο ΤΕΛΙΚΟΣ ΛΟΓΑΡΙΑΣΜΟΣ (άρθρα 72 §14, 152 ν.4412/2016).'
        using errcode = 'check_violation';
    end if;
  end if;

  update public.guarantees
     set current_amount = new.amount_after,
         status = case new.event_type
                    when 'meiosi_70'   then 'meiomeni_70'::public.guarantee_status
                    when 'apodesmevsi' then 'apodesmevmeni'::public.guarantee_status
                    when 'katapt'      then 'katapiptousa'::public.guarantee_status
                    else status end
   where id = new.guarantee_id;

  return new;
end $$;

create trigger trg_guard_guarantee_event
  before insert on public.guarantee_events
  for each row execute function app.guard_guarantee_event();

create or replace function app.guard_guarantee_reduction(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;
  if not exists (select 1 from public.final_measurement fm
                 where fm.project_id = v_pid and fm.approved_at is not null) then
    return next ('GUAR_RED_NO_FINAL',
      'Η μείωση της εγγύησης κατά 70% προϋποθέτει εγκεκριμένη τελική επιμέτρηση.',
      'hard','N4412/72/14b')::app.blocker;
  end if;
  if not exists (select 1 from public.guarantee_events ge
                 join public.guarantees g on g.id = ge.guarantee_id
                 where g.project_id = v_pid and ge.event_type = 'meiosi_70') then
    return next ('GUAR_RED_NOT_DONE',
      'Δεν έχει καταχωρηθεί η πράξη μείωσης της εγγύησης καλής εκτέλεσης κατά 70%.',
      'hard','N4412/72/14b')::app.blocker;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.9 GUARD: Παραλαβή (άρθρο 172)
-- ---------------------------------------------------------------------
create or replace function app.guard_acceptance(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare v_pid uuid; a public.acceptances%rowtype; v_members integer;
begin
  select project_id into v_pid from public.project_stages where id = p_project_stage_id;
  select * into a from public.acceptances where project_id = v_pid;

  if not found then
    return next ('ACC_NOT_OPEN','Δεν έχει ανοίξει διαδικασία παραλαβής.','hard','N4412/172')::app.blocker;
    return;
  end if;

  if a.committee_id is null then
    return next ('ACC_NO_COMMITTEE',
      'Δεν έχει οριστεί επιτροπή παραλαβής (ορίζεται τουλάχιστον 3 μήνες πριν τη λήξη του χρόνου υποχρεωτικής συντήρησης).',
      'hard','N4412/172')::app.blocker;
  else
    select count(*) into v_members from public.committee_members cm
    where cm.committee_id = a.committee_id and not cm.is_observer;
    if v_members < 5 then
      return next ('ACC_COMMITTEE_SIZE',
        format('Η επιτροπή παραλαβής έχει %s μέλη — απαιτείται πενταμελής σύνθεση με δύο εκπροσώπους ΤΕΕ/ΓΕΩΤΕΕ.', v_members),
        'hard','N4412/172')::app.blocker;
    end if;
  end if;

  if current_date > a.deadline_3m and a.protocol_date is null then
    return next ('ACC_AUTO',
      'Παρήλθε η τρίμηνη προθεσμία: η παραλαβή θεωρείται ΑΥΤΟΔΙΚΑΙΩΣ ΣΥΝΤΕΛΕΣΜΕΝΗ — απαιτείται βεβαιωτική πράξη.',
      'hard','N4412/172')::app.blocker;
  end if;

  if not (a.maintenance_manual and a.operation_manual and a.digital_archive) then
    return next ('ACC_DELIVERABLES',
      'Εκκρεμούν παραδοτέα αναδόχου: προϋπολογισμός/οδηγίες συντήρησης, εγχειρίδιο λειτουργίας, ψηφιακή τεκμηρίωση σταδίων κατασκευής.',
      'soft','N4412/172')::app.blocker;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11.10 ΟΨΕΙΣ ΠΑΡΑΚΟΛΟΥΘΗΣΗΣ
-- ---------------------------------------------------------------------

-- Ημέρες χωρίς εγγραφή ημερολογίου
create or replace view public.v_diary_missing_days as
with span as (
  select c.project_id,
         greatest(c.signed_at, coalesce(c.works_start_deadline, c.signed_at)) as from_d,
         least(current_date,
               coalesce((select cm.actual_completion_date from public.completions cm
                         where cm.project_id = c.project_id), current_date)) as to_d,
         c.diary_mode
  from public.contracts c
  where c.status = 'active' and c.diary_mode = 'imerisio'
)
select s.project_id, d::date as missing_date
from span s
cross join lateral generate_series(s.from_d, s.to_d, interval '1 day') g(d)
where extract(isodow from d) < 6                      -- Εργάσιμες (παραμετροποιήσιμο)
  and not exists (select 1 from public.diary_entries e
                  where e.project_id = s.project_id and e.entry_date = d::date);

comment on view public.v_diary_missing_days is
  'Ημέρες χωρίς εγγραφή ημερολογίου. Κάθε ημέρα γεννά ειδική ποινική ρήτρα '
  '100-500 € (άρθρο 146 ν.4412/2016).';

-- Οικονομική εικόνα έργου
create or replace view public.v_project_financials as
select p.id                            as project_id,
       p.code,
       p.title,
       c.initial_value_net,
       c.contingency_amount,
       c.contingency_pct,
       coalesce(ape.approved_delta, 0)                          as ape_delta,
       c.initial_value_net + coalesce(ape.approved_delta,0)     as current_value_net,
       round(coalesce(ape.approved_delta,0)
             / nullif(c.initial_value_net,0) * 100, 2)          as ape_delta_pct,
       round(c.initial_value_net * 0.50, 2)                     as limit_50pct,
       round(c.initial_value_net * 0.10, 2)                     as limit_savings_10pct,
       coalesce(pay.certified, 0)                               as certified_total,
       coalesce(pay.paid, 0)                                    as paid_total,
       round(coalesce(pay.certified,0)
             / nullif(c.initial_value_net + coalesce(ape.approved_delta,0),0) * 100, 2)
                                                                as financial_progress_pct,
       coalesce(adv.advance, 0)                                 as advance_total,
       coalesce(adv.advance,0) - coalesce(adv.amortized,0)      as advance_outstanding,
       coalesce(pen.total, 0)                                   as penalties_total,
       coalesce(gua.active_guarantees, 0)                       as guarantees_active,
       c.original_end_date,
       c.current_end_date,
       (c.current_end_date - current_date)                      as days_to_deadline
from public.projects p
join public.contracts c on c.project_id = p.id
left join lateral (
    select sum(a.delta_amount) as approved_delta
    from public.ape a where a.project_id = p.id and a.status = 'approved') ape on true
left join lateral (
    select sum(pc.gross_cumulative) filter (where pc.serial_no = (
             select max(x.serial_no) from public.payment_certificates x
             where x.project_id = p.id and x.ptype = 'tmimatikos')) as certified,
           sum(pc.net_payable) filter (where pc.paid_at is not null) as paid
    from public.payment_certificates pc where pc.project_id = p.id) pay on true
left join lateral (
    select sum(a.amount) as advance, sum(a.amortized_amount) as amortized
    from public.advances a where a.project_id = p.id) adv on true
left join lateral (
    select sum(x.amount) as total from public.penalties x
    where x.project_id = p.id and not x.waived) pen on true
left join lateral (
    select sum(g.current_amount) as active_guarantees from public.guarantees g
    where g.project_id = p.id and g.status in ('energi','meiomeni_70')) gua on true;

comment on view public.v_project_financials is
  'Συγκεντρωτική οικονομική εξέλιξη ανά έργο, με τα όρια ελέγχου του άρθρου 156.';

-- Πίνακας προθεσμιών (deadline radar)
create or replace view public.v_deadline_watch as
select ps.project_id, p.code as project_code, p.title as project_title,
       ws.code as stage_code, ws.title as stage_title,
       app.party_label(ws.responsible) as responsible,
       ps.status, ps.due_date,
       (ps.due_date - current_date) as days_left,
       case
         when ps.status in ('completed','not_applicable') then 'ok'
         when ps.due_date is null                          then 'no_deadline'
         when ps.due_date < current_date                   then 'overdue'
         when ps.due_date - current_date <= 5              then 'critical'
         when ps.due_date - current_date <= 15             then 'warning'
         else 'ok'
       end as alert_level,
       ws.legal_ref_id,
       ws.tacit_approval, ws.tacit_effect
from public.project_stages ps
join public.workflow_stages ws on ws.code = ps.stage_code
join public.projects p on p.id = ps.project_id
where ps.status not in ('completed','not_applicable');

-- Πίνακας ελέγχου σταδίων με τα εμπόδια
create or replace view public.v_stage_board as
select ps.id as project_stage_id, ps.project_id, ps.stage_code, ps.cycle_no,
       ws.ordinal, ws.phase, ws.title, ws.purpose,
       app.party_label(ws.responsible) as responsible,
       app.party_label(ws.approver)    as approver,
       ws.legal_ref_id, ws.risk_note, ws.recurrence,
       ps.status, ps.due_date, ps.completed_at,
       (select count(*) from app.stage_blockers(ps.id) b where b.severity='hard') as hard_blockers,
       (select count(*) from app.stage_blockers(ps.id) b where b.severity='soft') as soft_blockers,
       (select count(*) from public.project_stage_tasks t where t.project_stage_id = ps.id) as tasks_total,
       (select count(*) from public.project_stage_tasks t
         where t.project_stage_id = ps.id and (t.is_done or t.waived))                    as tasks_done
from public.project_stages ps
join public.workflow_stages ws on ws.code = ps.stage_code;

-- Εκκρεμείς αφανείς εργασίες
create or replace view public.v_hidden_works_alerts as
select h.project_id, h.serial_no, h.work_description, h.invitation_sent_at,
       h.inspection_due, h.inspected_at, h.photos_count, h.approval_due, h.approved_at,
       case
         when h.inspected_at is null and h.inspection_due < current_date then 'ΥΠΕΡΗΜΕΡΙΑ ΚΥΡΙΟΥ ΕΡΓΟΥ'
         when h.inspected_at is null                                     then 'ΕΚΚΡΕΜΕΙ ΕΛΕΓΧΟΣ'
         when h.photos_count = 0                                         then 'ΛΕΙΠΕΙ ΦΩΤΟΓΡΑΦΙΚΗ ΤΕΚΜΗΡΙΩΣΗ'
         when h.approved_at is null and h.approval_due < current_date    then 'ΕΚΠΡΟΘΕΣΜΗ ΕΓΚΡΙΤΙΚΗ ΠΡΑΞΗ'
         else 'ΟΚ'
       end as alert
from public.hidden_work_notices h;

-- Έλεγχος ορίων ΑΠΕ ανά έργο
create or replace view public.v_ape_limits as
select a.project_id, a.id as ape_id, a.serial_no, a.atype, a.status,
       a.delta_amount, c.initial_value_net,
       round(a.delta_amount / nullif(c.initial_value_net,0) * 100, 2) as delta_pct,
       a.contingency_used, c.contingency_amount,
       (select count(*) from app.ape_validation(a.id) b where b.severity='hard') as violations
from public.ape a
join public.contracts c on c.project_id = a.project_id;
