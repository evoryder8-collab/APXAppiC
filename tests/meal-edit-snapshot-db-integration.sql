-- Run on a disposable database with the meal migrations applied.
-- Everything is synthetic and rolls back.
begin;
insert into auth.users(id,email) values
 ('db66ea8d-5af3-449d-a392-3078fb222a01', 'meal-edit-fixture@example.invalid'),
 ('db66ea8d-5af3-449d-a392-3078fb222a02', 'other-meal-edit-fixture@example.invalid');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"db66ea8d-5af3-449d-a392-3078fb222a01","role":"authenticated"}',true);
create function pg_temp.portion(name text, grams numeric) returns jsonb language sql as $$
  select jsonb_build_object('snapshot_name',name,'quantity',grams,'equivalent_amount',grams,'unit','g',
    'snapshot_preparation_state','as_sold','snapshot_nutrition_basis','per_100g','snapshot_kcal_100',100,
    'snapshot_protein_100',0,'snapshot_carbs_100',25,'snapshot_fat_100',0);
$$;
do $check$
declare
  meal_id uuid := gen_random_uuid();
  header jsonb := jsonb_build_object('id',meal_id,'local_date','2026-06-01','meal_slot','breakfast','client_idempotency_key','original');
  snapshot jsonb;
  ids jsonb;
  edit jsonb;
  replay uuid;
begin
  perform public.log_structured_meal(header,jsonb_build_array(pg_temp.portion('first',100),pg_temp.portion('second',100)));
  -- More than one PostgREST page of newer ingredients must not truncate this meal.
  perform public.log_structured_meal(header || jsonb_build_object('id',gen_random_uuid(),'client_idempotency_key','many-newer'),
    (select jsonb_agg(pg_temp.portion('newer',1)) from generate_series(1,1001)));
  snapshot := public.get_meal_edit_snapshot(meal_id);
  if snapshot->>'version' <> 'original' or jsonb_array_length(snapshot->'entries') <> 2 then raise exception 'snapshot incomplete'; end if;
  select jsonb_agg(item->'id') into ids from jsonb_array_elements(snapshot->'entries') as e(item);
  edit := header || jsonb_build_object('replace_meal_id',meal_id, 'client_idempotency_key','edit');
  begin
    perform public.log_structured_meal(edit,jsonb_build_array(pg_temp.portion('first',110)));
    raise exception 'unguarded legacy replacement accepted';
  exception when sqlstate 'PT409' then null; end;
  begin
    perform public.log_structured_meal(edit || jsonb_build_object('expected_meal_version','original','expected_entry_ids',jsonb_build_array(ids->0)),jsonb_build_array(pg_temp.portion('first',110)));
    raise exception 'partially hydrated replacement accepted';
  exception when sqlstate 'PT409' then null; end;
  if jsonb_array_length(public.get_meal_edit_snapshot(meal_id)->'entries') <> 2 then raise exception 'guard damaged original'; end if;
  edit := edit || jsonb_build_object('expected_meal_version','original','expected_entry_ids',ids);
  -- A deliberate removal after opening a complete snapshot is allowed.
  replay := public.log_structured_meal(edit,jsonb_build_array(pg_temp.portion('first',110)));
  if replay <> meal_id or public.log_structured_meal(edit,jsonb_build_array(pg_temp.portion('first',110))) <> meal_id then raise exception 'edit replay was not idempotent'; end if;
  begin
    perform public.log_structured_meal(edit || '{"client_idempotency_key":"stale"}',jsonb_build_array(pg_temp.portion('other device',25)));
    raise exception 'stale edit accepted';
  exception when sqlstate 'PT409' then null; end;
  begin
    perform public.delete_structured_meal_checked(meal_id,'original'); raise exception 'stale deletion accepted';
  exception when sqlstate 'PT409' then null; end;
  if jsonb_array_length(public.get_meal_edit_snapshot(meal_id)->'entries') <> 1 then raise exception 'unexpected ingredients after guarded edit'; end if;
  perform set_config('request.jwt.claims','{"sub":"db66ea8d-5af3-449d-a392-3078fb222a02","role":"authenticated"}',true);
  if public.get_meal_edit_snapshot(meal_id) is not null then raise exception 'snapshot crossed account boundary'; end if;
  begin
    perform public.log_structured_meal(edit,jsonb_build_array(pg_temp.portion('other account',25)));
    raise exception 'cross-account replacement accepted';
  exception when sqlstate 'PT409' then null; end;
  perform set_config('request.jwt.claims','{"sub":"db66ea8d-5af3-449d-a392-3078fb222a01","role":"authenticated"}',true);
  if not public.delete_structured_meal_checked(meal_id,'edit') or not public.delete_structured_meal_checked(meal_id,'edit') then raise exception 'checked deletion failed'; end if;
end
$check$;
do $legacy$
declare
  meal_id uuid := gen_random_uuid();
  header jsonb := jsonb_build_object('id',meal_id, 'local_date','2026-06-02','meal_slot','dinner','client_idempotency_key','old-device-create');
  ids jsonb;
  original_entries jsonb;
  edit jsonb;
begin
  perform public.log_structured_meal(header, jsonb_build_array(pg_temp.portion('a',100),pg_temp.portion('b',100)));
  select jsonb_agg(item->'id' order by item->>'snapshot_name') into ids from jsonb_array_elements(public.get_meal_edit_snapshot(meal_id)->'entries') e(item);
  original_entries := jsonb_build_array(pg_temp.portion('a',120)||jsonb_build_object('id',ids->0),pg_temp.portion('b',100)||jsonb_build_object('id',ids->1));
  edit := header || jsonb_build_object('replace_meal_id',meal_id,'client_idempotency_key','old-device-edit');
  perform public.log_structured_meal(edit, original_entries);
  if (select total_kcal from public.logged_meals where id = meal_id) <> 220 then raise exception 'complete legacy edit failed'; end if;
  begin
    perform public.log_structured_meal(edit || '{"client_idempotency_key":"late-old-device"}', original_entries);
    raise exception 'stale legacy edit accepted';
  exception when sqlstate 'PT409' then null; end;
end;
$legacy$;
rollback;
