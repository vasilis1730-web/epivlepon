-- =====================================================================
-- Migration 0002 : Φορέας, χρήστες, ρόλοι, νομικές παραπομπές, audit trail
-- =====================================================================

-- ---------------------------------------------------------------------
-- 2.1 ΝΟΜΙΚΕΣ ΠΑΡΑΠΟΜΠΕΣ
--     Κεντρικό μητρώο διατάξεων. ΚΑΘΕ στάδιο, ενέργεια, έγγραφο και
--     κανόνας του συστήματος δείχνει εδώ (απαίτηση: αυστηρή νομική
--     τεκμηρίωση). Ενημερώνεται χωρίς αλλαγή κώδικα.
-- ---------------------------------------------------------------------
create table public.legal_refs (
  id              text primary key,                    -- π.χ. 'N4412/151/7'
  law             text not null,                       -- 'ν. 4412/2016'
  article         text not null,                       -- '151'
  paragraph       text,                                -- '7'
  title           text not null,                       -- 'Επιμετρήσεις — αφανείς εργασίες'
  fek             text,                                -- 'Α΄ 147/08.08.2016'
  amended_by      text[],                              -- {'ν. 4782/2021 άρθρο 70'}
  in_force_from   date,
  in_force_to     date,                                -- null = ισχύουσα
  url             text,
  notes           text,
  created_at      timestamptz not null default now()
);

comment on table public.legal_refs is
  'Μητρώο νομικών διατάξεων. Κάθε βήμα/έγγραφο/κανόνας φέρει υποχρεωτικά '
  'παραπομπή εδώ (fail-safe τεκμηρίωσης).';

-- ---------------------------------------------------------------------
-- 2.2 ΦΟΡΕΑΣ (Δήμος / Διεύθυνση) — υποστήριξη πολλαπλών υπηρεσιών
-- ---------------------------------------------------------------------
create table public.organizations (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,                       -- 'Δήμος Ρόδου'
  unit            text,                                -- 'Δ/νση Τεχνικών Έργων & Υποδομών'
  afm             text,
  address         text,
  phone           text,
  email           text,
  logo_path       text,                                -- storage: letterhead/λογότυπο
  letterhead_html text,                                -- Επικεφαλίδα εγγράφων
  created_at      timestamptz not null default now(),
  constraint organizations_afm_chk check (afm is null or afm ~ '^[0-9]{9}$')
);

-- ---------------------------------------------------------------------
-- 2.3 ΧΡΗΣΤΕΣ — προφίλ συνδεδεμένο με auth.users του Supabase
-- ---------------------------------------------------------------------
create table public.profiles (
  id              uuid primary key,                    -- = auth.users.id
  org_id          uuid not null references public.organizations(id) on delete restrict,
  full_name       text not null,
  email           text not null,
  phone           text,
  specialty       text,                                -- 'ΠΕ Μηχανολόγος Μηχανικός'
  grade           text,                                -- 'ΠΕ/ΤΕ' κ.λπ.
  registry_no     text,                                -- Αρ. Μητρώου ΤΕΕ
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on column public.profiles.id is
  'Ταυτίζεται με auth.users.id του Supabase (FK προστίθεται στο 0012 ή χειροκίνητα).';

-- Καθολικοί ρόλοι (ανεξάρτητοι έργου): admin, προϊστάμενος Δ.Υ., κ.λπ.
create table public.org_roles (
  id              bigint generated always as identity primary key,
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  org_id          uuid not null references public.organizations(id) on delete cascade,
  role            public.role_type not null,
  valid_from      date not null default current_date,
  valid_to        date,
  decision_ada    text,                                -- ΑΔΑ απόφασης τοποθέτησης
  unique (profile_id, org_id, role)
);

-- ---------------------------------------------------------------------
-- 2.4 ΑΝΑΔΟΧΟΙ
-- ---------------------------------------------------------------------
create table public.contractors (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null references public.organizations(id) on delete restrict,
  name               text not null,
  legal_form         text,                             -- Α.Ε. / Ο.Ε. / Ατομική / Κ/Ξ
  afm                text not null,
  doy                text,
  gemi               text,
  meep_mieedde       text,                             -- Αρ. ΜΗ.Ε.Ε.Δ.Ε. (πρώην ΜΕΕΠ)
  categories         text[],                           -- Κατηγορίες/τάξεις πτυχίου
  legal_rep_name     text,
  legal_rep_afm      text,
  address            text,
  email              text not null,
  phone              text,
  is_joint_venture   boolean not null default false,   -- Κοινοπραξία (άρθρο 140)
  jv_members         jsonb,                            -- [{name, afm, percent}]
  created_at         timestamptz not null default now(),
  constraint contractors_afm_chk check (afm ~ '^[0-9]{9}$'),
  unique (org_id, afm)
);

comment on column public.contractors.jv_members is
  'Μέλη κοινοπραξίας και ποσοστά — άρθρο 140 ν.4412/2016 (αλληλέγγυα ευθύνη).';

-- ---------------------------------------------------------------------
-- 2.5 ΙΔΙΩΤΙΚΟΣ ΦΟΡΕΑΣ ΕΠΙΒΛΕΨΗΣ (άρθρο 136 §3-5)
-- ---------------------------------------------------------------------
create table public.private_supervisors (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  afm                text not null,
  certification_no   text,                             -- Αρ. πιστοποίησης / μητρώου
  certification_to   date,
  email              text,
  phone              text,
  created_at         timestamptz not null default now()
);

comment on table public.private_supervisors is
  'Πιστοποιημένοι Ιδιωτικοί Φορείς Επίβλεψης — άρθρο 136 §3 ν.4412/2016. '
  'Η αμοιβή τους βαρύνει αποκλειστικά τον ανάδοχο.';

-- ---------------------------------------------------------------------
-- 2.6 AUDIT TRAIL — append-only, μη διαγράψιμο
-- ---------------------------------------------------------------------
create table public.audit_log (
  id              bigint generated always as identity primary key,
  occurred_at     timestamptz not null default now(),
  actor_id        uuid,                                -- profiles.id (nullable: system)
  actor_role      public.role_type,
  table_name      text not null,
  record_id       text not null,
  action          public.audit_action not null,
  project_id      uuid,
  old_data        jsonb,
  new_data        jsonb,
  reason          text,                                -- αιτιολόγηση (π.χ. lock_override)
  ip              inet
);

create index audit_log_project_idx on public.audit_log (project_id, occurred_at desc);
create index audit_log_record_idx  on public.audit_log (table_name, record_id);

comment on table public.audit_log is
  'Αμετάβλητο ιστορικό ενεργειών. Καμία διαγραφή/ενημέρωση δεν επιτρέπεται '
  '(βλ. πολιτικές RLS στο 0012) — τεκμηριώνει τη διοικητική αλυσίδα ευθύνης.';

-- ---------------------------------------------------------------------
-- 2.7 Γενικός trigger ενημέρωσης updated_at
-- ---------------------------------------------------------------------
create or replace function app.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger trg_profiles_touch
  before update on public.profiles
  for each row execute function app.touch_updated_at();
