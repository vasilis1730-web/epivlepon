-- Ελάχιστα υποκατάστατα των σχημάτων που παρέχει η πλατφόρμα Supabase,
-- ώστε τα migrations να μπορούν να ελεγχθούν σε τοπική PostgreSQL.
create schema if not exists auth;
create schema if not exists storage;
create schema if not exists extensions;

-- Το Supabase εγκαθιστά το pgcrypto στο σχήμα extensions· το demo seed
-- καλεί extensions.crypt()/gen_salt() για τους κωδικούς των χρηστών.
create extension if not exists pgcrypto with schema extensions;

do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon')          then create role anon          nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='service_role')  then create role service_role  nologin noinherit bypassrls; end if;
  if not exists (select 1 from pg_roles where rolname='supabase_auth_admin') then create role supabase_auth_admin nologin noinherit; end if;
end $$;

-- ΠΡΟΣΟΧΗ: οι στήλες των token αντιγράφουν το πραγματικό σχήμα του GoTrue,
-- όπου είναι text ΧΩΡΙΣ προεπιλογή. Η υπηρεσία Auth τις διαβάζει σε μη
-- μηδενίσιμα πεδία, οπότε ένα NULL εκεί ρίχνει κάθε προσπάθεια σύνδεσης με
-- «Database error querying schema». Τις κρατάμε έτσι επίτηδες, ώστε ο έλεγχος
-- να πιάνει το λάθος πριν φτάσει στην παραγωγή.
create table if not exists auth.users (
  instance_id uuid,
  id uuid primary key,
  aud text, role text, email text unique,
  encrypted_password text, email_confirmed_at timestamptz,
  raw_app_meta_data jsonb, raw_user_meta_data jsonb,
  confirmation_token text, recovery_token text,
  email_change_token_new text, email_change text,
  email_change_token_current text,
  phone text, phone_change text, phone_change_token text,
  reauthentication_token text,
  is_super_admin boolean, banned_until timestamptz, deleted_at timestamptz,
  last_sign_in_at timestamptz,
  created_at timestamptz default now(), updated_at timestamptz default now()
);

create table if not exists auth.identities (
  provider_id text, user_id uuid references auth.users(id) on delete cascade,
  identity_data jsonb, provider text,
  last_sign_in_at timestamptz, created_at timestamptz, updated_at timestamptz,
  primary key (provider, provider_id)
);

create or replace function auth.uid() returns uuid
language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

create table if not exists storage.buckets (
  id text primary key, name text not null, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[]
);

create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name text, owner uuid, created_at timestamptz default now()
);
alter table storage.objects enable row level security;
