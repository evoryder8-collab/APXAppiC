-- Strict, intent-preserving Food Memory search plus two distinct broccoli
-- references. This migration is additive and retains every existing food.

create extension if not exists fuzzystrmatch with schema extensions;

create or replace function public.food_search_normalize(p_value text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select trim(regexp_replace(
    replace(replace(replace(replace(
      lower(regexp_replace(coalesce(p_value, ''), '[^[:alnum:]]+', ' ', 'g')),
      'extra vergin', 'extra virgin'),
      'oliv oil', 'olive oil'),
      'omlette', 'omelette'),
      'raviolli', 'ravioli'),
    '[[:space:]]+', ' ', 'g'
  ));
$$;

create or replace function public.food_search_token_matches(
  p_query_token text,
  p_candidate_token text
)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = public, extensions
as $$
declare
  query_token text := public.food_search_normalize(p_query_token);
  candidate_token text := public.food_search_normalize(p_candidate_token);
  distance_limit integer;
  distance integer;
  ratio numeric;
begin
  if query_token = '' or candidate_token = '' then return false; end if;
  if query_token = candidate_token then return true; end if;
  if length(query_token) >= 3 and length(candidate_token) >= 3
     and candidate_token like query_token || '%' then
    return true;
  end if;
  if length(query_token) >= 3 and length(candidate_token) >= 3
     and query_token like candidate_token || '%'
     and length(query_token) - length(candidate_token) <= 2 then
    return true;
  end if;
  if length(query_token) < 4 or length(candidate_token) < 4
     or left(query_token, 1) <> left(candidate_token, 1) then
    return false;
  end if;
  distance_limit := case
    when length(query_token) >= 9 or length(query_token) between 5 and 6 then 2
    else 1
  end;
  distance := extensions.levenshtein_less_equal(query_token, candidate_token, distance_limit);
  if distance > distance_limit then return false; end if;
  ratio := 1 - distance::numeric / greatest(length(query_token), length(candidate_token));
  return ratio >= case when length(query_token) >= 5 then 0.66 else 0.74 end;
end;
$$;

create or replace function public.food_search_query_token_matches_candidate(
  p_query_token text,
  p_candidate text
)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = public
as $$
declare
  candidate_tokens text[] := regexp_split_to_array(public.food_search_normalize(p_candidate), '\s+');
  candidate_count integer := coalesce(array_length(candidate_tokens, 1), 0);
  candidate_index integer;
  span_length integer;
  candidate_form text;
begin
  if candidate_count = 0 then return false; end if;
  for candidate_index in 1..candidate_count loop
    if public.food_search_token_matches(p_query_token, candidate_tokens[candidate_index]) then
      return true;
    end if;
    if right(candidate_tokens[candidate_index], 3) = 'ies'
       and public.food_search_token_matches(
         p_query_token,
         left(candidate_tokens[candidate_index], length(candidate_tokens[candidate_index]) - 3) || 'y'
       ) then return true; end if;
    if right(candidate_tokens[candidate_index], 3) = 'oes'
       and public.food_search_token_matches(
         p_query_token,
         left(candidate_tokens[candidate_index], length(candidate_tokens[candidate_index]) - 2)
       ) then return true; end if;
    if right(candidate_tokens[candidate_index], 1) = 'o'
       and public.food_search_token_matches(p_query_token, candidate_tokens[candidate_index] || 'es') then
      return true;
    end if;
    for span_length in 2..3 loop
      if candidate_index + span_length - 1 <= candidate_count then
        select string_agg(candidate_tokens[position], '' order by position)
          into candidate_form
          from generate_series(candidate_index, candidate_index + span_length - 1) position;
        if public.food_search_token_matches(p_query_token, candidate_form) then return true; end if;
      end if;
    end loop;
  end loop;
  return false;
end;
$$;

create or replace function public.food_search_every_query_token_matches(
  p_query text,
  p_candidate text
)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = public
as $$
declare
  query_tokens text[] := regexp_split_to_array(public.food_search_normalize(p_query), '\s+');
  query_count integer := coalesce(array_length(query_tokens, 1), 0);
  query_index integer := 1;
  joined_query_token text;
begin
  if query_count = 0 then return false; end if;
  while query_index <= query_count loop
    -- every_query_token_matches, including a punctuation-split word such as
    -- `ext;ra`; the joined form is tried before accepting a short fragment.
    if query_index < query_count then
      joined_query_token := query_tokens[query_index] || query_tokens[query_index + 1];
      if length(joined_query_token) between 4 and 18
         and public.food_search_query_token_matches_candidate(joined_query_token, p_candidate) then
        query_index := query_index + 2;
        continue;
      end if;
    end if;
    if not public.food_search_query_token_matches_candidate(query_tokens[query_index], p_candidate) then
      return false;
    end if;
    query_index := query_index + 1;
  end loop;
  return true;
end;
$$;

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
      public.food_search_normalize(p_query) as needle,
      least(greatest(coalesce(p_limit, 25), 1), 50) as result_limit
  ), candidates as (
    select
      f.id,
      case
        when input.needle in ('oil', 'ulei', 'ol', 'huile', 'olio', 'aceite')
          and coalesce(f.fat_100, 0) >= 90
          and coalesce(f.protein_100, 0) <= 1
          and coalesce(f.carbs_100, 0) <= 1
          and (haystack.value ~ '(extra virgin olive|olive extra virgin|evoo)')
          then -3
        when input.needle in ('oil', 'ulei', 'ol', 'huile', 'olio', 'aceite')
          and coalesce(f.fat_100, 0) >= 90
          and coalesce(f.protein_100, 0) <= 1
          and coalesce(f.carbs_100, 0) <= 1
          and (haystack.value ~ '(olive oil|oil olive|vegetable oil|oil vegetable)')
          then -2
        when input.needle in ('oil', 'ulei', 'ol', 'huile', 'olio', 'aceite')
          and coalesce(f.fat_100, 0) >= 90
          and coalesce(f.protein_100, 0) <= 1
          and coalesce(f.carbs_100, 0) <= 1
          and (' ' || haystack.value || ' ') ~ (' (oil|ulei|ol|huile|olio|aceite) ')
          then -1
        when input.needle in ('oil', 'ulei', 'ol', 'huile', 'olio', 'aceite')
          and haystack.value ~ '(margarine|margarin|margarina)'
          then 1
        else 0
      end as category_rank,
      case
        when public.food_search_normalize(f.name) = input.needle then 0
        when public.food_search_normalize(coalesce(fp.personal_name, '')) = input.needle then 0
        when public.food_search_normalize(f.name) like input.needle || '%' then 1
        when haystack.value like '%' || input.needle || '%' then 2
        else 3
      end as search_rank,
      greatest(
        similarity(haystack.value, input.needle),
        similarity(public.food_search_normalize(f.name), input.needle),
        similarity(public.food_search_normalize(concat_ws(' ', f.brand, f.name)), input.needle)
      ) as fuzzy_rank,
      input.result_limit
    from public.foods f
    cross join input
    left join public.food_preferences fp
      on fp.food_id = f.id
     and fp.user_id = auth.uid()
    cross join lateral (
      select public.food_search_normalize(concat_ws(
        ' ', f.name, f.brand, f.names_i18n::text,
        fp.personal_name, array_to_string(fp.aliases, ' ')
      )) as value
    ) haystack
    where auth.uid() is not null
      and (f.owner_user_id is null or f.owner_user_id = auth.uid())
      and coalesce(fp.hidden, false) = false
      and length(input.needle) >= 2
      and public.food_search_every_query_token_matches(input.needle, haystack.value)
  )
  select f.*
  from candidates
  join public.foods f on f.id = candidates.id
  order by candidates.category_rank, candidates.search_rank, candidates.fuzzy_rank desc, f.name, candidates.id
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
    select public.food_search_normalize(p_query) as value
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

revoke all on function public.food_corpus_search_catalog(text, integer) from public, anon;
grant execute on function public.food_corpus_search_catalog(text, integer) to authenticated, service_role;

with broccoli_references (
  id, name, names_i18n, provider_product_id,
  kcal_100, protein_100, carbs_100, fat_100, fibre_100, sugar_100,
  water_ml_100, water_source_id
) as (
  values
    (
      'b70c0000-0000-4000-8000-000000000001'::uuid,
      'Wild broccoli (Broccoli rabe / Rapini), raw',
      '{"en":"Wild broccoli (Broccoli rabe / Rapini), raw","de":"Stängelkohl (Cime di rapa / Rapini), roh","de-CH":"Stängelkohl (Cime di rapa / Rapini), roh","fr":"Brocoli-rave (rapini), cru","it":"Cime di rapa (rapini), crude","es":"Grelo (rapini / brócoli rabe), crudo","pt":"Grelos (rapini), crus","ro":"Broccoli rabe (rapini), crud","th":"บรอกโคลีราเบ (ราพินี) ดิบ","ja":"ブロッコリーラーブ（ラピーニ）、生"}'::jsonb,
      'apex-curated:usda-fdc-170381',
      22.0, 3.17, 2.85, 0.49, 2.7, null,
      92.55, 'usda-fdc-sr-170381:water'
    ),
    (
      'b70c0000-0000-4000-8000-000000000002'::uuid,
      'Broccolini (Thin-stem broccoli), raw',
      '{"en":"Broccolini (Thin-stem broccoli), raw","de":"Broccolini (Spargelbrokkoli), roh","de-CH":"Broccolini (Spargelbrokkoli), roh","fr":"Broccolini (brocoli à tiges fines), cru","it":"Broccolini (broccoli a gambo sottile), crudi","es":"Broccolini (brócoli de tallo fino), crudo","pt":"Broccolini (brócolos de talo fino), cru","ro":"Broccolini (broccoli cu tulpină subțire), crud","th":"บรอกโคลินี (บรอกโคลีต้นเรียว) ดิบ","ja":"ブロッコリーニ（細茎ブロッコリー）、生"}'::jsonb,
      'apex-curated:afcd-F001909',
      29.0, 3.2, 2.0, 0.4, 2.5, 1.3,
      92.2, 'afcd-r3:F001909:moisture'
    )
)
insert into public.foods (
  id, owner_user_id, name, names_i18n, brand, source, provider_product_id,
  nutrition_basis, preparation_state,
  kcal_100, protein_100, carbs_100, fat_100, fibre_100, sugar_100,
  water_ml_100, water_basis, water_source_id, confidence
)
select
  id, null, name, names_i18n, null, 'apex_cache', provider_product_id,
  'per_100g', 'as_sold',
  kcal_100, protein_100, carbs_100, fat_100, fibre_100, sugar_100,
  water_ml_100, 'reference', water_source_id, 'provider_verified'
from broccoli_references
on conflict (id) do update set
  name = excluded.name,
  names_i18n = excluded.names_i18n,
  provider_product_id = excluded.provider_product_id,
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
  confidence = excluded.confidence,
  updated_at = now();

notify pgrst, 'reload schema';
