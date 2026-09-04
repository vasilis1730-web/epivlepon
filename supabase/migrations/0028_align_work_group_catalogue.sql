-- =====================================================================
-- Migration 0028 : Ευθυγράμμιση του ενδεικτικού καταλόγου ομάδων
-- =====================================================================
-- Το 0013 σπέρνει πλέον τον κατάλογο αριθμημένο (1, 2, 3 …) και για τις δέκα
-- κατηγορίες έργων. Μια βάση που είχε ήδη εφαρμόσει το παλιό 0013 κρατά τον
-- προηγούμενο κατάλογο με γράμματα (A..F) και μόνο πέντε κατηγορίες· αυτό το
-- migration τη φέρνει στη νέα μορφή.
--
-- Η διαγραφή αγγίζει ΜΟΝΟ γραμμές του καταλόγου (project_id is null) που δεν
-- τις δείχνει κανένα δεδομένο. Ομάδα που χρησιμοποιείται ήδη ΔΕΝ διαγράφεται:
-- θα έσπαγε τον έλεγχο του ορίου 20% ανά ομάδα (άρθρο 156 §3γ) σε υπάρχοντα
-- έργα. Σε καθαρή εγκατάσταση το migration δεν αλλάζει τίποτε.
-- ---------------------------------------------------------------------

delete from public.work_groups wg
where wg.project_id is null
  and not exists (select 1 from public.budget_items              x where x.work_group_id = wg.id)
  and not exists (select 1 from public.ape_lines                 x where x.work_group_id = wg.id)
  and not exists (select 1 from public.hidden_work_notices       x where x.work_group_id = wg.id)
  and not exists (select 1 from public.new_price_items           x where x.work_group_id = wg.id)
  and not exists (select 1 from public.payment_certificate_lines x where x.work_group_id = wg.id)
  and not exists (select 1 from public.schedule_activities       x where x.work_group_id = wg.id);

insert into public.work_groups (category, code, title, legal_ref_id) values
('odopoiia','1','ΧΩΜΑΤΟΥΡΓΙΚΑ','YA38107/2017'),
('odopoiia','2','ΤΕΧΝΙΚΑ ΕΡΓΑ','YA38107/2017'),
('odopoiia','3','ΟΔΟΣΤΡΩΣΙΑ','YA38107/2017'),
('odopoiia','4','ΑΣΦΑΛΤΙΚΑ','YA38107/2017'),
('odopoiia','5','ΣΗΜΑΝΣΗ - ΑΣΦΑΛΙΣΗ','YA38107/2017'),
('oikodomika','1','ΧΩΜΑΤΟΥΡΓΙΚΑ - ΚΑΘΑΙΡΕΣΕΙΣ','YA38107/2017'),
('oikodomika','2','ΣΚΥΡΟΔΕΜΑΤΑ - ΟΠΛΙΣΜΟΙ','YA38107/2017'),
('oikodomika','3','ΤΟΙΧΟΠΟΙΙΕΣ - ΕΠΙΧΡΙΣΜΑΤΑ','YA38107/2017'),
('oikodomika','4','ΕΠΕΝΔΥΣΕΙΣ - ΕΠΙΣΤΡΩΣΕΙΣ','YA38107/2017'),
('oikodomika','5','ΚΟΥΦΩΜΑΤΑ - ΥΑΛΟΥΡΓΙΚΑ','YA38107/2017'),
('oikodomika','6','ΧΡΩΜΑΤΙΣΜΟΙ - ΛΟΙΠΕΣ ΤΕΛΕΙΩΣΕΙΣ','YA38107/2017'),
('ydraulika','1','ΧΩΜΑΤΟΥΡΓΙΚΑ','YA38107/2017'),
('ydraulika','2','ΣΩΛΗΝΩΣΕΙΣ - ΔΙΚΤΥΑ','YA38107/2017'),
('ydraulika','3','ΤΕΧΝΙΚΑ ΕΡΓΑ - ΦΡΕΑΤΙΑ','YA38107/2017'),
('ydraulika','4','ΗΛΕΚΤΡΟΜΗΧΑΝΟΛΟΓΙΚΑ','YA38107/2017'),
('hlektromichanologika','1','ΗΛΕΚΤΡΙΚΕΣ ΕΓΚΑΤΑΣΤΑΣΕΙΣ ΙΣΧΥΡΩΝ ΡΕΥΜΑΤΩΝ','YA38107/2017'),
('hlektromichanologika','2','ΗΛΕΚΤΡΙΚΕΣ ΕΓΚΑΤΑΣΤΑΣΕΙΣ ΑΣΘΕΝΩΝ ΡΕΥΜΑΤΩΝ','YA38107/2017'),
('hlektromichanologika','3','ΕΓΚΑΤΑΣΤΑΣΕΙΣ ΘΕΡΜΑΝΣΗΣ - ΚΛΙΜΑΤΙΣΜΟΥ - ΑΕΡΙΣΜΟΥ','YA38107/2017'),
('hlektromichanologika','4','ΥΔΡΑΥΛΙΚΕΣ ΕΓΚΑΤΑΣΤΑΣΕΙΣ ΚΤΙΡΙΩΝ','YA38107/2017'),
('hlektromichanologika','5','ΠΥΡΟΣΒΕΣΗ - ΠΥΡΑΝΙΧΝΕΥΣΗ','YA38107/2017'),
('prasino','1','ΔΑΣΟΤΕΧΝΙΚΑ','YA38107/2017'),
('prasino','2','ΕΡΓΑ ΑΠΟΚΑΤΑΣΤΑΣΕΩΝ ΚΑΙ ΠΡΟΣΤΑΣΙΑΣ','YA38107/2017'),
('prasino','3','ΦΥΤΕΥΣΕΙΣ','YA38107/2017'),
('prasino','4','ΑΡΔΕΥΣΗ','YA38107/2017'),
('limenika','1','ΚΑΘΑΙΡΕΣΕΙΣ - ΒΥΘΟΚΟΡΗΣΕΙΣ - ΕΠΙΧΩΣΕΙΣ','YA38107/2017'),
('limenika','2','ΛΙΘΟΡΡΙΠΕΣ - ΦΥΣΙΚΟΙ ΟΓΚΟΛΙΘΟΙ','YA38107/2017'),
('limenika','3','ΣΚΥΡΟΔΕΜΑΤΑ','YA38107/2017'),
('limenika','4','ΤΕΧΝΙΚΑ ΕΡΓΑ - ΕΞΟΠΛΙΣΜΟΣ','YA38107/2017'),
('limenika','5','ΗΛΕΚΤΡΟΜΗΧΑΝΟΛΟΓΙΚΑ','YA38107/2017'),
('viomichanika_energeiaka','1','ΧΩΜΑΤΟΥΡΓΙΚΑ - ΚΑΘΑΙΡΕΣΕΙΣ','YA38107/2017'),
('viomichanika_energeiaka','2','ΔΟΜΙΚΑ ΕΡΓΑ','YA38107/2017'),
('viomichanika_energeiaka','3','ΜΗΧΑΝΟΛΟΓΙΚΟΣ ΕΞΟΠΛΙΣΜΟΣ','YA38107/2017'),
('viomichanika_energeiaka','4','ΗΛΕΚΤΡΟΛΟΓΙΚΟΣ ΕΞΟΠΛΙΣΜΟΣ - ΑΥΤΟΜΑΤΙΣΜΟΙ','YA38107/2017'),
('viomichanika_energeiaka','5','ΔΙΚΤΥΑ - ΣΩΛΗΝΩΣΕΙΣ','YA38107/2017'),
('katharismos_epexergasia','1','ΧΩΜΑΤΟΥΡΓΙΚΑ','YA38107/2017'),
('katharismos_epexergasia','2','ΔΟΜΙΚΑ ΕΡΓΑ - ΔΕΞΑΜΕΝΕΣ','YA38107/2017'),
('katharismos_epexergasia','3','ΔΙΚΤΥΑ - ΣΩΛΗΝΩΣΕΙΣ','YA38107/2017'),
('katharismos_epexergasia','4','ΜΗΧΑΝΟΛΟΓΙΚΟΣ ΕΞΟΠΛΙΣΜΟΣ','YA38107/2017'),
('katharismos_epexergasia','5','ΗΛΕΚΤΡΟΛΟΓΙΚΑ - ΑΥΤΟΜΑΤΙΣΜΟΙ','YA38107/2017'),
('geotrhseis','1','ΔΙΑΤΡΗΣΕΙΣ','YA38107/2017'),
('geotrhseis','2','ΣΩΛΗΝΩΣΕΙΣ - ΦΙΛΤΡΑ','YA38107/2017'),
('geotrhseis','3','ΑΝΑΠΤΥΞΗ - ΔΟΚΙΜΑΣΤΙΚΕΣ ΑΝΤΛΗΣΕΙΣ','YA38107/2017'),
('geotrhseis','4','ΗΛΕΚΤΡΟΜΗΧΑΝΟΛΟΓΙΚΑ','YA38107/2017'),
('loipa','1','ΧΩΜΑΤΟΥΡΓΙΚΑ','YA38107/2017'),
('loipa','2','ΔΟΜΙΚΑ ΕΡΓΑ','YA38107/2017'),
('loipa','3','ΗΛΕΚΤΡΟΜΗΧΑΝΟΛΟΓΙΚΑ','YA38107/2017'),
('loipa','4','ΛΟΙΠΕΣ ΕΡΓΑΣΙΕΣ','YA38107/2017')
on conflict do nothing;

-- Ομάδα του παλιού καταλόγου που επέζησε επειδή χρησιμοποιείται, ανήκει πλέον
-- στο έργο που τη χρησιμοποιεί: κατάλογος και δεδομένα έργου δεν ανακατεύονται.
update public.work_groups wg
set project_id = (
  select bi.project_id from public.budget_items bi
  where bi.work_group_id = wg.id limit 1)
where wg.project_id is null
  and exists (select 1 from public.budget_items bi where bi.work_group_id = wg.id);
