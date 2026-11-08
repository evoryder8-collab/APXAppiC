-- A meal and its ingredient set are one editable snapshot. Versions are the
-- operation keys already minted by both clients on every replacement.
create or replace function public.get_meal_edit_snapshot(p_meal_id uuid)
returns jsonb
language sql stable security invoker set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'version', m.client_idempotency_key, 'entries', coalesce((
      select jsonb_agg(to_jsonb(e) order by e.sort_order, e.id)
      from public.logged_food_entries e
      where e.user_id = m.user_id and e.meal_id = m.id
    ), '[]'::jsonb)
  ) from public.logged_meals m where m.user_id = (select auth.uid()) and m.id = p_meal_id;
$$;
revoke all on function public.get_meal_edit_snapshot(uuid) from public, anon;
grant execute on function public.get_meal_edit_snapshot(uuid) to authenticated;

do $migration$
begin
  if to_regprocedure('public.log_structured_meal_snapshot_unchecked(jsonb,jsonb)') is null then
    alter function public.log_structured_meal(jsonb,jsonb) rename to log_structured_meal_snapshot_unchecked;
  end if;
end;
$migration$;
revoke all on function public.log_structured_meal_snapshot_unchecked(jsonb,jsonb) from public, anon, authenticated;

create or replace function public.log_structured_meal(p_meal jsonb, p_entries jsonb) returns uuid
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  actor uuid := auth.uid();
  previous_id uuid := nullif(p_meal->>'replace_meal_id','')::uuid;
  previous_key text;
  replay uuid;
  operation_key text := p_meal->>'client_idempotency_key';
  stored_ids uuid[];
  expected_ids uuid[];
begin
  if actor is null then raise exception 'Sign in to save a meal' using errcode = '42501'; end if;
  if jsonb_typeof(p_entries) is distinct from 'array' or jsonb_array_length(p_entries) < 1 then
    raise exception 'A logged meal needs at least one food' using errcode = '22023';
  end if;
  if p_meal->>'meal_slot' = 'post_workout' and position('apex-meal-block=' in operation_key) = 0 then
    operation_key := operation_key || '|apex-meal-block=post_workout';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text || ':meal-operation:' || operation_key, 0));
  select id into replay from public.logged_meals where user_id = actor and client_idempotency_key = operation_key;
  if replay is not null then return replay; end if;
  if previous_id is not null then
    -- Older clients replace the row using the same UUID; a row lock alone cannot guard the gap.
    perform pg_advisory_xact_lock(hashtextextended(actor::text || ':' || previous_id::text, 0));
    select client_idempotency_key into previous_key from public.logged_meals where user_id = actor and id = previous_id for update;
    if previous_key is null then
      raise exception 'This meal changed. Reopen it before saving.' using errcode = 'PT409';
    end if;
    select coalesce(array_agg(id order by id), '{}'::uuid[]) into stored_ids
      from public.logged_food_entries where user_id = actor and meal_id = previous_id;
    if not (p_meal ? 'expected_meal_version' or p_meal ? 'expected_entry_ids') then
      -- Older iPhone builds send the ingredient UUIDs read by their editor. A
      -- complete set proves this edit did not silently omit a saved ingredient.
      select coalesce(array_agg((item->>'id')::uuid) filter (where item->>'id' is not null), '{}'::uuid[])
        into expected_ids from jsonb_array_elements(p_entries) as input(item);
      if cardinality(stored_ids) = 0 or not (stored_ids <@ expected_ids) then
        raise exception 'Update FITR MAX or reopen this meal in the updated web app before removing ingredients. Your saved meal is intact.' using errcode = 'PT409';
      end if;
    else
      if previous_key is distinct from (p_meal->>'expected_meal_version') or jsonb_typeof(p_meal->'expected_entry_ids') is distinct from 'array' then
        raise exception 'This meal changed. Reopen it before saving.' using errcode = 'PT409';
      end if;
      select coalesce(array_agg(id::uuid order by id::uuid), '{}'::uuid[]) into expected_ids
        from jsonb_array_elements_text(p_meal->'expected_entry_ids') as entry(id);
      if stored_ids <> expected_ids then
        raise exception 'Reopen this meal to load every ingredient before saving.' using errcode = 'PT409';
      end if;
    end if;
    -- Ingredient IDs are the implicit revision for older native builds. Retire
    -- reused IDs on a successful edit so a delayed unversioned edit cannot overwrite it.
    select jsonb_agg(case when (item->>'id')::uuid = any(stored_ids)
      then jsonb_set(item, '{id}', to_jsonb(gen_random_uuid())) else item end order by ord)
      into p_entries from jsonb_array_elements(p_entries) with ordinality as input(item, ord);
  end if;
  return public.log_structured_meal_snapshot_unchecked(p_meal, p_entries);
end;
$$;
revoke all on function public.log_structured_meal(jsonb,jsonb) from public, anon;
grant execute on function public.log_structured_meal(jsonb,jsonb) to authenticated;

create or replace function public.delete_structured_meal_checked(p_meal_id uuid, p_expected_meal_version text) returns boolean
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  actor uuid := auth.uid();
  previous_key text;
begin
  if actor is null then raise exception 'Sign in to remove a meal' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text || ':' || p_meal_id::text, 0));
  select client_idempotency_key into previous_key from public.logged_meals
    where user_id = actor and id = p_meal_id for update;
  if not found then return true; end if;
  if previous_key is distinct from p_expected_meal_version then
    raise exception 'This meal changed. Reopen it before removing it.' using errcode = 'PT409';
  end if;
  return public.delete_structured_meal(p_meal_id);
end;
$$;
revoke all on function public.delete_structured_meal_checked(uuid,text) from public, anon;
grant execute on function public.delete_structured_meal_checked(uuid,text) to authenticated;

notify pgrst, 'reload schema';
