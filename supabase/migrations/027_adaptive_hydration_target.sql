-- Account-scoped automatic/custom hydration target selection. The original
-- 2.75 L value was the app default; any other existing value required a user
-- edit and is retained as an explicit custom target.

alter table public.hydration_preferences
  add column if not exists target_mode text;

update public.hydration_preferences
set target_mode = case
  when target_ml = 2750 then 'automatic'
  when target_ml <> 2750 then 'custom'
  else 'automatic'
end
where target_mode is null;

alter table public.hydration_preferences
  alter column target_mode set default 'automatic';

alter table public.hydration_preferences
  alter column target_mode set not null;

do $$
begin
  alter table public.hydration_preferences
    add constraint hydration_target_mode
    check (target_mode in ('automatic', 'custom'));
exception
  when duplicate_object then null;
end
$$;
