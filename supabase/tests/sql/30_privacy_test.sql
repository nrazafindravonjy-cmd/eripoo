-- Users can never read or write other users' data; private tables are not
-- reachable directly; anonymous callers can do nothing.
begin;
select tests.create_user('aaaaaaaa-0000-4000-8000-000000000001');
select tests.create_user('bbbbbbbb-0000-4000-8000-000000000002');

select tests.login('aaaaaaaa-0000-4000-8000-000000000001');
select public.register_device('d0000000-0000-4000-8000-00000000000a', 'A');
select public.sync_push('d0000000-0000-4000-8000-00000000000a', jsonb_build_array(
  jsonb_build_object('id', '10000000-0000-4000-8000-000000000001', 'change_id', gen_random_uuid(),
    'base_version', null, 'deleted', false, 'umk_version', 1, 'payload', encode('\x01'::bytea, 'base64'))));
insert into public.profiles (id) values ('aaaaaaaa-0000-4000-8000-000000000001');
insert into public.consents (id, user_id, consent_type, policy_version, granted)
  values (gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-000000000001', 'privacy_policy', '1', true);
select tests.logout();

select tests.login('bbbbbbbb-0000-4000-8000-000000000002');
select public.register_device('d0000000-0000-4000-8000-00000000000b', 'B');
select tests.ok((select count(*) from public.devices) = 1, 'B sees only its own device');
select tests.ok((select count(*) from public.profiles) = 0, 'B cannot see A''s profile');
select tests.ok((select count(*) from public.consents) = 0, 'B cannot see A''s consents');
select tests.ok(jsonb_array_length(public.sync_pull('d0000000-0000-4000-8000-00000000000b', 0) -> 'records') = 0,
  'B pulls nothing of A');
select tests.throws($$select public.sync_pull('d0000000-0000-4000-8000-00000000000a', 0)$$,
  'device_unknown', 'B cannot use A''s device id');

-- Same record id written by B does not touch A's record (composite key).
select tests.ok(public.sync_push('d0000000-0000-4000-8000-00000000000b', jsonb_build_array(
  jsonb_build_object('id', '10000000-0000-4000-8000-000000000001', 'change_id', gen_random_uuid(),
    'base_version', null, 'deleted', false, 'umk_version', 1, 'payload', encode('\x02'::bytea, 'base64'))))
  -> 0 ->> 'status' = 'applied', 'same id in another account is a different record');

select tests.throws($$select * from public.sync_records$$, 'permission denied', 'no direct read of envelopes');
select tests.throws($$insert into public.sync_records (owner_id, id, version, change_id, device_id, umk_version, payload, payload_size)
  values ('bbbbbbbb-0000-4000-8000-000000000002', gen_random_uuid(), 99, gen_random_uuid(), gen_random_uuid(), 1, '\x01', 1)$$,
  'permission denied', 'no direct write of envelopes');
select tests.throws($$select * from public.user_keys$$, 'permission denied', 'no direct read of key wraps');
select tests.throws($$select * from public.sync_heads$$, 'permission denied', 'no direct read of heads');
select tests.throws($$select * from public.security_events$$, 'permission denied', 'no direct read of security events');
select tests.throws($$update public.devices set status = 'active'$$, 'permission denied', 'devices are not writable directly');
select tests.throws($$insert into public.profiles (id) values ('aaaaaaaa-0000-4000-8000-000000000001')$$,
  'row-level security', 'cannot create a profile for someone else');
select tests.throws($$select eripoo_internal.require_user()$$, 'permission denied', 'internal helpers are not callable');
select tests.logout();

-- Anonymous: nothing.
set local role anon;
select tests.throws($$select public.sync_pull('d0000000-0000-4000-8000-00000000000a', 0)$$,
  'permission denied', 'anonymous cannot call sync functions');
select tests.throws($$select * from public.profiles$$, 'permission denied', 'anonymous cannot read profiles');
reset role;

-- Not signed in but with the authenticated role: no user, no access.
set local role authenticated;
select tests.throws($$select public.get_recovery_wrap()$$, 'not_authenticated', 'a session is required');
reset role;
rollback;
