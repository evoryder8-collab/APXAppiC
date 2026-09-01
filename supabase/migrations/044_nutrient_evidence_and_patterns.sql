-- Bounded, provenance-preserving nutrient evidence for optional client detail
-- and immutable observed-intake patterns. Raw publisher archives remain private.

create or replace function public.apex_valid_nutrient_evidence(p_value jsonb)
returns boolean
language sql
immutable
parallel safe
set search_path = public
as $$
  select case
    -- CASE intentionally guards jsonb_array_elements: malformed objects must be
    -- rejected, never evaluated as an array and allowed to abort a write.
    when jsonb_typeof(p_value) = 'array' then
      jsonb_array_length(p_value) <= 96
      and octet_length(p_value::text) <= 65536
      and not exists (
        select 1
        from jsonb_array_elements(p_value) observation
        where jsonb_typeof(observation) <> 'object'
          or exists (
            select 1
            from jsonb_object_keys(
              case when jsonb_typeof(observation) = 'object' then observation else '{}'::jsonb end
            ) field(key)
            where field.key not in (
              'nutrient_code', 'name', 'value_per_100', 'unit',
              'observation_status', 'original_value_text', 'derivation_method',
              'source_key', 'source_reference'
            )
          )
          or jsonb_typeof(observation->'nutrient_code') <> 'string'
          or length(coalesce(observation->>'nutrient_code', '')) not between 1 and 80
          or jsonb_typeof(observation->'name') <> 'string'
          or length(coalesce(observation->>'name', '')) not between 1 and 180
          or jsonb_typeof(observation->'unit') <> 'string'
          or length(coalesce(observation->>'unit', '')) not between 1 and 24
          or jsonb_typeof(observation->'observation_status') <> 'string'
          or coalesce(observation->>'observation_status', '') not in (
            'measured', 'calculated', 'estimated', 'reported', 'trace',
            'below_detection', 'not_measured', 'missing'
          )
          or (
            observation ? 'value_per_100'
            and jsonb_typeof(observation->'value_per_100') not in ('number', 'null')
          )
          or case
            when jsonb_typeof(observation->'value_per_100') = 'number'
              then (observation->>'value_per_100')::numeric not between 0 and 1000000000000
            else false
          end
          or (
            observation ? 'original_value_text'
            and (
              jsonb_typeof(observation->'original_value_text') not in ('string', 'null')
              or length(coalesce(observation->>'original_value_text', '')) not between 0 and 180
            )
          )
          or (
            observation ? 'derivation_method'
            and (
              jsonb_typeof(observation->'derivation_method') not in ('string', 'null')
              or length(coalesce(observation->>'derivation_method', '')) not between 0 and 180
            )
          )
          or (
            observation ? 'source_key'
            and (
              jsonb_typeof(observation->'source_key') not in ('string', 'null')
              or length(coalesce(observation->>'source_key', '')) not between 0 and 120
            )
          )
          or (
            observation ? 'source_reference'
            and (
              jsonb_typeof(observation->'source_reference') not in ('string', 'null')
              or length(coalesce(observation->>'source_reference', '')) not between 0 and 240
            )
          )
          or (
            coalesce(observation->>'observation_status', '') in (
              'trace', 'below_detection', 'not_measured', 'missing'
            )
            and jsonb_typeof(observation->'value_per_100') = 'number'
          )
      )
    else false
  end;
$$;

revoke all on function public.apex_valid_nutrient_evidence(jsonb) from public, anon, authenticated;

alter table public.foods
  add column if not exists nutrient_evidence jsonb not null default '[]'::jsonb;
alter table public.foods
  drop constraint if exists foods_nutrient_evidence_valid;
alter table public.foods
  add constraint foods_nutrient_evidence_valid
  check (public.apex_valid_nutrient_evidence(nutrient_evidence));

alter table public.logged_food_entries
  add column if not exists snapshot_nutrient_evidence jsonb not null default '[]'::jsonb;
alter table public.logged_food_entries
  drop constraint if exists logged_food_entries_nutrient_evidence_valid;
alter table public.logged_food_entries
  add constraint logged_food_entries_nutrient_evidence_valid
  check (public.apex_valid_nutrient_evidence(snapshot_nutrient_evidence));

create or replace function public.apex_corpus_nutrient_evidence(p_record_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(observation.payload order by observation.sort_order), '[]'::jsonb)
  from (
    select
      nutrient.id as sort_order,
      jsonb_strip_nulls(jsonb_build_object(
        'nutrient_code', nutrient.nutrient_code,
        'name', nutrient.original_nutrient_name,
        'value_per_100', case
          when nutrient.observation_status in ('measured', 'calculated', 'estimated')
            and record.basis_kind in ('per_100g', 'per_100ml')
            and record.basis_amount > 0
            then round(nutrient.value * 100 / record.basis_amount, 8)
          when nutrient.observation_status in ('measured', 'calculated', 'estimated')
            and record.basis_kind = 'per_serving'
            and coalesce(record.source_metadata->>'published_serving', '') ~ '\([0-9]+([.,][0-9]+)?[[:space:]]*g\)'
            then round(
              nutrient.value * 100 / replace(
                substring(record.source_metadata->>'published_serving' from '\(([0-9]+([.,][0-9]+)?)[[:space:]]*g\)'),
                ',', '.'
              )::numeric,
              8
            )
          else null
        end,
        'unit', nutrient.unit,
        'observation_status', nutrient.observation_status,
        'original_value_text', nutrient.original_value_text,
        'derivation_method', nutrient.derivation_method,
        'source_key', record.source_key,
        'source_reference', nutrient.source_reference
      )) as payload
    from public.food_corpus_records record
    join public.food_corpus_sources source using (source_key)
    join public.food_corpus_batches batch on record.batch_id = batch.id
    join public.food_corpus_nutrients nutrient on nutrient.record_id = record.id
    where record.id = p_record_id
      and source.ingest_status = 'active'
      and batch.status = 'active'
    order by nutrient.id
    limit 96
  ) observation;
$$;

revoke all on function public.apex_corpus_nutrient_evidence(uuid) from public, anon, authenticated;

update public.foods food
set nutrient_evidence = public.apex_corpus_nutrient_evidence(record.id),
    updated_at = now()
from public.food_corpus_records record
join public.food_corpus_sources source using (source_key)
join public.food_corpus_batches batch on record.batch_id = batch.id
where food.id = record.id
  and source.ingest_status = 'active'
  and batch.status = 'active'
  and food.nutrient_evidence = '[]'::jsonb;

-- Keep the intent-aware matcher from migration 043, but use the existing
-- trigram GIN index to produce a bounded candidate set before invoking its
-- deliberately more expensive token-by-token typo checks.
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
    and (
      search.search_text like '%' || query.value || '%'
      or search.search_text %> query.value
      or search.search_text like '%' || split_part(query.value, ' ', 1) || '%'
      or search.search_text %> split_part(query.value, ' ', 1)
    )
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

create or replace function public.food_corpus_search_catalog_v3(
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
  basis_amount numeric,
  basis_unit text,
  source_metadata jsonb,
  preparation_state text,
  kcal numeric,
  protein_g numeric,
  carbs_g numeric,
  fat_g numeric,
  fibre_g numeric,
  sugar_g numeric,
  saturated_fat_g numeric,
  salt_g numeric,
  water_g numeric,
  nutrient_evidence jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    result.record_id,
    result.source_key,
    result.source_record_id,
    result.name,
    result.names_i18n,
    result.aliases,
    result.brand,
    result.barcode,
    result.market,
    result.basis_kind,
    result.basis_amount,
    result.basis_unit,
    result.source_metadata,
    result.preparation_state,
    result.kcal,
    result.protein_g,
    result.carbs_g,
    result.fat_g,
    result.fibre_g,
    result.sugar_g,
    result.saturated_fat_g,
    result.salt_g,
    result.water_g,
    public.apex_corpus_nutrient_evidence(result.record_id)
  from public.food_corpus_search_catalog_v2(p_query, p_limit) with ordinality as result (
    record_id, source_key, source_record_id, name, names_i18n, aliases, brand,
    barcode, market, basis_kind, basis_amount, basis_unit, source_metadata,
    preparation_state, kcal, protein_g, carbs_g, fat_g, fibre_g, sugar_g,
    saturated_fat_g, salt_g, water_g, result_order
  )
  order by result.result_order;
$$;

revoke all on function public.food_corpus_search_catalog_v3(text, integer) from public, anon;
grant execute on function public.food_corpus_search_catalog_v3(text, integer) to authenticated, service_role;

create or replace function public.log_structured_meal(p_meal jsonb, p_entries jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_meal_id uuid;
  v_existing uuid;
  v_replace uuid;
  v_date date;
  v_entry jsonb;
  v_factor numeric;
  v_evidence jsonb;
  v_kcal numeric := 0;
  v_protein numeric := 0;
  v_carbs numeric := 0;
  v_fat numeric := 0;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries) = 0 then
    raise exception 'A logged meal needs at least one food';
  end if;
  if coalesce(p_meal->>'client_idempotency_key', '') = '' then raise exception 'Missing idempotency key'; end if;

  select id into v_existing from public.logged_meals
    where user_id = v_user and client_idempotency_key = p_meal->>'client_idempotency_key';
  if v_existing is not null then return v_existing; end if;

  v_replace := nullif(p_meal->>'replace_meal_id', '')::uuid;
  if v_replace is not null then
    if not exists (select 1 from public.logged_meals where id = v_replace and user_id = v_user) then
      raise exception 'Meal replacement is not owned by the current user';
    end if;
    delete from public.logged_meals where id = v_replace and user_id = v_user;
  end if;

  v_meal_id := coalesce(nullif(p_meal->>'id', '')::uuid, gen_random_uuid());
  v_date := (p_meal->>'local_date')::date;
  insert into public.logged_meals (
    id, user_id, local_date, meal_slot, display_name, source_preset_id,
    source_planned_meal_id, logged_at, client_idempotency_key, logged_as
  ) values (
    v_meal_id, v_user, v_date, (p_meal->>'meal_slot')::apex_meal_slot,
    left(coalesce(nullif(p_meal->>'display_name', ''), 'Meal'), 120),
    nullif(p_meal->>'source_preset_id', '')::uuid,
    nullif(p_meal->>'source_planned_meal_id', '')::uuid,
    coalesce(nullif(p_meal->>'logged_at', '')::timestamptz, now()),
    p_meal->>'client_idempotency_key',
    coalesce(nullif(p_meal->>'logged_as', ''), 'custom')
  );

  for v_entry in select value from jsonb_array_elements(p_entries) loop
    if (v_entry->>'snapshot_kcal_100') is null or (v_entry->>'equivalent_amount')::numeric <= 0 then
      raise exception 'Incomplete food snapshot';
    end if;
    v_evidence := coalesce(v_entry->'snapshot_nutrient_evidence', '[]'::jsonb);
    if not public.apex_valid_nutrient_evidence(v_evidence) then
      raise exception 'Invalid nutrient evidence snapshot';
    end if;
    v_factor := (v_entry->>'equivalent_amount')::numeric / 100;
    insert into public.logged_food_entries (
      id, meal_id, user_id, food_id, sort_order, snapshot_name, snapshot_brand,
      snapshot_preparation_state, snapshot_nutrition_basis, snapshot_kcal_100,
      snapshot_protein_100, snapshot_carbs_100, snapshot_fat_100, snapshot_fibre_100,
      snapshot_sugar_100, snapshot_saturated_fat_100, snapshot_salt_100,
      snapshot_water_ml_100, snapshot_water_basis, snapshot_water_source_id,
      snapshot_nutrient_evidence, quantity, unit, equivalent_amount, kcal, protein_g,
      carbs_g, fat_g, fibre_g, sugar_g, saturated_fat_g, salt_g, water_ml
    ) values (
      coalesce(nullif(v_entry->>'id', '')::uuid, gen_random_uuid()), v_meal_id, v_user,
      nullif(v_entry->>'food_id', '')::uuid, coalesce((v_entry->>'sort_order')::integer, 0),
      left(v_entry->>'snapshot_name', 180), nullif(v_entry->>'snapshot_brand', ''),
      (v_entry->>'snapshot_preparation_state')::apex_preparation_state,
      (v_entry->>'snapshot_nutrition_basis')::apex_nutrition_basis,
      (v_entry->>'snapshot_kcal_100')::numeric, (v_entry->>'snapshot_protein_100')::numeric,
      (v_entry->>'snapshot_carbs_100')::numeric, (v_entry->>'snapshot_fat_100')::numeric,
      nullif(v_entry->>'snapshot_fibre_100', '')::numeric,
      nullif(v_entry->>'snapshot_sugar_100', '')::numeric,
      nullif(v_entry->>'snapshot_saturated_fat_100', '')::numeric,
      nullif(v_entry->>'snapshot_salt_100', '')::numeric,
      nullif(v_entry->>'snapshot_water_ml_100', '')::numeric,
      coalesce(nullif(v_entry->>'snapshot_water_basis', ''), 'unknown'),
      nullif(v_entry->>'snapshot_water_source_id', ''),
      v_evidence,
      (v_entry->>'quantity')::numeric, (v_entry->>'unit')::apex_food_unit,
      (v_entry->>'equivalent_amount')::numeric,
      round((v_entry->>'snapshot_kcal_100')::numeric * v_factor),
      round((v_entry->>'snapshot_protein_100')::numeric * v_factor, 2),
      round((v_entry->>'snapshot_carbs_100')::numeric * v_factor, 2),
      round((v_entry->>'snapshot_fat_100')::numeric * v_factor, 2),
      case when nullif(v_entry->>'snapshot_fibre_100', '') is null then null else round((v_entry->>'snapshot_fibre_100')::numeric * v_factor, 2) end,
      case when nullif(v_entry->>'snapshot_sugar_100', '') is null then null else round((v_entry->>'snapshot_sugar_100')::numeric * v_factor, 2) end,
      case when nullif(v_entry->>'snapshot_saturated_fat_100', '') is null then null else round((v_entry->>'snapshot_saturated_fat_100')::numeric * v_factor, 2) end,
      case when nullif(v_entry->>'snapshot_salt_100', '') is null then null else round((v_entry->>'snapshot_salt_100')::numeric * v_factor, 2) end,
      case when nullif(v_entry->>'snapshot_water_ml_100', '') is null then null else round((v_entry->>'snapshot_water_ml_100')::numeric * v_factor, 2) end
    );
    v_kcal := v_kcal + round((v_entry->>'snapshot_kcal_100')::numeric * v_factor);
    v_protein := v_protein + round((v_entry->>'snapshot_protein_100')::numeric * v_factor, 2);
    v_carbs := v_carbs + round((v_entry->>'snapshot_carbs_100')::numeric * v_factor, 2);
    v_fat := v_fat + round((v_entry->>'snapshot_fat_100')::numeric * v_factor, 2);
  end loop;

  update public.logged_meals set total_kcal = v_kcal, total_protein_g = v_protein,
    total_carbs_g = v_carbs, total_fat_g = v_fat, updated_at = now()
  where id = v_meal_id;
  perform public.apex_recalculate_structured_day(v_user, v_date);
  return v_meal_id;
end;
$$;

revoke all on function public.log_structured_meal(jsonb, jsonb) from public, anon;
grant execute on function public.log_structured_meal(jsonb, jsonb) to authenticated;

comment on column public.foods.nutrient_evidence is
  'Bounded source evidence used by optional detail; trace/not-measured/missing values remain null, never zero.';
comment on column public.logged_food_entries.snapshot_nutrient_evidence is
  'Immutable nutrient evidence captured when the food was logged so later corpus changes cannot rewrite intake history.';

notify pgrst, 'reload schema';
