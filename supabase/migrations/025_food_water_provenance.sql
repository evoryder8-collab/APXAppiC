-- Water is not part of the mandatory EU nutrition declaration and most
-- provider/catalogue values are derived rather than measured. Preserve how
-- every number was obtained so clients never present an estimate as exact.

alter table public.foods
  add column if not exists water_basis text,
  add column if not exists water_source_id text;

update public.foods
set water_basis = case
  when water_ml_100 is null then 'unknown'
  else 'legacy'
end
where water_basis is null;

-- These four bundled reference rows have an explicit source recorded in the
-- repository's hydration fixtures. They remain reference values, not a claim
-- that a particular retail package was laboratory measured.
update public.foods
set water_basis = 'reference',
    water_source_id = case provider_product_id
      when 'apex-common:oats' then 'swiss-fsvo-v7.1:oat-flakes'
      when 'apex-common:broccoli' then 'swiss-fsvo-v7.1:broccoli-steamed'
      when 'apex-common:chicken' then 'usda-fdc:171477'
      when 'apex-common:walnuts' then 'swiss-fsvo-v7.1:walnut'
    end
where provider_product_id in (
  'apex-common:oats',
  'apex-common:broccoli',
  'apex-common:chicken',
  'apex-common:walnuts'
);

alter table public.foods
  alter column water_basis set default 'unknown',
  alter column water_basis set not null;

alter table public.foods
  drop constraint if exists foods_water_basis_check;
alter table public.foods
  add constraint foods_water_basis_check check (
    water_basis in (
      'measured', 'provider_reported', 'reference', 'name', 'difference',
      'legacy', 'user_entered', 'unknown'
    )
  );

alter table public.logged_food_entries
  add column if not exists snapshot_water_basis text,
  add column if not exists snapshot_water_source_id text;

update public.logged_food_entries as entry
set snapshot_water_basis = coalesce(food.water_basis, 'legacy'),
    snapshot_water_source_id = food.water_source_id
from public.foods as food
where entry.food_id = food.id
  and entry.snapshot_water_ml_100 is not null
  and entry.snapshot_water_basis is null;

update public.logged_food_entries
set snapshot_water_basis = case
  when snapshot_water_ml_100 is null then 'unknown'
  else 'legacy'
end
where snapshot_water_basis is null;

alter table public.logged_food_entries
  alter column snapshot_water_basis set default 'unknown',
  alter column snapshot_water_basis set not null;

alter table public.logged_food_entries
  drop constraint if exists logged_food_entries_water_basis_check;
alter table public.logged_food_entries
  add constraint logged_food_entries_water_basis_check check (
    snapshot_water_basis in (
      'measured', 'provider_reported', 'reference', 'name', 'difference',
      'legacy', 'user_entered', 'unknown'
    )
  );

create or replace function public.apex_copy_food_water_provenance()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  source_basis text;
  source_id text;
begin
  if new.food_id is not null
     and (new.snapshot_water_basis is null or new.snapshot_water_basis = 'unknown') then
    select food.water_basis, food.water_source_id
      into source_basis, source_id
    from public.foods as food
    where food.id = new.food_id;

    if source_basis is not null then
      new.snapshot_water_basis := source_basis;
      new.snapshot_water_source_id := source_id;
    end if;
  end if;

  new.snapshot_water_basis := coalesce(new.snapshot_water_basis, 'unknown');
  return new;
end;
$$;

drop trigger if exists logged_food_entries_copy_water_provenance
  on public.logged_food_entries;
create trigger logged_food_entries_copy_water_provenance
before insert on public.logged_food_entries
for each row execute function public.apex_copy_food_water_provenance();

comment on column public.foods.water_basis is
  'Provenance of water_ml_100. Only measured is displayed as exact; every other value is disclosed as estimated or reported.';
comment on column public.foods.water_source_id is
  'Stable source identifier when a provider or composition reference is known; null means the value has not been source-verified.';
