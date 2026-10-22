-- Phase 10: rotation of the data key (UMK), docs/SECURITY.md §4.10, D17.
--
-- The server never sees any key. It only keeps, per account, the version
-- of the current data key, so that:
-- * once a phone has rotated the key, envelopes sealed with an older key
--   are refused (a phone that still has the old key, or an attacker who
--   copied it, can no longer add data the other phones would read);
-- * the recovery copy of the key always matches that version (a phone
--   with the old key cannot hand it back to the server as "the" key);
-- * phones learn from every pull that a newer key exists.
--
-- NOT FROZEN (DEVELOPMENT_PLAN P8).

alter table public.sync_heads
  add column umk_version smallint not null default 1 check (umk_version > 0);

alter table public.security_events drop constraint security_events_kind_check;
alter table public.security_events add constraint security_events_kind_check
  check (kind in (
    'recovery_wrap_fetched', 'recovery_wrap_replaced',
    'device_added', 'device_revoked', 'data_key_rotated'));

-- The account's current key version (1 until a rotation).
create function eripoo_internal.key_version(p_owner uuid) returns smallint
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select umk_version from public.sync_heads where owner_id = p_owner),
    1::smallint)
$$;

-- --------------------------------------------------------------- sync

-- As in the core schema, plus: an envelope must be sealed with the
-- current key (tombstones carry no content and are accepted).
create or replace function public.sync_push(p_device_id uuid, p_puts jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := eripoo_internal.require_user();
  v_head bigint;
  v_key smallint;
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
  select last_version, umk_version into v_head, v_key from public.sync_heads
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

    if v_payload is not null and v_umk <> v_key then
      v_results := v_results || jsonb_build_object(
        'id', v_id, 'status', 'rejected', 'reason', 'stale_key');
      continue;
    end if;

    select * into v_row from public.sync_records
     where owner_id = v_uid and id = v_id for update;

    if found and v_row.change_id = v_change then
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

-- As in the core schema, plus the account's current key version.
create or replace function public.sync_pull(p_device_id uuid, p_since bigint, p_limit integer default 200)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := eripoo_internal.require_user();
  v_limit integer := least(greatest(coalesce(p_limit, 200), 1), 500);
begin
  perform eripoo_internal.require_active_device(v_uid, p_device_id);
  return jsonb_build_object(
    'head', coalesce((select last_version from public.sync_heads where owner_id = v_uid), 0),
    'umk_version', eripoo_internal.key_version(v_uid),
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

-- ----------------------------------------------------------- recovery

-- As in the core schema, plus: the wrapped key must be the current one.
create or replace function public.set_recovery_wrap(
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
  if p_umk_version is distinct from eripoo_internal.key_version(v_uid) then
    raise exception 'key_version_mismatch' using errcode = 'P0001';
  end if;
  if (p_kdf_params ->> 'ops')::integer < 2
     or (p_kdf_params ->> 'mem')::bigint < 33554432 then
    raise exception 'kdf_params_too_weak' using errcode = '22023';
  end if;
  delete from public.user_keys where user_id = v_uid;
  insert into public.user_keys
    (user_id, wrap_id, umk_version, wrap_format, kdf_salt, kdf_params, wrapped_umk)
  values (v_uid, p_wrap_id, p_umk_version, 1,
          eripoo_internal.decode_base64(p_salt), p_kdf_params,
          eripoo_internal.decode_base64(p_wrapped));
  insert into public.security_events (owner_id, kind) values (v_uid, 'recovery_wrap_replaced');
end;
$$;

-- ----------------------------------------------------------- rotation

-- Switches the account to the next key version, atomically with the
-- recovery copy of that new key (sealed on the phone with the new
-- recovery code). The previous copy, and so the previous code, stop
-- working at once. Only from an active device, after a recent sign-in,
-- and only from the current version (two phones rotating at the same
-- time: the second one is refused and must start again).
create function public.rotate_data_key(
  p_device_id uuid, p_from_version smallint, p_wrap_id uuid, p_salt text,
  p_kdf_params jsonb, p_wrapped text)
returns smallint
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := eripoo_internal.require_user();
  v_current smallint;
  v_next smallint;
begin
  if not eripoo_internal.recently_authenticated(interval '10 minutes') then
    raise exception 'reauthentication_required' using errcode = 'P0001';
  end if;
  perform eripoo_internal.require_active_device(v_uid, p_device_id);
  if (p_kdf_params ->> 'ops')::integer < 2
     or (p_kdf_params ->> 'mem')::bigint < 33554432 then
    raise exception 'kdf_params_too_weak' using errcode = '22023';
  end if;

  insert into public.sync_heads (owner_id) values (v_uid) on conflict do nothing;
  select umk_version into v_current from public.sync_heads
   where owner_id = v_uid for update;
  if v_current is distinct from p_from_version or v_current >= 32767 then
    raise exception 'key_version_mismatch' using errcode = 'P0001';
  end if;
  v_next := v_current + 1;

  delete from public.user_keys where user_id = v_uid;
  insert into public.user_keys
    (user_id, wrap_id, umk_version, wrap_format, kdf_salt, kdf_params, wrapped_umk)
  values (v_uid, p_wrap_id, v_next, 1,
          eripoo_internal.decode_base64(p_salt), p_kdf_params,
          eripoo_internal.decode_base64(p_wrapped));
  update public.sync_heads set umk_version = v_next where owner_id = v_uid;
  insert into public.security_events (owner_id, kind) values (v_uid, 'data_key_rotated');
  return v_next;
end;
$$;

revoke all on function eripoo_internal.key_version(uuid) from public, anon, authenticated;
revoke all on function public.rotate_data_key(uuid, smallint, uuid, text, jsonb, text)
  from public, anon;
grant execute on function public.rotate_data_key(uuid, smallint, uuid, text, jsonb, text)
  to authenticated;
