-- Phase 5: the "My devices" list and the encrypted media files.
--
-- * list_devices: metadata only (name, state, dates), never the auth
--   session a device uses.
-- * Storage bucket `user-media` (private): `{owner_id}/{media_id}`, files
--   encrypted on the phone (docs/SECURITY.md §4.7). The server stores
--   opaque bytes; no role, staff included, gets a policy on other users'
--   files. Like every function, the policies refuse the session of a
--   revoked device.
--
-- NOT FROZEN (DEVELOPMENT_PLAN P8). Per-user quota: not enforced yet
-- (open point, docs/OFFLINE_SYNC.md §9).

-- ------------------------------------------------------------- devices

-- The session a device uses stays on the server: it only serves the
-- revocation (migration 20261007000001).
revoke select on public.devices from authenticated;
grant select (owner_id, id, label, status, created_at, last_seen_at,
  app_version, revoked_at) on public.devices to authenticated;

create function public.list_devices(p_current_device uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := eripoo_internal.require_user();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', d.id, 'label', d.label, 'status', d.status,
             'created_at', d.created_at, 'last_seen_at', d.last_seen_at,
             'app_version', d.app_version, 'revoked_at', d.revoked_at,
             'current', d.id = p_current_device)
           order by (d.status = 'revoked'), d.created_at)
      from public.devices d
     where d.owner_id = v_uid
       -- Removed devices stay listed 30 days, then only in the history.
       and (d.status <> 'revoked' or d.revoked_at > now() - interval '30 days')
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.list_devices(uuid) from public, anon;
grant execute on function public.list_devices(uuid) to authenticated;

-- ------------------------------------------------------------- media

-- Policies run as the caller: this schema holds only what they need.
create schema if not exists eripoo_policy;
revoke all on schema eripoo_policy from public;
grant usage on schema eripoo_policy to authenticated;

-- True when the caller is signed in with a session that no revoked device
-- used (same rule as eripoo_internal.require_user, without raising).
create function eripoo_policy.media_allowed() returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and not exists (
    select 1 from public.devices
     where owner_id = auth.uid()
       and session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid
       and status = 'revoked')
$$;

-- `{owner_id}/{media_id}` and nothing else.
create function eripoo_policy.own_media_path(p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_name ~ ('^' || auth.uid()::text
    || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
$$;

revoke all on all functions in schema eripoo_policy from public, anon;
grant execute on all functions in schema eripoo_policy to authenticated;

-- 10 MiB of photo (D15) + envelope header, nonce and tag (43 bytes).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('user-media', 'user-media', false, 10485803,
        array['application/octet-stream'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- No update policy: a file is written once (upload = insert); a new
-- version of a photo is a new media id.
create policy user_media_own_select on storage.objects
  for select to authenticated
  using (bucket_id = 'user-media'
         and eripoo_policy.own_media_path(name)
         and eripoo_policy.media_allowed());

create policy user_media_own_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'user-media'
              and eripoo_policy.own_media_path(name)
              and eripoo_policy.media_allowed());

create policy user_media_own_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'user-media'
         and eripoo_policy.own_media_path(name)
         and eripoo_policy.media_allowed());
