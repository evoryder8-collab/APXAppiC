-- Build 402 cannot be updated while TestFlight review is blocked. The meal-edit guard of
-- 20261108120100 answered its edits with PT409, which that build retries without end, holding
-- back every later write in its queue: workouts finished on 8-10 November never reached the
-- server and their sets were refused for a missing parent. Unversioned edits pass again;
-- builds that send a meal version keep the full guard.
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
  -- Builds before 404 send neither field and cannot be updated on demand.
  versioned boolean := p_meal ? 'expected_meal_version' or p_meal ? 'expected_entry_ids';
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
    if not versioned then
      -- An older build treats PT409 as a passing outage: it retries the edit forever and
      -- sends nothing queued behind it, so a refused meal edit silently held back workouts.
      -- Its edits are accepted as they were before the guard, the person's own latest entry.
      if previous_key is null then p_meal := p_meal - 'replace_meal_id'; end if;
    else
      if previous_key is null then
        raise exception 'This meal changed. Reopen it before saving.' using errcode = 'PT409';
      end if;
      select coalesce(array_agg(id order by id), '{}'::uuid[]) into stored_ids
        from public.logged_food_entries where user_id = actor and meal_id = previous_id;
      if previous_key is distinct from (p_meal->>'expected_meal_version') or jsonb_typeof(p_meal->'expected_entry_ids') is distinct from 'array' then
        raise exception 'This meal changed. Reopen it before saving.' using errcode = 'PT409';
      end if;
      select coalesce(array_agg(id::uuid order by id::uuid), '{}'::uuid[]) into expected_ids
        from jsonb_array_elements_text(p_meal->'expected_entry_ids') as entry(id);
      if stored_ids <> expected_ids then
        raise exception 'Reopen this meal to load every ingredient before saving.' using errcode = 'PT409';
      end if;
      -- Fresh ingredient IDs on every versioned edit, as before.
      select jsonb_agg(case when (item->>'id')::uuid = any(stored_ids)
        then jsonb_set(item, '{id}', to_jsonb(gen_random_uuid())) else item end order by ord)
        into p_entries from jsonb_array_elements(p_entries) with ordinality as input(item, ord);
    end if;
  end if;
  begin
    return public.log_structured_meal_snapshot_unchecked(p_meal, p_entries);
  exception when raise_exception then
    -- A plain refusal (P0001) is another error older builds retry forever; 22023 they file away.
    raise exception '%', sqlerrm using errcode = '22023';
  end;
end;
$$;
revoke all on function public.log_structured_meal(jsonb,jsonb) from public, anon;
grant execute on function public.log_structured_meal(jsonb,jsonb) to authenticated;
notify pgrst, 'reload schema';
