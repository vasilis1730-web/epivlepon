-- =====================================================================
-- Migration 0005 : ΜΗΧΑΝΗ ΡΟΗΣ (Workflow Engine) — Fail-Safe λειτουργία
--
-- Αρχή σχεδίασης: κάθε στάδιο είναι ΠΡΟΑΠΑΙΤΟΥΜΕΝΟ (checkpoint) του επομένου.
-- Κανένα στάδιο δεν κλείνει αν δεν ικανοποιηθούν:
--   (α) τα προαπαιτούμενα στάδια,
--   (β) όλες οι υποχρεωτικές ενέργειες της λίστας ελέγχου,
--   (γ) όλα τα υποχρεωτικά έγγραφα (συνημμένα/παραχθέντα),
--   (δ) ο ειδικός κανόνας ελέγχου (guard function) του σταδίου.
-- Παράκαμψη επιτρέπεται ΜΟΝΟ σε προϊστάμενο Δ.Υ., με υποχρεωτική
-- αιτιολόγηση, και καταγράφεται ανεξίτηλα στο audit_log.
-- =====================================================================

create type app.blocker as (
  code       text,
  message    text,
  severity   text,     -- 'hard' = απαγορευτικό, 'soft' = προειδοποίηση
  legal_ref  text
);

-- ---------------------------------------------------------------------
-- 5.1 ΚΑΤΑΛΟΓΟΣ ΣΤΑΔΙΩΝ (πρότυπη ροή — seed στο 0013)
-- ---------------------------------------------------------------------
create table public.workflow_stages (
  code             text primary key,                   -- 'S06_XRONODIAGRAMMA'
  phase            public.stage_phase not null,
  ordinal          integer not null unique,
  title            text not null,
  purpose          text not null,                      -- Τι επιτυγχάνεται στο στάδιο
  responsible      public.party_type not null,         -- Ποιος έχει την πρωτοβουλία
  approver         public.party_type,                  -- Ποιος εγκρίνει
  recurrence       public.recurrence_type not null default 'once',
  legal_ref_id     text references public.legal_refs(id),
  extra_legal_refs text[],
  deadline_days    integer,                            -- Προθεσμία σε ημέρες
  deadline_months  integer,                            -- ή σε μήνες
  deadline_basis   public.deadline_basis,
  deadline_is_working_days boolean not null default false,
  tacit_approval   boolean not null default false,     -- Σιωπηρή έγκριση αν παρέλθει άπρακτη
  tacit_effect     text,                               -- Τι επέρχεται σιωπηρά
  applies_when     jsonb,                              -- Συνθήκη εφαρμογής (βλ. app.stage_applies)
  guard_fn         text,                               -- Ειδικός κανόνας ελέγχου
  risk_note        text,                               -- Τι διακυβεύεται αν παραλειφθεί
  is_mandatory     boolean not null default true,
  created_at       timestamptz not null default now()
);

comment on table public.workflow_stages is
  'Πρότυπος οδηγός επίβλεψης: 35 στάδια από την υπογραφή της σύμβασης έως την '
  'παραλαβή. Κάθε στάδιο φέρει υποχρεωτική νομική παραπομπή.';

-- Προαπαιτούμενα (κατευθυνόμενος άκυκλος γράφος)
create table public.stage_prerequisites (
  stage_code       text not null references public.workflow_stages(code) on delete cascade,
  requires_code    text not null references public.workflow_stages(code) on delete cascade,
  is_hard          boolean not null default true,      -- false = προειδοποίηση μόνο
  rationale        text,
  primary key (stage_code, requires_code),
  constraint sp_no_self check (stage_code <> requires_code)
);

-- Λίστα ελέγχου ενεργειών ανά στάδιο — ΔΙΑΧΩΡΙΣΜΟΣ ΡΟΛΩΝ
create table public.stage_tasks (
  id               bigint generated always as identity primary key,
  stage_code       text not null references public.workflow_stages(code) on delete cascade,
  ordinal          integer not null,
  party            public.party_type not null,         -- Ανάδοχος ή Επιβλέπων ή Δ.Υ. ...
  title            text not null,
  detail           text,
  legal_ref_id     text references public.legal_refs(id),
  is_mandatory     boolean not null default true,
  needs_evidence   boolean not null default false,     -- Απαιτεί συνημμένο τεκμήριο
  unique (stage_code, ordinal)
);

comment on table public.stage_tasks is
  'Ενέργειες ανά στάδιο, διακριτά ανά υπόχρεο μέρος: τι κάνει ο ΑΝΑΔΟΧΟΣ και '
  'τι ελέγχει/συντάσσει ο ΕΠΙΒΛΕΠΩΝ ή η ΔΙΕΥΘΥΝΟΥΣΑ ΥΠΗΡΕΣΙΑ.';

-- Υποχρεωτικά έγγραφα ανά στάδιο (συνδέονται με πρότυπα στο 0006)
create table public.stage_documents (
  id               bigint generated always as identity primary key,
  stage_code       text not null references public.workflow_stages(code) on delete cascade,
  doc_code         text not null,                      -- 'BEBAIOSI_PERATOSIS'
  title            text not null,
  produced_by      public.party_type not null,
  is_mandatory     boolean not null default true,
  legal_ref_id     text references public.legal_refs(id),
  unique (stage_code, doc_code)
);

-- ---------------------------------------------------------------------
-- 5.2 ΣΤΙΓΜΙΟΤΥΠΑ ΑΝΑ ΕΡΓΟ
-- ---------------------------------------------------------------------
create table public.project_stages (
  id               uuid primary key default gen_random_uuid(),
  project_id       uuid not null references public.projects(id) on delete cascade,
  stage_code       text not null references public.workflow_stages(code) on delete restrict,
  cycle_no         integer not null default 1,         -- Για επαναλαμβανόμενα στάδια
  status           public.stage_status not null default 'locked',
  due_date         date,
  started_at       timestamptz,
  completed_at     timestamptz,
  completed_by     uuid references public.profiles(id),
  na_reason        text,                               -- Αιτιολόγηση 'not_applicable'
  override_by      uuid references public.profiles(id),-- Παράκαμψη κλειδώματος
  override_reason  text,
  override_at      timestamptz,
  notes            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (project_id, stage_code, cycle_no),
  constraint ps_na_chk check (status <> 'not_applicable' or na_reason is not null),
  constraint ps_override_chk check (override_by is null or override_reason is not null)
);

create index project_stages_project_idx on public.project_stages (project_id, status);
create index project_stages_due_idx     on public.project_stages (due_date)
  where status in ('available','in_progress','pending_approval');

create trigger trg_project_stages_touch
  before update on public.project_stages
  for each row execute function app.touch_updated_at();

create table public.project_stage_tasks (
  id               uuid primary key default gen_random_uuid(),
  project_stage_id uuid not null references public.project_stages(id) on delete cascade,
  stage_task_id    bigint not null references public.stage_tasks(id) on delete restrict,
  is_done          boolean not null default false,
  done_at          timestamptz,
  done_by          uuid references public.profiles(id),
  evidence_doc_id  uuid,                               -- FK ορίζεται στο 0006
  waived           boolean not null default false,
  waive_reason     text,
  notes            text,
  unique (project_stage_id, stage_task_id),
  constraint pst_waive_chk check (not waived or waive_reason is not null)
);

-- ---------------------------------------------------------------------
-- 5.3 ΣΥΝΑΡΤΗΣΕΙΣ ΜΗΧΑΝΗΣ
-- ---------------------------------------------------------------------

-- Εφαρμοσιμότητα σταδίου βάσει χαρακτηριστικών της σύμβασης
create or replace function app.stage_applies(p_project_id uuid, p_stage_code text)
returns boolean
language plpgsql stable as $$
declare
  v_cond jsonb;
  v_ctx  jsonb;
begin
  select applies_when into v_cond from public.workflow_stages where code = p_stage_code;
  if v_cond is null then
    return true;
  end if;

  select to_jsonb(t) into v_ctx from (
    select c.regime::text            as regime,
           c.supervision_mode::text  as supervision_mode,
           c.diary_mode::text        as diary_mode,
           c.has_prim_clause         as has_prim_clause,
           c.initial_value_net       as initial_value_net,
           p.category::text          as category
    from public.contracts c
    join public.projects  p on p.id = c.project_id
    where c.project_id = p_project_id
  ) t;

  if v_ctx is null then
    return true;                              -- Δεν έχει καταχωρηθεί σύμβαση ακόμη
  end if;

  -- Απλός μηχανισμός: {"key": value} ή {"key": {"gte": n}} / {"in": [...]}
  return (
    select bool_and(
      case
        when jsonb_typeof(value) = 'object' and value ? 'gte'
          then (v_ctx->>key)::numeric >= (value->>'gte')::numeric
        when jsonb_typeof(value) = 'object' and value ? 'lt'
          then (v_ctx->>key)::numeric <  (value->>'lt')::numeric
        when jsonb_typeof(value) = 'object' and value ? 'in'
          then (v_ctx->>key) in (select jsonb_array_elements_text(value->'in'))
        else (v_ctx->>key) = trim(both '"' from value::text)
      end)
    from jsonb_each(v_cond)
  );
end $$;

-- Υπολογισμός ημερομηνίας λήξης προθεσμίας σταδίου
create or replace function app.compute_stage_due(p_project_id uuid, p_stage_code text)
returns date
language plpgsql stable as $$
declare
  s        public.workflow_stages%rowtype;
  v_base   date;
  v_result date;
begin
  select * into s from public.workflow_stages where code = p_stage_code;
  if s.deadline_days is null and s.deadline_months is null then
    return null;
  end if;

  select case s.deadline_basis
           when 'ypografi_symvasis'  then c.signed_at
           when 'lixi_prothesmias'   then c.current_end_date
           when 'enarxi_ergasion'    then c.works_start_deadline
           else c.signed_at
         end
    into v_base
  from public.contracts c where c.project_id = p_project_id;

  if v_base is null then
    return null;
  end if;

  v_result := v_base;
  if s.deadline_months is not null then
    v_result := v_result + (s.deadline_months || ' months')::interval;
  end if;
  if s.deadline_days is not null then
    v_result := v_result + s.deadline_days;
  end if;
  return v_result;
end $$;

-- Δημιουργία στιγμιοτύπων ροής για νέο έργο
create or replace function app.instantiate_workflow(p_project_id uuid)
returns integer
language plpgsql security definer set search_path = public, app as $$
declare
  v_count integer := 0;
  r       record;
  v_ps_id uuid;
begin
  for r in select * from public.workflow_stages order by ordinal loop
    if not app.stage_applies(p_project_id, r.code) then
      continue;
    end if;

    insert into public.project_stages (project_id, stage_code, cycle_no, status, due_date)
    values (p_project_id, r.code, 1, 'locked',
            app.compute_stage_due(p_project_id, r.code))
    on conflict (project_id, stage_code, cycle_no) do nothing
    returning id into v_ps_id;

    if v_ps_id is not null then
      insert into public.project_stage_tasks (project_stage_id, stage_task_id)
      select v_ps_id, st.id from public.stage_tasks st where st.stage_code = r.code;
      v_count := v_count + 1;
    end if;
    v_ps_id := null;
  end loop;

  perform app.recompute_availability(p_project_id);
  return v_count;
end $$;

-- Εντοπισμός εμποδίων ολοκλήρωσης ενός σταδίου
create or replace function app.stage_blockers(p_project_stage_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare
  ps       public.project_stages%rowtype;
  ws       public.workflow_stages%rowtype;
  v_sql    text;
begin
  select * into ps from public.project_stages where id = p_project_stage_id;
  if not found then
    return;
  end if;
  select * into ws from public.workflow_stages where code = ps.stage_code;

  -- (α) Προαπαιτούμενα στάδια
  return query
    select 'PREREQ_' || sp.requires_code,
           format('Εκκρεμεί το προαπαιτούμενο στάδιο «%s».', w2.title),
           case when sp.is_hard then 'hard' else 'soft' end,
           coalesce(w2.legal_ref_id, '')
    from public.stage_prerequisites sp
    join public.workflow_stages w2 on w2.code = sp.requires_code
    left join public.project_stages ps2
           on ps2.project_id = ps.project_id
          and ps2.stage_code = sp.requires_code
          and ps2.cycle_no = 1
    where sp.stage_code = ps.stage_code
      and coalesce(ps2.status, 'locked') not in ('completed','not_applicable');

  -- (β) Υποχρεωτικές ενέργειες λίστας ελέγχου
  return query
    select 'TASK_' || st.id::text,
           format('Εκκρεμής υποχρεωτική ενέργεια (%s): %s',
                  app.party_label(st.party), st.title),
           'hard',
           coalesce(st.legal_ref_id, '')
    from public.project_stage_tasks pst
    join public.stage_tasks st on st.id = pst.stage_task_id
    where pst.project_stage_id = p_project_stage_id
      and st.is_mandatory
      and not pst.is_done
      and not pst.waived;

  -- (γ) Τεκμήρια που απαιτούνται αλλά λείπουν
  return query
    select 'EVIDENCE_' || st.id::text,
           format('Απαιτείται συνημμένο τεκμήριο για την ενέργεια: %s', st.title),
           'hard',
           coalesce(st.legal_ref_id, '')
    from public.project_stage_tasks pst
    join public.stage_tasks st on st.id = pst.stage_task_id
    where pst.project_stage_id = p_project_stage_id
      and st.needs_evidence
      and pst.is_done
      and pst.evidence_doc_id is null
      and not pst.waived;

  -- (δ) Υποχρεωτικά έγγραφα του σταδίου (ορίζεται στο 0006)
  return query select * from app.guard_required_documents(p_project_stage_id);

  -- (ε) Ειδικός κανόνας του σταδίου
  if ws.guard_fn is not null then
    v_sql := format('select code, message, severity, legal_ref from %s($1)', ws.guard_fn);
    return query execute v_sql using p_project_stage_id;
  end if;
end $$;

create or replace function app.party_label(p public.party_type)
returns text language sql immutable as $$
  select case p
    when 'anadochos'             then 'Ανάδοχος'
    when 'epivlepon'             then 'Επιβλέπων'
    when 'dieuthynousa_ypiresia' then 'Διευθύνουσα Υπηρεσία'
    when 'proistameni_arxi'      then 'Προϊσταμένη Αρχή'
    when 'techniko_symvoulio'    then 'Τεχνικό Συμβούλιο'
    when 'epitropi'              then 'Επιτροπή'
    when 'ife'                   then 'Ιδιωτικός Φορέας Επίβλεψης'
    when 'kyrios_ergou'          then 'Κύριος του Έργου'
  end $$;

-- Επανυπολογισμός: ποια στάδια ξεκλειδώνουν
create or replace function app.recompute_availability(p_project_id uuid)
returns void
language plpgsql security definer set search_path = public, app as $$
declare
  r record;
  v_hard integer;
begin
  for r in
    select ps.* from public.project_stages ps
    where ps.project_id = p_project_id
      and ps.status in ('locked','available')
    order by (select ordinal from public.workflow_stages w where w.code = ps.stage_code)
  loop
    select count(*) into v_hard
    from app.stage_blockers(r.id) b
    where b.severity = 'hard' and b.code like 'PREREQ%';

    if v_hard = 0 and r.status = 'locked' then
      update public.project_stages set status = 'available' where id = r.id;
    elsif v_hard > 0 and r.status = 'available' then
      update public.project_stages set status = 'locked' where id = r.id;
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5.4 TRIGGER FAIL-SAFE — απαγορεύει το κλείσιμο σταδίου με εκκρεμότητες
-- ---------------------------------------------------------------------
create or replace function app.guard_stage_transition()
returns trigger
language plpgsql security definer set search_path = public, app as $$
declare
  v_blockers text;
  v_is_head  boolean;
begin
  if new.status = old.status then
    return new;
  end if;

  -- Παράκαμψη: μόνο προϊστάμενος Δ.Υ. / Προϊσταμένη Αρχή, με αιτιολόγηση
  if new.override_by is not null and new.override_by is distinct from old.override_by then
    select exists (
      select 1 from public.project_assignments pa
      where pa.project_id = new.project_id
        and pa.profile_id = new.override_by
        and pa.role in ('proistamenos_dy','proistameni_arxi','admin')
        and pa.valid_to is null
    ) into v_is_head;

    if not v_is_head then
      raise exception
        'Η παράκαμψη κλειδώματος επιτρέπεται μόνο στον Προϊστάμενο της Διευθύνουσας Υπηρεσίας ή στην Προϊσταμένη Αρχή.';
    end if;

    insert into public.audit_log
      (actor_id, table_name, record_id, action, project_id, old_data, new_data, reason)
    values (new.override_by, 'project_stages', new.id::text, 'lock_override',
            new.project_id, to_jsonb(old), to_jsonb(new), new.override_reason);

    new.override_at := now();
    return new;
  end if;

  if new.status in ('in_progress','pending_approval','completed') then
    select string_agg('• ' || b.message ||
                      case when coalesce(b.legal_ref,'') <> ''
                           then ' [' || b.legal_ref || ']' else '' end,
                      E'\n')
      into v_blockers
    from app.stage_blockers(new.id) b
    where b.severity = 'hard'
      and (new.status = 'completed' or b.code like 'PREREQ%');

    if v_blockers is not null then
      raise exception E'ΑΠΑΓΟΡΕΥΕΤΑΙ η μετάβαση του σταδίου σε «%».\nΕκκρεμούν:\n%',
        new.status, v_blockers
        using errcode = 'check_violation',
              hint = 'Ολοκληρώστε τα εκκρεμή βήματα ή ζητήστε αιτιολογημένη παράκαμψη από τον Προϊστάμενο της Δ.Υ.';
    end if;
  end if;

  if new.status = 'completed' and new.completed_at is null then
    new.completed_at := now();
    if new.due_date is not null and current_date > new.due_date then
      new.status := 'overdue';
    end if;
  end if;

  return new;
end $$;

create trigger trg_guard_stage_transition
  before update on public.project_stages
  for each row execute function app.guard_stage_transition();

-- Μετά από κάθε ολοκλήρωση, ξεκλείδωσε τα επόμενα
create or replace function app.after_stage_update()
returns trigger language plpgsql as $$
begin
  if new.status in ('completed','not_applicable','overdue')
     and old.status is distinct from new.status then
    perform app.recompute_availability(new.project_id);
  end if;
  return null;
end $$;

create trigger trg_after_stage_update
  after update on public.project_stages
  for each row execute function app.after_stage_update();
