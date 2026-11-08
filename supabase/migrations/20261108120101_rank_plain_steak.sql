-- Put a plain cut of meat before steak sauces, fries and prepared dishes.
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
  with normalized_query as (
    select public.food_search_normalize(p_query) as value
  ), query as (
    select value, to_tsquery('simple', (
      select string_agg(
        case when token in ('seed', 'seeds', 'seeded')
          then '(''seed'' | ''seeds'' | ''seeded'')'
          else quote_literal(token) end,
        ' & '
      )
      from unnest(string_to_array(value, ' ')) token
      where token <> ''
    )) as document_query
    from normalized_query
  ), strong_matches as materialized (
    -- Require every whole word, regardless of order. The existing GIN index
    -- avoids fuzzy-scoring thousands of bread rows for a two-word query.
    select search.record_id
    from public.food_corpus_search search
    join public.food_corpus_records record on record.id = search.record_id
    join public.food_corpus_sources source on source.source_key = search.source_key
    join public.food_corpus_batches batch on record.batch_id = batch.id
    cross join query
    where source.ingest_status = 'active'
      and batch.status = 'active'
      and length(query.value) >= 2
      and to_tsvector('simple', search.search_text) @@ query.document_query
  ), candidates as materialized (
    select search.*
    from public.food_corpus_search search
    join strong_matches on strong_matches.record_id = search.record_id
    union all
    -- Preserve typo/connected-word matching when there is no active strong hit.
    -- The one-time NOT EXISTS guard prevents the expensive branch from running
    -- after an indexed match; inactive batches cannot suppress this fallback.
    select search.*
    from public.food_corpus_search search
    cross join query
    where not exists (select 1 from strong_matches)
      and length(query.value) >= 2
      and (
        search.search_text like '%' || query.value || '%'
        or search.search_text %> query.value
        or search.search_text like '%' || split_part(query.value, ' ', 1) || '%'
        or search.search_text %> split_part(query.value, ' ', 1)
      )
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
  from candidates search
  join public.food_corpus_records record on record.id = search.record_id
  join public.food_corpus_sources source on source.source_key = search.source_key
  join public.food_corpus_batches batch on record.batch_id = batch.id
  cross join query
  cross join lateral (
    select public.food_search_normalize(concat_ws(
      ' ', search.name, search.brand, search.names_i18n::text, array_to_string(search.aliases, ' ')
    )) as value
  ) normalized
  where source.ingest_status = 'active'
    and batch.status = 'active'
    and length(query.value) >= 2
    and public.food_search_every_query_token_matches(query.value, normalized.value)
  order by
    case
      when query.value = 'steak' and public.food_search_normalize(search.name) ~ '\m(sauce|fries|pudding|pie|sandwich|burger|seasoning|pizza|tartare|teriyaki)\M' then 2
      when query.value = 'steak' and search.protein_g >= 15 and search.carbs_g <= 5
        and public.food_search_normalize(search.name) ~ '\m(beef|sirloin|ribeye|entrecote|rump|tenderloin)\M' then -3
      when query.value = 'steak' and search.protein_g >= 15 and search.carbs_g <= 5 then -1
      when query.value in ('oil', 'ulei', 'ol', 'huile', 'olio', 'aceite')
        and coalesce(search.fat_g, 0) >= 90
        and normalized.value ~ '(extra virgin olive|olive extra virgin|evoo)'
        then -3
      when query.value in ('oil', 'ulei', 'ol', 'huile', 'olio', 'aceite')
        and coalesce(search.fat_g, 0) >= 90
        and normalized.value ~ '(olive oil|oil olive|vegetable oil|oil vegetable)'
        then -2
      when query.value in ('oil', 'ulei', 'ol', 'huile', 'olio', 'aceite')
        and coalesce(search.fat_g, 0) >= 90
        and (' ' || normalized.value || ' ') ~ (' (oil|ulei|ol|huile|olio|aceite) ')
        then -1
      when query.value in ('oil', 'ulei', 'ol', 'huile', 'olio', 'aceite')
        and normalized.value ~ '(margarine|margarin|margarina)'
        then 1
      else 0
    end,
    case
      when public.food_search_normalize(search.name) = query.value then 0
      when public.food_search_normalize(search.name) like query.value || '%' then 1
      when normalized.value like '%' || query.value || '%' then 2
      else 3
    end,
    case
      when search.kcal is not null and search.protein_g is not null and search.carbs_g is not null and search.fat_g is not null then 0
      when search.kcal is not null or search.protein_g is not null or search.carbs_g is not null or search.fat_g is not null then 1
      else 2
    end,
    search.source_priority,
    similarity(normalized.value, query.value) desc,
    search.name,
    search.source_key,
    search.source_record_id
  limit least(greatest(coalesce(p_limit, 25), 1), 50)
$$;
