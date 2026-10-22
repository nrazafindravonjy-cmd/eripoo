-- Binds each device to the auth session it uses, so that revoking a device
-- also cuts the session it used (docs/SECURITY.md §6.8).
--
-- Why this is needed: without it, revoking a device refused its device id
-- but the same sign-in (stolen tokens, or the revoked phone itself) could
-- register a new device id and keep synchronising. Supabase puts the
-- session id in every access token ("session_id" claim) and keeps it
-- across token refreshes, so the server can recognise that session.
--
-- NOT FROZEN (DEVELOPMENT_PLAN P8).

alter table public.devices add column session_id uuid;
create index devices_session_idx on public.devices (session_id)
  where session_id is not null;

-- The current auth session id, or null when the token carries none.
create function eripoo_internal.current_session() returns uuid
language sql stable security definer set search_path = '' as $$
  select nullif(auth.jwt() ->> 'session_id', '')::uuid
$$;

-- Every function calls this first: a session that belonged to a revoked
-- device is refused everywhere (sync, devices, recovery wrap).
create or replace function eripoo_internal.require_user() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_session uuid := eripoo_internal.current_session();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_session is not null and exists (
    select 1 from public.devices
     where owner_id = v_uid and session_id = v_session and status = 'revoked'
  ) then
    raise exception 'device_revoked' using errcode = 'P0001';
  end if;
  return v_uid;
end;
$$;

create or replace function eripoo_internal.require_active_device(p_owner uuid, p_device uuid)
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
  -- Follows the session after a new sign-in on the same device.
  update public.devices
     set last_seen_at = now(),
         session_id = coalesce(eripoo_internal.current_session(), session_id)
   where owner_id = p_owner and id = p_device;
end;
$$;

create or replace function public.register_device(
  p_device_id uuid, p_label text, p_app_version text default null)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := eripoo_internal.require_user();
  v_session uuid := eripoo_internal.current_session();
  v_status text;
  v_active integer;
begin
  select status into v_status from public.devices
   where owner_id = v_uid and id = p_device_id;
  if v_status = 'revoked' then
    raise exception 'device_revoked' using errcode = 'P0001';
  elsif v_status is not null then
    update public.devices
       set label = p_label, app_version = p_app_version, last_seen_at = now(),
           session_id = coalesce(v_session, session_id)
     where owner_id = v_uid and id = p_device_id;
    return 'active';
  end if;

  select count(*) into v_active from public.devices
   where owner_id = v_uid and status = 'active';
  if v_active >= 5 then
    raise exception 'device_limit' using errcode = 'P0001';
  end if;

  insert into public.devices (owner_id, id, label, app_version, last_seen_at, session_id)
  values (v_uid, p_device_id, p_label, p_app_version, now(), v_session);
  insert into public.security_events (owner_id, kind) values (v_uid, 'device_added');
  return 'active';
end;
$$;

create or replace function public.revoke_device(p_device_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := eripoo_internal.require_user();
  v_session uuid;
begin
  if not eripoo_internal.recently_authenticated(interval '10 minutes') then
    raise exception 'reauthentication_required' using errcode = 'P0001';
  end if;
  update public.devices set status = 'revoked', revoked_at = now()
   where owner_id = v_uid and id = p_device_id and status <> 'revoked'
  returning session_id into v_session;
  if not found then
    return;
  end if;
  insert into public.security_events (owner_id, kind) values (v_uid, 'device_revoked');
  -- Ends the revoked device's auth session (its refresh token stops
  -- working). Access tokens already issued stay valid until they expire,
  -- but every function refuses them (require_user above). Best effort:
  -- if this role may not write to auth.sessions, the refusal above still
  -- applies.
  if v_session is not null and v_session <> coalesce(eripoo_internal.current_session(), '00000000-0000-0000-0000-000000000000'::uuid) then
    begin
      delete from auth.sessions where id = v_session and user_id = v_uid;
    exception when insufficient_privilege or undefined_table then
      null;
    end;
  end if;
end;
$$;
