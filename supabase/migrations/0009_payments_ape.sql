-- =====================================================================
-- Migration 0009 : Λογαριασμοί (άρθρο 152) και Ανακεφαλαιωτικοί Πίνακες
--                  Εργασιών — ΑΠΕ (άρθρα 155-156)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 9.1 ΓΝΩΜΟΔΟΤΗΣΕΙΣ ΤΕΧΝΙΚΟΥ ΣΥΜΒΟΥΛΙΟΥ
-- ---------------------------------------------------------------------
create table public.technical_council_opinions (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects(id) on delete cascade,
  subject            text not null,
  subject_kind       text not null,                    -- 'ape','symplirwmatiki','epi_elasson','ensta','ekptosi'
  requested_at       date not null,
  meeting_date       date,
  opinion_no         text,
  outcome            public.decision_outcome not null default 'pending',
  opinion_text       text,
  document_id        uuid references public.documents(id),
  legal_ref_id       text references public.legal_refs(id),
  created_at         timestamptz not null default now(),
  constraint tco_kind_chk check (subject_kind in
    ('ape','symplirwmatiki','epi_elasson','ensta','ekptosi','dialysi','paratasi','allo'))
);

comment on table public.technical_council_opinions is
  'Γνωμοδοτήσεις Τεχνικού Συμβουλίου. Απαιτούνται υποχρεωτικά πριν την υπογραφή '
  'συμπληρωματικής σύμβασης (άρθρο 156 §1 περ. ε΄) και για τη χρήση επί έλασσον '
  'δαπανών (άρθρο 156 §3γ), κατόπιν εισήγησης της Δ.Υ.';

-- ---------------------------------------------------------------------
-- 9.2 ΑΝΑΚΕΦΑΛΑΙΩΤΙΚΟΙ ΠΙΝΑΚΕΣ ΕΡΓΑΣΙΩΝ (ΑΠΕ)
-- ---------------------------------------------------------------------
create table public.ape (
  id                      uuid primary key default gen_random_uuid(),
  project_id              uuid not null references public.projects(id) on delete cascade,
  serial_no               integer not null,            -- 1ος, 2ος ΑΠΕ ...
  atype                   public.ape_type not null,
  budget_version_id       uuid references public.budget_versions(id),
  new_price_protocol_id   uuid references public.new_price_protocols(id),

  reason                  text not null,               -- Αιτιολόγηση αναγκαιότητας
  drafted_at              date not null,
  drafted_by              uuid references public.profiles(id),

  -- Οικονομικά (όλα χωρίς ΦΠΑ)
  initial_contract_value  numeric(14,2) not null,      -- Αξία αρχικής σύμβασης
  previous_ape_value      numeric(14,2) not null default 0,
  works_value             numeric(14,2) not null default 0,
  ge_oe_amount            numeric(14,2) not null default 0,
  contingency_used        numeric(14,2) not null default 0,  -- Χρήση απροβλέπτων (§3β)
  contingency_remaining   numeric(14,2) not null default 0,
  savings_used            numeric(14,2) not null default 0,  -- Χρήση επί έλασσον (§3γ)
  revision_amount         numeric(14,2) not null default 0,
  new_total_value         numeric(14,2) not null,      -- Νέα συνολική δαπάνη
  delta_amount            numeric(14,2) generated always as
                            (new_total_value - initial_contract_value) stored,
  delta_pct               numeric(8,4),                -- % επί της αρχικής σύμβασης

  supplementary_needed    boolean not null default false,  -- Απαιτείται συμπληρωματική σύμβαση
  supplementary_value     numeric(14,2) not null default 0,
  extra_guarantee_id      uuid references public.guarantees(id),

  -- Έγκριση
  contractor_signature    public.signature_kind,
  contractor_signed_at    date,
  reservation_text        text,
  tc_opinion_id           uuid references public.technical_council_opinions(id),
  status                  public.ape_status not null default 'draft',
  approved_at             date,
  approved_by             uuid references public.profiles(id),
  approval_decision_no    text,
  approval_ada            text,
  document_id             uuid references public.documents(id),
  legal_ref_id            text references public.legal_refs(id),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (project_id, serial_no)
);

create trigger trg_ape_touch
  before update on public.ape
  for each row execute function app.touch_updated_at();

comment on table public.ape is
  'Ανακεφαλαιωτικοί Πίνακες Εργασιών (άρθρο 156 §2 ν.4412/2016). Κάθε τροποποίηση '
  'σύμβασης απαιτεί ΑΠΕ που περιλαμβάνει εργασίες, τιμές μονάδος, ποσότητες, '
  'κονδύλια απροβλέπτων, αναθεώρησης και ΦΠΑ, καθώς και τον αρχικό, τον προηγούμενο '
  'και τον νέο προϋπολογισμό. Οι εργασίες των άρθρων 154-155 δεν απαιτούν '
  'προηγούμενο ΑΠΕ.';

alter table public.budget_versions
  add constraint budget_versions_ape_fk
  foreign key (ape_id) references public.ape(id) on delete set null;

alter table public.apologistika
  add constraint apologistika_ape_fk
  foreign key (included_in_ape_id) references public.ape(id) on delete set null;

alter table public.guarantees
  add constraint guarantees_ape_fk
  foreign key (covers_ape_id) references public.ape(id) on delete set null;

alter table public.new_price_protocols
  add constraint npp_tc_opinion_fk
  foreign key (tc_opinion_id) references public.technical_council_opinions(id) on delete set null;

-- Γραμμές ΑΠΕ ανά άρθρο τιμολογίου
create table public.ape_lines (
  id                 uuid primary key default gen_random_uuid(),
  ape_id             uuid not null references public.ape(id) on delete cascade,
  budget_item_id     uuid references public.budget_items(id) on delete set null,
  new_price_item_id  uuid references public.new_price_items(id) on delete set null,
  work_group_id      bigint references public.work_groups(id),
  item_code          text not null,
  description        text not null,
  unit               text not null,
  unit_price         numeric(14,4) not null,
  qty_initial        numeric(16,4) not null default 0,
  qty_previous       numeric(16,4) not null default 0,
  qty_new            numeric(16,4) not null default 0,
  amount_initial     numeric(14,2) generated always as
                       (round(qty_initial * unit_price, 2)) stored,
  amount_new         numeric(14,2) generated always as
                       (round(qty_new * unit_price, 2)) stored,
  delta_amount       numeric(14,2) generated always as
                       (round((qty_new - qty_initial) * unit_price, 2)) stored,
  funding_source     text not null default 'symvatiko', -- 'symvatiko'|'apravlepta'|'epi_elasson'|'symplirwmatiki'
  is_new_item        boolean not null default false,
  notes              text,
  constraint al_funding_chk check (funding_source in
    ('symvatiko','apravlepta','epi_elasson','symplirwmatiki','apologistika'))
);

create index ape_lines_ape_idx   on public.ape_lines (ape_id);
create index ape_lines_group_idx on public.ape_lines (work_group_id);

-- ---------------------------------------------------------------------
-- 9.3 ΚΑΝΟΝΕΣ ΕΛΕΓΧΟΥ ΑΠΕ — Fail-Safe άρθρου 156
-- ---------------------------------------------------------------------
create or replace function app.ape_validation(p_ape_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare
  a               public.ape%rowtype;
  c               public.contracts%rowtype;
  v_cum_increase  numeric;
  v_group         record;
  v_savings_total numeric;
begin
  select * into a from public.ape where id = p_ape_id;
  if not found then return; end if;
  select * into c from public.contracts where project_id = a.project_id;

  -- (1) Σωρευτικό όριο αύξησης 50% της αξίας της αρχικής σύμβασης (άρθρο 156 §1)
  select coalesce(sum(x.delta_amount), 0) into v_cum_increase
  from public.ape x
  where x.project_id = a.project_id
    and (x.status = 'approved' or x.id = a.id)
    and x.delta_amount > 0;

  if c.initial_value_net > 0
     and v_cum_increase > c.initial_value_net * 0.50 then
    return next ('APE_LIMIT_50',
      format('Υπέρβαση του ανώτατου ορίου 50%%: σωρευτική αύξηση %s € έναντι ορίου %s €.',
             to_char(v_cum_increase,'FM999G999G990D00'),
             to_char(c.initial_value_net*0.50,'FM999G999G990D00')),
      'hard', 'N4412/156/1')::app.blocker;
  end if;

  -- (2) Όριο απροβλέπτων 9% ή 15% (άρθρο 156 §3β)
  if a.contingency_used > c.contingency_amount + 0.005 then
    return next ('APE_CONTINGENCY',
      format('Η χρήση απροβλέπτων (%s €) υπερβαίνει το εγκεκριμένο κονδύλιο %s%% (%s €).',
             to_char(a.contingency_used,'FM999G999G990D00'),
             to_char(c.contingency_pct,'FM990D00'),
             to_char(c.contingency_amount,'FM999G999G990D00')),
      'hard', 'N4412/156/3b')::app.blocker;
  end if;

  -- (3) Επί έλασσον: ≤ 20% ανά ΟΜΑΔΑ ΕΡΓΑΣΙΩΝ (άρθρο 156 §3γ)
  for v_group in
    select wg.title as group_title,
           sum(case when al.delta_amount < 0 then -al.delta_amount else 0 end) as savings,
           sum(al.amount_initial) as group_initial
    from public.ape_lines al
    join public.work_groups wg on wg.id = al.work_group_id
    where al.ape_id = p_ape_id
    group by wg.title
  loop
    if v_group.group_initial > 0
       and v_group.savings > v_group.group_initial * 0.20 then
      return next ('APE_SAVINGS_GROUP_20',
        format('Ομάδα «%s»: οι επί έλασσον δαπάνες (%s €) υπερβαίνουν το 20%% της συμβατικής δαπάνης της ομάδας (%s €).',
               v_group.group_title,
               to_char(v_group.savings,'FM999G999G990D00'),
               to_char(v_group.group_initial*0.20,'FM999G999G990D00')),
        'hard', 'N4412/156/3c')::app.blocker;
    end if;
  end loop;

  -- (4) Επί έλασσον: ≤ 10% της αξίας της αρχικής σύμβασης (άρθρο 156 §3γ)
  select coalesce(sum(case when al.delta_amount < 0 then -al.delta_amount else 0 end), 0)
    into v_savings_total
  from public.ape_lines al where al.ape_id = p_ape_id;

  if c.initial_value_net > 0
     and v_savings_total > c.initial_value_net * 0.10 then
    return next ('APE_SAVINGS_TOTAL_10',
      format('Οι επί έλασσον δαπάνες (%s €) υπερβαίνουν το 10%% της αξίας της αρχικής σύμβασης (%s €).',
             to_char(v_savings_total,'FM999G999G990D00'),
             to_char(c.initial_value_net*0.10,'FM999G999G990D00')),
      'hard', 'N4412/156/3c')::app.blocker;
  end if;

  -- (5) Απαγόρευση εισαγωγής ΝΕΩΝ άρθρων με χρηματοδότηση από επί έλασσον
  if exists (select 1 from public.ape_lines al
             where al.ape_id = p_ape_id
               and al.is_new_item
               and al.funding_source = 'epi_elasson') then
    return next ('APE_NEW_ITEM_FROM_SAVINGS',
      'Δεν επιτρέπεται η κάλυψη ΝΕΩΝ άρθρων (μη περιλαμβανομένων στην αρχική σύμβαση) από επί έλασσον δαπάνες.',
      'hard', 'N4412/156/3c')::app.blocker;
  end if;

  -- (6) Γνωμοδότηση Τεχνικού Συμβουλίου όπου απαιτείται
  if (a.supplementary_needed or v_savings_total > 0)
     and a.tc_opinion_id is null then
    return next ('APE_TC_OPINION',
      'Απαιτείται γνωμοδότηση Τεχνικού Συμβουλίου (συμπληρωματική σύμβαση ή χρήση επί έλασσον δαπανών).',
      'hard', 'N4412/156/1e')::app.blocker;
  end if;

  -- (7) Υπογραφή/κοινοποίηση στον ανάδοχο
  if a.contractor_signature is null then
    return next ('APE_SIGNATURE',
      'Ο ΑΠΕ δεν έχει υπογραφεί από τον ανάδοχο ούτε έχει κοινοποιηθεί κατ'' άρθρο 143.',
      'soft', 'N4412/156/7')::app.blocker;
  end if;

  -- (8) ΠΚΤΜΝΕ όταν υπάρχουν νέα άρθρα
  if exists (select 1 from public.ape_lines al where al.ape_id = p_ape_id and al.is_new_item)
     and a.new_price_protocol_id is null then
    return next ('APE_PKTMNE_MISSING',
      'Ο ΑΠΕ περιλαμβάνει νέες εργασίες χωρίς συνοδευτικό Π.Κ.Τ.Μ.Ν.Ε.',
      'hard', 'N4412/156/5')::app.blocker;
  end if;
end $$;

comment on function app.ape_validation(uuid) is
  'Ελεγκτής ορίων άρθρου 156 ν.4412/2016: 50% σωρευτική αύξηση, 9%/15% απρόβλεπτα, '
  '20% ανά ομάδα εργασιών και 10% συνολικά για επί έλασσον, απαγόρευση νέων άρθρων '
  'από επί έλασσον, υποχρεωτική γνωμοδότηση Τεχνικού Συμβουλίου, ΠΚΤΜΝΕ.';

create or replace function app.guard_ape_approval()
returns trigger language plpgsql security definer set search_path = public, app as $$
declare v_blockers text;
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    select string_agg('• ' || b.message || ' [' || b.legal_ref || ']', E'\n')
      into v_blockers
    from app.ape_validation(new.id) b where b.severity = 'hard';

    if v_blockers is not null then
      raise exception E'ΔΕΝ ΕΠΙΤΡΕΠΕΤΑΙ η έγκριση του ΑΠΕ.\n%', v_blockers
        using errcode = 'check_violation';
    end if;
    if new.approved_at is null then new.approved_at := current_date; end if;
  end if;
  return new;
end $$;

create trigger trg_guard_ape_approval
  before update on public.ape
  for each row execute function app.guard_ape_approval();

-- ---------------------------------------------------------------------
-- 9.4 ΛΟΓΑΡΙΑΣΜΟΙ / ΠΙΣΤΟΠΟΙΗΣΕΙΣ (άρθρο 152)
-- ---------------------------------------------------------------------
create table public.payment_certificates (
  id                    uuid primary key default gen_random_uuid(),
  project_id            uuid not null references public.projects(id) on delete cascade,
  ptype                 public.payment_type not null default 'tmimatikos',
  serial_no             integer not null,               -- Α/Α λογαριασμού
  period_from           date,
  period_to             date,
  measurement_id        uuid references public.measurements(id),
  budget_version_id     uuid references public.budget_versions(id),

  submitted_at          date,
  approval_due          date,                           -- submitted_at + 1 μήνας
  returned_at           date,                           -- Επιστροφή για συμπλήρωση
  resubmitted_at        date,
  status                public.payment_status not null default 'draft',
  approved_at           date,
  approved_by           uuid references public.profiles(id),
  deemed_approved       boolean not null default false, -- Σιωπηρή έγκριση

  -- Οικονομικά στοιχεία
  works_cumulative      numeric(14,2) not null default 0,
  ge_oe_amount          numeric(14,2) not null default 0,
  apologistika_amount   numeric(14,2) not null default 0,
  revision_amount       numeric(14,2) not null default 0,
  compensations         numeric(14,2) not null default 0,  -- Αναγνωρισμένες αποζημιώσεις
  gross_cumulative      numeric(14,2) not null default 0,
  previous_certified    numeric(14,2) not null default 0,
  period_amount         numeric(14,2) generated always as
                          (gross_cumulative - previous_certified) stored,

  -- Κρατήσεις / μειώσεις
  advance_amortization  numeric(14,2) not null default 0, -- Απόσβεση προκαταβολής (άρθρο 150)
  advance_interest      numeric(14,2) not null default 0,
  penalties_amount      numeric(14,2) not null default 0, -- Ποινικές ρήτρες (άρθρα 146,148,151)
  retentions_pct        numeric(5,2)  not null default 5.00,  -- Κρατήσεις 5% (άρθρο 152)
  retentions_amount     numeric(14,2) not null default 0,
  other_deductions      numeric(14,2) not null default 0,
  vat_rate              numeric(5,2)  not null default 24.00,
  vat_amount            numeric(14,2) not null default 0,
  net_payable           numeric(14,2) not null default 0,

  -- Συνημμένα (άρθρο 152)
  has_summary_table     boolean not null default false, -- Ανακεφαλαιωτικός συνοπτικός πίνακας επιμετρήσεων
  has_revision_calc     boolean not null default false, -- Υπολογισμός αναθεώρησης
  has_apologistika_docs boolean not null default false, -- Δικαιολογητικά απολογιστικών
  has_decisions         boolean not null default false, -- Αποφάσεις αποζημιώσεων/ρητρών

  payment_order_no      text,                           -- Αρ. χρηματικού εντάλματος
  paid_at               date,
  document_id           uuid references public.documents(id),
  legal_ref_id          text references public.legal_refs(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (project_id, ptype, serial_no)
);

create trigger trg_payment_certificates_touch
  before update on public.payment_certificates
  for each row execute function app.touch_updated_at();

comment on table public.payment_certificates is
  'Λογαριασμοί (άρθρο 152 ν.4412/2016). Υποβάλλονται στη Δ.Υ., η οποία τους '
  'ελέγχει, διορθώνει και ΕΓΚΡΙΝΕΙ ΕΝΤΟΣ ΕΝΟΣ (1) ΜΗΝΟΣ. Αν η προθεσμία παρέλθει '
  'άπρακτη, ο λογαριασμός ΘΕΩΡΕΙΤΑΙ ΕΓΚΕΚΡΙΜΕΝΟΣ και καθίσταται πληρωτέος, '
  'υπόκειται όμως σε μεταγενέστερο έλεγχο και διόρθωση. Σε κάθε πληρωμή '
  'διενεργούνται κρατήσεις 5%.';

create table public.payment_certificate_lines (
  id                 uuid primary key default gen_random_uuid(),
  certificate_id     uuid not null references public.payment_certificates(id) on delete cascade,
  budget_item_id     uuid references public.budget_items(id) on delete set null,
  item_code          text not null,
  description        text not null,
  unit               text,
  unit_price         numeric(14,4) not null default 0,
  qty_cumulative     numeric(16,4) not null default 0,
  qty_previous       numeric(16,4) not null default 0,
  amount_cumulative  numeric(14,2) not null default 0,
  work_group_id      bigint references public.work_groups(id)
);

-- Κανόνες: προαπαιτούμενα υποβολής λογαριασμού
create or replace function app.payment_validation(p_cert_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare pc public.payment_certificates%rowtype;
begin
  select * into pc from public.payment_certificates where id = p_cert_id;
  if not found then return; end if;

  if pc.measurement_id is null then
    return next ('PAY_NO_MEASUREMENT',
      'Δεν έχει συνδεθεί εγκεκριμένη επιμέτρηση. Η υποβολή επιμέτρησης αποτελεί προϋπόθεση πληρωμής.',
      'hard', 'N4412/151/2')::app.blocker;
  else
    if not exists (select 1 from public.measurements m
                   where m.id = pc.measurement_id
                     and m.status in ('approved','deemed_approved')) then
      return next ('PAY_MEASUREMENT_NOT_APPROVED',
        'Η συνδεδεμένη επιμέτρηση δεν έχει εγκριθεί.',
        'hard', 'N4412/151/2')::app.blocker;
    end if;
  end if;

  if not pc.has_summary_table then
    return next ('PAY_NO_SUMMARY',
      'Λείπει ο ανακεφαλαιωτικός συνοπτικός πίνακας των επιμετρήσεων εργασιών.',
      'hard', 'N4412/152')::app.blocker;
  end if;

  if pc.revision_amount <> 0 and not pc.has_revision_calc then
    return next ('PAY_NO_REVISION_CALC',
      'Περιλαμβάνεται αναθεώρηση χωρίς συνημμένο υπολογισμό αναθεώρησης.',
      'hard', 'N4412/152')::app.blocker;
  end if;

  if pc.apologistika_amount <> 0 and not pc.has_apologistika_docs then
    return next ('PAY_NO_APOL_DOCS',
      'Περιλαμβάνονται απολογιστικές εργασίες χωρίς τα προβλεπόμενα δικαιολογητικά.',
      'hard', 'N4412/154')::app.blocker;
  end if;

  -- Ο τελικός λογαριασμός προϋποθέτει παραλαβή & εγκεκριμένο πρωτόκολλο
  if pc.ptype = 'telikos' then
    if not exists (select 1 from public.acceptances ac
                   where ac.project_id = pc.project_id
                     and ac.status in ('completed','auto_completed')) then
      return next ('PAY_FINAL_NO_ACCEPTANCE',
        'Ο τελικός λογαριασμός υποβάλλεται μετά την παραλαβή του έργου και την έγκριση του πρωτοκόλλου.',
        'hard', 'N4412/152')::app.blocker;
    end if;
  end if;
end $$;

-- Αυτόματος υπολογισμός προθεσμίας & σιωπηρής έγκρισης
create or replace function app.set_payment_dates()
returns trigger language plpgsql as $$
begin
  if new.submitted_at is not null then
    new.approval_due := (coalesce(new.resubmitted_at, new.submitted_at)
                         + interval '1 month')::date;
  end if;
  new.retentions_amount := round(new.gross_cumulative * new.retentions_pct / 100, 2)
                           - coalesce((select sum(p.retentions_amount)
                                       from public.payment_certificates p
                                       where p.project_id = new.project_id
                                         and p.serial_no < new.serial_no
                                         and p.ptype = new.ptype), 0);
  -- Σημείωση: η period_amount είναι generated column και υπολογίζεται ΜΕΤΑ τα
  -- BEFORE triggers, γι' αυτό εδώ αναπαράγεται ρητά ο τύπος της.
  new.net_payable := round(
      (new.gross_cumulative - new.previous_certified)
    - new.advance_amortization - new.advance_interest
    - new.penalties_amount - new.retentions_amount - new.other_deductions, 2);
  new.vat_amount := round(greatest(new.net_payable,0) * new.vat_rate / 100, 2);
  return new;
end $$;

create trigger trg_set_payment_dates
  before insert or update on public.payment_certificates
  for each row execute function app.set_payment_dates();
