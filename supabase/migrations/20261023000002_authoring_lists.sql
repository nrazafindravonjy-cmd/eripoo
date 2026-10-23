-- Some content files are lists at the top level (missions, sections,
-- tools, badges): authoring documents may be objects or arrays.
alter table authoring.documents
  drop constraint documents_body_check,
  add constraint documents_body_check
    check (jsonb_typeof(body) in ('object', 'array'));
