begin;
select tests.create_user('aaaaaaaa-0000-4000-8000-000000000001');
select tests.login('aaaaaaaa-0000-4000-8000-000000000001');
select public.register_device('d0000000-0000-4000-8000-000000000001', 'A');

create temp table r (step text, result jsonb) on commit drop;
grant all on r to authenticated;

-- New record.
insert into r select 'create', public.sync_push('d0000000-0000-4000-8000-000000000001', jsonb_build_array(
  jsonb_build_object('id', '10000000-0000-4000-8000-000000000001', 'change_id', 'c0000000-0000-4000-8000-000000000001',
    'base_version', null, 'deleted', false, 'umk_version', 1, 'payload', encode('\x0102'::bytea, 'base64'))));
select tests.ok((select result -> 0 ->> 'status' from r where step = 'create') = 'applied', 'new envelope applied');
select tests.ok((select (result -> 0 ->> 'version')::int from r where step = 'create') = 1, 'first version is 1');

-- Replay of the same change: idempotent.
insert into r select 'replay', public.sync_push('d0000000-0000-4000-8000-000000000001', jsonb_build_array(
  jsonb_build_object('id', '10000000-0000-4000-8000-000000000001', 'change_id', 'c0000000-0000-4000-8000-000000000001',
    'base_version', null, 'deleted', false, 'umk_version', 1, 'payload', encode('\x0102'::bytea, 'base64'))));
select tests.ok((select result -> 0 ->> 'status' from r where step = 'replay') = 'applied'
  and (select (result -> 0 ->> 'version')::int from r where step = 'replay') = 1, 'replay is idempotent');

-- Update on the right base, then a stale update.
insert into r select 'update', public.sync_push('d0000000-0000-4000-8000-000000000001', jsonb_build_array(
  jsonb_build_object('id', '10000000-0000-4000-8000-000000000001', 'change_id', 'c0000000-0000-4000-8000-000000000002',
    'base_version', 1, 'deleted', false, 'umk_version', 1, 'payload', encode('\x03'::bytea, 'base64'))));
select tests.ok((select (result -> 0 ->> 'version')::int from r where step = 'update') = 2, 'update gets version 2');

insert into r select 'stale', public.sync_push('d0000000-0000-4000-8000-000000000001', jsonb_build_array(
  jsonb_build_object('id', '10000000-0000-4000-8000-000000000001', 'change_id', 'c0000000-0000-4000-8000-000000000003',
    'base_version', 1, 'deleted', false, 'umk_version', 1, 'payload', encode('\x04'::bytea, 'base64'))));
select tests.ok((select result -> 0 ->> 'status' from r where step = 'stale') = 'conflict', 'stale base is a conflict');
select tests.ok((select (result -> 0 -> 'current' ->> 'version')::int from r where step = 'stale') = 2,
  'conflict returns the current version');
select tests.ok((select result -> 0 -> 'current' ->> 'payload' from r where step = 'stale') = encode('\x03'::bytea, 'base64'),
  'conflict returns the current envelope');

insert into r select 'blind', public.sync_push('d0000000-0000-4000-8000-000000000001', jsonb_build_array(
  jsonb_build_object('id', '10000000-0000-4000-8000-000000000001', 'change_id', 'c0000000-0000-4000-8000-000000000004',
    'base_version', null, 'deleted', false, 'umk_version', 1, 'payload', encode('\x05'::bytea, 'base64'))));
select tests.ok((select result -> 0 ->> 'status' from r where step = 'blind') = 'conflict',
  'creating over an existing record is a conflict');

-- Purge: deleted without payload is allowed; payload missing otherwise is rejected.
insert into r select 'purge', public.sync_push('d0000000-0000-4000-8000-000000000001', jsonb_build_array(
  jsonb_build_object('id', '10000000-0000-4000-8000-000000000001', 'change_id', 'c0000000-0000-4000-8000-000000000005',
    'base_version', 2, 'deleted', true, 'umk_version', 1, 'payload', null),
  jsonb_build_object('id', '10000000-0000-4000-8000-000000000002', 'change_id', 'c0000000-0000-4000-8000-000000000006',
    'base_version', null, 'deleted', false, 'umk_version', 1, 'payload', null)));
select tests.ok((select result -> 0 ->> 'status' from r where step = 'purge') = 'applied', 'purge applied');
select tests.ok((select result -> 1 ->> 'status' from r where step = 'purge') = 'rejected', 'missing payload rejected');

select tests.throws($$select public.sync_push('d0000000-0000-4000-8000-000000000001',
  (select jsonb_agg('{}'::jsonb) from generate_series(1, 51)))$$, 'batch_too_large', 'batches are limited to 50');

-- Pull: ordered, contiguous, from a cursor.
select tests.ok((public.sync_pull('d0000000-0000-4000-8000-000000000001', 0) ->> 'head')::int = 3, 'head is 3');
select tests.ok(jsonb_array_length(public.sync_pull('d0000000-0000-4000-8000-000000000001', 0) -> 'records') = 1,
  'one record (latest state only)');
select tests.ok((public.sync_pull('d0000000-0000-4000-8000-000000000001', 0) -> 'records' -> 0 ->> 'deleted')::boolean,
  'the purged record is a tombstone');
select tests.ok(jsonb_array_length(public.sync_pull('d0000000-0000-4000-8000-000000000001', 3) -> 'records') = 0,
  'nothing after the head');

-- Versions are contiguous per user across batches.
select public.sync_push('d0000000-0000-4000-8000-000000000001', (
  select jsonb_agg(jsonb_build_object('id', ('20000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
    'change_id', gen_random_uuid(), 'base_version', null, 'deleted', false, 'umk_version', 1,
    'payload', encode('\x01'::bytea, 'base64')))
  from generate_series(1, 10) as n));
select tests.ok((select array_agg((x ->> 'version')::int order by (x ->> 'version')::int)
  from jsonb_array_elements(public.sync_pull('d0000000-0000-4000-8000-000000000001', 3) -> 'records') as x)
  = array[4,5,6,7,8,9,10,11,12,13], 'versions are contiguous');
select tests.ok(jsonb_array_length(public.sync_pull('d0000000-0000-4000-8000-000000000001', 3, 4) -> 'records') = 4,
  'pull honours the limit');

select tests.logout();
rollback;
