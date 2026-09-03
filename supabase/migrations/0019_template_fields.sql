-- =====================================================================
-- 0019_template_fields.sql — Δηλωτική χαρτογράφηση placeholder → πηγή
-- ---------------------------------------------------------------------
-- Κάθε placeholder ενός προτύπου αντιστοιχίζεται σε ΔΙΑΔΡΟΜΗ μέσα στο
-- αντικείμενο περιβάλλοντος που συνθέτει η Edge Function — ποτέ σε
-- αυθαίρετο SQL. Έτσι η προσθήκη νέου πεδίου σε πρότυπο δεν απαιτεί
-- ανάπτυξη κώδικα, και ταυτόχρονα δεν ανοίγει επιφάνεια επίθεσης.
--
--  source_kind: 'field'    → στήλη πίνακα           (π.χ. contracts.signed_at)
--               'query'    → παράγωγο αντικείμενο   (π.χ. supervisor.full_name)
--               'computed' → υπολογισμένη τιμή      (π.χ. maintenance_start)
--               'manual'   → συμπληρώνεται από τον χρήστη
--  data_type:   text | number | currency | quantity | date | date_long |
--               boolean | table
-- =====================================================================

-- ---- 1. Κοινά πεδία σε ΟΛΑ τα πρότυπα -------------------------------
insert into public.template_fields
  (template_id, placeholder, label, source_kind, source_path, data_type, is_required)
select t.id, f.placeholder, f.label, f.source_kind, f.source_path, f.data_type, f.is_required
from public.document_templates t
cross join (values
  ('{{ergo.titlos}}',                 'Τίτλος έργου',                    'field', 'projects.title',              'text',     true),
  ('{{ergo.kodikos}}',                'Κωδικός έργου',                   'field', 'projects.code',               'text',     true),
  ('{{symvasi.arithmos}}',            'Αριθμός σύμβασης',                'field', 'contracts.contract_no',       'text',     true),
  ('{{symvasi.imerominia_ypografis}}','Ημερομηνία υπογραφής',            'field', 'contracts.signed_at',         'date',     true),
  ('{{symvasi.aksia}}',               'Αξία αρχικής σύμβασης',           'field', 'contracts.initial_value_net', 'currency', true),
  ('{{anadoxos.epwnymia}}',           'Επωνυμία αναδόχου',               'field', 'contractors.name',            'text',     true),
  ('{{epivlepon.full_name}}',         'Ονοματεπώνυμο επιβλέποντος',      'query', 'supervisor.full_name',        'text',     true),
  ('{{epivlepon.specialty}}',         'Ειδικότητα επιβλέποντος',         'query', 'supervisor.specialty',        'text',     false),
  ('{{proistamenos.full_name}}',      'Ονοματεπώνυμο Προϊσταμένου Δ.Υ.', 'query', 'head.full_name',              'text',     true),
  ('{{proistamenos.specialty}}',      'Ειδικότητα Προϊσταμένου Δ.Υ.',    'query', 'head.specialty',              'text',     false)
) as f(placeholder, label, source_kind, source_path, data_type, is_required)
where t.is_active
on conflict do nothing;

-- ---- 2. Ειδικά πεδία ανά πρότυπο ------------------------------------
insert into public.template_fields
  (template_id, placeholder, label, source_kind, source_path, data_type, is_required)
select t.id, f.placeholder, f.label, f.source_kind, f.source_path, f.data_type, f.is_required
from public.document_templates t
join (values
  -- Έγκριση χρονοδιαγράμματος (άρθρο 145)
  ('EGKRISI_XRONOD', '{{symvasi.prothesmia_imeres}}',           'Συνολική προθεσμία (ημέρες)',           'field',    'contracts.total_duration_days', 'number', true),
  ('EGKRISI_XRONOD', '{{symvasi.lixi_prothesmias}}',            'Λήξη συνολικής προθεσμίας',             'field',    'contracts.current_end_date',    'date',   true),
  ('EGKRISI_XRONOD', '{{xronodiagramma.imerominia_ypovolis}}',  'Ημερομηνία υποβολής χρονοδιαγράμματος', 'field',    'schedules.submitted_at',        'date',   true),

  -- Π.Π.Α.Ε. (άρθρο 151 §7)
  ('PPAE', '{{afaneis.aa}}',                        'Α/Α δήλωσης αφανών',             'field',    'hidden_work_notices.serial_no',          'number', true),
  ('PPAE', '{{afaneis.perigrafi}}',                 'Περιγραφή αφανών εργασιών',      'field',    'hidden_work_notices.work_description',   'text',   true),
  ('PPAE', '{{afaneis.thesi}}',                     'Θέση',                           'field',    'hidden_work_notices.location',           'text',   true),
  ('PPAE', '{{afaneis.imerominia_prosklisis}}',     'Ημερομηνία πρόσκλησης',          'field',    'hidden_work_notices.invitation_sent_at', 'date',   true),
  ('PPAE', '{{afaneis.prothesmia_elegxou}}',        'Προθεσμία ελέγχου (3 ημέρες)',   'field',    'hidden_work_notices.inspection_due',     'date',   true),
  ('PPAE', '{{afaneis.imerominia_elegxou}}',        'Ημερομηνία ελέγχου',             'field',    'hidden_work_notices.inspected_at',       'date',   true),
  ('PPAE', '{{afaneis.imerominia_elegxou_pliris}}', 'Ημερομηνία ελέγχου (ολογράφως)', 'computed', 'inspection_date_long',                   'text',   true),
  ('PPAE', '{{afaneis.plithos_fotografion}}',       'Πλήθος ψηφιακών φωτογραφιών',    'field',    'hidden_work_notices.photos_count',       'number', true),

  -- Αναλυτική επιμέτρηση (άρθρο 151 §2)
  ('ANAL_EPIMETRISI', '{{epimetrisi.aa}}',                 'Α/Α επιμέτρησης',        'field',    'measurements.serial_no',          'number',   true),
  ('ANAL_EPIMETRISI', '{{epimetrisi.periodos}}',           'Περίοδος',               'computed', 'measurement_period',              'text',     false),
  ('ANAL_EPIMETRISI', '{{epimetrisi.tmima}}',              'Τμήμα έργου',            'field',    'measurements.work_section',       'text',     false),
  ('ANAL_EPIMETRISI', '{{epimetrisi.imerominia_ypovolis}}','Ημερομηνία υποβολής',    'field',    'measurements.submitted_at',       'date',     true),
  ('ANAL_EPIMETRISI', '{{epimetrisi.synolo_symvatikwn}}',  'Σύνολο συμβατικών',      'field',    'measurements.contractual_amount', 'currency', true),
  ('ANAL_EPIMETRISI', '{{epimetrisi.synolo_ektos}}',       'Σύνολο εκτός σύμβασης',  'field',    'measurements.extra_amount',       'currency', true),
  ('ANAL_EPIMETRISI', '{{epimetrisi.geniko_synolo}}',      'Γενικό σύνολο',          'field',    'measurements.total_amount',       'currency', true),
  ('ANAL_EPIMETRISI', '{{#each grammes}}',                 'Γραμμές επιμέτρησης (επαναλαμβανόμενη σειρά)', 'query', 'measurement_lines', 'table', true),

  -- Βεβαίωση περάτωσης (άρθρο 168)
  ('BEBAIOSI_PERATOSIS', '{{peraiosi.egkekrimenos_xronos}}',  'Εγκεκριμένος χρόνος περαίωσης',   'field',    'completions.approved_completion_date', 'date',   true),
  ('BEBAIOSI_PERATOSIS', '{{peraiosi.ekthesi_epivleponta}}',  'Ημ/νία έκθεσης επιβλέποντος',     'field',    'completions.supervisor_report_at',     'date',   true),
  ('BEBAIOSI_PERATOSIS', '{{peraiosi.pragmatiki_imerominia}}','Πραγματική ημερομηνία περαίωσης', 'field',    'completions.actual_completion_date',   'date',   true),
  ('BEBAIOSI_PERATOSIS', '{{peraiosi.enarksi_syntirisis}}',   'Έναρξη χρόνου συντήρησης',        'computed', 'maintenance_start',                   'date',   true),
  ('BEBAIOSI_PERATOSIS', '{{symvasi.mines_syntirisis}}',      'Μήνες υποχρεωτικής συντήρησης',   'field',    'contracts.maintenance_months',        'number', true),

  -- Πράξη μείωσης εγγύησης (άρθρο 72 §14 περ. β΄)
  ('PRAXH_MEIWSHS_EGG', '{{eggyisi.arithmos}}',            'Αριθμός εγγυητικής',                 'field',    'guarantees.guarantee_no',    'text',     true),
  ('PRAXH_MEIWSHS_EGG', '{{eggyisi.ekdotis}}',             'Εκδότης εγγυητικής',                 'field',    'guarantees.issuer',          'text',     true),
  ('PRAXH_MEIWSHS_EGG', '{{eggyisi.arxiko_poso}}',         'Αρχικό ποσό εγγύησης',               'field',    'guarantees.current_amount',  'currency', true),
  ('PRAXH_MEIWSHS_EGG', '{{eggyisi.poso_meiosis}}',        'Ποσό μείωσης (70%)',                 'computed', 'guarantee_reduction',        'currency', true),
  ('PRAXH_MEIWSHS_EGG', '{{eggyisi.ypoloipo}}',            'Υπόλοιπο μετά τη μείωση',            'computed', 'guarantee_remaining',        'currency', true),
  ('PRAXH_MEIWSHS_EGG', '{{teliki.imerominia_egkrisis}}',  'Ημ/νία έγκρισης τελικής επιμέτρησης','field',    'final_measurement.approved_at','date',    true)
) as f(doc_code, placeholder, label, source_kind, source_path, data_type, is_required)
  on f.doc_code = t.doc_code
where t.is_active
on conflict do nothing;
