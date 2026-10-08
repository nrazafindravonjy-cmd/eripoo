-- Leaving a phone, deleting the account, the file quota
-- (migration 20261009000002_account_lifecycle.sql).
begin;
select tests.create_user('aaaaaaaa-0000-4000-8000-000000000070');
select tests.create_user('bbbbbbbb-0000-4000-8000-000000000070');

-- Two phones of A, each with its own session.
select tests.login('aaaaaaaa-0000-4000-8000-000000000070', interval '1 minute',
  '5e570000-0000-4000-8000-000000000001');
select public.register_device('d7000000-0000-4000-8000-000000000001', 'Téléphone');
select tests.logout();
select tests.login('aaaaaaaa-0000-4000-8000-000000000070', interval '1 hour',
  '5e570000-0000-4000-8000-000000000002');
select public.register_device('d7000000-0000-4000-8000-000000000002', 'Tablette');

-- The tablet cannot remove the phone this way (no recent sign-in needed
-- here, so only its own device).
select public.leave_device('d7000000-0000-4000-8000-000000000001');
select tests.logout();
select tests.ok((select status from public.devices
   where id = 'd7000000-0000-4000-8000-000000000001') = 'active',
  'leave_device never removes another phone');

-- The phone leaves: removed, and its session refused afterwards.
select tests.login('aaaaaaaa-0000-4000-8000-000000000070', interval '1 hour',
  '5e570000-0000-4000-8000-000000000001');
select public.leave_device('d7000000-0000-4000-8000-000000000001');
select tests.throws($$select public.sync_pull('d7000000-0000-4000-8000-000000000001', 0)$$,
  'device_revoked', 'a phone that left cannot synchronise any more');
select tests.logout();
select tests.ok((select status from public.devices
   where id = 'd7000000-0000-4000-8000-000000000001') = 'revoked',
  'the phone that left is removed from the account');

-- ------------------------------------------------------------- quota
select tests.login('aaaaaaaa-0000-4000-8000-000000000070', interval '1 minute',
  '5e570000-0000-4000-8000-000000000002');
insert into storage.objects (bucket_id, name)
  select 'user-media', 'aaaaaaaa-0000-4000-8000-000000000070/' || gen_random_uuid()
  from generate_series(1, 2000);
select tests.throws($$insert into storage.objects (bucket_id, name) values
  ('user-media', 'aaaaaaaa-0000-4000-8000-000000000070/' || gen_random_uuid())$$,
  'row-level security', 'no more than 2 000 files per account');
select tests.logout();
select tests.login('bbbbbbbb-0000-4000-8000-000000000070');
insert into storage.objects (bucket_id, name) values
  ('user-media', 'bbbbbbbb-0000-4000-8000-000000000070/' || gen_random_uuid());
select tests.ok(true, 'another account''s quota is its own');
select tests.logout();
delete from storage.objects where name like 'aaaaaaaa-0000-4000-8000-000000000070/%';

-- --------------------------------------------------- deleting the account
select tests.login('aaaaaaaa-0000-4000-8000-000000000070', interval '1 minute',
  '5e570000-0000-4000-8000-000000000002');
select public.sync_push('d7000000-0000-4000-8000-000000000002', jsonb_build_array(
  jsonb_build_object('id', gen_random_uuid(), 'change_id', gen_random_uuid(),
    'base_version', null, 'deleted', false, 'umk_version', 1,
    'payload', encode('\x01'::bytea, 'base64'))));
select public.set_recovery_wrap(gen_random_uuid(), 1::smallint,
  encode(gen_random_bytes_stub(16), 'base64'), '{"ops":3,"mem":67108864}', encode(gen_random_bytes_stub(73), 'base64'));
select tests.logout();

select tests.login('aaaaaaaa-0000-4000-8000-000000000070', interval '1 hour',
  '5e570000-0000-4000-8000-000000000002');
select tests.throws($$select public.delete_account()$$, 'reauthentication_required',
  'deleting the account needs a recent sign-in');
select tests.logout();

select tests.login('aaaaaaaa-0000-4000-8000-000000000070', interval '1 minute',
  '5e570000-0000-4000-8000-000000000002');
select public.delete_account();
select tests.logout();
select tests.ok(not exists (select 1 from auth.users where id = 'aaaaaaaa-0000-4000-8000-000000000070'),
  'the account is gone');
select tests.ok(not exists (select 1 from public.devices where owner_id = 'aaaaaaaa-0000-4000-8000-000000000070')
  and not exists (select 1 from public.sync_records where owner_id = 'aaaaaaaa-0000-4000-8000-000000000070')
  and not exists (select 1 from public.sync_heads where owner_id = 'aaaaaaaa-0000-4000-8000-000000000070')
  and not exists (select 1 from public.user_keys where user_id = 'aaaaaaaa-0000-4000-8000-000000000070')
  and not exists (select 1 from public.security_events where owner_id = 'aaaaaaaa-0000-4000-8000-000000000070'),
  'nothing of it stays on the server (records, key copy, devices, events)');
select tests.ok(exists (select 1 from auth.users where id = 'bbbbbbbb-0000-4000-8000-000000000070'),
  'other accounts are untouched');
rollback;
