-- Eripoo core schema, version 1 (Phase 2).
-- NOT FROZEN until the first real user data (DEVELOPMENT_PLAN P8).
--
-- Principles (docs/SECURITY.md, docs/OFFLINE_SYNC.md):
-- * private project content is stored only as client-side encrypted
--   envelopes (sync_records.payload); the server cannot read it;
-- * RLS is enabled on every table; no table is writable directly by
--   clients: writes go through the functions below;
-- * no policy grants any staff role access to private tables;
-- * security definer functions use an empty search_path and fully
--   qualified names.

create schema if not exists eripoo_internal;
revoke all on schema eripoo_internal from public;

-- ---------------------------------------------------------------- tables

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  preferred_locale text not null default 'mg'
    check (preferred_locale in ('mg', 'fr', 'en')),
  jurisdiction_code text not null default 'MG'
    check (jurisdiction_code ~ '^[A-Z]{2}$'),
  age_bracket text check (age_bracket in ('under_min', 'minor', 'adult')),
  parental_consent_status text not null default 'not_required'
    check (parental_consent_status in
      ('not_required', 'pending', 'granted', 'refused'))
);

create table public.devices (
  owner_id uuid not null references auth.users (id) on delete cascade,
  id uuid not null,
  label text not null check (char_length(label) between 1 and 40),
  status text not null default 'active'
    check (status in ('pending', 'active', 'revoked')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz,
  app_version text check (char_length(app_version) <= 32),
  revoked_at timestamptz,
  primary key (owner_id, id)
);

create table public.sync_heads (
  owner_id uuid primary key references auth.users (id) on delete cascade,
  last_version bigint not null default 0
);

create table public.sync_records (
  owner_id uuid not null references auth.users (id) on delete cascade,
  id uuid not null,
  version bigint not null,
  change_id uuid not null,
  device_id uuid not null,
  deleted boolean not null default false,
  umk_version smallint not null check (umk_version > 0),
  payload bytea,
  payload_size integer not null check (payload_size >= 0),
  updated_at timestamptz not null default now(),
  primary key (owner_id, id),
  -- A payload may only be absent for a purged (deleted) record.
  check (payload is not null or deleted),
  check (payload is null or octet_length(payload) <= 70000)
);
create index sync_records_owner_version on public.sync_records (owner_id, version);

-- The data key wrapped with the recovery code. No verifier, hash or hint
-- of the code is ever stored (docs/SECURITY.md §5.5).
create table public.user_keys (
  user_id uuid not null references auth.users (id) on delete cascade,
  wrap_id uuid not null,
  umk_version smallint not null check (umk_version > 0),
  wrap_format smallint not null check (wrap_format = 1),
  kdf_salt bytea not null check (octet_length(kdf_salt) = 16),
  kdf_params jsonb not null,
  wrapped_umk bytea not null check (octet_length(wrapped_umk) = 73),
  created_at timestamptz not null default now(),
  primary key (user_id, wrap_id)
);

-- Metadata only, for rate limits and alerts. Never content.
create table public.security_events (
  id bigint generated always as identity primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in (
    'recovery_wrap_fetched', 'recovery_wrap_replaced',
    'device_added', 'device_revoked')),
  at timestamptz not null default now()
);
create index security_events_owner_kind_at on public.security_events (owner_id, kind, at);

-- Append-only consent records.
create table public.consents (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  consent_type text not null check (consent_type in
    ('privacy_policy', 'analytics', 'ai_processing', 'parental')),
  policy_version text not null check (char_length(policy_version) <= 32),
  granted boolean not null,
  recorded_at timestamptz not null default now()
);

-- -------------------------------------------------------------- privileges
-- Supabase grants broad table privileges to API roles by default; take
-- them back and grant only what the policies below allow.

revoke all on public.profiles, public.devices, public.sync_heads,
  public.sync_records, public.user_keys, public.security_events,
  public.consents
  from anon, authenticated;

grant select, insert, update on public.profiles to authenticated;
grant select on public.devices to authenticated;
grant select, insert on public.consents to authenticated;

alter table public.profiles enable row level security;
alter table public.devices enable row level security;
alter table public.sync_heads enable row level security;
alter table public.sync_records enable row level security;
alter table public.user_keys enable row level security;
alter table public.security_events enable row level security;
alter table public.consents enable row level security;

create policy profiles_own_select on public.profiles
  for select to authenticated using (id = auth.uid());
create policy profiles_own_insert on public.profiles
  for insert to authenticated with check (id = auth.uid());
create policy profiles_own_update on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy devices_own_select on public.devices
  for select to authenticated using (owner_id = auth.uid());

create policy consents_own_select on public.consents
  for select to authenticated using (user_id = auth.uid());
create policy consents_own_insert on public.consents
  for insert to authenticated with check (user_id = auth.uid());

-- sync_heads, sync_records, user_keys, security_events: no policy at all.
-- Only the security definer functions below touch them.

-- ----------------------------------------------------------- helpers

create function eripoo_internal.require_user() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  return v_uid;
end;
$$;

create function eripoo_internal.require_active_device(p_owner uuid, p_device uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_status text;
begin
  select status into v_status from public.devices
   where owner_id = p_owner and id = p_device;
  if v_status is null then
    raise exception 'device_unknown' using errcode = 'P0001';
  elsif v_status = 'revoked' then
    raise exception 'device_revoked' using errcode = 'P0001';
  end if;
  update public.devices set last_seen_at = now()
   where owner_id = p_owner and id = p_device;
end;
$$;

-- True if the session was authenticated less than p_max_age ago, from the
-- JWT "amr" claim. Claim format to be confirmed on real Supabase
-- (NOT VERIFIED: tested only with the local auth stub).
create function eripoo_internal.recently_authenticated(p_max_age interval)
returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(bool_or(
    (entry ->> 'timestamp')::bigint >= extract(epoch from now() - p_max_age)
  ), false)
  from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) as entry;
$$;

create function eripoo_internal.decode_base64(p_value text) returns bytea
language plpgsql immutable set search_path = '' as $$
begin
  if p_value is null then
    return null;
  end if;
  return decode(p_value, 'base64');
exception when others then
  raise exception 'invalid_base64' using errcode = '22023';
end;
$$;

-- ------------------------------------------------------------- devices

create function public.register_device(
  p_device_id uuid, p_label text, p_app_version text default null)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := eripoo_internal.require_user();
  v_status text;
  v_active integer;
begin
  select status into v_status from public.devices
   where owner_id = v_uid and id = p_device_id;
  if v_status = 'revoked' then
    raise exception 'device_revoked' using errcode = 'P0001';
  elsif v_status is not null then
    update public.devices
       set label = p_label, app_version = p_app_version, last_seen_at = now()
     where owner_id = v_uid and id = p_device_id;
    return 'active';
  end if;

  select count(*) into v_active from public.devices
   where owner_id = v_uid and status = 'active';
  if v_active >= 5 then
    raise exception 'device_limit' using errcode = 'P0001';
  end if;

  insert into public.devices (owner_id, id, label, app_version, last_seen_at)
  values (v_uid, p_device_id, p_label, p_app_version, now());
  insert into public.security_events (owner_id, kind) values (v_uid, 'device_added');
  return 'active';
end;
$$;

create function public.revoke_device(p_device_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := eripoo_internal.require_user();
begin
  if not eripoo_internal.recently_authenticated(interval '10 minutes') then
    raise exception 'reauthentication_required' using errcode = 'P0001';
  end if;
  update public.devices set status = 'revoked', revoked_at = now()
   where owner_id = v_uid and id = p_device_id and status <> 'revoked';
  if found then
    insert into public.security_events (owner_id, kind) values (v_uid, 'device_revoked');
  end if;
end;
$$;

-- ---------------------------------------------------------------- sync

-- Applies a batch of encrypted envelopes (docs/OFFLINE_SYNC.md §4.1).
-- Locks the user's version counter, so versions are assigned and committed
-- in order: a reader never sees version N+1 without version N.
create function public.sync_push(p_device_id uuid, p_puts jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := eripoo_internal.require_user();
  v_head bigint;
  v_put jsonb;
  v_id uuid;
  v_change uuid;
  v_base bigint;
  v_deleted boolean;
  v_umk smallint;
  v_payload bytea;
  v_row public.sync_records%rowtype;
  v_results jsonb := '[]'::jsonb;
begin
  perform eripoo_internal.require_active_device(v_uid, p_device_id);
  if jsonb_typeof(p_puts) <> 'array' then
    raise exception 'invalid_batch' using errcode = '22023';
  end if;
  if jsonb_array_length(p_puts) > 50 then
    raise exception 'batch_too_large' using errcode = '22023';
  end if;

  insert into public.sync_heads (owner_id) values (v_uid) on conflict do nothing;
  select last_version into v_head from public.sync_heads
   where owner_id = v_uid for update;

  for v_put in select value from jsonb_array_elements(p_puts) loop
    v_id := (v_put ->> 'id')::uuid;
    v_change := (v_put ->> 'change_id')::uuid;
    v_base := (v_put ->> 'base_version')::bigint;
    v_deleted := coalesce((v_put ->> 'deleted')::boolean, false);
    v_umk := (v_put ->> 'umk_version')::smallint;
    v_payload := eripoo_internal.decode_base64(v_put ->> 'payload');

    if v_id is null or v_change is null or v_umk is null or v_umk < 1
       or (v_payload is null and not v_deleted)
       or (v_payload is not null and octet_length(v_payload) > 70000) then
      v_results := v_results || jsonb_build_object(
        'id', v_id, 'status', 'rejected', 'reason', 'invalid_put');
      continue;
    end if;

    select * into v_row from public.sync_records
     where owner_id = v_uid and id = v_id for update;

    if found and v_row.change_id = v_change then
      -- Replay of an already applied change (idempotency).
      v_results := v_results || jsonb_build_object(
        'id', v_id, 'status', 'applied', 'version', v_row.version);
    elsif (found and (v_base is null or v_row.version <> v_base))
       or (not found and v_base is not null) then
      v_results := v_results || jsonb_build_object(
        'id', v_id, 'status', 'conflict',
        'current', case when found then jsonb_build_object(
          'version', v_row.version,
          'change_id', v_row.change_id,
          'device_id', v_row.device_id,
          'deleted', v_row.deleted,
          'umk_version', v_row.umk_version,
          'payload', encode(v_row.payload, 'base64'))
        else null end);
    else
      v_head := v_head + 1;
      insert into public.sync_records as r
        (owner_id, id, version, change_id, device_id, deleted, umk_version,
         payload, payload_size, updated_at)
      values (v_uid, v_id, v_head, v_change, p_device_id, v_deleted, v_umk,
              v_payload, coalesce(octet_length(v_payload), 0), now())
      on conflict (owner_id, id) do update set
        version = excluded.version, change_id = excluded.change_id,
        device_id = excluded.device_id, deleted = excluded.deleted,
        umk_version = excluded.umk_version, payload = excluded.payload,
        payload_size = excluded.payload_size, updated_at = excluded.updated_at;
      v_results := v_results || jsonb_build_object(
        'id', v_id, 'status', 'applied', 'version', v_head);
    end if;
  end loop;

  update public.sync_heads set last_version = v_head where owner_id = v_uid;
  return v_results;
end;
$$;

-- Returns the caller's envelopes with version > p_since, in version order.
create function public.sync_pull(p_device_id uuid, p_since bigint, p_limit integer default 200)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := eripoo_internal.require_user();
  v_limit integer := least(greatest(coalesce(p_limit, 200), 1), 500);
begin
  perform eripoo_internal.require_active_device(v_uid, p_device_id);
  return jsonb_build_object(
    'head', coalesce((select last_version from public.sync_heads where owner_id = v_uid), 0),
    'records', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'version', r.version, 'change_id', r.change_id,
        'device_id', r.device_id, 'deleted', r.deleted,
        'umk_version', r.umk_version, 'payload', encode(r.payload, 'base64'),
        'updated_at', r.updated_at) order by r.version)
      from (select * from public.sync_records
             where owner_id = v_uid and version > coalesce(p_since, 0)
             order by version limit v_limit) as r), '[]'::jsonb));
end;
$$;

-- ------------------------------------------------------------- recovery

create function public.set_recovery_wrap(
  p_wrap_id uuid, p_umk_version smallint, p_salt text, p_kdf_params jsonb,
  p_wrapped text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := eripoo_internal.require_user();
begin
  if not eripoo_internal.recently_authenticated(interval '10 minutes') then
    raise exception 'reauthentication_required' using errcode = 'P0001';
  end if;
  if (p_kdf_params ->> 'ops')::integer < 2
     or (p_kdf_params ->> 'mem')::bigint < 33554432 then
    raise exception 'kdf_params_too_weak' using errcode = '22023';
  end if;
  -- Replacing the code invalidates the previous one immediately.
  delete from public.user_keys where user_id = v_uid;
  insert into public.user_keys
    (user_id, wrap_id, umk_version, wrap_format, kdf_salt, kdf_params, wrapped_umk)
  values (v_uid, p_wrap_id, p_umk_version, 1,
          eripoo_internal.decode_base64(p_salt), p_kdf_params,
          eripoo_internal.decode_base64(p_wrapped));
  insert into public.security_events (owner_id, kind) values (v_uid, 'recovery_wrap_replaced');
end;
$$;

-- Rate limited (5 per hour, 20 per day) and recorded for alerts.
create function public.get_recovery_wrap() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := eripoo_internal.require_user();
  v_hour integer;
  v_day integer;
  v_wrap public.user_keys%rowtype;
begin
  select count(*) filter (where at > now() - interval '1 hour'),
         count(*) filter (where at > now() - interval '1 day')
    into v_hour, v_day
    from public.security_events
   where owner_id = v_uid and kind = 'recovery_wrap_fetched';
  if v_hour >= 5 or v_day >= 20 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  insert into public.security_events (owner_id, kind) values (v_uid, 'recovery_wrap_fetched');

  select * into v_wrap from public.user_keys where user_id = v_uid
   order by created_at desc limit 1;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'wrap_id', v_wrap.wrap_id, 'umk_version', v_wrap.umk_version,
    'format', v_wrap.wrap_format, 'salt', encode(v_wrap.kdf_salt, 'base64'),
    'kdf_params', v_wrap.kdf_params, 'wrapped', encode(v_wrap.wrapped_umk, 'base64'));
end;
$$;

-- ------------------------------------------------------------- execute

revoke all on all functions in schema eripoo_internal from public, anon, authenticated;
revoke all on function public.register_device(uuid, text, text),
  public.revoke_device(uuid), public.sync_push(uuid, jsonb),
  public.sync_pull(uuid, bigint, integer),
  public.set_recovery_wrap(uuid, smallint, text, jsonb, text),
  public.get_recovery_wrap()
  from public, anon;
grant execute on function public.register_device(uuid, text, text),
  public.revoke_device(uuid), public.sync_push(uuid, jsonb),
  public.sync_pull(uuid, bigint, integer),
  public.set_recovery_wrap(uuid, smallint, text, jsonb, text),
  public.get_recovery_wrap()
  to authenticated;
