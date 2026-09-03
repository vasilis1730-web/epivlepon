-- Ελάχιστα υποκατάστατα των σχημάτων που παρέχει η πλατφόρμα Supabase,
-- ώστε τα migrations να μπορούν να ελεγχθούν σε τοπική PostgreSQL.
create schema if not exists auth;
create schema if not exists storage;
create schema if not exists extensions;

do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon')          then create role anon          nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='service_role')  then create role service_role  nologin noinherit bypassrls; end if;
end $$;

create table if not exists auth.users (
  instance_id uuid,
  id uuid primary key,
  aud text, role text, email text unique,
  encrypted_password text, email_confirmed_at timestamptz,
  raw_app_meta_data jsonb, raw_user_meta_data jsonb,
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
