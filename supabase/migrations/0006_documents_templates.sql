-- =====================================================================
-- Migration 0006 : Πρότυπα εγγράφων (templates) & παραγόμενα έγγραφα
--
-- Λογική αυτοματοποίησης:
--   document_templates  = τα πρότυπα της Υπηρεσίας (.docx/.xlsx με πεδία)
--   template_fields     = χάρτης «placeholder → πηγή δεδομένων»
--   documents           = τα παραχθέντα έγγραφα του συγκεκριμένου έργου
-- Η παραγωγή γίνεται server-side (Edge Function) με βάση το payload,
-- ώστε κάθε έγγραφο να είναι αναπαραγώγιμο και ελέγξιμο.
-- =====================================================================

create table public.document_templates (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid references public.organizations(id) on delete cascade, -- null = καθολικό
  doc_code         text not null,                      -- 'ANAL_EPIMETRISI', 'APE', 'PPAE' ...
  title            text not null,
  category         text not null,                      -- 'imerologio','epimetrisi','ape','peraiosi' ...
  file_type        text not null default 'docx',       -- docx | xlsx | html | pdf
  storage_path     text not null,                      -- Supabase Storage: templates/...
  version          integer not null default 1,
  is_active        boolean not null default true,
  stage_code       text references public.workflow_stages(code),
  legal_ref_id     text references public.legal_refs(id),
  numbering_scheme text,                               -- Μοτίβο αρίθμησης, π.χ. '{ΕΤΟΣ}/{ΑΑ}'
  requires_ada     boolean not null default false,     -- Ανάρτηση στη Διαύγεια (ν.4727/2020)
  requires_adam    boolean not null default false,     -- ΚΗΜΔΗΣ (άρθρο 38 ν.4412/2016)
  notes            text,
  created_at       timestamptz not null default now(),
  unique (org_id, doc_code, version),
  constraint dt_filetype_chk check (file_type in ('docx','xlsx','html','pdf','odt'))
);

comment on table public.document_templates is
  'Πρότυπα της Υπηρεσίας. Ο Δήμος ανεβάζει τα δικά του .docx/.xlsx με '
  'placeholders· το σύστημα τα συμπληρώνει από τα δεδομένα του έργου.';

-- Χάρτης πεδίων: πώς γεμίζει κάθε placeholder
create table public.template_fields (
  id               bigint generated always as identity primary key,
  template_id      uuid not null references public.document_templates(id) on delete cascade,
  placeholder      text not null,                      -- '{{ergo.titlos}}'
  label            text not null,                      -- 'Τίτλος έργου'
  source_kind      text not null,                      -- 'field' | 'query' | 'computed' | 'manual'
  source_path      text,                               -- 'projects.title' ή όνομα view/συνάρτησης
  data_type        text not null default 'text',       -- text|number|date|currency|table
  format_mask      text,                               -- '#.##0,00', 'dd/MM/yyyy'
  is_required      boolean not null default true,
  default_value    text,
  unique (template_id, placeholder),
  constraint tf_kind_chk check (source_kind in ('field','query','computed','manual'))
);

comment on table public.template_fields is
  'Δηλωτικός χάρτης συμπλήρωσης προτύπων. Επιτρέπει την προσθήκη νέου προτύπου '
  'από τη διοίκηση ΧΩΡΙΣ αλλαγή κώδικα.';

-- ---------------------------------------------------------------------
-- 6.2 ΠΑΡΑΓΟΜΕΝΑ ΕΓΓΡΑΦΑ
-- ---------------------------------------------------------------------
create table public.documents (
  id               uuid primary key default gen_random_uuid(),
  project_id       uuid not null references public.projects(id) on delete cascade,
  project_stage_id uuid references public.project_stages(id) on delete set null,
  template_id      uuid references public.document_templates(id) on delete set null,
  doc_code         text not null,
  title            text not null,
  protocol_no      text,                               -- Αρ. πρωτοκόλλου Υπηρεσίας
  protocol_date    date,
  ada              text,                               -- Διαύγεια
  adam             text,                               -- ΚΗΜΔΗΣ
  status           public.document_status not null default 'draft',
  storage_path     text,                               -- Το τελικό αρχείο
  payload          jsonb,                              -- Τιμές πεδίων κατά την παραγωγή
  checksum         text,                               -- SHA-256 ακεραιότητας
  entity_type      text,                               -- 'measurement','ape','payment_certificate' ...
  entity_id        uuid,                               -- Σύνδεση με τη δομημένη εγγραφή
  version          integer not null default 1,
  supersedes_id    uuid references public.documents(id),
  created_by       uuid references public.profiles(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index documents_project_idx on public.documents (project_id, doc_code);
create index documents_entity_idx  on public.documents (entity_type, entity_id);

create trigger trg_documents_touch
  before update on public.documents
  for each row execute function app.touch_updated_at();

-- Υπογραφές
create table public.document_signatures (
  id               uuid primary key default gen_random_uuid(),
  document_id      uuid not null references public.documents(id) on delete cascade,
  signer_profile   uuid references public.profiles(id),
  signer_name      text not null,
  signer_capacity  text not null,                      -- 'Επιβλέπων', 'Νόμιμος εκπρόσωπος αναδόχου'
  party            public.party_type not null,
  kind             public.signature_kind not null default 'apla',
  reservation_text text,                               -- Κείμενο επιφύλαξης (άρθρο 156 §7)
  signed_at        timestamptz not null default now(),
  certificate_info jsonb,
  constraint ds_reservation_chk check (kind <> 'me_epifylaxi' or reservation_text is not null)
);

comment on column public.document_signatures.kind is
  'Η υπογραφή ΑΠΕ/ΠΚΤΜΝΕ «με επιφύλαξη» διατηρεί τα δικαιώματα του αναδόχου· '
  'η άρνηση υπογραφής οδηγεί σε κοινοποίηση κατ'' άρθρο 143 ν.4412/2016.';

-- Κοινοποιήσεις (άρθρο 143 — κοινοποίηση στον ανάδοχο)
create table public.document_communications (
  id               uuid primary key default gen_random_uuid(),
  document_id      uuid not null references public.documents(id) on delete cascade,
  recipient_party  public.party_type not null,
  recipient_name   text not null,
  method           text not null,                      -- 'ilektroniki','epidosi','systimeni'
  sent_at          timestamptz not null default now(),
  received_at      timestamptz,                        -- Αφετηρία προθεσμιών ένστασης
  proof_path       text,                               -- Αποδεικτικό επίδοσης
  legal_ref_id     text references public.legal_refs(id),
  constraint dc_method_chk check (method in ('ilektroniki','epidosi','systimeni','autopswia'))
);

comment on table public.document_communications is
  'Κοινοποίηση πράξεων στον ανάδοχο (άρθρο 143 ν.4412/2016). Το received_at '
  'αποτελεί την αφετηρία της ανατρεπτικής προθεσμίας ένστασης (άρθρο 174).';

-- Σύνδεση τεκμηρίων της λίστας ελέγχου με έγγραφα
alter table public.project_stage_tasks
  add constraint pst_evidence_fk
  foreign key (evidence_doc_id) references public.documents(id) on delete set null;

-- ---------------------------------------------------------------------
-- 6.3 ΓΕΝΙΚΟΣ ΚΑΝΟΝΑΣ: στάδιο δεν κλείνει χωρίς τα υποχρεωτικά έγγραφα
-- ---------------------------------------------------------------------
create or replace function app.guard_required_documents(p_project_stage_id uuid)
returns setof app.blocker
language sql stable security definer set search_path = public, app as $$
  select ('DOC_' || sd.doc_code)::text,
         format('Λείπει το υποχρεωτικό έγγραφο: %s (συντάσσεται από: %s).',
                sd.title, app.party_label(sd.produced_by))::text,
         'hard'::text,
         coalesce(sd.legal_ref_id, '')::text
  from public.project_stages ps
  join public.stage_documents sd on sd.stage_code = ps.stage_code
  where ps.id = p_project_stage_id
    and sd.is_mandatory
    and not exists (
      select 1 from public.documents d
      where d.project_id = ps.project_id
        and d.doc_code = sd.doc_code
        and d.status in ('signed','approved','communicated','deemed_approved')
    );
$$;
