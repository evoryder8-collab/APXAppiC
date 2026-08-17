-- Food-derived hydration snapshots for native and web parity.
-- Additive and safe to run repeatedly against production.

alter table public.foods
  add column if not exists water_ml_100 numeric;

alter table public.logged_food_entries
  add column if not exists snapshot_water_ml_100 numeric,
  add column if not exists water_ml numeric;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'foods_water_nonnegative'
  ) then
    alter table public.foods
      add constraint foods_water_nonnegative
      check (water_ml_100 is null or water_ml_100 between 0 and 100);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'logged_food_water_nonnegative'
  ) then
    alter table public.logged_food_entries
      add constraint logged_food_water_nonnegative
      check (
        (snapshot_water_ml_100 is null or snapshot_water_ml_100 between 0 and 100)
        and (water_ml is null or water_ml >= 0)
      );
  end if;
end $$;

-- Conservative starter values for foods whose names identify them clearly.
-- Existing curated values always win, and ambiguous foods remain unknown.
update public.foods set water_ml_100 = 95.0
where water_ml_100 is null
  and lower(name) ~ '(^|[^a-z])(cucumber|gurke|castravete|แตงกวา)([^a-z]|$)';

update public.foods set water_ml_100 = 94.5
where water_ml_100 is null
  and lower(name) ~ '(^|[^a-z])(tomato|tomate|tomatoe|roșie|rosie|มะเขือเทศ)([^a-z]|$)';

update public.foods set water_ml_100 = 91.5
where water_ml_100 is null
  and lower(name) ~ '(^|[^a-z])(watermelon|wassermelone|pepene verde|แตงโม)([^a-z]|$)';

update public.foods set water_ml_100 = 87.5
where water_ml_100 is null
  and lower(name) ~ '(^|[^a-z])(milk|milch|lapte|นม)([^a-z]|$)';

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
    v_factor := (v_entry->>'equivalent_amount')::numeric / 100;
    insert into public.logged_food_entries (
      id, meal_id, user_id, food_id, sort_order, snapshot_name, snapshot_brand,
      snapshot_preparation_state, snapshot_nutrition_basis, snapshot_kcal_100,
      snapshot_protein_100, snapshot_carbs_100, snapshot_fat_100, snapshot_fibre_100,
      snapshot_sugar_100, snapshot_saturated_fat_100, snapshot_salt_100,
      snapshot_water_ml_100, quantity, unit, equivalent_amount, kcal, protein_g,
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
