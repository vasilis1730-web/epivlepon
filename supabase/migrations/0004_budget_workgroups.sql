-- =====================================================================
-- Migration 0004 : Ομάδες εργασιών, τιμολόγιο, προϋπολογισμός, νέες τιμές
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4.1 ΟΜΑΔΕΣ ΕΡΓΑΣΙΩΝ
--     Υ.Α. ΔΝΣγ/οικ.38107/ΦΝ 466/2017 (ΦΕΚ Β΄1956/07.06.2017)
--     «Καθορισμός Ομάδων εργασιών ανά κατηγορία έργων».
--     Απαραίτητο για τον έλεγχο του ορίου 20% ανά ομάδα (άρθρο 156 §3γ).
-- ---------------------------------------------------------------------
create table public.work_groups (
  id              bigint generated always as identity primary key,
  category        public.project_category not null,
  code            text not null,                       -- 'A', 'B', 'Γ' ...
  title           text not null,                       -- 'Χωματουργικά', 'Τεχνικά έργα' ...
  legal_ref_id    text references public.legal_refs(id),
  unique (category, code)
);

comment on table public.work_groups is
  'Ομάδες εργασιών ανά κατηγορία έργου (Υ.Α. ΔΝΣγ/οικ.38107/ΦΝ 466/2017). '
  'Ο περιορισμός των επί έλασσον δαπανών (20% ανά ομάδα) υπολογίζεται πάνω σε αυτές.';

-- ---------------------------------------------------------------------
-- 4.2 ΕΚΔΟΣΕΙΣ ΠΡΟΫΠΟΛΟΓΙΣΜΟΥ
--     v0 = αρχική σύμβαση, v1..vN = εγκεκριμένοι ΑΠΕ
-- ---------------------------------------------------------------------
create table public.budget_versions (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid not null references public.projects(id) on delete cascade,
  version_no      integer not null,                    -- 0 = αρχική σύμβαση
  label           text not null,                       -- 'Αρχική Σύμβαση', '1ος ΑΠΕ'
  ape_id          uuid,                                -- FK ορίζεται στο 0009
  is_current      boolean not null default false,
  approved_at     date,
  total_net       numeric(14,2) not null default 0,
  created_at      timestamptz not null default now(),
  unique (project_id, version_no)
);

create unique index budget_versions_one_current_idx
  on public.budget_versions (project_id) where is_current;

-- ---------------------------------------------------------------------
-- 4.3 ΑΡΘΡΑ ΤΙΜΟΛΟΓΙΟΥ / ΠΡΟΫΠΟΛΟΓΙΣΜΟΥ
-- ---------------------------------------------------------------------
create table public.budget_items (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  version_id         uuid not null references public.budget_versions(id) on delete cascade,
  line_no            integer not null,                 -- Α/Α στον προϋπολογισμό
  item_code          text not null,                    -- Κωδ. άρθρου (ΝΕΤ/ΑΤΟΕ/ΗΛΜ/ΝΕΤ ΟΔΟ)
  etep_code          text,                             -- Κωδικός ΕΤΕΠ / ΕΛΟΤ ΤΠ
  revision_code      text,                             -- Κωδικός αναθεώρησης (π.χ. ΟΔΟ-1123Α)
  description        text not null,
  unit               text not null,                    -- m3, m2, kg, τεμ., κατ' αποκοπή
  work_group_id      bigint references public.work_groups(id),
  unit_price         numeric(14,4) not null check (unit_price >= 0),
  quantity           numeric(16,4) not null check (quantity >= 0),
  amount             numeric(14,2) generated always as
                       (round(unit_price * quantity, 2)) stored,
  is_new_price       boolean not null default false,   -- Προήλθε από ΠΚΤΜΝΕ
  new_price_item_id  uuid,                             -- FK ορίζεται στο 0009
  is_apologistiki    boolean not null default false,   -- Απολογιστική εργασία (άρθρο 154)
  notes              text,
  created_at         timestamptz not null default now(),
  unique (version_id, line_no)
);

create index budget_items_project_idx on public.budget_items (project_id, version_id);
create index budget_items_group_idx   on public.budget_items (work_group_id);

comment on column public.budget_items.is_new_price is
  'true όταν το άρθρο προέρχεται από Π.Κ.Τ.Μ.Ν.Ε. (άρθρο 156 §5-6). '
  'Κανόνας ελέγχου: νέο άρθρο ΔΕΝ επιτρέπεται να χρηματοδοτηθεί από επί έλασσον '
  'δαπάνες (άρθρο 156 §3γ) — βλ. trigger στο 0009.';

-- ---------------------------------------------------------------------
-- 4.4 ΠΡΩΤΟΚΟΛΛΑ ΚΑΝΟΝΙΣΜΟΥ ΤΙΜΩΝ ΜΟΝΑΔΟΣ ΝΕΩΝ ΕΡΓΑΣΙΩΝ (Π.Κ.Τ.Μ.Ν.Ε.)
--     Άρθρο 156 §5-6 ν.4412/2016
-- ---------------------------------------------------------------------
create table public.new_price_protocols (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  protocol_no        integer not null,                 -- 1ο ΠΚΤΜΝΕ, 2ο ΠΚΤΜΝΕ ...
  drafted_at         date not null,
  committee_members  jsonb not null,                   -- [{profile_id, name, role}] ≥2, κανόνας: 3 τεχνικοί
  sigma_coefficient  numeric(10,6),                    -- Συντελεστής σ = Α:Β (άρθρο 156 §6)
  discount_applied   numeric(6,3),                     -- Τεκμαρτή έκπτωση δημοπρασίας
  contractor_signed  public.signature_kind,
  status             public.ape_status not null default 'draft',
  tc_opinion_id      uuid,                             -- Γνωμοδότηση Τεχνικού Συμβουλίου
  approved_at        date,
  approval_ada       text,
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  unique (project_id, protocol_no)
);

comment on column public.new_price_protocols.committee_members is
  'Επιτροπή κανονισμού νέων τιμών: τρεις τεχνικοί υπάλληλοι της υπηρεσίας, '
  'μεταξύ των οποίων ΥΠΟΧΡΕΩΤΙΚΑ ο επιβλέπων· κατ'' εξαίρεση δύο, εφόσον δεν '
  'επαρκεί το προσωπικό (άρθρο 156 §5 ν.4412/2016).';

create table public.new_price_items (
  id                 uuid primary key default gen_random_uuid(),
  protocol_id        uuid not null references public.new_price_protocols(id) on delete cascade,
  item_code          text not null,                    -- 'Ν.1', 'Ν.2' ...
  description        text not null,
  unit               text not null,
  work_group_id      bigint references public.work_groups(id),
  basis              public.new_price_basis not null,
  basis_reference    text not null,                    -- Ποιο συμβατικό άρθρο / αναλυτικό τιμολόγιο
  analysis           jsonb,                            -- Ανάλυση τιμής (υλικά, εργασία, ΜΕ)
  price_before_disc  numeric(14,4) not null,
  price_final        numeric(14,4) not null,           -- Μετά την τεκμαρτή έκπτωση
  quantity           numeric(16,4) not null default 0,
  justification      text not null,                    -- Τεκμηρίωση αναγκαιότητας
  created_at         timestamptz not null default now(),
  unique (protocol_id, item_code),
  constraint npi_price_chk check (price_final <= price_before_disc)
);

comment on table public.new_price_items is
  'Νέες τιμές μονάδος. Ιεράρχηση πηγών κατά το άρθρο 156 §5: (α) όμοιες ή '
  'ανάλογες συμβατικές τιμές, (β) εγκεκριμένα αναλυτικά τιμολόγια, '
  '(γ) απολογιστικά στοιχεία κόστους. Επί των τιμών εφαρμόζεται η τεκμαρτή έκπτωση.';

alter table public.budget_items
  add constraint budget_items_new_price_fk
  foreign key (new_price_item_id) references public.new_price_items(id) on delete set null;

-- ---------------------------------------------------------------------
-- 4.5 ΑΠΟΛΟΓΙΣΤΙΚΕΣ ΕΡΓΑΣΙΕΣ (άρθρο 154) &
--     ΕΠΕΙΓΟΥΣΕΣ / ΑΠΡΟΒΛΕΠΤΕΣ ΠΡΟΣΘΕΤΕΣ (άρθρο 155)
-- ---------------------------------------------------------------------
create table public.apologistika (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  kind               text not null,                    -- 'apologistiki' (154) | 'epeigousa' (155)
  ordered_at         date not null,
  order_ref          text not null,                    -- Εντολή Δ.Υ. / εγγραφή στο ημερολόγιο
  description        text not null,
  justification      text not null,
  cost_documented    numeric(14,2) not null default 0,
  contractor_fee_pct numeric(5,2) not null default 18.00,  -- Όφελος αναδόχου
  total_amount       numeric(14,2) generated always as
                       (round(cost_documented * (1 + contractor_fee_pct/100), 2)) stored,
  supporting_docs    jsonb,                            -- Παραστατικά / ζυγολόγια
  included_in_ape_id uuid,                             -- Τακτοποιείται σε επόμενο ΑΠΕ
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  constraint apologistika_kind_chk check (kind in ('apologistiki','epeigousa'))
);

comment on table public.apologistika is
  'Απολογιστικές εργασίες (άρθρο 154) και επείγουσες/απρόβλεπτες πρόσθετες '
  'εργασίες (άρθρο 155). Κατ'' άρθρο 156 §2, οι εργασίες των άρθρων 154-155 '
  'ΔΕΝ απαιτούν προηγούμενο ΑΠΕ, τακτοποιούνται όμως σε επόμενο.';
