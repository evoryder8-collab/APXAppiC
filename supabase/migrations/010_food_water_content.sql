-- Water content for every curated food, and the hydration columns 009 defined.
--
-- 009 was never applied to production: `foods.water_ml_100` does not exist
-- there, so the food-derived hydration path has been dead on both clients.
-- This migration is self-contained and idempotent, so it repairs a database
-- that skipped 009 and is a no-op on one that ran it.
--
-- Values are grams of water per 100 g of food. Each is either a measured
-- value from the reference the row itself was sourced from, or derived by
-- difference (100 - protein - fat - carbohydrate - ash) when no reference
-- record matches the stored macros. Sources:
--   * Swiss Food Composition Database V7.1 (FSVO/BLV, 01.07.2026),
--     naehrwertdaten.ch - used with attribution, commercial use permitted.
--   * USDA FoodData Central, for rows whose provider_product_id already
--     cites an FDC identifier.
-- Deriving by difference is the standard composition-table method; it is used
-- here only where no measured record shares the row's macro profile.

alter table public.foods
  add column if not exists water_ml_100 numeric;

alter table public.logged_food_entries
  add column if not exists snapshot_water_ml_100 numeric,
  add column if not exists water_ml numeric;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'foods_water_nonnegative') then
    alter table public.foods
      add constraint foods_water_nonnegative
      check (water_ml_100 is null or water_ml_100 between 0 and 100);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'logged_food_water_nonnegative') then
    alter table public.logged_food_entries
      add constraint logged_food_water_nonnegative
      check (
        (snapshot_water_ml_100 is null or snapshot_water_ml_100 between 0 and 100)
        and (water_ml is null or water_ml >= 0)
      );
  end if;
end $$;

-- Curated catalogue. Explicit ids, so a renamed food is never mismatched.
update public.foods as f set water_ml_100 = v.water, updated_at = now()
from (values
  ('10000000-0000-4000-8000-000000000001'::uuid,  8.7),  -- Swiss FSVO, Oat flakes
  ('10000000-0000-4000-8000-000000000002'::uuid, 12.3),  -- Swiss FSVO, Rice polished, raw
  ('10000000-0000-4000-8000-000000000003'::uuid, 68.5),  -- derived; USDA parboiled cooked 70.4
  ('10000000-0000-4000-8000-000000000004'::uuid,  9.0),  -- derived; matches USDA bulgur, dry
  ('10000000-0000-4000-8000-000000000005'::uuid, 77.8),  -- USDA FDC 170287, bulgur cooked
  ('10000000-0000-4000-8000-000000000006'::uuid, 81.4),  -- derived, whole-milk Greek yoghurt
  ('10000000-0000-4000-8000-000000000007'::uuid, 76.0),  -- Swiss FSVO, Egg, raw
  ('10000000-0000-4000-8000-000000000008'::uuid, 65.3),  -- USDA FDC 171477, breast roasted
  ('10000000-0000-4000-8000-000000000009'::uuid, 73.2),  -- Swiss FSVO, Sweet potato, baked
  ('10000000-0000-4000-8000-000000000010'::uuid, 90.4),  -- Swiss FSVO, Broccoli, steamed
  ('10000000-0000-4000-8000-000000000011'::uuid, 78.6),  -- Swiss FSVO, Cottage cheese
  ('10000000-0000-4000-8000-000000000012'::uuid,  4.0),  -- Swiss FSVO, Walnut
  ('10000000-0000-4000-8000-000000000013'::uuid, 74.8),  -- USDA FDC 2646170, breast raw
  ('10000000-0000-4000-8000-000000000014'::uuid, 73.2),  -- Swiss FSVO, Sweet potato, baked
  ('10000000-0000-4000-8000-000000000015'::uuid, 66.9),  -- derived, simmered breast
  ('10000000-0000-4000-8000-000000000016'::uuid, 65.3),  -- as roasted; air frying adds no water
  ('10000000-0000-4000-8000-000000000017'::uuid, 79.7),  -- Swiss FSVO, Potato, peeled, raw
  ('10000000-0000-4000-8000-000000000018'::uuid, 71.0),  -- Swiss FSVO, Potato, with skin, baked
  ('10000000-0000-4000-8000-000000000019'::uuid, 71.0),  -- as baked
  ('10000000-0000-4000-8000-000000000020'::uuid, 66.7),  -- Swiss FSVO, French fries for oven
  ('10000000-0000-4000-8000-000000000021'::uuid,  6.4),  -- derived residual moisture
  ('10000000-0000-4000-8000-000000000022'::uuid,  8.6),  -- derived residual moisture
  ('10000000-0000-4000-8000-000000000023'::uuid,  5.3),  -- derived residual moisture
  ('10000000-0000-4000-8000-000000000024'::uuid,  7.3),  -- derived residual moisture
  ('10000000-0000-4000-8000-000000000025'::uuid,  7.0),  -- derived residual moisture
  ('10000000-0000-4000-8000-000000000026'::uuid, 10.8),  -- USDA FDC 173904, oats dry
  ('10000000-0000-4000-8000-000000000027'::uuid, 76.8),  -- derived recipe, green papaya base
  ('10000000-0000-4000-8000-000000000028'::uuid, 71.1),  -- USDA FDC 2706457, fish sauce
  ('10000000-0000-4000-8000-000000000029'::uuid, 73.2),  -- USDA FDC 171705, avocado raw
  ('10000000-0000-4000-8000-000000000030'::uuid, 76.2),  -- USDA FDC 171287, egg raw
  ('10000000-0000-4000-8000-000000000031'::uuid, 74.6)   -- USDA FDC 173424, egg hard-boiled
) as v(id, water)
where f.id = v.id and f.water_ml_100 is distinct from v.water;

-- Water-dense whole foods that arrive from a provider without a water figure.
-- Name-anchored and conservative: a curated value always wins, and anything
-- ambiguous is left unknown rather than guessed.
update public.foods set water_ml_100 = 96.0
where water_ml_100 is null and lower(name) ~ '(^|[^a-z])(cucumber|gurke|concombre|cetriolo|castravete|แตงกวา)([^a-z]|$)';

update public.foods set water_ml_100 = 94.0
where water_ml_100 is null and lower(name) ~ '(^|[^a-z])(tomato|tomatoes|tomate|tomaten|pomodoro|roșie|rosie|มะเขือเทศ)([^a-z]|$)';

update public.foods set water_ml_100 = 91.5
where water_ml_100 is null and lower(name) ~ '(^|[^a-z])(watermelon|wassermelone|pastèque|anguria|pepene verde|แตงโม)([^a-z]|$)';

update public.foods set water_ml_100 = 90.9
where water_ml_100 is null and lower(name) ~ '(^|[^a-z])(lettuce|salat|kopfsalat|laitue|lattuga|salată verde|ผักกาดหอม)([^a-z]|$)';

update public.foods set water_ml_100 = 88.1
where water_ml_100 is null and lower(name) ~ '(^|[^a-z])(orange|orangen|arancia|portocal|ส้ม)([^a-z]|$)';

update public.foods set water_ml_100 = 85.6
where water_ml_100 is null and lower(name) ~ '(^|[^a-z])(apple|apfel|äpfel|pomme|mela|măr|mar|แอปเปิล)([^a-z]|$)';

update public.foods set water_ml_100 = 87.4
where water_ml_100 is null and lower(name) ~ '(^|[^a-z])(milk|milch|lait|latte|lapte|นม)([^a-z]|$)'
  and lower(name) !~ '(powder|pulver|condensed|evaporated)';

update public.foods set water_ml_100 = 99.5
where water_ml_100 is null and lower(name) ~ '(^|[^a-z])(water|wasser|eau|acqua|apă|apa|น้ำเปล่า)([^a-z]|$)'
  and lower(name) !~ '(coconut|melon|rose|micellar)';

-- Existing history predates the column, so entries carry no water at all.
-- Fill both the snapshot and the computed millilitres from the food row.
update public.logged_food_entries as e
set snapshot_water_ml_100 = f.water_ml_100,
    water_ml = round(f.water_ml_100 * e.equivalent_amount / 100, 2)
from public.foods as f
where e.food_id = f.id
  and f.water_ml_100 is not null
  and e.snapshot_water_ml_100 is null;

notify pgrst, 'reload schema';
