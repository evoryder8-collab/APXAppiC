-- Keep superseded source releases retained for provenance while exposing only
-- the active, validated batch to authenticated clients.

alter policy food_corpus_records_authenticated_read
  on public.food_corpus_records
  using (
    exists (
      select 1
      from public.food_corpus_sources source
      join public.food_corpus_batches batch using (source_key)
      where source.source_key = food_corpus_records.source_key
        and batch.id = food_corpus_records.batch_id
        and source.ingest_status = 'active'
        and batch.status = 'active'
    )
  );

alter policy food_corpus_names_authenticated_read
  on public.food_corpus_names
  using (
    exists (
      select 1
      from public.food_corpus_records record
      join public.food_corpus_sources source using (source_key)
      join public.food_corpus_batches batch on record.batch_id = batch.id
      where record.id = food_corpus_names.record_id
        and source.ingest_status = 'active'
        and batch.status = 'active'
    )
  );

alter policy food_corpus_nutrients_authenticated_read
  on public.food_corpus_nutrients
  using (
    exists (
      select 1
      from public.food_corpus_records record
      join public.food_corpus_sources source using (source_key)
      join public.food_corpus_batches batch on record.batch_id = batch.id
      where record.id = food_corpus_nutrients.record_id
        and source.ingest_status = 'active'
        and batch.status = 'active'
    )
  );

alter policy food_corpus_search_authenticated_read
  on public.food_corpus_search
  using (
    exists (
      select 1
      from public.food_corpus_records record
      join public.food_corpus_sources source using (source_key)
      join public.food_corpus_batches batch on record.batch_id = batch.id
      where record.id = food_corpus_search.record_id
        and source.ingest_status = 'active'
        and batch.status = 'active'
    )
  );

create or replace function public.food_corpus_search_catalog(
  p_query text,
  p_limit integer default 25
)
returns table (
  record_id uuid,
  source_key text,
  source_record_id text,
  name text,
  names_i18n jsonb,
  aliases text[],
  brand text,
  barcode text,
  market text,
  basis_kind text,
  preparation_state text,
  kcal numeric,
  protein_g numeric,
  carbs_g numeric,
  fat_g numeric,
  fibre_g numeric,
  sugar_g numeric,
  saturated_fat_g numeric,
  salt_g numeric,
  water_g numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with query as (
    select lower(trim(regexp_replace(coalesce(p_query, ''), '[[:space:]]+', ' ', 'g'))) as value
  )
  select
    search.record_id,
    search.source_key,
    search.source_record_id,
    search.name,
    search.names_i18n,
    search.aliases,
    search.brand,
    search.barcode,
    search.market,
    search.basis_kind,
    search.preparation_state,
    search.kcal,
    search.protein_g,
    search.carbs_g,
    search.fat_g,
    search.fibre_g,
    search.sugar_g,
    search.saturated_fat_g,
    search.salt_g,
    search.water_g
  from public.food_corpus_search search
  join public.food_corpus_records record on record.id = search.record_id
  join public.food_corpus_sources source on source.source_key = search.source_key
  join public.food_corpus_batches batch on record.batch_id = batch.id
  cross join query
  where source.ingest_status = 'active'
    and batch.status = 'active'
    and length(query.value) >= 2
    and (
      lower(search.search_text) like '%' || query.value || '%'
      or to_tsvector('simple', search.search_text) @@ websearch_to_tsquery('simple', query.value)
      or lower(search.search_text) % query.value
    )
  order by
    case
      when lower(search.name) = query.value then 0
      when lower(search.name) like query.value || '%' then 1
      when lower(coalesce(search.brand, '')) like query.value || '%' then 2
      else 3
    end,
    case
      when search.kcal is not null and search.protein_g is not null and search.carbs_g is not null and search.fat_g is not null then 0
      when search.kcal is not null or search.protein_g is not null or search.carbs_g is not null or search.fat_g is not null then 1
      else 2
    end,
    search.source_priority,
    similarity(lower(search.search_text), query.value) desc,
    search.name,
    search.source_key,
    search.source_record_id
  limit least(greatest(coalesce(p_limit, 25), 1), 50)
$$;

revoke all on function public.food_corpus_search_catalog(text, integer) from public, anon;
grant execute on function public.food_corpus_search_catalog(text, integer) to authenticated, service_role;

notify pgrst, 'reload schema';
