-- Malagasy dropped (owner's decision, 2026-10-23): French and English only.
update public.profiles set preferred_locale = 'fr' where preferred_locale = 'mg';
alter table public.profiles
  alter column preferred_locale set default 'fr',
  drop constraint profiles_preferred_locale_check,
  add constraint profiles_preferred_locale_check
    check (preferred_locale in ('fr', 'en'));

create or replace function public.staff_set_translation(p_path text, p_pointer text[],
  p_locale text, p_text text, p_expected_version integer) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := authoring.require_staff(array['content_editor', 'translator']);
  v_body jsonb;
  v_target jsonb;
  v_version integer;
begin
  if p_locale is null or p_locale not in ('fr', 'en')
     or p_text is null or char_length(p_text) not between 1 and 5000 then
    raise exception 'invalid_translation' using errcode = 'P0001';
  end if;
  select body into v_body from authoring.documents
   where path = p_path and version = p_expected_version for update;
  if v_body is null then
    raise exception 'version_conflict' using errcode = 'P0001';
  end if;
  v_target := v_body #> p_pointer;
  if v_target is null or jsonb_typeof(v_target) <> 'object'
     or jsonb_typeof(v_target -> 'fr') is distinct from 'string' then
    raise exception 'invalid_translation' using errcode = 'P0001';
  end if;
  update authoring.documents
     set body = jsonb_set(v_body, p_pointer || p_locale, to_jsonb(p_text)),
         version = version + 1, updated_by = v_uid, updated_at = now()
   where path = p_path
  returning version into v_version;
  insert into authoring.audit_log (actor, action, target)
  values (v_uid, 'set_translation:' || p_locale, p_path);
  return v_version;
end;
$$;
