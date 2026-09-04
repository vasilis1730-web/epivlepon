-- =====================================================================
-- Migration 0027 : Ποιος αποκτά προφίλ όταν εγγράφεται
-- =====================================================================
-- Οι δημόσιες εγγραφές του Supabase απενεργοποιούνται από τον πίνακα
-- ελέγχου (Authentication → Sign In / Providers). Αυτό όμως είναι ΡΥΘΜΙΣΗ:
-- ένα κατά λάθος «on» αρκεί για να ξανανοίξει.
--
-- Το πρόβλημα που λύνεται εδώ: η `app.handle_new_user()` πρόσδενε ΚΑΘΕ νέο
-- λογαριασμό στον μοναδικό φορέα. Δοκιμή σε καθαρή βάση με χρήστη χωρίς
-- κανέναν υπηρεσιακό ρόλο έδειξε 0 έργα, 0 συμβάσεις, 0 έγγραφα — αλλά
-- **3 προφίλ και 1 φορέα**: ονόματα, ειδικότητες και στοιχεία επικοινωνίας
-- του προσωπικού της Δ/νσης. Δεν είναι δεδομένα έργου, είναι όμως διαρροή.
--
-- Λύση: προφίλ αποκτά μόνο διεύθυνση που περιλαμβάνεται στη λίστα. Χωρίς
-- προφίλ η `app.my_org()` επιστρέφει NULL και ΚΑΘΕ policy του σχήματος
-- αποκλείει τη γραμμή — ο λογαριασμός υπάρχει και δεν βλέπει τίποτε.
-- ---------------------------------------------------------------------

create table if not exists app.signup_allowlist (
  pattern     text primary key,     -- '@dimosrodou.gr' ή πλήρης διεύθυνση
  note        text,
  created_at  timestamptz not null default now()
);

comment on table app.signup_allowlist is
  'Ποιες διευθύνσεις αποκτούν προφίλ κατά την εγγραφή. Μοτίβο που αρχίζει με '
  '«@» ταιριάζει σε ολόκληρο τομέα· διαφορετικά συγκρίνεται ολόκληρη η '
  'διεύθυνση. Η σύγκριση είναι case-insensitive.';

-- Σπάρσιμο από ό,τι ήδη δουλεύει, με ΑΚΡΙΒΕΙΣ διευθύνσεις — όχι τομείς.
-- Ο διαχειριστής μπορεί κάλλιστα να έχει λογαριασμό σε δημόσιο πάροχο· ένα
-- '@gmail.com' στη λίστα θα άνοιγε την εφαρμογή σε ολόκληρο τον πλανήτη.
-- Ο τομέας του ΦΟΡΕΑ προστίθεται χωριστά, από τη διεύθυνση επικοινωνίας του.
insert into app.signup_allowlist (pattern, note)
select distinct lower(p.email), 'υπάρχον προφίλ κατά την εφαρμογή του 0027'
from public.profiles p
where p.email like '%@%'
on conflict (pattern) do nothing;

insert into app.signup_allowlist (pattern, note)
select distinct '@' || lower(split_part(o.email, '@', 2)),
       'τομέας του φορέα (organizations.email)'
from public.organizations o
where o.email like '%@%'
on conflict (pattern) do nothing;

create or replace function app.signup_allowed(p_email text)
returns boolean
language sql stable security definer set search_path = public, app as $$
  select exists (
    select 1 from app.signup_allowlist a
    where lower(p_email) = lower(a.pattern)
       or (a.pattern like '@%' and lower(p_email) like '%' || lower(a.pattern))
  )
$$;

comment on function app.signup_allowed(text) is
  'Ταιριάζει η διεύθυνση σε κάποιο μοτίβο του app.signup_allowlist;';

-- ---------------------------------------------------------------------
-- 27.1 handle_new_user: προφίλ μόνο σε επιτρεπόμενη διεύθυνση
--      ΠΟΤΕ exception εδώ. Το trigger τρέχει μέσα στη ροή του GoTrue και
--      κάθε σφάλμα του γίνεται «Database error querying schema» σε ΚΑΘΕ
--      ενέργεια στον auth.users — και στην απλή σύνδεση.
-- ---------------------------------------------------------------------
create or replace function app.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare v_org uuid;
begin
  if new.email is null or not app.signup_allowed(new.email) then
    -- Ο λογαριασμός δημιουργείται, προφίλ δεν αποκτά: my_org() = NULL,
    -- οπότε καμία policy δεν του επιστρέφει γραμμή. Η ένταξη γίνεται
    -- ρητά, από διαχειριστή, με public.admit_user().
    return new;
  end if;

  select id into v_org from public.organizations order by created_at limit 1;
  if v_org is null then return new; end if;

  insert into public.profiles (id, org_id, full_name, email, specialty)
  values (new.id, v_org,
          coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
          new.email, new.raw_user_meta_data->>'specialty')
  on conflict (id) do nothing;
  return new;
end $$;

grant execute on function app.handle_new_user() to supabase_auth_admin;

-- ---------------------------------------------------------------------
-- 27.2 Ένταξη υπάρχοντος λογαριασμού από διαχειριστή
-- ---------------------------------------------------------------------
create or replace function public.admit_user(
  p_email text, p_full_name text default null, p_specialty text default null)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare v_uid uuid; v_org uuid;
begin
  if not app.is_admin() then
    raise exception 'Η ένταξη χρήστη ανήκει στον διαχειριστή του φορέα.';
  end if;

  select id into v_uid from auth.users where lower(email) = lower(p_email);
  if v_uid is null then
    raise exception 'Δεν υπάρχει λογαριασμός με τη διεύθυνση %.', p_email;
  end if;

  select id into v_org from public.organizations order by created_at limit 1;
  if v_org is null then
    raise exception 'Δεν έχει οριστεί φορέας.';
  end if;

  insert into public.profiles (id, org_id, full_name, email, specialty)
  values (v_uid, v_org, coalesce(p_full_name, split_part(p_email,'@',1)),
          p_email, p_specialty)
  on conflict (id) do update
    set full_name = excluded.full_name,
        specialty = coalesce(excluded.specialty, public.profiles.specialty);
  return v_uid;
end $$;

comment on function public.admit_user(text, text, text) is
  'Δίνει προφίλ σε λογαριασμό που εγγράφηκε εκτός λίστας. SECURITY DEFINER με '
  'εσωτερικό έλεγχο app.is_admin(). Ο ρόλος του χρήστη ορίζεται χωριστά — '
  'το προφίλ από μόνο του δεν δίνει πρόσβαση σε κανένα έργο.';

revoke all on function public.admit_user(text, text, text) from public, anon;
grant execute on function public.admit_user(text, text, text) to authenticated, service_role;

-- Η λίστα δεν εκτίθεται μέσω PostgREST (σχήμα app), αλλά ας είναι ρητό.
revoke all on table app.signup_allowlist from public, anon, authenticated;
