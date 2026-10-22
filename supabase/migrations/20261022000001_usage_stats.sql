-- Opt-in usage statistics (decision D7, 2026-10-22; NEXT_STEPS C-13).
-- Only daily totals per event and app version: no user id, no device id,
-- no IP, no timestamp finer than the server's day, no content. Events are
-- a fixed list. Written only through record_usage(); nobody can read the
-- table through the API (owner reports run with the service role).

create table public.usage_daily (
  day date not null,
  event text not null check (event in (
    'app_opened', 'diagnostic_completed', 'quest_completed',
    'mission_completed', 'pdf_exported')),
  app_version text not null check (char_length(app_version) between 1 and 32),
  count bigint not null default 0 check (count >= 0),
  primary key (day, event, app_version)
);

revoke all on public.usage_daily from anon, authenticated;
alter table public.usage_daily enable row level security;
-- No policy: not readable or writable through the API.

-- p_events: [{"event": "app_opened", "count": 1}, ...], at most 20 items,
-- each count between 1 and 100. Anonymous callers are allowed: sending
-- statistics never needs (nor reveals) an account.
create function public.record_usage(p_events jsonb, p_app_version text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_item jsonb;
  v_count integer;
begin
  if jsonb_typeof(p_events) is distinct from 'array'
     or jsonb_array_length(p_events) not between 1 and 20
     or p_app_version is null
     or char_length(p_app_version) not between 1 and 32 then
    raise exception 'invalid_usage' using errcode = 'P0001';
  end if;
  for v_item in select value from jsonb_array_elements(p_events) loop
    v_count := (v_item->>'count')::integer;
    if v_count is null or v_count not between 1 and 100 then
      raise exception 'invalid_usage' using errcode = 'P0001';
    end if;
    insert into public.usage_daily (day, event, app_version, count)
    values (current_date, v_item->>'event', p_app_version, v_count)
    on conflict (day, event, app_version)
      do update set count = public.usage_daily.count + excluded.count;
  end loop;
exception
  when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'invalid_usage' using errcode = 'P0001';
end;
$$;

revoke all on function public.record_usage(jsonb, text) from public;
grant execute on function public.record_usage(jsonb, text) to anon, authenticated;
