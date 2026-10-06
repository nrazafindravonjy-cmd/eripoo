-- A revoked device's auth session is refused everywhere, even with a new
-- device id (migration 20261007000001_device_sessions.sql).
begin;
select tests.create_user('aaaaaaaa-0000-4000-8000-000000000015');
insert into auth.sessions (id, user_id) values
  ('5e550000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000015'),
  ('5e550000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000015');

-- Phone A signs in (session 1) and registers.
select tests.login('aaaaaaaa-0000-4000-8000-000000000015', interval '1 minute',
  '5e550000-0000-4000-8000-000000000001');
select public.register_device('da000000-0000-4000-8000-000000000001', 'Téléphone A');
select tests.logout();
select tests.ok((select session_id from public.devices
   where id = 'da000000-0000-4000-8000-000000000001')
  = '5e550000-0000-4000-8000-000000000001', 'the device remembers its session');

-- Phone B (session 2) registers, then revokes A.
select tests.login('aaaaaaaa-0000-4000-8000-000000000015', interval '1 minute',
  '5e550000-0000-4000-8000-000000000002');
select public.register_device('db000000-0000-4000-8000-000000000002', 'Téléphone B');
select public.revoke_device('da000000-0000-4000-8000-000000000001');
select tests.logout();
select tests.ok(not exists (select 1 from auth.sessions
   where id = '5e550000-0000-4000-8000-000000000001'),
  'revoking ends the revoked device''s auth session');
select tests.ok(exists (select 1 from auth.sessions
   where id = '5e550000-0000-4000-8000-000000000002'),
  'the revoking device keeps its session');

-- A's old tokens (session 1) are refused, whatever the device id.
select tests.login('aaaaaaaa-0000-4000-8000-000000000015', interval '1 minute',
  '5e550000-0000-4000-8000-000000000001');
select tests.throws($$select public.register_device('da000000-0000-4000-8000-000000000099', 'Nouveau')$$,
  'device_revoked', 'the old session cannot register a new device id');
select tests.throws($$select public.sync_pull('db000000-0000-4000-8000-000000000002', 0)$$,
  'device_revoked', 'the old session cannot use another device''s id');
select tests.throws($$select public.get_recovery_wrap()$$,
  'device_revoked', 'the old session cannot fetch the recovery wrap');
select tests.logout();

-- B keeps working; a fresh sign-in (session 3) can register again.
select tests.login('aaaaaaaa-0000-4000-8000-000000000015', interval '1 minute',
  '5e550000-0000-4000-8000-000000000002');
select tests.ok((public.sync_pull('db000000-0000-4000-8000-000000000002', 0) ->> 'head') is not null,
  'other devices keep synchronising');
select tests.logout();
select tests.login('aaaaaaaa-0000-4000-8000-000000000015', interval '1 minute',
  '5e550000-0000-4000-8000-000000000003');
select tests.ok(public.register_device('dc000000-0000-4000-8000-000000000003', 'Nouveau') = 'active',
  'a new sign-in can register a new device');
select tests.logout();
rollback;
