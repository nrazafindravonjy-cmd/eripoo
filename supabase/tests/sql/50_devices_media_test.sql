-- "My devices" and the encrypted media bucket
-- (migration 20261008000001_devices_media.sql).
begin;
select tests.create_user('aaaaaaaa-0000-4000-8000-000000000050');
select tests.create_user('bbbbbbbb-0000-4000-8000-000000000050');

-- ---------------------------------------------------------- list_devices
select tests.login('aaaaaaaa-0000-4000-8000-000000000050', interval '1 minute',
  '5e550000-0000-4000-8000-000000000051');
select public.register_device('d5000000-0000-4000-8000-000000000001', 'Téléphone');
select tests.logout();
select tests.login('aaaaaaaa-0000-4000-8000-000000000050', interval '1 minute',
  '5e550000-0000-4000-8000-000000000052');
select public.register_device('d5000000-0000-4000-8000-000000000002', 'Tablette');
select tests.ok(jsonb_array_length(public.list_devices()) = 2, 'both devices are listed');
select tests.ok((select bool_and(not (e ? 'session_id'))
   from jsonb_array_elements(public.list_devices()) e),
  'the auth session of a device is never returned');
select tests.ok((select count(*) from jsonb_array_elements(
    public.list_devices('d5000000-0000-4000-8000-000000000002')) e
   where (e ->> 'current')::boolean and e ->> 'label' = 'Tablette') = 1,
  'the calling device is marked as current');
select tests.throws($$select session_id from public.devices$$,
  'permission denied', 'the session column is not readable directly');
select tests.ok((select count(*) from public.devices) = 2,
  'the other device columns stay readable (own rows)');
select public.revoke_device('d5000000-0000-4000-8000-000000000001');
select tests.ok((select e ->> 'status' from jsonb_array_elements(public.list_devices()) e
   where e ->> 'id' = 'd5000000-0000-4000-8000-000000000001') = 'revoked',
  'a removed device is shown as removed');
select tests.logout();

select tests.login('bbbbbbbb-0000-4000-8000-000000000050');
select tests.ok(public.list_devices() = '[]'::jsonb, 'another user sees none of them');
select tests.logout();

select tests.login('aaaaaaaa-0000-4000-8000-000000000050', interval '1 minute',
  '5e550000-0000-4000-8000-000000000051');
select tests.throws($$select public.list_devices()$$, 'device_revoked',
  'the removed device cannot list devices');
select tests.logout();

-- ---------------------------------------------------------- user-media
select tests.ok((select not public and file_size_limit = 10485803
   from storage.buckets where id = 'user-media'), 'the bucket is private and capped');

select tests.login('aaaaaaaa-0000-4000-8000-000000000050', interval '1 minute',
  '5e550000-0000-4000-8000-000000000052');
insert into storage.objects (bucket_id, name) values
  ('user-media', 'aaaaaaaa-0000-4000-8000-000000000050/01920000-0000-7000-8000-000000000001');
select tests.ok((select count(*) from storage.objects where bucket_id = 'user-media') = 1,
  'a user stores and sees a file in their folder');
select tests.throws($$insert into storage.objects (bucket_id, name) values
  ('user-media', 'bbbbbbbb-0000-4000-8000-000000000050/01920000-0000-7000-8000-000000000002')$$,
  'row-level security', 'nobody writes into another user''s folder');
select tests.throws($$insert into storage.objects (bucket_id, name) values
  ('user-media', 'aaaaaaaa-0000-4000-8000-000000000050/sub/01920000-0000-7000-8000-000000000003')$$,
  'row-level security', 'only {owner}/{media id} paths');
select tests.throws($$insert into storage.objects (bucket_id, name) values
  ('user-media', 'aaaaaaaa-0000-4000-8000-000000000050/photo.jpg')$$,
  'row-level security', 'file names are media ids, never user text');
select tests.logout();

select tests.login('bbbbbbbb-0000-4000-8000-000000000050');
select tests.ok((select count(*) from storage.objects where bucket_id = 'user-media') = 0,
  'another user does not see the file');
select tests.logout();

-- The removed device's session no longer reads or writes files.
select tests.login('aaaaaaaa-0000-4000-8000-000000000050', interval '1 minute',
  '5e550000-0000-4000-8000-000000000051');
select tests.ok((select count(*) from storage.objects where bucket_id = 'user-media') = 0,
  'a removed device''s session sees no file');
select tests.throws($$insert into storage.objects (bucket_id, name) values
  ('user-media', 'aaaaaaaa-0000-4000-8000-000000000050/01920000-0000-7000-8000-000000000004')$$,
  'row-level security', 'a removed device''s session cannot upload');
select tests.logout();

select tests.login(null);
select tests.ok((select count(*) from storage.objects where bucket_id = 'user-media') = 0,
  'no session, no file');
select tests.logout();
rollback;
