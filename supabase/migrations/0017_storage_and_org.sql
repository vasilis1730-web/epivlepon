-- =====================================================================
-- 0017_storage_and_org.sql — Φορέας, αποθηκευτικοί κάδοι, πρωτόκολλο
-- ---------------------------------------------------------------------
--  • εγγραφή του φορέα (Δήμος Ρόδου) με στοιχεία επιστολόχαρτου
--  • τρεις κάδοι Supabase Storage: templates / documents / photos
--  • πολιτικές πρόσβασης στα αντικείμενα κάθε κάδου
--  • μετρητής αριθμού πρωτοκόλλου ανά φορέα και έτος
-- =====================================================================

-- ---- 1. Φορέας ------------------------------------------------------
insert into public.organizations (id, name, unit, afm, address, phone, email, letterhead_html)
values ('00000000-0000-0000-0000-0000000000d1',
        'Δήμος Ρόδου',
        'Διεύθυνση Τεχνικών Έργων & Υποδομών',
        '997654321',
        'Πλατεία Ελευθερίας 1, 851 00 Ρόδος',
        '2241361300',
        'texniki@rhodes.gr',
        '<div class="letterhead"><div class="emblem">ΕΛΛΗΝΙΚΗ ΔΗΜΟΚΡΑΤΙΑ</div>' ||
        '<div class="org">ΔΗΜΟΣ ΡΟΔΟΥ</div>' ||
        '<div class="unit">Δ/ΝΣΗ ΤΕΧΝΙΚΩΝ ΕΡΓΩΝ &amp; ΥΠΟΔΟΜΩΝ</div></div>')
on conflict (id) do nothing;

-- ---- 2. Κάδοι αποθήκευσης ------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('templates', 'templates', false, 20971520, array[
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'text/html']),
  ('documents', 'documents', false, 52428800, null),
  ('photos',    'photos',    false, 26214400, array[
      'image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do nothing;

-- ---- 3. Πολιτικές αντικειμένων --------------------------------------
-- templates: ανάγνωση από κάθε συνδεδεμένο χρήστη, ανέβασμα/τροποποίηση
-- μόνο από τη Δ.Υ./Προϊσταμένη Αρχή (τα πρότυπα είναι υπηρεσιακά έντυπα).
drop policy if exists templates_read   on storage.objects;
create policy templates_read on storage.objects
  for select using (bucket_id = 'templates' and app.uid() is not null);

drop policy if exists templates_write  on storage.objects;
create policy templates_write on storage.objects
  for insert with check (bucket_id = 'templates' and app.is_service_wide());

drop policy if exists templates_update on storage.objects;
create policy templates_update on storage.objects
  for update using (bucket_id = 'templates' and app.is_service_wide());

-- documents: κάθε παραγόμενο έγγραφο ακολουθεί τα δικαιώματα του έργου
-- του, μέσω της αντίστοιχης εγγραφής public.documents.
drop policy if exists documents_read  on storage.objects;
create policy documents_read on storage.objects
  for select using (
    bucket_id = 'documents'
    and exists (select 1 from public.documents d
                 where d.storage_path = storage.objects.name
                   and app.can_read_project(d.project_id)));

drop policy if exists documents_write on storage.objects;
create policy documents_write on storage.objects
  for insert with check (bucket_id = 'documents' and app.uid() is not null);

-- photos: ψηφιακές φωτογραφίες αφανών εργασιών (άρθρο 151 §7)
drop policy if exists photos_read  on storage.objects;
create policy photos_read on storage.objects
  for select using (bucket_id = 'photos' and app.uid() is not null);

drop policy if exists photos_write on storage.objects;
create policy photos_write on storage.objects
  for insert with check (bucket_id = 'photos' and app.uid() is not null);

-- ---- 4. Μετρητής πρωτοκόλλου ----------------------------------------
create table if not exists public.protocol_counters (
  org_id   uuid    not null references public.organizations(id) on delete cascade,
  year     integer not null,
  last_no  integer not null default 0,
  primary key (org_id, year)
);

alter table public.protocol_counters enable row level security;

drop policy if exists protocol_counters_sel on public.protocol_counters;
create policy protocol_counters_sel on public.protocol_counters
  for select using (org_id = app.my_org());

create or replace function public.next_protocol_no(p_org uuid)
returns integer
language plpgsql
security definer
set search_path = public, app
as $$
declare v_year integer := extract(year from current_date)::int; v_no integer;
begin
  -- Ο αριθμός πρωτοκόλλου αποδίδεται ΜΟΝΟ για τον φορέα του χρήστη· έτσι
  -- η συνάρτηση δεν μπορεί να χρησιμοποιηθεί για κατανάλωση της σειράς
  -- πρωτοκόλλου άλλου φορέα.
  if p_org is distinct from app.my_org() then
    raise exception 'Δεν έχετε δικαίωμα απόδοσης αριθμού πρωτοκόλλου για τον φορέα αυτόν.';
  end if;

  insert into public.protocol_counters (org_id, year, last_no)
  values (p_org, v_year, 1)
  on conflict (org_id, year) do update set last_no = public.protocol_counters.last_no + 1
  returning last_no into v_no;
  return v_no;
end $$;

comment on function public.next_protocol_no(uuid) is
  'Επόμενος αύξων αριθμός πρωτοκόλλου του φορέα για το τρέχον έτος (ατομική πράξη).';

revoke all on function public.next_protocol_no(uuid) from public, anon;
grant execute on function public.next_protocol_no(uuid) to authenticated, service_role;
