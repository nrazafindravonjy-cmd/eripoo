-- Back-office technical health (NEXT_STEPS C-14): service-wide totals of
-- technical metadata only (SECURITY §1), never a row per person, never a
-- payload. Totals under 10 are hidden like the usage statistics, and a
-- byte sum is hidden with its file or record count.
create function public.staff_health() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  c record;
begin
  perform authoring.require_staff(array['analyst']);
  select
    (select count(*) from auth.users) as accounts,
    (select count(*) from public.profiles
      where created_at > now() - interval '7 days') as accounts_new_7d,
    (select count(*) from public.devices where status = 'active') as devices_active,
    (select count(*) from public.devices where status = 'active'
      and last_seen_at > now() - interval '7 days') as devices_seen_7d,
    (select count(*) from public.sync_records) as sync_records,
    (select coalesce(sum(payload_size), 0) from public.sync_records) as sync_bytes,
    (select count(*) from public.sync_records
      where updated_at > now() - interval '1 day') as sync_changes_24h,
    (select count(*) from public.sync_records
      where updated_at > now() - interval '7 days') as sync_changes_7d,
    (select count(*) from storage.objects
      where bucket_id = 'user-media') as media_files,
    (select coalesce(sum((metadata ->> 'size')::bigint), 0) from storage.objects
      where bucket_id = 'user-media') as media_bytes,
    (select count(*) from authoring.documents) as content_documents
  into c;
  return jsonb_build_object(
    'accounts', eripoo_internal.at_least_10(c.accounts, c.accounts),
    'accounts_new_7d', eripoo_internal.at_least_10(c.accounts_new_7d, c.accounts_new_7d),
    'devices_active', eripoo_internal.at_least_10(c.devices_active, c.devices_active),
    'devices_seen_7d', eripoo_internal.at_least_10(c.devices_seen_7d, c.devices_seen_7d),
    'sync_records', eripoo_internal.at_least_10(c.sync_records, c.sync_records),
    'sync_bytes', eripoo_internal.at_least_10(c.sync_records, c.sync_bytes),
    'sync_changes_24h', eripoo_internal.at_least_10(c.sync_changes_24h, c.sync_changes_24h),
    'sync_changes_7d', eripoo_internal.at_least_10(c.sync_changes_7d, c.sync_changes_7d),
    'media_files', eripoo_internal.at_least_10(c.media_files, c.media_files),
    'media_bytes', eripoo_internal.at_least_10(c.media_files, c.media_bytes),
    'content_documents', c.content_documents,
    'app_versions', coalesce((
      select jsonb_agg(jsonb_build_object('version', app_version,
               'devices', n) order by app_version)
        from (select app_version, count(*) as n from public.devices
               where status = 'active'
                 and last_seen_at > now() - interval '30 days'
                 and app_version is not null
               group by app_version having count(*) >= 10) a), '[]'::jsonb));
end;
$$;

-- p_value, or null when p_count (the number of people, devices or files
-- behind it) is under 10.
create function eripoo_internal.at_least_10(p_count bigint, p_value numeric)
returns numeric language sql immutable set search_path = '' as $$
  select case when p_count < 10 then null else p_value end
$$;
revoke all on function eripoo_internal.at_least_10(bigint, numeric) from public;

revoke all on function public.staff_health() from public, anon;
grant execute on function public.staff_health() to authenticated;
