-- Minimal stand-in for the parts of Supabase used by the migrations, to run
-- the SQL tests on a plain PostgreSQL when the Supabase CLI is unavailable.
-- PARTIAL by nature: it does not reproduce Supabase Auth, PostgREST or the
-- exact JWT contents. The same tests also run on a real Supabase local
-- stack in CI (see .github/workflows/ci.yml, job "supabase").

-- Roles are cluster-wide: create them only once.
do $$
begin
  if not exists (select from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end;
$$;
grant anon, authenticated, service_role to current_user;

grant usage on schema public to anon, authenticated, service_role;
-- Like Supabase: API roles get broad default privileges on new tables, so
-- the migrations' explicit revokes are actually exercised.
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;

create schema auth;
grant usage on schema auth to anon, authenticated, service_role;
create table auth.users (id uuid primary key, email text);
-- Subset of Supabase's auth.sessions (one row per sign-in).
create table auth.sessions (id uuid primary key, user_id uuid not null);

create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid
$$;
grant execute on function auth.jwt(), auth.uid() to anon, authenticated, service_role;

-- Subset of Supabase Storage: buckets, objects (RLS on, as in Supabase) and
-- the path helper used by policies. The file bytes themselves live outside
-- the database in Supabase; only the rows matter for the policies.
create schema storage;
grant usage on schema storage to anon, authenticated, service_role;
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text,
  owner uuid default auth.uid(),
  metadata jsonb,
  created_at timestamptz default now(),
  unique (bucket_id, name)
);
alter table storage.objects enable row level security;
grant select, insert, update, delete on storage.objects to anon, authenticated, service_role;
grant select on storage.buckets to anon, authenticated, service_role;
create function storage.foldername(name text) returns text[]
language plpgsql immutable as $$
declare
  _parts text[] := string_to_array(name, '/');
begin
  return _parts[1:array_length(_parts, 1) - 1];
end;
$$;
