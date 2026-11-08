-- Run only in an isolated fixture database named fitr_food_search_test.
-- Harness: node tools/food_corpus/tests/run_search_db_contract.mjs (PGHOST/PGPORT select the local server).
-- Public catalogue names below are real records; no invented nutrient values are needed.
begin;
do $$
begin
  if current_database() <> 'fitr_food_search_test' then
    raise exception 'Food-search fixtures must run in the isolated test database';
  end if;
end $$;

insert into public.food_corpus_sources (source_key, ingest_status) values
  ('test-active', 'active'), ('test-inactive', 'quarantined');
insert into public.food_corpus_batches (id, status) values
  ('00000000-0000-0000-0000-000000000001', 'active'),
  ('00000000-0000-0000-0000-000000000002', 'staged');

with fixtures(name, source_key, batch_id, aliases) as (values
  ('Steak and kidney pudding', 'test-active', 1, array[]::text[]),
  ('Steak fries', 'test-active', 1, array[]::text[]),
  ('Steak sauce', 'test-active', 1, array[]::text[]),
  ('Beef, sirloin steak', 'test-active', 1, array[]::text[]),
  ('Bread, seeded', 'test-active', 1, array[]::text[]),
  ('Bread, sunflower meal', 'test-active', 1, array[]::text[]),
  ('Wheat bread, white, with sunflower kernels', 'test-active', 1, array[]::text[]),
  ('Breadnut seeds, dried', 'test-active', 1, array[]::text[]),
  ('Scampi in breadcrumbs with sunflower oil', 'test-active', 1, array[]::text[]),
  ('Strawberry, raw', 'test-active', 1, array[]::text[]),
  ('Mango, raw', 'test-active', 1, array[]::text[]),
  ('Bread, sunflower, unavailable source', 'test-inactive', 1, array[]::text[]),
  ('Bread, sunflower, unavailable batch', 'test-active', 2, array[]::text[]),
  ('Strawbery', 'test-inactive', 1, array[]::text[]),
  ('Milk bread', 'test-active', 1, array['Pain au lait']::text[])
), records as (
  insert into public.food_corpus_records (id, batch_id)
  select md5(name)::uuid,
    ('00000000-0000-0000-0000-00000000000' || batch_id)::uuid
  from fixtures returning id
)
insert into public.food_corpus_search (
  record_id, source_key, source_record_id, name, names_i18n, aliases,
  search_text, source_priority
)
select md5(name)::uuid, source_key, name, name, '{}'::jsonb, aliases,
  public.food_search_normalize(name || ' ' || array_to_string(aliases, ' ')), 1
from fixtures;

update public.food_corpus_search set protein_g = 22, carbs_g = 0 where name = 'Beef, sirloin steak';

do $$
declare names text[];
begin
  if (select name from public.food_corpus_search_catalog('steak', 1)) is distinct from 'Beef, sirloin steak'
     or (select name from public.food_corpus_search_catalog('steak sauce', 1)) is distinct from 'Steak sauce' then
    raise exception 'steak intent was lost before the result limit';
  end if;

  select array_agg(name) into names
  from public.food_corpus_search_catalog('bread seeds', 25);
  if names is distinct from array['Bread, seeded'] then
    raise exception 'bread seeds must find seeded bread without breadnut: %', names;
  end if;

  select array_agg(name order by name) into names
  from public.food_corpus_search_catalog('BRead sunflower', 25);
  if names is distinct from array['Bread, sunflower meal', 'Wheat bread, white, with sunflower kernels'] then
    raise exception 'BRead sunflower must find relevant active breads, not breadcrumbs: %', names;
  end if;

  select array_agg(name order by name) into names
  from public.food_corpus_search_catalog('sunflower bread', 25);
  if names is distinct from array['Bread, sunflower meal', 'Wheat bread, white, with sunflower kernels'] then
    raise exception 'All query words must match in either order: %', names;
  end if;

  select array_agg(name) into names
  from public.food_corpus_search_catalog('strawbery', 25);
  if names is distinct from array['Strawberry, raw'] then
    raise exception 'Inactive exact matches must not suppress active typo fallback: %', names;
  end if;

  select array_agg(name) into names
  from public.food_corpus_search_catalog('mango', 25);
  if names is distinct from array['Mango, raw'] then
    raise exception 'A basic exact food query must remain available: %', names;
  end if;

  select array_agg(name) into names
  from public.food_corpus_search_catalog('pain lait', 25);
  if names is distinct from array['Milk bread'] then
    raise exception 'Multilingual aliases must remain searchable: %', names;
  end if;

  if exists (select 1 from public.food_corpus_search_catalog('', 25)) then
    raise exception 'Empty queries must not return the entire catalogue';
  end if;
  if (select count(*) from public.food_corpus_search_catalog('bread', 1)) <> 1 then
    raise exception 'The requested result limit must remain bounded';
  end if;
end $$;
rollback;
