-- =====================================================================
-- 0016_rls_child_tables_hardening.sql — Θωράκιση RLS θυγατρικών πινάκων
-- ---------------------------------------------------------------------
-- Ο γεννήτορας πολιτικών του 0012 παρακάμπτει τους πίνακες που ΔΕΝ έχουν
-- στήλη project_id. Έτσι δέκα θυγατρικοί πίνακες έμεναν ΧΩΡΙΣ RLS —
-- σοβαρό κενό: μέσω PostgREST ήταν αναγνώσιμοι από κάθε συνδεδεμένο
-- χρήστη. Εδώ ενεργοποιείται RLS και ορίζονται πολιτικές που αντλούν το
-- δικαίωμα από τον γονικό πίνακα.
--
-- Επιπλέον:
--  • καθηλώνεται το search_path σε όλες τις SECURITY DEFINER συναρτήσεις
--    (προστασία από search_path hijacking)
--  • αφαιρείται το δικαίωμα εκτέλεσης των RPC από τον ρόλο anon
--  • οι επεκτάσεις μεταφέρονται εκτός του σχήματος public
-- =====================================================================

-- ---- 1. Ενεργοποίηση RLS -------------------------------------------
alter table public.private_supervisors        enable row level security;
alter table public.new_price_items            enable row level security;
alter table public.schedule_activities        enable row level security;
alter table public.schedule_periods           enable row level security;
alter table public.measurement_audits         enable row level security;
alter table public.measurement_lines          enable row level security;
alter table public.ape_lines                  enable row level security;
alter table public.hidden_work_photos         enable row level security;
alter table public.payment_certificate_lines  enable row level security;
alter table public.project_stage_tasks        enable row level security;

-- ---- 2. Πολιτικές αντλούμενες από τον γονέα -------------------------

-- private_supervisors: μητρώο Ι.Φ.Ε. — ανάγνωση από κάθε χρήστη της
-- υπηρεσίας, μεταβολή μόνο από τη Δ.Υ./Προϊσταμένη Αρχή.
drop policy if exists ps_sel on public.private_supervisors;
create policy ps_sel on public.private_supervisors
  for select using (app.uid() is not null);
drop policy if exists ps_mod on public.private_supervisors;
create policy ps_mod on public.private_supervisors
  for all using (app.is_service_wide());

-- new_price_items → new_price_protocols
drop policy if exists npi_sel on public.new_price_items;
create policy npi_sel on public.new_price_items
  for select using (exists (select 1 from public.new_price_protocols p
    where p.id = new_price_items.protocol_id and app.can_read_project(p.project_id)));
drop policy if exists npi_mod on public.new_price_items;
create policy npi_mod on public.new_price_items
  for all using (exists (select 1 from public.new_price_protocols p
    where p.id = new_price_items.protocol_id
      and (app.can_supervise(p.project_id) or app.can_approve(p.project_id))));

-- schedule_activities → schedules  (ο ανάδοχος συντάσσει το χρονοδιάγραμμα)
drop policy if exists sa_sel on public.schedule_activities;
create policy sa_sel on public.schedule_activities
  for select using (exists (select 1 from public.schedules s
    where s.id = schedule_activities.schedule_id and app.can_read_project(s.project_id)));
drop policy if exists sa_mod on public.schedule_activities;
create policy sa_mod on public.schedule_activities
  for all using (exists (select 1 from public.schedules s
    where s.id = schedule_activities.schedule_id
      and (app.can_supervise(s.project_id) or app.can_approve(s.project_id)
           or app.is_contractor_of(s.project_id))));

-- schedule_periods → schedules
drop policy if exists sp_sel on public.schedule_periods;
create policy sp_sel on public.schedule_periods
  for select using (exists (select 1 from public.schedules s
    where s.id = schedule_periods.schedule_id and app.can_read_project(s.project_id)));
drop policy if exists sp_mod on public.schedule_periods;
create policy sp_mod on public.schedule_periods
  for all using (exists (select 1 from public.schedules s
    where s.id = schedule_periods.schedule_id
      and (app.can_supervise(s.project_id) or app.can_approve(s.project_id)
           or app.is_contractor_of(s.project_id))));

-- measurement_audits → measurements
-- Ο δειγματοληπτικός έλεγχος (άρθρο 151 §3) δεν είναι ορατός στον ανάδοχο.
drop policy if exists ma_sel on public.measurement_audits;
create policy ma_sel on public.measurement_audits
  for select using (exists (select 1 from public.measurements m
    where m.id = measurement_audits.measurement_id
      and (app.can_supervise(m.project_id) or app.can_approve(m.project_id))));
drop policy if exists ma_mod on public.measurement_audits;
create policy ma_mod on public.measurement_audits
  for all using (exists (select 1 from public.measurements m
    where m.id = measurement_audits.measurement_id
      and (app.can_supervise(m.project_id) or app.can_approve(m.project_id))));

-- measurement_lines → measurements
-- Ο ανάδοχος συντάσσει την επιμέτρηση, αλλά μόνο όσο είναι σε 'draft'.
drop policy if exists ml_sel on public.measurement_lines;
create policy ml_sel on public.measurement_lines
  for select using (exists (select 1 from public.measurements m
    where m.id = measurement_lines.measurement_id and app.can_read_project(m.project_id)));
drop policy if exists ml_mod on public.measurement_lines;
create policy ml_mod on public.measurement_lines
  for all using (exists (select 1 from public.measurements m
    where m.id = measurement_lines.measurement_id
      and (app.can_supervise(m.project_id) or app.can_approve(m.project_id)
           or (app.is_contractor_of(m.project_id) and m.status = 'draft'))));

-- ape_lines → ape
drop policy if exists al_sel on public.ape_lines;
create policy al_sel on public.ape_lines
  for select using (exists (select 1 from public.ape a
    where a.id = ape_lines.ape_id and app.can_read_project(a.project_id)));
drop policy if exists al_mod on public.ape_lines;
create policy al_mod on public.ape_lines
  for all using (exists (select 1 from public.ape a
    where a.id = ape_lines.ape_id
      and (app.can_supervise(a.project_id) or app.can_approve(a.project_id))));

-- hidden_work_photos → hidden_work_notices
-- Ο ανάδοχος ανεβάζει τις ψηφιακές φωτογραφίες (άρθρο 151 §7).
drop policy if exists hwp_sel on public.hidden_work_photos;
create policy hwp_sel on public.hidden_work_photos
  for select using (exists (select 1 from public.hidden_work_notices h
    where h.id = hidden_work_photos.notice_id and app.can_read_project(h.project_id)));
drop policy if exists hwp_mod on public.hidden_work_photos;
create policy hwp_mod on public.hidden_work_photos
  for all using (exists (select 1 from public.hidden_work_notices h
    where h.id = hidden_work_photos.notice_id
      and (app.can_supervise(h.project_id) or app.can_approve(h.project_id)
           or app.is_contractor_of(h.project_id))));

-- payment_certificate_lines → payment_certificates
drop policy if exists pcl_sel on public.payment_certificate_lines;
create policy pcl_sel on public.payment_certificate_lines
  for select using (exists (select 1 from public.payment_certificates p
    where p.id = payment_certificate_lines.certificate_id and app.can_read_project(p.project_id)));
drop policy if exists pcl_mod on public.payment_certificate_lines;
create policy pcl_mod on public.payment_certificate_lines
  for all using (exists (select 1 from public.payment_certificates p
    where p.id = payment_certificate_lines.certificate_id
      and (app.can_supervise(p.project_id) or app.can_approve(p.project_id)
           or (app.is_contractor_of(p.project_id) and p.status = 'draft'))));

-- project_stage_tasks → project_stages
-- Οι εσωτερικές εργασίες του οδηγού δεν είναι ορατές στον ανάδοχο.
drop policy if exists pst_sel on public.project_stage_tasks;
create policy pst_sel on public.project_stage_tasks
  for select using (exists (select 1 from public.project_stages ps
    where ps.id = project_stage_tasks.project_stage_id
      and (app.can_supervise(ps.project_id) or app.can_approve(ps.project_id))));
drop policy if exists pst_mod on public.project_stage_tasks;
create policy pst_mod on public.project_stage_tasks
  for all using (exists (select 1 from public.project_stages ps
    where ps.id = project_stage_tasks.project_stage_id
      and (app.can_supervise(ps.project_id) or app.can_approve(ps.project_id))));

-- ---- 3. Καθήλωση search_path στις SECURITY DEFINER συναρτήσεις ------
do $$
declare r record;
begin
  for r in
    select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as args
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('app','public')
       and p.prokind = 'f'
       and not exists (select 1 from unnest(coalesce(p.proconfig,'{}')) c
                        where c like 'search_path=%')
  loop
    execute format('alter function %I.%I(%s) set search_path = public, app',
                   r.nspname, r.proname, r.args);
  end loop;
end $$;

-- ---- 4. Αφαίρεση δικαιωμάτων από τον ρόλο anon ----------------------
revoke execute on function public.stage_blockers(uuid)       from anon;
revoke execute on function public.instantiate_workflow(uuid) from anon;
revoke execute on function public.required_audit_count(uuid) from anon;
revoke all on all tables in schema public from anon;

-- ---- 5. Επεκτάσεις εκτός του σχήματος public ------------------------
create schema if not exists extensions;
alter extension btree_gist set schema extensions;
alter extension unaccent   set schema extensions;
