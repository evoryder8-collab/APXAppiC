-- Production Food Memory hotfix: Swiss McDonald's whole-item servings,
-- source-aware food water, and forgiving joined-word / typo search.

create or replace function public.search_food_catalog(
  p_query text,
  p_limit integer default 25
)
returns setof public.foods
language sql
stable
security definer
set search_path = public
as $function$
  with input as (
    select
      lower(trim(regexp_replace(coalesce(p_query, ''), '[[:space:]]+', ' ', 'g'))) as needle,
      regexp_replace(lower(coalesce(p_query, '')), '[^[:alnum:]]', '', 'g') as compact_needle,
      least(greatest(coalesce(p_limit, 25), 1), 50) as result_limit
  ), candidates as (
    select
      f.id,
      case
        when lower(f.name) = input.needle then 0
        when lower(coalesce(fp.personal_name, '')) = input.needle then 0
        when lower(f.name) like input.needle || '%' then 1
        when lower(coalesce(f.brand, '')) like input.needle || '%' then 1
        when haystack.compact_name = input.compact_needle then 1
        when lower(f.name) like '%' || input.needle || '%' then 2
        when haystack.compact_name like '%' || input.compact_needle || '%' then 2
        when haystack.compact_brand_name like '%' || input.compact_needle || '%' then 2
        when lower(coalesce(f.names_i18n::text, '')) like '%' || input.needle || '%' then 3
        when lower(coalesce(fp.personal_name, '')) like '%' || input.needle || '%' then 3
        else 4
      end as search_rank,
      greatest(
        similarity(haystack.value, input.needle),
        similarity(haystack.compact_name, input.compact_needle),
        similarity(haystack.compact_brand_name, input.compact_needle),
        word_similarity(input.compact_needle, haystack.compact_name),
        word_similarity(input.compact_needle, haystack.compact_brand_name)
      ) as fuzzy_rank,
      input.result_limit
    from public.foods f
    cross join input
    left join public.food_preferences fp
      on fp.food_id = f.id
     and fp.user_id = auth.uid()
    cross join lateral (
      select
        lower(concat_ws(
          ' ', f.name, f.brand, f.names_i18n::text,
          fp.personal_name, array_to_string(fp.aliases, ' ')
        )) as value,
        regexp_replace(lower(concat_ws(
          ' ', f.name, f.brand, f.names_i18n::text,
          fp.personal_name, array_to_string(fp.aliases, ' ')
        )), '[^[:alnum:]]', '', 'g') as compact_value,
        regexp_replace(lower(f.name), '[^[:alnum:]]', '', 'g') as compact_name,
        regexp_replace(lower(concat_ws(' ', f.brand, f.name)), '[^[:alnum:]]', '', 'g') as compact_brand_name
    ) haystack
    where auth.uid() is not null
      and (f.owner_user_id is null or f.owner_user_id = auth.uid())
      and coalesce(fp.hidden, false) = false
      and length(input.needle) >= 2
      and (
        haystack.value like '%' || input.needle || '%'
        or haystack.compact_name like '%' || input.compact_needle || '%'
        or haystack.compact_brand_name like '%' || input.compact_needle || '%'
        or similarity(haystack.value, input.needle) >= 0.18
        or similarity(haystack.compact_name, input.compact_needle) >= 0.24
        or similarity(haystack.compact_brand_name, input.compact_needle) >= 0.24
        or word_similarity(input.compact_needle, haystack.compact_name) >= 0.42
        or word_similarity(input.compact_needle, haystack.compact_brand_name) >= 0.42
        or not exists (
          select 1
          from regexp_split_to_table(input.needle, '\s+') token
          where haystack.value not like '%' || token || '%'
            and similarity(haystack.value, token) < 0.18
        )
      )
  )
  select f.*
  from candidates
  join public.foods f on f.id = candidates.id
  order by candidates.search_rank, candidates.fuzzy_rank desc, f.name, candidates.id
  limit (select result_limit from input);
$function$;

revoke all on function public.search_food_catalog(text, integer) from public, anon;
grant execute on function public.search_food_catalog(text, integer) to authenticated;

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
    select
      lower(trim(regexp_replace(coalesce(p_query, ''), '[[:space:]]+', ' ', 'g'))) as value,
      regexp_replace(lower(coalesce(p_query, '')), '[^[:alnum:]]', '', 'g') as compact_value
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
  cross join lateral (
    select
      regexp_replace(lower(search.search_text), '[^[:alnum:]]', '', 'g') as compact_search,
      regexp_replace(lower(search.name), '[^[:alnum:]]', '', 'g') as compact_name,
      regexp_replace(lower(concat_ws(' ', search.brand, search.name)), '[^[:alnum:]]', '', 'g') as compact_brand_name
  ) normalized
  where source.ingest_status = 'active'
    and batch.status = 'active'
    and length(query.value) >= 2
    and (
      lower(search.search_text) like '%' || query.value || '%'
      or normalized.compact_search like '%' || query.compact_value || '%'
      or to_tsvector('simple', search.search_text) @@ websearch_to_tsquery('simple', query.value)
      or lower(search.search_text) % query.value
      or similarity(lower(search.search_text), query.value) >= 0.18
      or similarity(normalized.compact_name, query.compact_value) >= 0.24
      or similarity(normalized.compact_brand_name, query.compact_value) >= 0.24
      or word_similarity(query.compact_value, normalized.compact_name) >= 0.42
      or word_similarity(query.compact_value, normalized.compact_brand_name) >= 0.42
    )
  order by
    case
      when lower(search.name) = query.value then 0
      when lower(search.name) like query.value || '%' then 1
      when normalized.compact_name = query.compact_value then 1
      when lower(coalesce(search.brand, '')) like query.value || '%' then 2
      when normalized.compact_name like '%' || query.compact_value || '%' then 2
      when normalized.compact_brand_name like '%' || query.compact_value || '%' then 2
      else 3
    end,
    case
      when search.kcal is not null and search.protein_g is not null and search.carbs_g is not null and search.fat_g is not null then 0
      when search.kcal is not null or search.protein_g is not null or search.carbs_g is not null or search.fat_g is not null then 1
      else 2
    end,
    search.source_priority,
    greatest(
      similarity(lower(search.search_text), query.value),
      similarity(normalized.compact_name, query.compact_value),
      similarity(normalized.compact_brand_name, query.compact_value),
      word_similarity(query.compact_value, normalized.compact_name),
      word_similarity(query.compact_value, normalized.compact_brand_name)
    ) desc,
    search.name,
    search.source_key,
    search.source_record_id
  limit least(greatest(coalesce(p_limit, 25), 1), 50)
$$;

revoke all on function public.food_corpus_search_catalog(text, integer) from public, anon;
grant execute on function public.food_corpus_search_catalog(text, integer) to authenticated, service_role;

with swiss_mcdonalds (
  id, name, names_i18n, provider_product_id, grams,
  kcal_100, protein_100, carbs_100, fat_100, fibre_100, sugar_100,
  water_ml_100, water_basis, water_source_id, confidence
) as (
  values
    (
      'f4570000-0000-4000-8000-000000000001'::uuid,
      'Cheeseburger Royal',
      '{"en":"Cheeseburger Royal","de":"Cheeseburger Royal","de-CH":"Cheeseburger Royal","fr":"Cheeseburger Royal","it":"Cheeseburger Royal","es":"Cheeseburger Royal","pt":"Cheeseburger Royal","ro":"Cheeseburger Royal","th":"ชีสเบอร์เกอร์รอยัล","ja":"チーズバーガー・ロイヤル"}'::jsonb,
      'fsvo-v5.3:10675',
      207.0, 256.0, 15.5, 17.4, 13.5, 1.4, 4.3,
      52.2, 'reference', 'swiss-fsvo-v5.3:10675', 'provider_verified'
    ),
    (
      'f4570000-0000-4000-8000-000000000021'::uuid,
      'Big Tasty Single',
      '{"en":"Big Tasty Single","de":"Big Tasty Single","de-CH":"Big Tasty Single","fr":"Big Tasty Single","it":"Big Tasty Single","es":"Big Tasty Single","pt":"Big Tasty Single","ro":"Big Tasty Single","th":"บิ๊กเทสตี้ซิงเกิล","ja":"ビッグテイスティ・シングル"}'::jsonb,
      'mcdonalds-ch:big-tasty-single-273g',
      273.0, 223.0769, 11.7216, 12.8205, 13.5531, null, null,
      61.0, 'difference', null, 'complete'
    ),
    (
      'f4570000-0000-4000-8000-000000000022'::uuid,
      'Big Tasty Double',
      '{"en":"Big Tasty Double","de":"Big Tasty Double","de-CH":"Big Tasty Double","fr":"Big Tasty Double","it":"Big Tasty Double","es":"Big Tasty Double","pt":"Big Tasty Double","ro":"Big Tasty Double","th":"บิ๊กเทสตี้ดับเบิล","ja":"ビッグテイスティ・ダブル"}'::jsonb,
      'mcdonalds-ch:big-tasty-double-370g',
      370.0, 239.1892, 14.8649, 9.7297, 15.6757, null, null,
      58.8, 'difference', null, 'complete'
    ),
    (
      'f4570000-0000-4000-8000-000000000002'::uuid,
      'McRaclette Classic',
      '{"en":"McRaclette Classic","de":"McRaclette Classic","de-CH":"McRaclette Classic","fr":"McRaclette Classic","it":"McRaclette Classic","es":"McRaclette Classic","pt":"McRaclette Classic","ro":"McRaclette Classic","th":"แมคราแคลตต์คลาสสิก","ja":"マックラクレット・クラシック"}'::jsonb,
      'mcdonalds-ch:mcraclette-classic-archive',
      269.0, 272.0, 16.0, 16.0, 16.0, 1.0, null,
      51.1, 'difference', null, 'complete'
    )
)
insert into public.foods (
  id, owner_user_id, name, names_i18n, brand, source, provider_product_id,
  package_quantity, nutrition_basis, preparation_state,
  kcal_100, protein_100, carbs_100, fat_100, fibre_100, sugar_100,
  water_ml_100, water_basis, water_source_id,
  serving_amount, serving_unit, serving_grams_or_ml, confidence
)
select
  id, null, name, names_i18n, 'McDonald''s Switzerland', 'apex_cache', provider_product_id,
  concat(grams, ' g'), 'per_100g', 'as_sold',
  kcal_100, protein_100, carbs_100, fat_100, fibre_100, sugar_100,
  water_ml_100, water_basis, water_source_id,
  1, 'serving', grams, confidence
from swiss_mcdonalds
on conflict (id) do update set
  name = excluded.name,
  names_i18n = excluded.names_i18n,
  brand = excluded.brand,
  source = excluded.source,
  provider_product_id = excluded.provider_product_id,
  package_quantity = excluded.package_quantity,
  nutrition_basis = excluded.nutrition_basis,
  preparation_state = excluded.preparation_state,
  kcal_100 = excluded.kcal_100,
  protein_100 = excluded.protein_100,
  carbs_100 = excluded.carbs_100,
  fat_100 = excluded.fat_100,
  fibre_100 = excluded.fibre_100,
  sugar_100 = excluded.sugar_100,
  water_ml_100 = excluded.water_ml_100,
  water_basis = excluded.water_basis,
  water_source_id = excluded.water_source_id,
  serving_amount = excluded.serving_amount,
  serving_unit = excluded.serving_unit,
  serving_grams_or_ml = excluded.serving_grams_or_ml,
  confidence = excluded.confidence,
  updated_at = now();

with usda_reference(provider_product_id, grams, water, source_id) as (
  values
    ('apex-curated:usda-fdc-170693', 78.0, 38.45, 'usda-fdc:170693'),
    ('apex-curated:usda-fdc-170717', 95.0, 44.53, 'usda-fdc:170717'),
    ('apex-curated:usda-fdc-170320', 119.0, 45.0, 'usda-fdc:170320'),
    ('apex-curated:usda-fdc-172065', 155.0, 47.0, 'usda-fdc:172065'),
    ('apex-curated:usda-fdc-170328', 99.0, 45.97, 'usda-fdc:170328'),
    ('apex-curated:usda-fdc-170329', 133.0, 44.59, 'usda-fdc:170329')
)
update public.foods food
set
  water_ml_100 = reference.water,
  water_basis = 'reference',
  water_source_id = reference.source_id,
  serving_amount = 1,
  serving_unit = 'serving',
  serving_grams_or_ml = reference.grams,
  package_quantity = concat(reference.grams, ' g'),
  updated_at = now()
from usda_reference reference
where food.provider_product_id = reference.provider_product_id;

with derived as (
  select
    food.id,
    food.nutrition_basis = 'per_100ml' as per_ml,
    food.protein_100 as protein,
    food.carbs_100 as carbs,
    food.fat_100 as fat,
    coalesce(food.fibre_100, 0) as fibre,
    food.kcal_100 as kcal,
    case
      when food.salt_100 is not null and food.salt_100 > 0
        then least(20, greatest(0.5, food.salt_100 * 1.1))
      when food.protein_100 >= 60 then 3.5
      when food.protein_100 >= 15 and food.fat_100 <= 12 then 1.2
      when food.fat_100 >= 50 then 1.8
      else 0.9
    end as ash
  from public.foods food
  where food.water_ml_100 is null
    and food.protein_100 is not null
    and food.carbs_100 is not null
    and food.fat_100 is not null
    and coalesce(food.provider_product_id, '') not like 'apex-plan:%'
    and coalesce(food.brand, '') <> 'APEX plan'
), resolved as (
  select
    id,
    case
      when fat >= (case when per_ml then 80 else 90 end) and protein + carbs <= 2 then 0
      when per_ml and fat >= 20 then null
      else greatest(0, least(100, round(
        100 - (protein + carbs + fat + ash + case
          when fibre <= 0 then 0
          when kcal is null or kcal <= 0 then fibre
          when abs((4*protein + 4*carbs + 9*fat + 2*fibre) - kcal)
             <= abs((4*protein + 4*(carbs - fibre) + 9*fat + 2*fibre) - kcal) then fibre
          else 0
        end), 1
      )))
    end as water
  from derived
)
update public.foods food
set
  water_ml_100 = resolved.water,
  water_basis = 'difference',
  water_source_id = null,
  updated_at = now()
from resolved
where food.id = resolved.id and resolved.water is not null;

update public.logged_food_entries entry
set
  snapshot_water_ml_100 = food.water_ml_100,
  snapshot_water_basis = food.water_basis,
  snapshot_water_source_id = food.water_source_id,
  water_ml = round(food.water_ml_100 * entry.equivalent_amount / 100, 2)
from public.foods food
where entry.food_id = food.id
  and food.water_ml_100 is not null
  and entry.snapshot_water_ml_100 is null;

notify pgrst, 'reload schema';
