-- Structured food tracking and private Visual Progress
-- Additive, idempotent, and scoped to the existing APEX Supabase project.

do $$ begin
  create type apex_food_source as enum ('open_food_facts', 'private', 'apex_cache');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type apex_nutrition_basis as enum ('per_100g', 'per_100ml');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type apex_preparation_state as enum ('dry', 'cooked', 'prepared', 'drained', 'as_sold', 'unknown');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type apex_food_unit as enum ('g', 'ml', 'serving', 'piece');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type apex_meal_slot as enum ('breakfast', 'lunch', 'dinner', 'snack');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type apex_progress_pose as enum ('front', 'side', 'back');
exception when duplicate_object then null;
end $$;

create table if not exists foods (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users (id) on delete cascade,
  name text not null,
  names_i18n jsonb not null default '{}'::jsonb,
  brand text,
  barcode text,
  source apex_food_source not null,
  provider_product_id text,
  external_image_url text,
  package_quantity text,
  nutrition_basis apex_nutrition_basis not null default 'per_100g',
  preparation_state apex_preparation_state not null default 'unknown',
  kcal_100 numeric,
  protein_100 numeric,
  carbs_100 numeric,
  fat_100 numeric,
  fibre_100 numeric,
  sugar_100 numeric,
  saturated_fat_100 numeric,
  salt_100 numeric,
  serving_amount numeric,
  serving_unit apex_food_unit,
  serving_grams_or_ml numeric,
  piece_grams_or_ml numeric,
  provider_updated_at timestamptz,
  confidence text not null default 'partial',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint foods_owner_source check (
    (source = 'private' and owner_user_id is not null) or
    (source <> 'private')
  ),
  constraint foods_barcode_digits check (barcode is null or barcode ~ '^[0-9]{8,13}$'),
  constraint foods_nutrition_nonnegative check (
    coalesce(kcal_100, 0) >= 0 and coalesce(protein_100, 0) >= 0 and
    coalesce(carbs_100, 0) >= 0 and coalesce(fat_100, 0) >= 0 and
    coalesce(fibre_100, 0) >= 0 and coalesce(sugar_100, 0) >= 0 and
    coalesce(saturated_fat_100, 0) >= 0 and coalesce(salt_100, 0) >= 0
  )
);

create unique index if not exists idx_foods_shared_provider
  on foods (source, provider_product_id) where owner_user_id is null and provider_product_id is not null;
create unique index if not exists idx_foods_shared_barcode
  on foods (barcode) where owner_user_id is null and barcode is not null;
create index if not exists idx_foods_private_owner_name on foods (owner_user_id, lower(name));
create index if not exists idx_foods_brand_name on foods (lower(brand), lower(name));

create table if not exists food_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  food_id uuid not null references foods (id) on delete cascade,
  personal_name text,
  aliases text[] not null default '{}',
  favourite boolean not null default false,
  usual_amount numeric,
  usual_unit apex_food_unit,
  usage_count integer not null default 0,
  last_used_at timestamptz,
  hidden boolean not null default false,
  slot_usage jsonb not null default '{}'::jsonb,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, food_id)
);

create table if not exists meal_presets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  meal_slot apex_meal_slot not null,
  source_planned_meal_id uuid references meals (id) on delete set null,
  archived boolean not null default false,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists meal_preset_items (
  id uuid primary key default gen_random_uuid(),
  preset_id uuid not null references meal_presets (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  food_id uuid not null references foods (id) on delete restrict,
  sort_order integer not null default 0,
  quantity numeric not null,
  unit apex_food_unit not null,
  optional boolean not null default false,
  locked boolean not null default false,
  adjustable boolean not null default true,
  minimum_amount numeric,
  maximum_amount numeric,
  step_amount numeric,
  adjustment_role text not null default 'none',
  constraint meal_preset_quantity_positive check (quantity > 0),
  constraint meal_preset_bounds check (
    (minimum_amount is null or minimum_amount >= 0) and
    (maximum_amount is null or maximum_amount > 0) and
    (minimum_amount is null or maximum_amount is null or maximum_amount >= minimum_amount) and
    (step_amount is null or step_amount > 0)
  ),
  constraint meal_preset_role check (adjustment_role in ('carb', 'protein', 'energy', 'none'))
);

create table if not exists logged_meals (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  local_date date not null,
  meal_slot apex_meal_slot not null,
  display_name text not null,
  source_preset_id uuid references meal_presets (id) on delete set null,
  source_planned_meal_id uuid references meals (id) on delete set null,
  logged_at timestamptz not null,
  client_idempotency_key text not null,
  logged_as text not null default 'custom',
  total_kcal numeric not null default 0,
  total_protein_g numeric not null default 0,
  total_carbs_g numeric not null default 0,
  total_fat_g numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, client_idempotency_key),
  constraint logged_meal_kind check (logged_as in ('planned', 'changed', 'custom'))
);

create table if not exists logged_food_entries (
  id uuid primary key,
  meal_id uuid not null references logged_meals (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  food_id uuid references foods (id) on delete set null,
  sort_order integer not null default 0,
  snapshot_name text not null,
  snapshot_brand text,
  snapshot_preparation_state apex_preparation_state not null,
  snapshot_nutrition_basis apex_nutrition_basis not null,
  snapshot_kcal_100 numeric not null,
  snapshot_protein_100 numeric not null,
  snapshot_carbs_100 numeric not null,
  snapshot_fat_100 numeric not null,
  snapshot_fibre_100 numeric,
  snapshot_sugar_100 numeric,
  snapshot_saturated_fat_100 numeric,
  snapshot_salt_100 numeric,
  quantity numeric not null,
  unit apex_food_unit not null,
  equivalent_amount numeric not null,
  kcal numeric not null,
  protein_g numeric not null,
  carbs_g numeric not null,
  fat_g numeric not null,
  fibre_g numeric,
  sugar_g numeric,
  saturated_fat_g numeric,
  salt_g numeric,
  created_at timestamptz not null default now(),
  constraint logged_food_positive check (quantity > 0 and equivalent_amount > 0)
);

create index if not exists idx_food_preferences_user_rank
  on food_preferences (user_id, favourite desc, usage_count desc, last_used_at desc);
create index if not exists idx_presets_user_slot on meal_presets (user_id, meal_slot, archived, updated_at desc);
create index if not exists idx_preset_items_parent on meal_preset_items (preset_id, sort_order);
create index if not exists idx_logged_meals_user_date on logged_meals (user_id, local_date desc, meal_slot);
create index if not exists idx_logged_entries_meal on logged_food_entries (meal_id, sort_order);

alter table daily_logs add column if not exists nutrition_source text not null default 'manual';
alter table daily_logs add column if not exists manual_kcal integer;
alter table daily_logs add column if not exists manual_protein_g integer;
alter table daily_logs add column if not exists manual_fat_g integer;
alter table daily_logs add column if not exists manual_carbs_g integer;

update daily_logs
set manual_kcal = coalesce(manual_kcal, kcal),
    manual_protein_g = coalesce(manual_protein_g, protein_g),
    manual_fat_g = coalesce(manual_fat_g, fat_g),
    manual_carbs_g = coalesce(manual_carbs_g, carbs_g)
where nutrition_source = 'manual';

create table if not exists progress_photos (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  local_date date not null,
  captured_at timestamptz not null,
  pose apex_progress_pose not null,
  storage_path text not null,
  thumbnail_path text not null,
  width integer not null,
  height integer not null,
  aspect_ratio numeric not null,
  crop_x numeric not null default 0.5,
  crop_y numeric not null default 0.5,
  crop_scale numeric not null default 1,
  reference_photo_id uuid references progress_photos (id) on delete set null,
  weight_kg numeric,
  note text not null default '',
  client_idempotency_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, client_idempotency_key),
  unique (user_id, storage_path),
  constraint progress_dimensions check (width > 0 and height > 0 and aspect_ratio > 0),
  constraint progress_crop check (
    crop_x between 0 and 1 and crop_y between 0 and 1 and crop_scale between 1 and 3
  ),
  constraint progress_owner_path check (split_part(storage_path, '/', 1) = user_id::text)
);

create index if not exists idx_progress_photos_user_date_pose
  on progress_photos (user_id, local_date desc, pose);

alter table foods enable row level security;
alter table food_preferences enable row level security;
alter table meal_presets enable row level security;
alter table meal_preset_items enable row level security;
alter table logged_meals enable row level security;
alter table logged_food_entries enable row level security;
alter table progress_photos enable row level security;

drop policy if exists "visible_foods" on foods;
create policy "visible_foods" on foods for select to authenticated
  using (owner_user_id is null or owner_user_id = auth.uid());
drop policy if exists "create_private_food" on foods;
create policy "create_private_food" on foods for insert to authenticated
  with check (owner_user_id = auth.uid() and source = 'private');
drop policy if exists "update_private_food" on foods;
create policy "update_private_food" on foods for update to authenticated
  using (owner_user_id = auth.uid() and source = 'private')
  with check (owner_user_id = auth.uid() and source = 'private');
drop policy if exists "delete_private_food" on foods;
create policy "delete_private_food" on foods for delete to authenticated
  using (owner_user_id = auth.uid() and source = 'private');

do $$
declare t text;
begin
  foreach t in array array[
    'food_preferences', 'meal_presets', 'meal_preset_items', 'progress_photos'
  ] loop
    execute format('drop policy if exists "owner_all" on %I', t);
    execute format(
      'create policy "owner_all" on %I for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())',
      t
    );
  end loop;
end $$;

drop policy if exists "owner_all" on logged_meals;
drop policy if exists "owner_read" on logged_meals;
create policy "owner_read" on logged_meals for select to authenticated using (user_id = auth.uid());
drop policy if exists "owner_insert" on logged_meals;
create policy "owner_insert" on logged_meals for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "owner_delete" on logged_meals;
create policy "owner_delete" on logged_meals for delete to authenticated using (user_id = auth.uid());

drop policy if exists "owner_all" on logged_food_entries;
drop policy if exists "owner_read" on logged_food_entries;
create policy "owner_read" on logged_food_entries for select to authenticated using (user_id = auth.uid());
drop policy if exists "owner_insert" on logged_food_entries;
create policy "owner_insert" on logged_food_entries for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "owner_delete" on logged_food_entries;
create policy "owner_delete" on logged_food_entries for delete to authenticated using (user_id = auth.uid());

revoke all on table foods, food_preferences, meal_presets, meal_preset_items,
  logged_meals, logged_food_entries, progress_photos from anon;
grant select, insert, update, delete on table foods, food_preferences, meal_presets,
  meal_preset_items, logged_meals, logged_food_entries, progress_photos to authenticated;
revoke update on table logged_meals, logged_food_entries from authenticated;

create or replace function apex_recalculate_structured_day(p_user_id uuid, p_date date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_kcal integer;
  v_protein integer;
  v_fat integer;
  v_carbs integer;
begin
  select count(*),
         round(coalesce(sum(total_kcal), 0))::integer,
         round(coalesce(sum(total_protein_g), 0))::integer,
         round(coalesce(sum(total_fat_g), 0))::integer,
         round(coalesce(sum(total_carbs_g), 0))::integer
  into v_count, v_kcal, v_protein, v_fat, v_carbs
  from logged_meals where user_id = p_user_id and local_date = p_date;

  if v_count > 0 then
    insert into daily_logs (
      id, user_id, date, kcal, protein_g, fat_g, carbs_g, water_l,
      nutrition_source, manual_kcal, manual_protein_g, manual_fat_g, manual_carbs_g
    ) values (
      gen_random_uuid(), p_user_id, p_date, v_kcal, v_protein, v_fat, v_carbs, 0,
      'structured', null, null, null, null
    )
    on conflict (user_id, date) do update set
      manual_kcal = case when daily_logs.nutrition_source = 'manual' then daily_logs.kcal else daily_logs.manual_kcal end,
      manual_protein_g = case when daily_logs.nutrition_source = 'manual' then daily_logs.protein_g else daily_logs.manual_protein_g end,
      manual_fat_g = case when daily_logs.nutrition_source = 'manual' then daily_logs.fat_g else daily_logs.manual_fat_g end,
      manual_carbs_g = case when daily_logs.nutrition_source = 'manual' then daily_logs.carbs_g else daily_logs.manual_carbs_g end,
      kcal = excluded.kcal,
      protein_g = excluded.protein_g,
      fat_g = excluded.fat_g,
      carbs_g = excluded.carbs_g,
      nutrition_source = 'structured';
  else
    update daily_logs set
      kcal = manual_kcal,
      protein_g = manual_protein_g,
      fat_g = manual_fat_g,
      carbs_g = manual_carbs_g,
      nutrition_source = 'manual'
    where user_id = p_user_id and date = p_date and nutrition_source = 'structured';
  end if;
end;
$$;

revoke all on function apex_recalculate_structured_day(uuid, date) from public, anon, authenticated;

create or replace function log_structured_meal(p_meal jsonb, p_entries jsonb)
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

  select id into v_existing from logged_meals
    where user_id = v_user and client_idempotency_key = p_meal->>'client_idempotency_key';
  if v_existing is not null then return v_existing; end if;

  v_replace := nullif(p_meal->>'replace_meal_id', '')::uuid;
  if v_replace is not null then
    if not exists (select 1 from logged_meals where id = v_replace and user_id = v_user) then
      raise exception 'Meal replacement is not owned by the current user';
    end if;
    delete from logged_meals where id = v_replace and user_id = v_user;
  end if;

  v_meal_id := coalesce(nullif(p_meal->>'id', '')::uuid, gen_random_uuid());
  v_date := (p_meal->>'local_date')::date;
  insert into logged_meals (
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
    insert into logged_food_entries (
      id, meal_id, user_id, food_id, sort_order, snapshot_name, snapshot_brand,
      snapshot_preparation_state, snapshot_nutrition_basis, snapshot_kcal_100,
      snapshot_protein_100, snapshot_carbs_100, snapshot_fat_100, snapshot_fibre_100,
      snapshot_sugar_100, snapshot_saturated_fat_100, snapshot_salt_100,
      quantity, unit, equivalent_amount, kcal, protein_g, carbs_g, fat_g,
      fibre_g, sugar_g, saturated_fat_g, salt_g
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
      (v_entry->>'quantity')::numeric, (v_entry->>'unit')::apex_food_unit,
      (v_entry->>'equivalent_amount')::numeric,
      round((v_entry->>'snapshot_kcal_100')::numeric * v_factor),
      round((v_entry->>'snapshot_protein_100')::numeric * v_factor, 2),
      round((v_entry->>'snapshot_carbs_100')::numeric * v_factor, 2),
      round((v_entry->>'snapshot_fat_100')::numeric * v_factor, 2),
      case when nullif(v_entry->>'snapshot_fibre_100', '') is null then null else round((v_entry->>'snapshot_fibre_100')::numeric * v_factor, 2) end,
      case when nullif(v_entry->>'snapshot_sugar_100', '') is null then null else round((v_entry->>'snapshot_sugar_100')::numeric * v_factor, 2) end,
      case when nullif(v_entry->>'snapshot_saturated_fat_100', '') is null then null else round((v_entry->>'snapshot_saturated_fat_100')::numeric * v_factor, 2) end,
      case when nullif(v_entry->>'snapshot_salt_100', '') is null then null else round((v_entry->>'snapshot_salt_100')::numeric * v_factor, 2) end
    );
    v_kcal := v_kcal + round((v_entry->>'snapshot_kcal_100')::numeric * v_factor);
    v_protein := v_protein + round((v_entry->>'snapshot_protein_100')::numeric * v_factor, 2);
    v_carbs := v_carbs + round((v_entry->>'snapshot_carbs_100')::numeric * v_factor, 2);
    v_fat := v_fat + round((v_entry->>'snapshot_fat_100')::numeric * v_factor, 2);
  end loop;

  update logged_meals set total_kcal = v_kcal, total_protein_g = v_protein,
    total_carbs_g = v_carbs, total_fat_g = v_fat, updated_at = now()
  where id = v_meal_id;
  perform apex_recalculate_structured_day(v_user, v_date);
  return v_meal_id;
end;
$$;

create or replace function delete_structured_meal(p_meal_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_date date;
begin
  select local_date into v_date from logged_meals where id = p_meal_id and user_id = v_user;
  if v_date is null then return false; end if;
  delete from logged_meals where id = p_meal_id and user_id = v_user;
  perform apex_recalculate_structured_day(v_user, v_date);
  return true;
end;
$$;

revoke all on function log_structured_meal(jsonb, jsonb) from public, anon;
grant execute on function log_structured_meal(jsonb, jsonb) to authenticated;
revoke all on function delete_structured_meal(uuid) from public, anon;
grant execute on function delete_structured_meal(uuid) to authenticated;

create or replace function save_meal_preset(p_preset jsonb, p_items jsonb, p_expected_version integer default 0)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid := coalesce(nullif(p_preset->>'id', '')::uuid, gen_random_uuid());
  v_current_version integer;
  v_item jsonb;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
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
$$;

create or replace function delete_meal_preset(p_preset_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  with deleted as (
    delete from meal_presets where id = p_preset_id and user_id = auth.uid() returning id
  ) select exists(select 1 from deleted);
$$;

revoke all on function save_meal_preset(jsonb, jsonb, integer) from public, anon;
grant execute on function save_meal_preset(jsonb, jsonb, integer) to authenticated;
revoke all on function delete_meal_preset(uuid) from public, anon;
grant execute on function delete_meal_preset(uuid) to authenticated;

insert into foods (
  id, owner_user_id, name, names_i18n, source, provider_product_id,
  nutrition_basis, preparation_state, kcal_100, protein_100, carbs_100, fat_100, confidence
) values
  ('10000000-0000-4000-8000-000000000001', null, 'Rolled oats', '{"en":"Rolled oats","de":"Haferflocken","fr":"Flocons d’avoine","it":"Fiocchi d’avena"}', 'apex_cache', 'apex-common:oats', 'per_100g', 'as_sold', 372, 13.5, 58.7, 7, 'complete'),
  ('10000000-0000-4000-8000-000000000002', null, 'White rice, dry', '{"en":"White rice, dry","de":"Weisser Reis, trocken","fr":"Riz blanc, sec","it":"Riso bianco, secco"}', 'apex_cache', 'apex-common:rice-dry', 'per_100g', 'dry', 360, 7, 79, 0.7, 'complete'),
  ('10000000-0000-4000-8000-000000000003', null, 'White rice, cooked', '{"en":"White rice, cooked","de":"Weisser Reis, gekocht","fr":"Riz blanc, cuit","it":"Riso bianco, cotto"}', 'apex_cache', 'apex-common:rice-cooked', 'per_100g', 'cooked', 130, 2.7, 28, 0.3, 'complete'),
  ('10000000-0000-4000-8000-000000000004', null, 'Bulgur, dry', '{"en":"Bulgur, dry","de":"Bulgur, trocken","fr":"Boulgour, sec","it":"Bulgur, secco"}', 'apex_cache', 'apex-common:bulgur-dry', 'per_100g', 'dry', 342, 12.3, 63.4, 1.3, 'complete'),
  ('10000000-0000-4000-8000-000000000005', null, 'Bulgur, cooked', '{"en":"Bulgur, cooked","de":"Bulgur, gekocht","fr":"Boulgour, cuit","it":"Bulgur, cotto"}', 'apex_cache', 'apex-common:bulgur-cooked', 'per_100g', 'cooked', 83, 3.1, 18.6, 0.2, 'complete'),
  ('10000000-0000-4000-8000-000000000006', null, 'Greek yoghurt, plain', '{"en":"Greek yoghurt, plain","de":"Griechischer Joghurt, nature","fr":"Yaourt grec, nature","it":"Yogurt greco, naturale"}', 'apex_cache', 'apex-common:yoghurt', 'per_100g', 'as_sold', 97, 9, 3.9, 5, 'complete'),
  ('10000000-0000-4000-8000-000000000007', null, 'Whole egg', '{"en":"Whole egg","de":"Vollei","fr":"Œuf entier","it":"Uovo intero"}', 'apex_cache', 'apex-common:egg', 'per_100g', 'as_sold', 143, 12.6, 0.7, 9.5, 'complete'),
  ('10000000-0000-4000-8000-000000000008', null, 'Chicken breast, cooked', '{"en":"Chicken breast, cooked","de":"Pouletbrust, gegart","fr":"Blanc de poulet, cuit","it":"Petto di pollo, cotto"}', 'apex_cache', 'apex-common:chicken', 'per_100g', 'cooked', 165, 31, 0, 3.6, 'complete'),
  ('10000000-0000-4000-8000-000000000009', null, 'Sweet potato, cooked', '{"en":"Sweet potato, cooked","de":"Süsskartoffel, gegart","fr":"Patate douce, cuite","it":"Patata dolce, cotta"}', 'apex_cache', 'apex-common:sweet-potato', 'per_100g', 'cooked', 90, 2, 20.7, 0.2, 'complete'),
  ('10000000-0000-4000-8000-000000000010', null, 'Broccoli, cooked', '{"en":"Broccoli, cooked","de":"Brokkoli, gegart","fr":"Brocoli, cuit","it":"Broccoli, cotti"}', 'apex_cache', 'apex-common:broccoli', 'per_100g', 'cooked', 35, 2.4, 7.2, 0.4, 'complete'),
  ('10000000-0000-4000-8000-000000000011', null, 'Cottage cheese', '{"en":"Cottage cheese","de":"Hüttenkäse","fr":"Cottage cheese","it":"Fiocchi di latte"}', 'apex_cache', 'apex-common:cottage-cheese', 'per_100g', 'as_sold', 98, 11.1, 3.4, 4.3, 'complete'),
  ('10000000-0000-4000-8000-000000000012', null, 'Walnuts', '{"en":"Walnuts","de":"Walnüsse","fr":"Noix","it":"Noci"}', 'apex_cache', 'apex-common:walnuts', 'per_100g', 'as_sold', 654, 15.2, 13.7, 65.2, 'complete')
on conflict (id) do nothing;

update foods set piece_grams_or_ml = 58 where id = '10000000-0000-4000-8000-000000000007';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('apex-progress', 'apex-progress', false, 8388608, array['image/webp', 'image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = 8388608,
  allowed_mime_types = array['image/webp', 'image/jpeg'];

drop policy if exists "progress_owner_select" on storage.objects;
create policy "progress_owner_select" on storage.objects for select to authenticated
  using (bucket_id = 'apex-progress' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "progress_owner_insert" on storage.objects;
create policy "progress_owner_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'apex-progress' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "progress_owner_update" on storage.objects;
create policy "progress_owner_update" on storage.objects for update to authenticated
  using (bucket_id = 'apex-progress' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'apex-progress' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "progress_owner_delete" on storage.objects;
create policy "progress_owner_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'apex-progress' and (storage.foldername(name))[1] = auth.uid()::text);

do $$
declare t text;
begin
  foreach t in array array[
    'food_preferences', 'meal_presets', 'meal_preset_items',
    'logged_meals', 'logged_food_entries', 'progress_photos'
  ] loop
    begin
      execute format('alter publication supabase_realtime add table %I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

notify pgrst, 'reload schema';
