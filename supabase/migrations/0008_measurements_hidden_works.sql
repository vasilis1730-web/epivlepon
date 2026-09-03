-- =====================================================================
-- Migration 0008 : Επιμετρήσεις & Αφανείς Εργασίες (άρθρο 151 ν.4412/2016)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 8.1 ΕΠΙΜΕΤΡΗΣΕΙΣ
-- ---------------------------------------------------------------------
create table public.measurements (
  id                    uuid primary key default gen_random_uuid(),
  project_id            uuid not null references public.projects(id) on delete cascade,
  mtype                 public.measurement_type not null default 'tmimatiki',
  serial_no             integer not null,               -- Α/Α επιμέτρησης
  period_from           date,
  period_to             date,
  work_section          text,                           -- Διακριτό τμήμα έργου (§2)
  budget_version_id     uuid references public.budget_versions(id),

  -- Υποβολή από τον ΑΝΑΔΟΧΟ
  submitted_at          date,
  submitted_by_staff    uuid references public.contractor_staff(id),
  truth_declaration     boolean not null default false, -- Δήλωση περί αληθείας (§1)
  has_drawings          boolean not null default false, -- Επιμετρητικά σχέδια (§2)
  electronic_form       boolean not null default true,  -- Έντυπη & ηλεκτρονική μορφή (§2)

  -- Έλεγχος από την ΕΠΙΒΛΕΨΗ / Δ.Υ.
  status                public.measurement_status not null default 'draft',
  selected_for_audit    boolean not null default false, -- Δειγματοληψία (§3)
  checked_by            uuid references public.profiles(id),
  checked_at            date,
  approval_due          date,                           -- submitted_at + 30 ημέρες
  approved_at           date,
  approved_by           uuid references public.profiles(id),
  deemed_approved       boolean not null default false,
  inaccuracy            public.inaccuracy_grade not null default 'kamia',
  inaccuracy_pct        numeric(6,3),
  correction_deadline   date,
  remarks               text,

  contractual_amount    numeric(14,2) not null default 0, -- Ποσότητες εντός σύμβασης
  extra_amount          numeric(14,2) not null default 0, -- Πέραν των συμβατικών (§1)
  total_amount          numeric(14,2) generated always as
                          (contractual_amount + extra_amount) stored,

  document_id           uuid references public.documents(id),
  legal_ref_id          text references public.legal_refs(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (project_id, mtype, serial_no)
);

create index measurements_project_status_idx on public.measurements (project_id, status);

create trigger trg_measurements_touch
  before update on public.measurements
  for each row execute function app.touch_updated_at();

comment on table public.measurements is
  'Επιμετρήσεις (άρθρο 151 ν.4412/2016). Συντάσσονται σε κάθε τμηματική '
  'προθεσμία ή μηνιαίως, ανά διακριτό τμήμα έργου, με δήλωση αληθείας του '
  'αναδόχου, και αποτελούν ΠΡΟΑΠΑΙΤΟΥΜΕΝΟ για την υποβολή λογαριασμού.';

comment on column public.measurements.selected_for_audit is
  'Άρθρο 151 §3: ο προϊστάμενος της Δ.Υ. διενεργεί ΥΠΟΧΡΕΩΤΙΚΑ δειγματοληπτικό '
  'έλεγχο στο 40% των υποβληθεισών επιμετρήσεων ή σε τουλάχιστον τέσσερις (4), '
  'εφόσον οι υποβληθείσες είναι λιγότερες από δέκα (10).';

create table public.measurement_lines (
  id                 uuid primary key default gen_random_uuid(),
  measurement_id     uuid not null references public.measurements(id) on delete cascade,
  budget_item_id     uuid not null references public.budget_items(id) on delete restrict,
  quantity_period    numeric(16,4) not null default 0,  -- Ποσότητα περιόδου
  quantity_cumul     numeric(16,4) not null default 0,  -- Σωρευτική ποσότητα
  unit_price         numeric(14,4) not null,
  amount_period      numeric(14,2) generated always as
                       (round(quantity_period * unit_price, 2)) stored,
  amount_cumul       numeric(14,2) generated always as
                       (round(quantity_cumul  * unit_price, 2)) stored,
  measurement_data   jsonb,                             -- Επιμετρητικά στοιχεία/υπολογισμοί
  drawing_refs       text[],
  is_hidden_work     boolean not null default false,    -- Αφανής εργασία (§7)
  hidden_notice_id   uuid,                              -- FK ορίζεται πιο κάτω
  exceeds_contract   boolean not null default false,
  unique (measurement_id, budget_item_id)
);

create index measurement_lines_item_idx on public.measurement_lines (budget_item_id);

-- Δειγματοληπτικοί έλεγχοι (άρθρο 151 §3-6)
create table public.measurement_audits (
  id                 uuid primary key default gen_random_uuid(),
  measurement_id     uuid not null references public.measurements(id) on delete cascade,
  audit_round        integer not null default 1,
  ordered_at         date not null,
  ordered_by         uuid references public.profiles(id),
  auditor            text not null,
  performed_at       date,
  findings           text,
  grade              public.inaccuracy_grade not null default 'kamia',
  deviation_pct      numeric(6,3),
  full_audit_ordered boolean not null default false,    -- Πλήρης έλεγχος (§4)
  sanction_applied   text,                              -- Κύρωση/κατάπτωση εγγύησης (§5-6)
  document_id        uuid references public.documents(id),
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  unique (measurement_id, audit_round)
);

comment on table public.measurement_audits is
  'Δειγματοληπτικός/πλήρης έλεγχος επιμετρήσεων. Επανειλημμένη υποβολή ψευδών '
  'επιμετρήσεων επισύρει υποχρεωτική έκπτωση του αναδόχου και κατάπτωση της '
  'εγγύησης καλής εκτέλεσης (άρθρο 151 §5-6 ν.4412/2016).';

-- ---------------------------------------------------------------------
-- 8.2 ΑΦΑΝΕΙΣ ΕΡΓΑΣΙΕΣ — «ΠΠΑΕ» (άρθρο 151 §7)
-- ---------------------------------------------------------------------
create table public.hidden_work_notices (
  id                   uuid primary key default gen_random_uuid(),
  project_id           uuid not null references public.projects(id) on delete cascade,
  serial_no            integer not null,
  work_description     text not null,
  location             text not null,
  work_group_id        bigint references public.work_groups(id),

  -- ΑΝΑΔΟΧΟΣ: δήλωση γνωστοποίησης αφανών εργασιών + πρόσκληση επιβλέποντος
  declaration_at       date not null,                   -- Δήλωση γνωστοποίησης
  declared_by_staff    uuid references public.contractor_staff(id),
  truth_declaration    boolean not null default false,  -- Δήλωση περί αληθείας
  invitation_sent_at   date not null,                   -- Πρόσκληση προς επιβλέποντα
  inspection_due       date generated always as (invitation_sent_at + 3) stored,

  -- ΕΠΙΒΛΕΠΩΝ: έλεγχος πριν την επικάλυψη & έκθεση
  inspected_at         date,
  inspected_by         uuid references public.profiles(id),
  supervisor_report_at date,                            -- Υποβάλλεται αμελλητί στη Δ.Υ.
  photos_count         integer not null default 0,
  video_path           text,
  covered_at           date,                            -- Ημερομηνία επικάλυψης

  -- Δ.Υ.: εγκριτική πράξη της επιμέτρησης αφανών εντός 30 ημερών
  measurement_id       uuid references public.measurements(id),
  approval_due         date,
  approved_at          date,
  approved_by          uuid references public.profiles(id),
  deemed_approved      boolean not null default false,

  supervisor_overdue   boolean not null default false,  -- Υπερημερία κυρίου του έργου
  status               text not null default 'declared',
  document_id          uuid references public.documents(id),
  legal_ref_id         text references public.legal_refs(id),
  created_at           timestamptz not null default now(),
  unique (project_id, serial_no),
  constraint hwn_status_chk check (status in
    ('declared','inspected','reported','measured','approved','overdue','rejected')),
  constraint hwn_cover_chk check (covered_at is null or inspected_at is not null),
  constraint hwn_photos_chk check (inspected_at is null or photos_count > 0)
);

create index hidden_work_notices_due_idx on public.hidden_work_notices (inspection_due)
  where inspected_at is null;

comment on table public.hidden_work_notices is
  'Αφανείς εργασίες / πρωτόκολλα παραλαβής αφανών εργασιών (ΠΠΑΕ) — άρθρο 151 §7 '
  'ν.4412/2016, όπως ισχύει. Ο ανάδοχος ΠΡΙΝ ΤΗΝ ΕΠΙΚΑΛΥΨΗ καλεί τον επιβλέποντα '
  'σε ημερομηνία που ΔΕΝ ΑΠΕΧΕΙ ΠΕΡΙΣΣΟΤΕΡΟ ΑΠΟ ΤΡΕΙΣ (3) ΗΜΕΡΕΣ από την '
  'κοινοποίηση. Ο επιβλέπων συντάσσει έκθεση με ΕΠΑΡΚΕΙΣ ΨΗΦΙΑΚΕΣ ΦΩΤΟΓΡΑΦΙΕΣ '
  '(εντάσσονται στο Μητρώο του Έργου). Η παράλειψη ελέγχου εντός της προθεσμίας '
  'ΣΥΝΙΣΤΑ ΥΠΕΡΗΜΕΡΙΑ ΤΟΥ ΚΥΡΙΟΥ ΤΟΥ ΕΡΓΟΥ. Η εγκριτική πράξη της επιμέτρησης '
  'εκδίδεται από τη Δ.Υ. εντός ΤΡΙΑΝΤΑ (30) ΗΜΕΡΩΝ από την υποβολή.';

comment on constraint hwn_photos_chk on public.hidden_work_notices is
  'Δεν επιτρέπεται καταχώριση ελέγχου αφανών χωρίς ψηφιακές φωτογραφίες '
  '(άρθρο 151 §7 — τεκμηρίωση στο Μητρώο Έργου).';

create table public.hidden_work_photos (
  id                 uuid primary key default gen_random_uuid(),
  notice_id          uuid not null references public.hidden_work_notices(id) on delete cascade,
  storage_path       text not null,
  taken_at           timestamptz,
  latitude           numeric(9,6),
  longitude          numeric(9,6),
  caption            text,
  checksum           text,
  uploaded_by        uuid references public.profiles(id),
  created_at         timestamptz not null default now()
);

alter table public.measurement_lines
  add constraint ml_hidden_notice_fk
  foreign key (hidden_notice_id) references public.hidden_work_notices(id) on delete set null;

-- Συγχρονισμός αριθμού φωτογραφιών
create or replace function app.sync_hidden_photos_count()
returns trigger language plpgsql as $$
begin
  update public.hidden_work_notices h
     set photos_count = (select count(*) from public.hidden_work_photos p
                         where p.notice_id = h.id)
   where h.id = coalesce(new.notice_id, old.notice_id);
  return null;
end $$;

create trigger trg_sync_hidden_photos
  after insert or delete on public.hidden_work_photos
  for each row execute function app.sync_hidden_photos_count();

-- ---------------------------------------------------------------------
-- 8.3 ΤΕΛΙΚΗ ΕΠΙΜΕΤΡΗΣΗ (άρθρο 151 §9-11)
-- ---------------------------------------------------------------------
create table public.final_measurement (
  id                     uuid primary key default gen_random_uuid(),
  project_id             uuid not null unique references public.projects(id) on delete cascade,
  measurement_id         uuid references public.measurements(id),
  completion_date        date not null,                 -- Ημερομηνία περαίωσης εργασιών
  contractor_due         date,                          -- +2 μήνες: υποβολή από ανάδοχο
  submitted_at           date,
  supervisor_report_due  date,                          -- +2 μήνες: έκθεση επιβλέποντος
  supervisor_report_at   date,
  approval_due           date,                          -- +2 μήνες: έγκριση Δ.Υ.
  approved_at            date,
  approved_by            uuid references public.profiles(id),
  approval_ada           text,
  prepared_by_service    boolean not null default false, -- Συντάχθηκε από την υπηρεσία (§10)
  service_cost_charged   numeric(14,2),                  -- Σε βάρος του αναδόχου
  penalty_months         integer not null default 0,     -- Μήνες καθυστέρησης (max 6)
  penalty_amount         numeric(14,2) not null default 0, -- 2‰ ανά μήνα (§10)
  document_id            uuid references public.documents(id),
  legal_ref_id           text references public.legal_refs(id),
  created_at             timestamptz not null default now(),
  constraint fm_penalty_months_chk check (penalty_months between 0 and 6)
);

comment on table public.final_measurement is
  'Τελική επιμέτρηση (άρθρο 151 §9-11). Υποβάλλεται από τον ανάδοχο εντός ΔΥΟ (2) '
  'ΜΗΝΩΝ από την περαίωση· ο επιβλέπων υποβάλλει έκθεση εντός ΔΥΟ (2) ΜΗΝΩΝ· η '
  'Δ.Υ. εγκρίνει εντός ΔΥΟ (2) ΜΗΝΩΝ. Καθυστέρηση υποβολής επισύρει ποινική ρήτρα '
  '2‰ της συμβατικής αξίας ανά συμπληρωμένο μήνα, με ανώτατο όριο έξι (6) μήνες. '
  'Η ΕΓΚΡΙΣΗ ΤΗΣ ΤΕΛΙΚΗΣ ΕΠΙΜΕΤΡΗΣΗΣ ΕΙΝΑΙ ΤΟ ΓΕΓΟΝΟΣ ΠΟΥ ΕΝΕΡΓΟΠΟΙΕΙ ΤΗ ΜΕΙΩΣΗ '
  'ΤΗΣ ΕΓΓΥΗΣΗΣ ΚΑΛΗΣ ΕΚΤΕΛΕΣΗΣ ΚΑΤΑ 70% (άρθρο 72 §14 περ. β΄).';

-- ---------------------------------------------------------------------
-- 8.4 ΑΥΤΟΜΑΤΙΣΜΟΙ ΠΡΟΘΕΣΜΙΩΝ
-- ---------------------------------------------------------------------
create or replace function app.set_measurement_dates()
returns trigger language plpgsql as $$
begin
  if new.submitted_at is not null and new.approval_due is null then
    new.approval_due := new.submitted_at + 30;   -- άρθρο 151 §7 (εγκριτική πράξη)
  end if;
  return new;
end $$;

create trigger trg_measurement_dates
  before insert or update on public.measurements
  for each row execute function app.set_measurement_dates();

create or replace function app.set_final_measurement_dates()
returns trigger language plpgsql as $$
begin
  new.contractor_due := (new.completion_date + interval '2 months')::date;
  if new.submitted_at is not null then
    new.supervisor_report_due := (new.submitted_at + interval '2 months')::date;
  end if;
  if new.supervisor_report_at is not null then
    new.approval_due := (new.supervisor_report_at + interval '2 months')::date;
  end if;
  -- Ποινική ρήτρα 2‰ ανά μήνα καθυστέρησης, έως 6 μήνες (άρθρο 151 §10)
  if new.submitted_at is not null and new.submitted_at > new.contractor_due then
    new.penalty_months := least(6,
      greatest(0, (extract(year  from age(new.submitted_at, new.contractor_due))*12
                 + extract(month from age(new.submitted_at, new.contractor_due)))::int));
    new.penalty_amount := round(
      coalesce((select c.initial_value_net from public.contracts c
                where c.project_id = new.project_id), 0)
      * 0.002 * new.penalty_months, 2);
  end if;
  return new;
end $$;

create trigger trg_final_measurement_dates
  before insert or update on public.final_measurement
  for each row execute function app.set_final_measurement_dates();

-- Κανόνας δειγματοληψίας άρθρου 151 §3
create or replace function public.required_audit_count(p_project_id uuid)
returns integer language sql stable as $$
  select case
           when count(*) = 0 then 0
           when count(*) < 10 then least(4, count(*))::int
           else ceil(count(*) * 0.40)::int
         end
  from public.measurements m
  where m.project_id = p_project_id
    and m.mtype = 'tmimatiki'
    and m.submitted_at is not null;
$$;

comment on function public.required_audit_count(uuid) is
  'Επιστρέφει τον ελάχιστο αριθμό επιμετρήσεων που πρέπει να ελεγχθούν '
  'δειγματοληπτικά: 40% των υποβληθεισών, ή τουλάχιστον 4 αν είναι λιγότερες '
  'από 10 (άρθρο 151 §3 ν.4412/2016).';
