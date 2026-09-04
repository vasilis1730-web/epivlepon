-- =====================================================================
-- 0021_nightly_jobs.sql — Νυχτερινή αυτοματοποίηση προθεσμιών
-- ---------------------------------------------------------------------
-- Οι προθεσμίες του ν. 4412/2016 τρέχουν είτε τις παρακολουθεί κανείς είτε
-- όχι. Η εργασία αυτή εκτελείται κάθε νύχτα και αποτυπώνει στη βάση ό,τι
-- ΕΧΕΙ ΗΔΗ επέλθει από τον νόμο:
--
--   • σιωπηρές εγκρίσεις εκεί — και ΜΟΝΟ εκεί — όπου ο νόμος τις ορίζει
--   • σήμανση υπερημερίας επιβλέποντος και εκπρόθεσμων σταδίων
--   • υπολογισμό της ειδικής ποινικής ρήτρας ημερολογίου
--
-- ΣΗΜΑΝΤΙΚΗ ΔΙΑΚΡΙΣΗ: η εργασία ΔΕΝ επιβάλλει κυρώσεις. Οι ρήτρες
-- καταχωρίζονται ως ΥΠΟΛΟΓΙΣΜΟΣ, χωρίς αριθμό/ημερομηνία απόφασης· η
-- επιβολή παραμένει πράξη της Διευθύνουσας Υπηρεσίας.
--
-- Οι τμηματικές επιμετρήσεις ΔΕΝ εγκρίνονται σιωπηρά: ο ν. 4412/2016
-- προβλέπει τεκμήριο έγκρισης για το χρονοδιάγραμμα (145 §2), τις αφανείς
-- εργασίες (151 §7), τους λογαριασμούς (152) και τις παρατάσεις (147 §5).
-- Οι επιμετρήσεις απλώς σημαίνονται ως εκπρόθεσμες προς έλεγχο.
-- =====================================================================

-- Το pg_cron παρέχεται από το Supabase. Σε σκέτη PostgreSQL απλώς δεν
-- υπάρχει· η συνάρτηση εγκαθίσταται κανονικά και προγραμματίζεται εξωτερικά.
do $ext$
begin
  create extension if not exists pg_cron;
exception when others then
  raise notice 'pg_cron μη διαθέσιμο — προγραμματίστε εξωτερικά την app.run_nightly_jobs().';
end $ext$;

-- ---- 1. Μητρώο εκτελέσεων -------------------------------------------
create table if not exists app.nightly_runs (
  id          bigint generated always as identity primary key,
  ran_at      timestamptz not null default now(),
  result      jsonb       not null,
  duration_ms integer
);

comment on table app.nightly_runs is
  'Ιστορικό εκτελέσεων της νυχτερινής εργασίας προθεσμιών — τι μεταβλήθηκε και πότε.';

-- ---- 2. Η εργασία ----------------------------------------------------
create or replace function app.run_nightly_jobs()
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  t0            timestamptz := clock_timestamp();
  v_sched       integer := 0;
  v_hidden      integer := 0;
  v_pay         integer := 0;
  v_ext         integer := 0;
  v_sup_overdue integer := 0;
  v_meas_late   integer := 0;
  v_stages      integer := 0;
  v_penalties   integer := 0;
  v_from        date := date_trunc('month', current_date - interval '1 month')::date;
  v_to          date := (date_trunc('month', current_date) - interval '1 day')::date;
  v_result      jsonb;
begin
  -- 2.1 Χρονοδιάγραμμα — τεκμήριο έγκρισης (άρθρο 145 §2)
  update public.schedules s
     set deemed_approved = true
   where s.submitted_at is not null
     and s.approved_at is null
     and s.deemed_approved = false
     and s.approval_due_date is not null
     and s.approval_due_date < current_date;
  get diagnostics v_sched = row_count;

  -- 2.2 Αφανείς εργασίες — εγκριτική πράξη εντός 30 ημερών (άρθρο 151 §7)
  update public.hidden_work_notices h
     set deemed_approved = true,
         status = 'approved'
   where h.approval_due is not null
     and h.approval_due < current_date
     and h.approved_at is null
     and h.deemed_approved = false
     and h.status <> 'rejected';
  get diagnostics v_hidden = row_count;

  -- 2.3 Λογαριασμοί — σιωπηρή έγκριση (άρθρο 152)
  update public.payment_certificates p
     set deemed_approved = true,
         status = 'deemed_approved'
   where p.approval_due is not null
     and p.approval_due < current_date
     and p.approved_at is null
     and p.deemed_approved = false
     and p.status in ('submitted', 'under_review');
  get diagnostics v_pay = row_count;

  -- 2.4 Παρατάσεις — σιωπηρή αποδοχή (άρθρο 147 §5)
  update public.time_extensions e
     set deemed_accepted = true,
         outcome = 'deemed_accepted'
   where e.decision_due is not null
     and e.decision_due < current_date
     and e.decided_at is null
     and e.deemed_accepted = false
     and e.outcome = 'pending';
  get diagnostics v_ext = row_count;

  -- 2.5 Υπερημερία επιβλέποντος στον έλεγχο αφανών (άρθρο 151 §7, 3 ημέρες)
  update public.hidden_work_notices h
     set supervisor_overdue = true
   where h.inspection_due is not null
     and h.inspection_due < current_date
     and h.inspected_at is null
     and h.supervisor_overdue = false;
  get diagnostics v_sup_overdue = row_count;

  -- 2.6 Επιμετρήσεις εκπρόθεσμες προς έλεγχο — ΣΗΜΑΝΣΗ, όχι έγκριση
  select count(*) into v_meas_late
    from public.measurements m
   where m.approval_due is not null
     and m.approval_due < current_date
     and m.approved_at is null
     and m.deemed_approved = false
     and m.status in ('submitted', 'sampled', 'under_check');

  -- 2.7 Εκπρόθεσμα στάδια του οδηγού
  update public.project_stages ps
     set status = 'overdue'
   where ps.due_date is not null
     and ps.due_date < current_date
     and ps.status in ('available', 'in_progress', 'pending_approval');
  get diagnostics v_stages = row_count;

  -- 2.8 Ειδική ποινική ρήτρα ημερολογίου (άρθρο 146) — ΥΠΟΛΟΓΙΣΜΟΣ
  --     Μία εγγραφή ανά έργο και ανά ημερολογιακό μήνα, ιδεμποτικά.
  with missing as (
    select v.project_id, count(*)::int as days
      from public.v_diary_missing_days v
     where v.missing_date between v_from and v_to
     group by v.project_id
  )
  insert into public.penalties
    (project_id, kind, period_from, period_to, days_count,
     rate_description, base_amount, amount, reason, legal_ref_id)
  select m.project_id,
         'eidiki_ritra_imerologiou',
         v_from, v_to, m.days,
         format('%s ημέρες × %s €/ημέρα', m.days, c.diary_penalty_per_day),
         c.diary_penalty_per_day,
         round(m.days * c.diary_penalty_per_day, 2),
         format('Αυτόματος υπολογισμός ειδικής ποινικής ρήτρας για %s εργάσιμες '
                'ημέρες χωρίς καταχώριση ημερολογίου (%s έως %s), κατά το άρθρο 146 '
                'του ν. 4412/2016. ΑΠΑΙΤΕΙΤΑΙ ΑΠΟΦΑΣΗ ΤΗΣ ΔΙΕΥΘΥΝΟΥΣΑΣ ΥΠΗΡΕΣΙΑΣ '
                'για την επιβολή — η παρούσα εγγραφή αποτελεί υπολογισμό, όχι κύρωση.',
                m.days, to_char(v_from, 'DD/MM/YYYY'), to_char(v_to, 'DD/MM/YYYY')),
         'N4412/146'
    from missing m
    join public.contracts c on c.project_id = m.project_id
   where m.days > 0
     and not exists (
       select 1 from public.penalties p
        where p.project_id = m.project_id
          and p.kind = 'eidiki_ritra_imerologiou'
          and p.period_from = v_from
          and p.period_to = v_to);
  get diagnostics v_penalties = row_count;

  v_result := jsonb_build_object(
    'xronodiagrammata_sioipiri_egkrisi', v_sched,
    'afaneis_egkritiki_praxi',           v_hidden,
    'logariasmoi_sioipiri_egkrisi',      v_pay,
    'paratasseis_sioipiri_apodoxi',      v_ext,
    'ypermeria_epivleponta',             v_sup_overdue,
    'epimetriseis_ekprothesmes',         v_meas_late,
    'stadia_ekprothesma',                v_stages,
    'ritres_imerologiou_ypologistikan',  v_penalties,
    'periodos_ritras', jsonb_build_object('apo', v_from, 'eos', v_to)
  );

  insert into app.nightly_runs (result, duration_ms)
  values (v_result,
          extract(milliseconds from clock_timestamp() - t0)::int);

  return v_result;
end $$;

comment on function app.run_nightly_jobs() is
  'Νυχτερινή αποτύπωση προθεσμιών ν. 4412/2016: σιωπηρές εγκρίσεις (145 §2, '
  '151 §7, 152, 147 §5), σήμανση υπερημερίας και εκπρόθεσμων σταδίων, '
  'υπολογισμός ρήτρας ημερολογίου (146). Δεν επιβάλλει κυρώσεις.';

revoke all on function app.run_nightly_jobs() from public, anon, authenticated;

-- ---- 3. Χρονοπρογραμματισμός ----------------------------------------
-- Κάθε βράδυ στις 02:15 UTC (≈ 04:15/05:15 ώρα Ελλάδας).
do $sched$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('epivlepsi-nightly');
    exception when others then
      null; -- δεν υπάρχει ακόμη
    end;
    perform cron.schedule('epivlepsi-nightly', '15 2 * * *',
                          'select app.run_nightly_jobs();');
    raise notice 'Η νυχτερινή εργασία προγραμματίστηκε (02:15 UTC).';
  else
    raise notice 'Χωρίς pg_cron: εκτελέστε την app.run_nightly_jobs() από εξωτερικό χρονοπρογραμματιστή.';
  end if;
end $sched$;
