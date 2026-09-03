-- =====================================================================
-- Migration 0012 : Ασφάλεια — Row Level Security & διαχωρισμός ρόλων
--
-- Αρχή: κάθε χρήστης βλέπει μόνο τα έργα στα οποία έχει ρητή ανάθεση,
-- και γράφει μόνο ό,τι του επιτρέπει ο ρόλος του κατά τον ν.4412/2016.
-- Ο ΑΝΑΔΟΧΟΣ έχει «θυρίδα υποβολής»: καταχωρεί τα δικά του, δεν βλέπει
-- εσωτερικά έγγραφα της Υπηρεσίας και δεν τροποποιεί ό,τι έχει υποβάλει.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 12.1 ΒΟΗΘΗΤΙΚΕΣ ΣΥΝΑΡΤΗΣΕΙΣ ΤΑΥΤΟΤΗΤΑΣ
-- ---------------------------------------------------------------------
create or replace function app.uid() returns uuid
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), '')::uuid,
    nullif((nullif(current_setting('request.jwt.claims', true),'')::jsonb ->> 'sub'), '')::uuid
  );
$$;

-- Σύνδεση χρηστών-αναδόχων με την επιχείρησή τους
create table public.contractor_users (
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  contractor_id  uuid not null references public.contractors(id) on delete cascade,
  is_legal_rep   boolean not null default false,
  created_at     timestamptz not null default now(),
  primary key (profile_id, contractor_id)
);

create or replace function app.my_org() returns uuid
language sql stable security definer set search_path = public, app as $$
  select org_id from public.profiles where id = app.uid();
$$;

create or replace function app.is_admin() returns boolean
language sql stable security definer set search_path = public, app as $$
  select exists (select 1 from public.org_roles r
                 where r.profile_id = app.uid()
                   and r.role in ('admin')
                   and (r.valid_to is null or r.valid_to >= current_date));
$$;

-- Καθολικοί ρόλοι υπηρεσίας (βλέπουν όλα τα έργα του φορέα)
create or replace function app.is_service_wide() returns boolean
language sql stable security definer set search_path = public, app as $$
  select exists (select 1 from public.org_roles r
                 where r.profile_id = app.uid()
                   and r.role in ('admin','proistamenos_dy','proistameni_arxi','techniko_symvoulio')
                   and (r.valid_to is null or r.valid_to >= current_date));
$$;

create or replace function app.has_project_role(p_project uuid, p_roles public.role_type[])
returns boolean
language sql stable security definer set search_path = public, app as $$
  select exists (
    select 1
    from public.project_assignments pa
    where pa.project_id = p_project
      and pa.valid_to is null
      and pa.role = any(p_roles)
      and (
        pa.profile_id = app.uid()
        or pa.contractor_id in (select cu.contractor_id
                                from public.contractor_users cu
                                where cu.profile_id = app.uid())
      )
  );
$$;

create or replace function app.is_contractor_of(p_project uuid) returns boolean
language sql stable security definer set search_path = public, app as $$
  select exists (
    select 1 from public.contracts c
    join public.contractor_users cu on cu.contractor_id = c.contractor_id
    where c.project_id = p_project and cu.profile_id = app.uid()
  );
$$;

create or replace function app.can_read_project(p_project uuid) returns boolean
language sql stable security definer set search_path = public, app as $$
  select app.is_admin()
      or (app.is_service_wide()
          and exists (select 1 from public.projects p
                      where p.id = p_project and p.org_id = app.my_org()))
      or app.has_project_role(p_project, array[
           'epivlepon','voithos_epivlepon','syntonistis','ife',
           'epitropi_paralavis','epitropi_timon','theatis',
           'proistamenos_dy','proistameni_arxi']::public.role_type[])
      or app.is_contractor_of(p_project);
$$;

create or replace function app.can_supervise(p_project uuid) returns boolean
language sql stable security definer set search_path = public, app as $$
  select app.is_admin()
      or (app.is_service_wide()
          and exists (select 1 from public.projects p
                      where p.id = p_project and p.org_id = app.my_org()))
      or app.has_project_role(p_project,
           array['epivlepon','voithos_epivlepon','syntonistis','ife']::public.role_type[]);
$$;

create or replace function app.can_approve(p_project uuid) returns boolean
language sql stable security definer set search_path = public, app as $$
  select app.is_admin()
      or app.has_project_role(p_project,
           array['proistamenos_dy','proistameni_arxi']::public.role_type[])
      or (app.is_service_wide()
          and exists (select 1 from public.projects p
                      where p.id = p_project and p.org_id = app.my_org()));
$$;

-- ---------------------------------------------------------------------
-- 12.2 ΠΙΝΑΚΑΣ ΔΙΚΑΙΩΜΑΤΩΝ (τεκμηριώνει τον διαχωρισμό ρόλων)
-- ---------------------------------------------------------------------
create table app.table_access (
  table_name        text primary key,
  contractor_reads  boolean not null default false,
  contractor_writes boolean not null default false,  -- Δικαίωμα υποβολής (INSERT)
  contractor_update text not null default 'none',    -- none | draft_only | full
  supervisor_writes boolean not null default true,
  approver_only     boolean not null default false,  -- Γράφει μόνο ο Προϊστάμενος Δ.Υ.
  note              text,
  constraint ta_upd_chk check (contractor_update in ('none','draft_only','full'))
);

insert into app.table_access
  (table_name, contractor_reads, contractor_writes, contractor_update,
   supervisor_writes, approver_only, note) values
  ('project_stages',        true,  false, 'none',       true,  false, 'Ροή ελέγχου — ο ανάδοχος βλέπει μόνο την πρόοδο'),
  ('project_stage_tasks',   false, false, 'none',       true,  false, 'Εσωτερική λίστα ελέγχου της Υπηρεσίας'),
  ('documents',             true,  true,  'draft_only', true,  false, 'Ο ανάδοχος βλέπει μόνο κοινοποιημένα ή δικά του'),
  ('schedules',             true,  true,  'draft_only', true,  false, 'Άρθρο 145: υποβολή αναδόχου, έγκριση Δ.Υ.'),
  ('schedule_activities',   true,  true,  'full',       true,  false, 'Λεπτομέρειες χρονοδιαγράμματος'),
  ('schedule_periods',      true,  true,  'full',       true,  false, null),
  ('site_organograms',      true,  true,  'full',       true,  false, 'Άρθρο 145 §4'),
  ('diary_entries',         true,  true,  'draft_only', true,  false, 'Άρθρο 146: τηρεί ο ανάδοχος, ελέγχει ο επιβλέπων'),
  ('contractor_staff',      true,  true,  'full',       true,  false, 'Άρθρο 139'),
  ('measurements',          true,  true,  'draft_only', true,  false, 'Άρθρο 151: υποβάλλει ο ανάδοχος με δήλωση αληθείας'),
  ('measurement_lines',     true,  true,  'full',       true,  false, 'Κλειδώνουν μέσω της κατάστασης της επιμέτρησης'),
  ('measurement_audits',    false, false, 'none',       true,  false, 'Δειγματοληπτικός έλεγχος — αμιγώς υπηρεσιακό'),
  ('hidden_work_notices',   true,  true,  'draft_only', true,  false, 'Άρθρο 151 §7'),
  ('hidden_work_photos',    true,  true,  'full',       true,  false, null),
  ('final_measurement',     true,  true,  'draft_only', true,  false, 'Άρθρο 151 §9'),
  ('payment_certificates',  true,  true,  'draft_only', true,  false, 'Άρθρο 152'),
  ('payment_certificate_lines', true, true, 'full',     true,  false, null),
  ('ape',                   true,  false, 'none',       true,  false, 'Άρθρο 156: συντάσσει η υπηρεσία, υπογράφει ο ανάδοχος'),
  ('ape_lines',             true,  false, 'none',       true,  false, null),
  ('new_price_protocols',   true,  false, 'none',       true,  false, 'Άρθρο 156 §5'),
  ('new_price_items',       true,  false, 'none',       true,  false, null),
  ('budget_versions',       true,  false, 'none',       true,  false, null),
  ('budget_items',          true,  false, 'none',       true,  false, null),
  ('guarantees',            true,  false, 'none',       true,  false, 'Άρθρο 72'),
  ('advances',              true,  true,  'draft_only', true,  false, 'Άρθρο 150'),
  ('time_extensions',       true,  true,  'draft_only', true,  false, 'Άρθρο 147: αίτημα αναδόχου'),
  ('suspensions',           true,  true,  'draft_only', true,  false, 'Άρθρο 147 §7'),
  ('penalties',             true,  false, 'none',       false, true,  'Επιβάλλονται από τη Δ.Υ.'),
  ('bonus_clauses',         true,  false, 'none',       false, true,  'Άρθρο 149'),
  ('objections',            true,  true,  'draft_only', false, false, 'Άρθρο 174: ένσταση αναδόχου'),
  ('technical_council_opinions', true, false, 'none',   false, true,  null),
  ('quality_plans',         true,  true,  'draft_only', true,  false, 'Άρθρο 158'),
  ('material_approvals',    true,  true,  'draft_only', true,  false, 'Άρθρο 138 §12'),
  ('lab_tests',             true,  true,  'full',       true,  false, null),
  ('site_inspections',      true,  false, 'none',       true,  false, 'Άρθρο 136 §11'),
  ('quarterly_reports',     true,  true,  'draft_only', true,  false, 'Άρθρο 136 §10 / 138 §17'),
  ('completions',           true,  false, 'none',       true,  false, 'Άρθρο 168'),
  ('defects',               true,  false, 'none',       true,  false, null),
  ('maintenance_periods',   true,  false, 'none',       true,  false, 'Άρθρο 171'),
  ('committees',            true,  false, 'none',       false, true,  'Άρθρο 172'),
  ('acceptances',           true,  false, 'none',       true,  false, 'Άρθρο 172'),
  ('apologistika',          true,  false, 'none',       true,  false, 'Άρθρα 154-155'),
  ('contract_deadlines',    true,  false, 'none',       true,  false, 'Άρθρο 147'),
  ('project_assignments',   true,  false, 'none',       false, true,  'Άρθρο 136 — ορίζει η Δ.Υ.');

comment on table app.table_access is
  'Μητρώο δικαιωμάτων ανά πίνακα. Αποτυπώνει τον ΔΙΑΧΩΡΙΣΜΟ ΡΟΛΩΝ του ν.4412/2016 '
  'και οδηγεί τη δημιουργία των πολιτικών RLS.';

-- ---------------------------------------------------------------------
-- 12.3 ΑΥΤΟΜΑΤΗ ΠΑΡΑΓΩΓΗ ΠΟΛΙΤΙΚΩΝ ΓΙΑ ΠΙΝΑΚΕΣ ΜΕ project_id
-- ---------------------------------------------------------------------
do $$
declare
  t          record;
  v_read     text;
  v_service  text;
  v_insert   text;
  v_update   text;
  v_lock     text;
  v_cand     text;
begin
  for t in select * from app.table_access loop
    -- Ο πίνακας πρέπει να υπάρχει και να έχει στήλη project_id
    if not exists (select 1 from information_schema.columns
                   where table_schema='public' and table_name=t.table_name
                     and column_name='project_id') then
      continue;
    end if;

    execute format('alter table public.%I enable row level security', t.table_name);

    v_read := case when t.contractor_reads
                   then 'app.can_read_project(project_id)'
                   else '(app.can_supervise(project_id) or app.can_approve(project_id))' end;

    -- Δικαίωμα γραφής της Υπηρεσίας
    v_service := case
                   when t.approver_only     then 'app.can_approve(project_id)'
                   when t.supervisor_writes then '(app.can_supervise(project_id) or app.can_approve(project_id))'
                   else 'app.can_approve(project_id)' end;

    v_insert := v_service;
    if t.contractor_writes then
      v_insert := v_insert || ' or app.is_contractor_of(project_id)';
    end if;

    v_update := v_service;
    if t.contractor_update = 'full' then
      v_update := v_update || ' or app.is_contractor_of(project_id)';
    end if;

    execute format('create policy %I on public.%I for select using (%s)',
                   t.table_name || '_sel', t.table_name, v_read);
    execute format('create policy %I on public.%I for insert with check (%s)',
                   t.table_name || '_ins', t.table_name, v_insert);
    execute format('create policy %I on public.%I for update using (%s) with check (%s)',
                   t.table_name || '_upd', t.table_name, v_update, v_update);
    execute format('create policy %I on public.%I for delete using (app.is_admin())',
                   t.table_name || '_del', t.table_name);

    -- Ο ανάδοχος διορθώνει ΜΟΝΟ όσο η εγγραφή είναι σε κατάσταση 'draft'.
    -- Μετά την υποβολή, το περιεχόμενο κλειδώνει (ιχνηλασιμότητα υποβολών).
    if t.contractor_update = 'draft_only' then
      v_lock := null;
      foreach v_cand in array array['status','submitted_at','filed_at',
                                    'decided_at','approved_at','requested_at'] loop
        if exists (select 1 from information_schema.columns
                   where table_schema='public' and table_name=t.table_name
                     and column_name=v_cand) then
          v_lock := v_cand;
          exit;
        end if;
      end loop;

      if v_lock = 'status' then
        execute format(
          'create policy %I on public.%I for update
             using (app.is_contractor_of(project_id) and status::text = %L)
             with check (app.is_contractor_of(project_id)
                         and status::text in (%L, %L))',
          t.table_name || '_contractor_upd', t.table_name, 'draft', 'draft', 'submitted');
      elsif v_lock is not null then
        execute format(
          'create policy %I on public.%I for update
             using (app.is_contractor_of(project_id) and %I is null)
             with check (app.is_contractor_of(project_id))',
          t.table_name || '_contractor_upd', t.table_name, v_lock);
      end if;
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 12.4 ΕΙΔΙΚΕΣ ΠΟΛΙΤΙΚΕΣ
-- ---------------------------------------------------------------------

-- Έργα & συμβάσεις
alter table public.projects  enable row level security;
alter table public.contracts enable row level security;

create policy projects_sel on public.projects for select
  using (app.can_read_project(id));
create policy projects_ins on public.projects for insert
  with check (app.is_service_wide() and org_id = app.my_org());
create policy projects_upd on public.projects for update
  using (app.can_approve(id) or app.can_supervise(id))
  with check (app.can_approve(id) or app.can_supervise(id));
create policy projects_del on public.projects for delete using (app.is_admin());

create policy contracts_sel on public.contracts for select
  using (app.can_read_project(project_id));
create policy contracts_ins on public.contracts for insert
  with check (app.can_approve(project_id) or app.can_supervise(project_id));
create policy contracts_upd on public.contracts for update
  using (app.can_approve(project_id)) with check (app.can_approve(project_id));

comment on policy contracts_upd on public.contracts is
  'Η τροποποίηση των στοιχείων σύμβασης (ποσά, προθεσμίες) ανήκει στον '
  'Προϊστάμενο της Διευθύνουσας Υπηρεσίας, όχι στον επιβλέποντα.';

-- Έγγραφα: ο ανάδοχος βλέπει μόνο όσα του έχουν κοινοποιηθεί ή υπέβαλε ο ίδιος
drop policy if exists documents_sel on public.documents;
create policy documents_sel on public.documents for select
  using (
    app.can_supervise(project_id) or app.can_approve(project_id)
    or (app.is_contractor_of(project_id) and (
          status in ('communicated','approved','deemed_approved')
          or exists (select 1 from public.document_communications dc
                     where dc.document_id = documents.id
                       and dc.recipient_party = 'anadochos')
          or created_by = app.uid()))
  );

-- Προφίλ & φορείς
alter table public.profiles enable row level security;
create policy profiles_sel on public.profiles for select
  using (id = app.uid() or org_id = app.my_org());
create policy profiles_upd on public.profiles for update
  using (id = app.uid() or app.is_admin()) with check (id = app.uid() or app.is_admin());

alter table public.organizations enable row level security;
create policy organizations_sel on public.organizations for select
  using (id = app.my_org());
create policy organizations_upd on public.organizations for update
  using (app.is_admin()) with check (app.is_admin());

alter table public.contractors enable row level security;
create policy contractors_sel on public.contractors for select
  using (org_id = app.my_org()
         or id in (select contractor_id from public.contractor_users
                   where profile_id = app.uid()));
create policy contractors_ins on public.contractors for insert
  with check (app.is_service_wide() and org_id = app.my_org());
create policy contractors_upd on public.contractors for update
  using (app.is_service_wide() and org_id = app.my_org())
  with check (app.is_service_wide() and org_id = app.my_org());

alter table public.contractor_users enable row level security;
create policy contractor_users_sel on public.contractor_users for select
  using (profile_id = app.uid() or app.is_service_wide());
create policy contractor_users_mod on public.contractor_users for all
  using (app.is_admin()) with check (app.is_admin());

alter table public.org_roles enable row level security;
create policy org_roles_sel on public.org_roles for select
  using (profile_id = app.uid() or app.is_service_wide());
create policy org_roles_mod on public.org_roles for all
  using (app.is_admin()) with check (app.is_admin());

-- Θυγατρικοί πίνακες χωρίς project_id — κληρονομούν από τον γονέα
alter table public.committee_members enable row level security;
create policy committee_members_sel on public.committee_members for select
  using (exists (select 1 from public.committees c
                 where c.id = committee_id and app.can_read_project(c.project_id)));
create policy committee_members_mod on public.committee_members for all
  using (exists (select 1 from public.committees c
                 where c.id = committee_id and app.can_approve(c.project_id)))
  with check (exists (select 1 from public.committees c
                 where c.id = committee_id and app.can_approve(c.project_id)));

alter table public.document_signatures enable row level security;
create policy document_signatures_sel on public.document_signatures for select
  using (exists (select 1 from public.documents d
                 where d.id = document_id and app.can_read_project(d.project_id)));
create policy document_signatures_ins on public.document_signatures for insert
  with check (exists (select 1 from public.documents d
                 where d.id = document_id and app.can_read_project(d.project_id)));

alter table public.document_communications enable row level security;
create policy document_communications_sel on public.document_communications for select
  using (exists (select 1 from public.documents d
                 where d.id = document_id and app.can_read_project(d.project_id)));
create policy document_communications_mod on public.document_communications for all
  using (exists (select 1 from public.documents d
                 where d.id = document_id and app.can_supervise(d.project_id)))
  with check (exists (select 1 from public.documents d
                 where d.id = document_id and app.can_supervise(d.project_id)));

alter table public.guarantee_events enable row level security;
create policy guarantee_events_sel on public.guarantee_events for select
  using (exists (select 1 from public.guarantees g
                 where g.id = guarantee_id and app.can_read_project(g.project_id)));
create policy guarantee_events_ins on public.guarantee_events for insert
  with check (exists (select 1 from public.guarantees g
                 where g.id = guarantee_id and app.can_approve(g.project_id)));

comment on policy guarantee_events_ins on public.guarantee_events is
  'Η μείωση/αποδέσμευση εγγύησης είναι πράξη της Διευθύνουσας Υπηρεσίας.';

-- ---------------------------------------------------------------------
-- 12.5 AUDIT LOG — μόνο ανάγνωση & προσθήκη, ποτέ μεταβολή/διαγραφή
-- ---------------------------------------------------------------------
alter table public.audit_log enable row level security;
create policy audit_sel on public.audit_log for select
  using (app.is_service_wide()
         or (project_id is not null and app.can_supervise(project_id)));
create policy audit_ins on public.audit_log for insert with check (true);
revoke update, delete on public.audit_log from public;

-- Κατάλογοι (ανάγνωση για όλους τους πιστοποιημένους χρήστες)
alter table public.legal_refs        enable row level security;
alter table public.work_groups       enable row level security;
alter table public.workflow_stages   enable row level security;
alter table public.stage_tasks       enable row level security;
alter table public.stage_prerequisites enable row level security;
alter table public.stage_documents   enable row level security;
alter table public.document_templates enable row level security;
alter table public.template_fields   enable row level security;

create policy legal_refs_sel  on public.legal_refs  for select using (true);
create policy work_groups_sel on public.work_groups for select using (true);
create policy stages_sel      on public.workflow_stages for select using (true);
create policy stage_tasks_sel on public.stage_tasks for select using (true);
create policy stage_prereq_sel on public.stage_prerequisites for select using (true);
create policy stage_docs_sel  on public.stage_documents for select using (true);
create policy templates_sel   on public.document_templates for select
  using (org_id is null or org_id = app.my_org());
create policy templates_mod   on public.document_templates for all
  using (app.is_service_wide() and org_id = app.my_org())
  with check (app.is_service_wide() and org_id = app.my_org());
create policy template_fields_sel on public.template_fields for select using (true);

-- ---------------------------------------------------------------------
-- 12.6 ΓΕΝΙΚΟΣ AUDIT TRIGGER
-- ---------------------------------------------------------------------
create or replace function app.audit_row()
returns trigger language plpgsql security definer set search_path = public, app as $$
declare v_pid uuid;
begin
  begin
    v_pid := (coalesce(to_jsonb(new), to_jsonb(old)) ->> 'project_id')::uuid;
  exception when others then v_pid := null;
  end;

  insert into public.audit_log
    (actor_id, table_name, record_id, action, project_id, old_data, new_data)
  values (app.uid(), tg_table_name,
          coalesce((to_jsonb(new)->>'id'), (to_jsonb(old)->>'id')),
          lower(tg_op)::public.audit_action, v_pid,
          case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'contracts','project_stages','measurements','hidden_work_notices',
    'payment_certificates','ape','guarantees','guarantee_events',
    'completions','acceptances','time_extensions','penalties','objections',
    'final_measurement','documents']
  loop
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on public.%1$I
       for each row execute function app.audit_row()', t);
  end loop;
end $$;
