-- Opt-in usage statistics (migration 20261022000001_usage_stats.sql):
-- daily totals only, a fixed list of events, no identity, unreadable
-- through the API.
begin;

set local role anon;
select public.record_usage('[{"event": "app_opened", "count": 1}]', '1.0.0+1');
select public.record_usage('[{"event": "app_opened", "count": 2},
  {"event": "pdf_exported", "count": 1}]', '1.0.0+1');
select tests.throws($$select * from public.usage_daily$$, 'permission denied',
  'the totals cannot be read through the API');
select tests.throws($$select public.record_usage('[{"event": "screen_viewed", "count": 1}]', '1.0.0+1')$$,
  'invalid_usage', 'only the listed events are accepted');
select tests.throws($$select public.record_usage('[{"event": "app_opened", "count": 1000}]', '1.0.0+1')$$,
  'invalid_usage', 'a count is between 1 and 100');
select tests.throws($$select public.record_usage('{"event": "app_opened"}', '1.0.0+1')$$,
  'invalid_usage', 'a batch is a list');
reset role;

select tests.ok((select count from public.usage_daily
   where day = current_date and event = 'app_opened' and app_version = '1.0.0+1') = 3,
  'totals add up per day, event and version');
select tests.ok((select count(*) from information_schema.columns
   where table_schema = 'public' and table_name = 'usage_daily') = 4,
  'nothing but the day, the event, the version and the total is stored');
rollback;
