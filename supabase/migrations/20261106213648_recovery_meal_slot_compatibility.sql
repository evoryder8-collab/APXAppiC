-- Accept recovery meals from already-installed native builds without changing
-- canonical meal slots, ownership checks, nutrient snapshots or retry identity.
-- Existing function privileges are retained by CREATE OR REPLACE.

CREATE OR REPLACE FUNCTION public.log_structured_meal(p_meal jsonb, p_entries jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- Older native clients sent the Dayline block kind as the storage enum.
  -- Keep the four canonical slots and retain the recovery block in the key.
  if p_meal->>'meal_slot' = 'post_workout' then
    p_meal := jsonb_set(p_meal, '{meal_slot}', '"snack"'::jsonb);
    if position('apex-meal-block=' in p_meal->>'client_idempotency_key') = 0 then
      p_meal := jsonb_set(p_meal, '{client_idempotency_key}',
        to_jsonb((p_meal->>'client_idempotency_key') || '|apex-meal-block=post_workout'));
    end if;
  end if;

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
$function$
;

CREATE OR REPLACE FUNCTION public.save_meal_preset(p_preset jsonb, p_items jsonb, p_expected_version integer DEFAULT 0)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid := auth.uid();
  v_id uuid := coalesce(nullif(p_preset->>'id', '')::uuid, gen_random_uuid());
  v_current_version integer;
  v_item jsonb;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_preset->>'meal_slot' = 'post_workout' then
    p_preset := jsonb_set(p_preset, '{meal_slot}', '"snack"'::jsonb);
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'A preset needs at least one food';
  end if;
  select version into v_current_version from meal_presets where id = v_id and user_id = v_user for update;
  if v_current_version is not null and v_current_version <> p_expected_version then
    raise exception 'Preset changed on another device';
  end if;
  if v_current_version is null then
    insert into meal_presets (id, user_id, name, meal_slot, source_planned_meal_id, archived, version)
    values (v_id, v_user, left(p_preset->>'name', 120), (p_preset->>'meal_slot')::apex_meal_slot,
      nullif(p_preset->>'source_planned_meal_id', '')::uuid,
      coalesce((p_preset->>'archived')::boolean, false), 1);
  else
    update meal_presets set name = left(p_preset->>'name', 120),
      meal_slot = (p_preset->>'meal_slot')::apex_meal_slot,
      source_planned_meal_id = nullif(p_preset->>'source_planned_meal_id', '')::uuid,
      archived = coalesce((p_preset->>'archived')::boolean, false),
      version = version + 1, updated_at = now()
    where id = v_id and user_id = v_user;
    delete from meal_preset_items where preset_id = v_id and user_id = v_user;
  end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    insert into meal_preset_items (
      id, preset_id, user_id, food_id, sort_order, quantity, unit, optional,
      locked, adjustable, minimum_amount, maximum_amount, step_amount, adjustment_role
    ) values (
      coalesce(nullif(v_item->>'id', '')::uuid, gen_random_uuid()), v_id, v_user,
      (v_item->>'food_id')::uuid, coalesce((v_item->>'sort_order')::integer, 0),
      (v_item->>'quantity')::numeric, (v_item->>'unit')::apex_food_unit,
      coalesce((v_item->>'optional')::boolean, false),
      coalesce((v_item->>'locked')::boolean, false),
      coalesce((v_item->>'adjustable')::boolean, true),
      nullif(v_item->>'minimum_amount', '')::numeric,
      nullif(v_item->>'maximum_amount', '')::numeric,
      nullif(v_item->>'step_amount', '')::numeric,
      coalesce(nullif(v_item->>'adjustment_role', ''), 'none')
    );
  end loop;
  return v_id;
end;
$function$
;
