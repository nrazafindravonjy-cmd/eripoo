-- Back-office (migration 20261023000001_backoffice.sql): staff roles with
-- a second factor, versioned documents, translators limited to localized
-- texts, masked statistics, no access to private data.
begin;

select tests.create_user('00000000-0000-4000-8000-0000000000e1'); -- editor
select tests.create_user('00000000-0000-4000-8000-0000000000e2'); -- translator
select tests.create_user('00000000-0000-4000-8000-0000000000e3'); -- analyst
select tests.create_user('00000000-0000-4000-8000-0000000000e4'); -- no role
insert into authoring.staff_roles (user_id, role) values
  ('00000000-0000-4000-8000-0000000000e1', 'content_editor'),
  ('00000000-0000-4000-8000-0000000000e2', 'translator'),
  ('00000000-0000-4000-8000-0000000000e3', 'analyst');
insert into public.usage_daily (day, event, app_version, count) values
  (current_date, 'app_opened', '1.0.0+1', 25),
  (current_date, 'pdf_exported', '1.0.0+1', 3);

-- Second factor required.
select tests.login_aal('00000000-0000-4000-8000-0000000000e1', 'aal1');
select tests.throws($$select public.staff_my_roles()$$, 'mfa_required',
  'a password-only session cannot use the back-office');
select tests.logout();

-- No role.
select tests.login_aal('00000000-0000-4000-8000-0000000000e4', 'aal2');
select tests.throws($$select public.staff_my_roles()$$, 'not_staff',
  'an ordinary account is not staff');
select tests.throws($$select * from authoring.documents$$, 'permission denied',
  'the authoring schema is not reachable directly');
select tests.logout();

set local role anon;
select tests.throws($$select public.staff_list_documents()$$, 'permission denied',
  'anonymous callers cannot call staff functions');
reset role;

-- Editor.
select tests.login_aal('00000000-0000-4000-8000-0000000000e1', 'aal2');
select tests.ok(public.staff_my_roles() = array['content_editor'], 'roles are listed');
select tests.ok(public.staff_save_document('quests/q99_test.yaml',
  '{"id": "q99", "title": {"fr": "Titre", "mg": "Lohateny", "en": "Title"}}', 0) = 1,
  'an editor creates a document');
select tests.throws($$select public.staff_save_document('quests/q99_test.yaml', '{}', 0)$$,
  'version_conflict', 'an existing document is not created twice');
select tests.ok(public.staff_save_document('quests/q99_test.yaml',
  '{"id": "q99", "title": {"fr": "Titre 2", "mg": "Lohateny", "en": "Title"}}', 1) = 2,
  'an editor saves a new version');
select tests.throws($$select public.staff_save_document('quests/q99_test.yaml', '{}', 1)$$,
  'version_conflict', 'a stale version is refused');
select tests.throws($$select public.staff_save_document('../secret.yaml', '{}', 0)$$,
  'invalid_document', 'paths stay inside the content tree');
select tests.throws($$select public.staff_usage_stats(current_date, current_date)$$,
  'not_staff', 'an editor does not see statistics');
select tests.logout();

-- Translator.
select tests.login_aal('00000000-0000-4000-8000-0000000000e2', 'aal2');
select tests.ok(public.staff_set_translation('quests/q99_test.yaml',
  array['title'], 'mg', 'Lohateny vaovao', 2) = 3, 'a translator changes a localized text');
select tests.ok((select body from public.staff_get_document('quests/q99_test.yaml'))
  #>> '{title,mg}' = 'Lohateny vaovao', 'the translation is stored');
select tests.throws($$select public.staff_set_translation('quests/q99_test.yaml',
  array['id'], 'mg', 'x', 3)$$, 'invalid_translation', 'only localized texts can be translated');
select tests.throws($$select public.staff_set_translation('quests/q99_test.yaml',
  array['title'], 'de', 'x', 3)$$, 'invalid_translation', 'only mg, fr and en are accepted');
select tests.throws($$select public.staff_save_document('quests/q99_test.yaml', '{}', 3)$$,
  'not_staff', 'a translator cannot rewrite a document');
select tests.logout();

-- Analyst.
select tests.login_aal('00000000-0000-4000-8000-0000000000e3', 'aal2');
select tests.ok((select count from public.staff_usage_stats(current_date, current_date)
   where event = 'app_opened') = 25, 'an analyst reads aggregated totals');
select tests.ok((select count from public.staff_usage_stats(current_date, current_date)
   where event = 'pdf_exported') is null, 'totals under 10 are hidden');
select tests.throws($$select public.staff_list_documents()$$, 'not_staff',
  'an analyst does not edit content');
select tests.logout();

select tests.ok((select count(*) from authoring.audit_log) = 3,
  'each change is logged');
select tests.ok(not exists (select from pg_policies
   where tablename in ('profiles', 'sync_records', 'user_keys', 'consents')
     and qual ilike '%staff_roles%'),
  'no staff policy on private tables');
rollback;
