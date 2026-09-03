-- =====================================================================
-- 0015_auth_grants_rpc.sql — Σύνδεση με το Supabase Auth, RPC, δικαιώματα
-- ---------------------------------------------------------------------
--  • ξένο κλειδί profiles → auth.users
--  • αυτόματη δημιουργία profile σε κάθε νέο χρήστη
--  • security_invoker στα views (ώστε να εφαρμόζονται τα RLS του καλούντος)
--  • δημόσια περιτυλίγματα (RPC) των συναρτήσεων του σχήματος app
--  • grants σε authenticated / service_role
-- =====================================================================

-- ---- 1. profiles ↔ auth.users --------------------------------------
alter table public.profiles
  drop constraint if exists profiles_auth_fk;
alter table public.profiles
  add constraint profiles_auth_fk
  foreign key (id) references auth.users (id) on delete cascade;

create or replace function app.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare v_org uuid;
begin
  select id into v_org from public.organizations order by created_at limit 1;
  if v_org is null then return new; end if;
  insert into public.profiles (id, org_id, full_name, email, specialty)
  values (new.id, v_org,
          coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
          new.email, new.raw_user_meta_data->>'specialty')
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.handle_new_user();

-- ---- 2. Views με δικαιώματα του καλούντος ---------------------------
-- Χωρίς security_invoker τα views εκτελούνται με τα δικαιώματα του
-- ιδιοκτήτη τους και παρακάμπτουν τα RLS των υποκείμενων πινάκων.
alter view public.v_ape_limits            set (security_invoker = on);
alter view public.v_deadline_watch        set (security_invoker = on);
alter view public.v_diary_missing_days    set (security_invoker = on);
alter view public.v_hidden_works_alerts   set (security_invoker = on);
alter view public.v_project_financials    set (security_invoker = on);
alter view public.v_stage_board           set (security_invoker = on);

-- ---- 3. RPC περιτυλίγματα ------------------------------------------
-- Το σχήμα app δεν εκτίθεται μέσω PostgREST· εκθέτουμε μόνο ό,τι
-- χρειάζεται το front-end, με ρητό έλεγχο δικαιωμάτων.
create or replace function public.stage_blockers(p_project_stage_id uuid)
returns table (code text, message text, severity text, legal_ref text)
language sql
stable
security definer
set search_path = public, app
as $$
  select b.code, b.message, b.severity, b.legal_ref
  from app.stage_blockers(p_project_stage_id) b
  where exists (select 1 from public.project_stages ps
                where ps.id = p_project_stage_id and app.can_read_project(ps.project_id));
$$;

comment on function public.stage_blockers(uuid) is
  'Εμπόδια μετάβασης ενός σταδίου. SECURITY DEFINER με εσωτερικό έλεγχο app.can_read_project().';

create or replace function public.instantiate_workflow(p_project_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if not app.can_approve(p_project_id) and not app.can_supervise(p_project_id) then
    raise exception 'Δεν έχετε δικαίωμα δημιουργίας ροής για το έργο αυτό.';
  end if;
  return app.instantiate_workflow(p_project_id);
end $$;

comment on function public.instantiate_workflow(uuid) is
  'Δημιουργία στιγμιοτύπου ροής εργασιών για έργο. SECURITY DEFINER με εσωτερικό έλεγχο app.can_approve()/can_supervise().';

-- ---- 4. Δικαιώματα --------------------------------------------------
grant usage on schema public to authenticated, service_role;

grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on all sequences in schema public to authenticated;
grant usage on all sequences in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;

alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant usage, select on sequences to authenticated;

revoke all on function public.stage_blockers(uuid)       from public, anon;
revoke all on function public.instantiate_workflow(uuid) from public, anon;
grant execute on function public.stage_blockers(uuid)       to authenticated, service_role;
grant execute on function public.instantiate_workflow(uuid) to authenticated, service_role;
grant execute on function public.required_audit_count(uuid) to authenticated, service_role;

-- Τα καθαρά αναγνωστικά μητρώα είναι ορατά σε κάθε συνδεδεμένο χρήστη.
grant select on public.legal_refs, public.workflow_stages, public.stage_prerequisites,
                public.stage_tasks, public.stage_documents, public.work_groups
  to authenticated;
