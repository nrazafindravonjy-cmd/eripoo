begin;
select tests.create_user('aaaaaaaa-0000-4000-8000-000000000001');
select tests.login('aaaaaaaa-0000-4000-8000-000000000001');

select tests.ok(public.register_device('d0000000-0000-4000-8000-000000000001', 'Téléphone') = 'active',
  'a device registers');
select tests.ok(public.register_device('d0000000-0000-4000-8000-000000000001', 'Téléphone') = 'active',
  'registering again is idempotent');
select public.register_device(('d0000000-0000-4000-8000-00000000000' || n)::uuid, 'Appareil')
  from generate_series(2, 5) as n;
select tests.throws($$select public.register_device('d0000000-0000-4000-8000-000000000009', 'X')$$,
  'device_limit', 'at most 5 active devices');

select public.revoke_device('d0000000-0000-4000-8000-000000000002');
select tests.ok((select status from public.devices where id = 'd0000000-0000-4000-8000-000000000002') = 'revoked',
  'a device can be revoked');
select tests.throws($$select public.register_device('d0000000-0000-4000-8000-000000000002', 'X')$$,
  'device_revoked', 'a revoked device cannot come back');
select tests.throws($$select public.sync_pull('d0000000-0000-4000-8000-000000000002', 0)$$,
  'device_revoked', 'a revoked device cannot pull');
select tests.throws($$select public.sync_push('d0000000-0000-4000-8000-000000000002', '[]')$$,
  'device_revoked', 'a revoked device cannot push');
select tests.throws($$select public.sync_pull('d0000000-0000-4000-8000-0000000000ff', 0)$$,
  'device_unknown', 'an unknown device cannot pull');

select tests.logout();
select tests.login('aaaaaaaa-0000-4000-8000-000000000001', interval '2 hours');
select tests.throws($$select public.revoke_device('d0000000-0000-4000-8000-000000000003')$$,
  'reauthentication_required', 'revoking needs a recent sign-in');
select tests.logout();
rollback;
