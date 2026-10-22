begin;
select tests.create_user('aaaaaaaa-0000-4000-8000-000000000001');
select tests.login('aaaaaaaa-0000-4000-8000-000000000001');

select tests.ok(public.get_recovery_wrap() is null, 'no wrap before setting one');

select public.set_recovery_wrap('f0000000-0000-4000-8000-000000000001', 1::smallint,
  encode(gen_random_bytes_stub(16), 'base64'), '{"ops":3,"mem":67108864}', encode(gen_random_bytes_stub(73), 'base64'));
select tests.ok((public.get_recovery_wrap() ->> 'wrap_id') = 'f0000000-0000-4000-8000-000000000001', 'wrap stored');

select public.set_recovery_wrap('f0000000-0000-4000-8000-000000000002', 1::smallint,
  encode(gen_random_bytes_stub(16), 'base64'), '{"ops":3,"mem":67108864}', encode(gen_random_bytes_stub(73), 'base64'));
select tests.ok((public.get_recovery_wrap() ->> 'wrap_id') = 'f0000000-0000-4000-8000-000000000002',
  'a new code replaces the previous wrap');
select tests.logout();
select tests.ok((select count(*) from public.user_keys) = 1, 'the old wrap is deleted immediately');

select tests.login('aaaaaaaa-0000-4000-8000-000000000001');
select tests.throws($$select public.set_recovery_wrap(gen_random_uuid(), 1::smallint,
  encode(gen_random_bytes_stub(16), 'base64'), '{"ops":1,"mem":67108864}', encode(gen_random_bytes_stub(73), 'base64'))$$,
  'kdf_params_too_weak', 'weak Argon2id parameters are refused');
select tests.throws($$select public.set_recovery_wrap(gen_random_uuid(), 1::smallint,
  encode(gen_random_bytes_stub(8), 'base64'), '{"ops":3,"mem":67108864}', encode(gen_random_bytes_stub(73), 'base64'))$$,
  'check constraint', 'salt must be 16 bytes');
select tests.throws($$select public.set_recovery_wrap(gen_random_uuid(), 1::smallint,
  encode(gen_random_bytes_stub(16), 'base64'), '{"ops":3,"mem":67108864}', 'not base64!')$$,
  'invalid_base64', 'malformed input is refused');
-- 2 fetches so far; 3 more reach the hourly limit.
select public.get_recovery_wrap() from generate_series(1, 2);
select tests.throws($$select public.get_recovery_wrap()$$, 'rate_limited', 'fetching the wrap is rate limited');
select tests.logout();

select tests.login('aaaaaaaa-0000-4000-8000-000000000001', interval '1 hour');
select tests.throws($$select public.set_recovery_wrap(gen_random_uuid(), 1::smallint,
  encode(gen_random_bytes_stub(16), 'base64'), '{"ops":3,"mem":67108864}', encode(gen_random_bytes_stub(73), 'base64'))$$,
  'reauthentication_required', 'replacing the code needs a recent sign-in');
select tests.logout();
rollback;
