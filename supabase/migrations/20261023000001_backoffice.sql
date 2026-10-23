-- Back-office foundations (NEXT_STEPS C-14, decision D5 revised 2026-10-23:
-- content is edited in Supabase, schema "authoring").
-- Staff never reach private data: no role here has any policy on
-- profiles, sync_records, user_keys, consents or user-media, and the
-- back-office never holds the service_role key (SECURITY §1, §8).
-- The "authoring" schema is not exposed through the API: every access goes
-- through the staff_* functions below, which require a staff role AND a
-- session verified with a second factor (JWT claim aal = aal2).
-- Roles are granted by the project owner in the SQL editor, never by
-- the back-office itself.

create schema if not exists authoring;
revoke all on schema authoring from public, anon, authenticated;

create table authoring.staff_roles (
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in
    ('content_editor', 'translator', 'content_publisher', 'analyst')),
  granted_at timestamptz not null default now(),
  primary key (user_id, role)
);

-- One row per content file of content/ (same relative path, YAML parsed
-- to JSON). The repository YAML is the initial import.
create table authoring.documents (
  path text primary key check (path ~ '^[a-z0-9_/]+\.yaml$'),
  body jsonb not null check (jsonb_typeof(body) = 'object'),
  version integer not null default 1 check (version >= 1),
  updated_by uuid,
  updated_at timestamptz not null default now()
);

-- What a staff member did, never content.
create table authoring.audit_log (
  id bigint generated always as identity primary key,
  actor uuid not null,
  action text not null,
  target text not null,
  at timestamptz not null default now()
);

alter table authoring.staff_roles enable row level security;
alter table authoring.documents enable row level security;
alter table authoring.audit_log enable row level security;
-- No policy: not readable or writable through the API.

-- Returns the caller's id when they hold one of p_roles in an MFA session.
create function authoring.require_staff(p_roles text[]) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception 'mfa_required' using errcode = 'P0001';
  end if;
  if not exists (select from authoring.staff_roles
                 where user_id = v_uid and role = any (p_roles)) then
    raise exception 'not_staff' using errcode = 'P0001';
  end if;
  return v_uid;
end;
$$;
revoke all on function authoring.require_staff(text[]) from public;

create function public.staff_my_roles() returns text[]
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := authoring.require_staff(
    array['content_editor', 'translator', 'content_publisher', 'analyst']);
begin
  return array(select role from authoring.staff_roles
               where user_id = v_uid order by role);
end;
$$;

create function public.staff_list_documents()
returns table (path text, version integer, updated_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform authoring.require_staff(
    array['content_editor', 'translator', 'content_publisher']);
  return query select d.path, d.version, d.updated_at
    from authoring.documents d order by d.path;
end;
$$;

create function public.staff_get_document(p_path text)
returns table (body jsonb, version integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform authoring.require_staff(
    array['content_editor', 'translator', 'content_publisher']);
  return query select d.body, d.version
    from authoring.documents d where d.path = p_path;
end;
$$;

-- Creates (p_expected_version = 0) or replaces a document. A stale
-- version is refused so two editors never overwrite each other.
create function public.staff_save_document(p_path text, p_body jsonb,
  p_expected_version integer) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := authoring.require_staff(array['content_editor']);
  v_version integer;
begin
  if p_expected_version = 0 then
    insert into authoring.documents (path, body, updated_by)
    values (p_path, p_body, v_uid)
    on conflict (path) do nothing
    returning version into v_version;
  else
    update authoring.documents
       set body = p_body, version = version + 1,
           updated_by = v_uid, updated_at = now()
     where path = p_path and version = p_expected_version
    returning version into v_version;
  end if;
  if v_version is null then
    raise exception 'version_conflict' using errcode = 'P0001';
  end if;
  insert into authoring.audit_log (actor, action, target)
  values (v_uid, 'save_document', p_path);
  return v_version;
exception
  when check_violation then
    raise exception 'invalid_document' using errcode = 'P0001';
end;
$$;

-- Translators change one localized text only: p_pointer designates an
-- object that already holds a French text (a localized string of the
-- content format), p_locale one of its languages.
create function public.staff_set_translation(p_path text, p_pointer text[],
  p_locale text, p_text text, p_expected_version integer) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := authoring.require_staff(array['content_editor', 'translator']);
  v_body jsonb;
  v_target jsonb;
  v_version integer;
begin
  if p_locale is null or p_locale not in ('mg', 'fr', 'en')
     or p_text is null or char_length(p_text) not between 1 and 5000 then
    raise exception 'invalid_translation' using errcode = 'P0001';
  end if;
  select body into v_body from authoring.documents
   where path = p_path and version = p_expected_version for update;
  if v_body is null then
    raise exception 'version_conflict' using errcode = 'P0001';
  end if;
  v_target := v_body #> p_pointer;
  if v_target is null or jsonb_typeof(v_target) <> 'object'
     or jsonb_typeof(v_target -> 'fr') is distinct from 'string' then
    raise exception 'invalid_translation' using errcode = 'P0001';
  end if;
  update authoring.documents
     set body = jsonb_set(v_body, p_pointer || p_locale, to_jsonb(p_text)),
         version = version + 1, updated_by = v_uid, updated_at = now()
   where path = p_path
  returning version into v_version;
  insert into authoring.audit_log (actor, action, target)
  values (v_uid, 'set_translation:' || p_locale, p_path);
  return v_version;
end;
$$;

-- Aggregated opt-in statistics (C-13). Totals under 10 are hidden
-- (SECURITY §1: cells < 10 masked).
create function public.staff_usage_stats(p_from date, p_to date)
returns table (day date, event text, app_version text, count bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform authoring.require_staff(array['analyst']);
  if p_from is null or p_to is null or p_to < p_from
     or p_to - p_from > 366 then
    raise exception 'invalid_period' using errcode = 'P0001';
  end if;
  return query select u.day, u.event, u.app_version,
      case when u.count < 10 then null else u.count end
    from public.usage_daily u
   where u.day between p_from and p_to
   order by u.day, u.event, u.app_version;
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.staff_my_roles()',
    'public.staff_list_documents()',
    'public.staff_get_document(text)',
    'public.staff_save_document(text, jsonb, integer)',
    'public.staff_set_translation(text, text[], text, text, integer)',
    'public.staff_usage_stats(date, date)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;
