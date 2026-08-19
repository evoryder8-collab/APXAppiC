-- Water content for the foods that already existed before the estimator.
--
-- 010 set measured values on the curated catalogue, but the catalogue is only
-- 12 of the 141 rows here. The foods people actually log are their own private
-- entries and Open Food Facts imports, and those arrived before any client
-- estimated water, so hydration still read as nothing for real meals.
--
-- Derives water by difference using the same rules as src/lib/hydration.ts and
-- FoodHydration.swift, so a row backfilled here and a row imported tomorrow
-- get the same answer:
--   * a pressed or refined oil is reported as no water rather than unknown
--   * a fatty per-100 ml row is left unknown, because its missing grams are
--     density rather than water
--   * ash is estimated from the macro shape, or from salt when it is known
--   * fibre is counted separately only when the row's own energy says the
--     stored carbohydrate excludes it (Europe) rather than includes it (USDA)

with derived as (
  select
    f.id,
    f.nutrition_basis = 'per_100ml' as per_ml,
    coalesce(f.protein_100, 0) as p,
    coalesce(f.carbs_100, 0) as c,
    coalesce(f.fat_100, 0) as fat,
    coalesce(f.fibre_100, 0) as fibre,
    f.kcal_100 as kcal,
    case
      when f.salt_100 is not null and f.salt_100 > 0
        then least(20, greatest(0.5, f.salt_100 * 1.1))
      when coalesce(f.protein_100, 0) >= 60 then 3.5
      when coalesce(f.protein_100, 0) >= 15 and coalesce(f.fat_100, 0) <= 12 then 1.2
      when coalesce(f.fat_100, 0) >= 50 then 1.8
      else 0.9
    end as ash
  from public.foods f
  where f.water_ml_100 is null
    and f.protein_100 is not null
    and f.carbs_100 is not null
    and f.fat_100 is not null
    -- A planned prescription stands for a meal not yet chosen. Its macros are
    -- a target, not a composition, so it stays unknown rather than claiming
    -- hydration nobody has eaten. The clients treat it the same way.
    and coalesce(f.provider_product_id, '') not like 'apex-plan:%'
    and coalesce(f.brand, '') <> 'APEX plan'
),
resolved as (
  select
    id,
    case
      -- A pressed or refined oil: fat all the way down, water below 0.1 g.
      when fat >= (case when per_ml then 80 else 90 end) and p + c <= 2 then 0
      -- A fatty liquid cannot be resolved by difference alone.
      when per_ml and fat >= 20 then null
      else greatest(0, least(100, round(
        100 - (p + c + fat + ash + case
          when fibre <= 0 then 0
          -- No energy to arbitrate: assume fibre is listed separately, the
          -- commoner case here and the one that never overstates hydration.
          when kcal is null or kcal <= 0 then fibre
          -- Score the row against Atwater under both conventions.
          when abs((4*p + 4*c + 9*fat + 2*fibre) - kcal)
             <= abs((4*p + 4*(c - fibre) + 9*fat + 2*fibre) - kcal) then fibre
          else 0
        end)
      , 1)))
    end as water
  from derived
)
update public.foods as f
set water_ml_100 = r.water, updated_at = now()
from resolved as r
where f.id = r.id and r.water is not null;

-- History predating the column carries no water; fill it from the food row.
update public.logged_food_entries as e
set snapshot_water_ml_100 = f.water_ml_100,
    water_ml = round(f.water_ml_100 * e.equivalent_amount / 100, 2)
from public.foods as f
where e.food_id = f.id
  and f.water_ml_100 is not null
  and e.snapshot_water_ml_100 is null;

notify pgrst, 'reload schema';
