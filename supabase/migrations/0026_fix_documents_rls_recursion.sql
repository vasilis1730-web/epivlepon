-- =====================================================================
-- Migration 0026 : Άρση αμοιβαίας αναδρομής στα RLS των εγγράφων
-- =====================================================================
-- ΣΟΒΑΡΟ ΣΦΑΛΜΑ ΠΑΡΑΓΩΓΗΣ. Δύο policies παρέπεμπαν η μία στην άλλη:
--
--   documents_sel               → select ... from document_communications
--   document_communications_sel → select ... from documents
--
-- Η PostgreSQL εντοπίζει τον κύκλο κατά τον σχεδιασμό και ματαιώνει ΟΛΟ το
-- ερώτημα — δεν «κόβει» τον έναν κλάδο του OR. Αποτέλεσμα: κάθε select στα
-- `documents`, `document_communications` και `document_signatures` απέτυχε με
-- «infinite recursion detected in policy» για ΚΑΘΕ χρήστη, επιβλέποντα και
-- προϊστάμενο συμπεριλαμβανομένων. Η οθόνη «Έγγραφα» ήταν άχρηστη στην
-- παραγωγή· δεν φάνηκε επειδή η ανάπτυξη γινόταν σε λειτουργία επίδειξης.
--
-- Λύση: ο ένας κρίκος γίνεται συνάρτηση SECURITY DEFINER, ώστε να μη
-- ξαναπερνά από το RLS του άλλου πίνακα. Η συνάρτηση επιστρέφει ΜΟΝΟ boolean
-- για συγκεκριμένο έγγραφο και δεν διευρύνει την ορατότητα: ο έλεγχος
-- `app.is_contractor_of(project_id)` παραμένει έξω από αυτήν.
-- ---------------------------------------------------------------------

create or replace function app.doc_communicated_to(p_doc uuid, p_party public.party_type)
returns boolean
language sql stable security definer set search_path = public, app as $$
  select exists (
    select 1 from public.document_communications dc
    where dc.document_id = p_doc and dc.recipient_party = p_party
  )
$$;

comment on function app.doc_communicated_to(uuid, public.party_type) is
  'Έχει κοινοποιηθεί το έγγραφο στο συγκεκριμένο μέρος; SECURITY DEFINER ώστε '
  'το policy των documents να μη διαβάζει τον document_communications μέσω RLS '
  'που με τη σειρά του διαβάζει τα documents (αμοιβαία αναδρομή).';

revoke all on function app.doc_communicated_to(uuid, public.party_type) from public, anon;

drop policy if exists documents_sel on public.documents;
create policy documents_sel on public.documents for select
  using (
    app.can_supervise(project_id) or app.can_approve(project_id)
    or (app.is_contractor_of(project_id) and (
          status in ('communicated','approved','deemed_approved')
          or app.doc_communicated_to(documents.id, 'anadochos')
          or created_by = app.uid()))
  );

comment on policy documents_sel on public.documents is
  'Επιβλέπων και Δ.Υ. βλέπουν τα πάντα· ο ανάδοχος μόνο όσα του κοινοποιήθηκαν, '
  'όσα εγκρίθηκαν (ρητά ή σιωπηρά) και όσα υπέβαλε ο ίδιος.';

-- Ο δεύτερος κρίκος: για να διαβαστεί μια κοινοποίηση αρκεί το δικαίωμα στο
-- ΕΡΓΟ του εγγράφου — δεν χρειάζεται να περάσει και από το policy των
-- documents, που ξαναφέρνει τον κύκλο.
create or replace function app.doc_project(p_doc uuid)
returns uuid
language sql stable security definer set search_path = public, app as $$
  select d.project_id from public.documents d where d.id = p_doc
$$;

comment on function app.doc_project(uuid) is
  'Το έργο στο οποίο ανήκει ένα έγγραφο, χωρίς να ενεργοποιείται το RLS των '
  'documents. Ο έλεγχος δικαιώματος γίνεται από τον καλούντα.';

revoke all on function app.doc_project(uuid) from public, anon;
grant execute on function app.doc_project(uuid) to authenticated, service_role;
grant execute on function app.doc_communicated_to(uuid, public.party_type) to authenticated, service_role;

drop policy if exists document_communications_sel on public.document_communications;
create policy document_communications_sel on public.document_communications for select
  using (app.can_read_project(app.doc_project(document_id)));

drop policy if exists document_communications_mod on public.document_communications;
create policy document_communications_mod on public.document_communications for all
  using (app.can_supervise(app.doc_project(document_id)))
  with check (app.can_supervise(app.doc_project(document_id)));

drop policy if exists document_signatures_sel on public.document_signatures;
create policy document_signatures_sel on public.document_signatures for select
  using (app.can_read_project(app.doc_project(document_id)));

drop policy if exists document_signatures_ins on public.document_signatures;
create policy document_signatures_ins on public.document_signatures for insert
  with check (app.can_read_project(app.doc_project(document_id)));
