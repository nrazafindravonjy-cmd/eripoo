-- Tiny assertion helpers for the SQL tests (not part of the migrations).
create schema if not exists tests;
grant usage on schema tests to anon, authenticated;

create or replace function tests.ok(p_condition boolean, p_description text)
returns void language plpgsql as $$
begin
  if p_condition is distinct from true then
    raise exception 'FAILED: %', p_description;
  end if;
  raise notice 'ok - %', p_description;
end;
$$;

-- Runs p_sql and checks that it fails with a message containing p_expected.
create or replace function tests.throws(p_sql text, p_expected text, p_description text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if position(p_expected in sqlerrm) > 0 then
      raise notice 'ok - %', p_description;
      return;
    end if;
    raise exception 'FAILED: % (got: %)', p_description, sqlerrm;
  end;
  raise exception 'FAILED: % (no error raised)', p_description;
end;
$$;

-- Acts as user p_uid for the rest of the transaction, with a JWT "amr"
-- entry authenticated p_auth_age ago.
create or replace function tests.login(p_uid uuid, p_auth_age interval default interval '1 minute')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', p_uid, 'role', 'authenticated',
    'amr', jsonb_build_array(jsonb_build_object(
      'method', 'password',
      'timestamp', extract(epoch from now() - p_auth_age)::bigint)))::text, true);
  execute 'set local role authenticated';
end;
$$;

create or replace function tests.logout() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end;
$$;

create or replace function tests.create_user(p_uid uuid) returns void
language sql as $$
  insert into auth.users (id, email) values (p_uid, p_uid || '@example.invalid')
$$;

-- Random bytes without extensions (test data only).
create or replace function public.gen_random_bytes_stub(p_length integer) returns bytea
language sql volatile as $$
  select decode(string_agg(lpad(to_hex((random() * 255)::int), 2, '0'), ''), 'hex')
  from generate_series(1, p_length)
$$;
grant execute on function public.gen_random_bytes_stub(integer) to authenticated;

grant execute on all functions in schema tests to anon, authenticated;
