-- Phase 10: leaving a phone, deleting the account, a quota of files.
-- NOT FROZEN (DEVELOPMENT_PLAN P8).

-- ------------------------------------------------------- leaving a phone

-- "Sign out and erase this phone": the phone removes itself from the
-- account, so it no longer counts among the 5 devices and its session is
-- refused everywhere afterwards. Only the device bound to the calling
-- session (no other phone can be removed this way: that needs a recent
-- sign-in, revoke_device). Idempotent.
create function public.leave_device(p_device_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := eripoo_internal.require_user();
  v_session uuid := eripoo_internal.current_session();
begin
  if v_session is null then
    raise exception 'device_unknown' using errcode = 'P0001';
  end if;
  update public.devices set status = 'revoked', revoked_at = now()
   where owner_id = v_uid and id = p_device_id
     and session_id = v_session and status <> 'revoked';
  if found then
    insert into public.security_events (owner_id, kind) values (v_uid, 'device_revoked');
  end if;
end;
$$;

-- ---------------------------------------------------- deleting the account

-- Deletes the account and, by cascade, everything the server holds for
-- it: profile, devices, encrypted records, the recovery copy of the key,
-- consents and security events. The encrypted files are removed by the
-- app through Storage just before (they are opaque bytes; Storage keeps
-- its own bookkeeping). Needs a sign-in of less than 10 minutes.
create function public.delete_account() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := eripoo_internal.require_user();
begin
  if not eripoo_internal.recently_authenticated(interval '10 minutes') then
    raise exception 'reauthentication_required' using errcode = 'P0001';
  end if;
  delete from auth.users where id = v_uid;
end;
$$;

revoke all on function public.leave_device(uuid), public.delete_account()
  from public, anon;
grant execute on function public.leave_device(uuid), public.delete_account()
  to authenticated;

-- ------------------------------------------------------------ media quota

-- At most 2 000 files per account (photos ≈ 300 KB, spoken answers ≈
-- 250 KB a minute, each 10 MiB at most). Counted by file, which Storage
-- always records; a quota in bytes needs a check on the real Storage
-- first (NOT VERIFIED there).
create function eripoo_policy.media_quota_ok() returns boolean
language sql stable security definer set search_path = '' as $$
  select count(*) < 2000 from storage.objects
   where bucket_id = 'user-media'
     and name like auth.uid()::text || '/%'
$$;
revoke all on function eripoo_policy.media_quota_ok() from public, anon;
grant execute on function eripoo_policy.media_quota_ok() to authenticated;

drop policy user_media_own_insert on storage.objects;
create policy user_media_own_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'user-media'
              and eripoo_policy.own_media_path(name)
              and eripoo_policy.media_allowed()
              and eripoo_policy.media_quota_ok());
