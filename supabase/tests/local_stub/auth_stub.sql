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
