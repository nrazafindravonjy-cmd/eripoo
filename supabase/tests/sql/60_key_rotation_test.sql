-- Rotation of the data key (migration 20261009000001).
begin;
select tests.create_user('aaaaaaaa-0000-4000-8000-000000000061');
select tests.create_user('aaaaaaaa-0000-4000-8000-000000000062');
select tests.login('aaaaaaaa-0000-4000-8000-000000000061');
select public.register_device('d0000000-0000-4000-8000-000000000061', 'A');
select public.register_device('d0000000-0000-4000-8000-000000000062', 'B');

create temp table r (step text, result jsonb) on commit drop;
grant all on r to authenticated;

-- Before any rotation: version 1, the usual recovery copy.
select tests.ok((public.sync_pull('d0000000-0000-4000-8000-000000000061', 0) ->> 'umk_version')::int = 1,
  'a new account is at key version 1');
select public.set_recovery_wrap('f0000000-0000-4000-8000-000000000061', 1::smallint,
  encode(gen_random_bytes_stub(16), 'base64'), '{"ops":3,"mem":67108864}', encode(gen_random_bytes_stub(73), 'base64'));
insert into r select 'v1', public.sync_push('d0000000-0000-4000-8000-000000000061', jsonb_build_array(
  jsonb_build_object('id', '10000000-0000-4000-8000-000000000061', 'change_id', gen_random_uuid(),
    'base_version', null, 'deleted', false, 'umk_version', 1, 'payload', encode('\x01'::bytea, 'base64'))));
select tests.ok((select result -> 0 ->> 'status' from r where step = 'v1') = 'applied', 'version 1 envelopes accepted');

select tests.throws($$select public.rotate_data_key('d0000000-0000-4000-8000-000000000061', 2::smallint,
  gen_random_uuid(), encode(gen_random_bytes_stub(16), 'base64'), '{"ops":3,"mem":67108864}',
  encode(gen_random_bytes_stub(73), 'base64'))$$, 'key_version_mismatch', 'rotation must start from the current version');
select tests.throws($$select public.rotate_data_key('d0000000-0000-4000-8000-000000000061', 1::smallint,
  gen_random_uuid(), encode(gen_random_bytes_stub(16), 'base64'), '{"ops":1,"mem":67108864}',
  encode(gen_random_bytes_stub(73), 'base64'))$$, 'kdf_params_too_weak', 'weak Argon2id parameters are refused');
select tests.throws($$select public.rotate_data_key('d0000000-0000-4000-8000-0000000000ff', 1::smallint,
  gen_random_uuid(), encode(gen_random_bytes_stub(16), 'base64'), '{"ops":3,"mem":67108864}',
  encode(gen_random_bytes_stub(73), 'base64'))$$, 'device_unknown', 'only a device of the account can rotate');

-- Rotation from A.
select tests.ok(public.rotate_data_key('d0000000-0000-4000-8000-000000000061', 1::smallint,
  'f0000000-0000-4000-8000-000000000062', encode(gen_random_bytes_stub(16), 'base64'),
  '{"ops":3,"mem":67108864}', encode(gen_random_bytes_stub(73), 'base64')) = 2, 'rotation gives version 2');
select tests.ok((public.sync_pull('d0000000-0000-4000-8000-000000000062', 0) ->> 'umk_version')::int = 2,
  'every device learns the new version from a pull');
select tests.ok((public.get_recovery_wrap() ->> 'umk_version')::int = 2
  and (public.get_recovery_wrap() ->> 'wrap_id') = 'f0000000-0000-4000-8000-000000000062',
  'the recovery copy is the new key''s');
select tests.throws($$select public.rotate_data_key('d0000000-0000-4000-8000-000000000062', 1::smallint,
  gen_random_uuid(), encode(gen_random_bytes_stub(16), 'base64'), '{"ops":3,"mem":67108864}',
  encode(gen_random_bytes_stub(73), 'base64'))$$, 'key_version_mismatch',
  'a second rotation from the old version is refused');

-- Old-key envelopes are refused; tombstones and new-key envelopes pass.
insert into r select 'stale', public.sync_push('d0000000-0000-4000-8000-000000000062', jsonb_build_array(
  jsonb_build_object('id', '10000000-0000-4000-8000-000000000062', 'change_id', gen_random_uuid(),
    'base_version', null, 'deleted', false, 'umk_version', 1, 'payload', encode('\x02'::bytea, 'base64'))));
select tests.ok((select result -> 0 ->> 'status' from r where step = 'stale') = 'rejected'
  and (select result -> 0 ->> 'reason' from r where step = 'stale') = 'stale_key',
  'an envelope sealed with the old key is refused');
insert into r select 'rekey', public.sync_push('d0000000-0000-4000-8000-000000000061', jsonb_build_array(
  jsonb_build_object('id', '10000000-0000-4000-8000-000000000061', 'change_id', gen_random_uuid(),
    'base_version', 1, 'deleted', false, 'umk_version', 2, 'payload', encode('\x03'::bytea, 'base64'))));
select tests.ok((select result -> 0 ->> 'status' from r where step = 'rekey') = 'applied',
  'a record sealed again with the new key replaces the old envelope');
insert into r select 'tomb', public.sync_push('d0000000-0000-4000-8000-000000000061', jsonb_build_array(
  jsonb_build_object('id', '10000000-0000-4000-8000-000000000063', 'change_id', gen_random_uuid(),
    'base_version', null, 'deleted', true, 'umk_version', 1, 'payload', null)));
select tests.ok((select result -> 0 ->> 'status' from r where step = 'tomb') = 'applied',
  'a tombstone carries no content and is accepted');

-- The old key cannot come back as the recovery copy.
select tests.throws($$select public.set_recovery_wrap(gen_random_uuid(), 1::smallint,
  encode(gen_random_bytes_stub(16), 'base64'), '{"ops":3,"mem":67108864}', encode(gen_random_bytes_stub(73), 'base64'))$$,
  'key_version_mismatch', 'a recovery copy of the old key is refused');
select public.set_recovery_wrap(gen_random_uuid(), 2::smallint,
  encode(gen_random_bytes_stub(16), 'base64'), '{"ops":3,"mem":67108864}', encode(gen_random_bytes_stub(73), 'base64'));
select tests.ok((public.get_recovery_wrap() ->> 'umk_version')::int = 2, 'a new code for the current key is accepted');
select tests.logout();

select tests.ok((select count(*) from public.user_keys
  where user_id = 'aaaaaaaa-0000-4000-8000-000000000061') = 1, 'one recovery copy only');
select tests.ok((select count(*) from public.security_events
  where owner_id = 'aaaaaaaa-0000-4000-8000-000000000061' and kind = 'data_key_rotated') = 1,
  'the rotation is recorded (metadata only)');
select tests.ok(eripoo_internal.key_version('aaaaaaaa-0000-4000-8000-000000000062') = 1,
  'other accounts are not affected');

-- Needs a recent sign-in; another account cannot touch it.
select tests.login('aaaaaaaa-0000-4000-8000-000000000061', interval '1 hour');
select tests.throws($$select public.rotate_data_key('d0000000-0000-4000-8000-000000000061', 2::smallint,
  gen_random_uuid(), encode(gen_random_bytes_stub(16), 'base64'), '{"ops":3,"mem":67108864}',
  encode(gen_random_bytes_stub(73), 'base64'))$$, 'reauthentication_required', 'rotation needs a recent sign-in');
select tests.logout();
select tests.login('aaaaaaaa-0000-4000-8000-000000000062');
select tests.throws($$select public.rotate_data_key('d0000000-0000-4000-8000-000000000061', 2::smallint,
  gen_random_uuid(), encode(gen_random_bytes_stub(16), 'base64'), '{"ops":3,"mem":67108864}',
  encode(gen_random_bytes_stub(73), 'base64'))$$, 'device_unknown', 'another account cannot rotate this key');
select tests.throws($$select eripoo_internal.key_version('aaaaaaaa-0000-4000-8000-000000000061')$$,
  'permission denied', 'the internal helper is not callable by clients');
select tests.logout();
rollback;
