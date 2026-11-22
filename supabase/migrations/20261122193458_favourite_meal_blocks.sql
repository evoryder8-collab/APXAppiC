-- Favourites belong to meals: breakfast has its own, dinner its own. The list holds the dayline
-- block kinds a favourite is saved to; null or empty means every meal (a star given outside a meal,
-- or by a build that predates this). Older builds never send the column, and a one-row upsert
-- leaves a column it does not name untouched, so build 402 keeps working unchanged.
alter table public.food_preferences
  add column if not exists favourite_meal_blocks text[];

alter table public.food_preferences
  drop constraint if exists food_preferences_favourite_meal_blocks_known;
alter table public.food_preferences
  add constraint food_preferences_favourite_meal_blocks_known
  check (favourite_meal_blocks <@ array['breakfast', 'lunch', 'dinner', 'snack', 'post_workout']::text[]);

-- Existing favourites start in the meals they were eaten in over the last 90 days: those eaten
-- there at least twice, else wherever they were eaten at all. One not eaten in that time stays
-- in every meal. The block is read the way the app reads it (MealBlocks.kind).
with uses as (
  select p.id as preference_id,
    case
      when substring(m.client_idempotency_key from 'apex-meal-block=([a-z_]+)')
           in ('breakfast', 'lunch', 'dinner', 'snack', 'post_workout')
        then substring(m.client_idempotency_key from 'apex-meal-block=([a-z_]+)')
      when m.meal_slot::text = 'post_workout' then 'post_workout'
      when lower(m.display_name) ~ '(post-workout|post workout|after training|recovery|după antrenament|หลังฝึก)'
        then 'post_workout'
      else m.meal_slot::text
    end as block,
    count(*) as times
  from public.food_preferences p
  join public.logged_food_entries e on e.user_id = p.user_id and e.food_id = p.food_id
  join public.logged_meals m on m.id = e.meal_id and m.user_id = p.user_id
  where p.favourite and p.favourite_meal_blocks is null and m.local_date >= current_date - 90
  group by 1, 2
), picked as (
  select preference_id,
    coalesce(
      array_agg(block order by block) filter (where times >= 2),
      array_agg(block order by block)
    ) as blocks
  from uses
  where block in ('breakfast', 'lunch', 'dinner', 'snack', 'post_workout')
  group by preference_id
)
update public.food_preferences p
set favourite_meal_blocks = picked.blocks
from picked
where p.id = picked.preference_id;
