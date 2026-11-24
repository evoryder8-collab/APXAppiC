-- Train together, wheel hardening (from the build 429 review).
--
-- 1. Each validator answers false, never null, so a snapshot or plan with a
--    key missing is refused instead of slipping past "if not valid".
-- 2. A room leaves its lobby only into its warm-up or first set, so a build
--    427/428 phone in a wheel room (it never gets the chosen workout) cannot
--    start everyone at the end.
-- 3. Such a phone's sound or voice switch keeps the wheel it does not know about.
--
-- Only Train together functions change; build 402 calls none of them.

create or replace function public.group_workout_plan_is_valid(p_plan jsonb)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select coalesce((
    jsonb_typeof(p_plan) = 'object'
      and pg_column_size(p_plan) <= 65536
      and jsonb_typeof(p_plan -> 'exercises') = 'array'
      and jsonb_array_length(p_plan -> 'exercises') between 0 and 40
      and coalesce(jsonb_typeof(p_plan -> 'warmup_duration'), 'number') = 'number'
      and coalesce((p_plan ->> 'warmup_duration')::numeric, 0) between 0 and 3600
      and char_length(coalesce(p_plan ->> 'warmup_text', '')) <= 500
      and not exists (
        select 1 from jsonb_array_elements(p_plan -> 'exercises') as x(e)
        where jsonb_typeof(e) <> 'object'
          or char_length(coalesce(e ->> 'name', '')) not between 1 and 120
          or jsonb_typeof(e -> 'sets') is distinct from 'number'
          or jsonb_typeof(e -> 'rep_min') is distinct from 'number'
          or jsonb_typeof(e -> 'rep_max') is distinct from 'number'
          or jsonb_typeof(e -> 'rest_sec') is distinct from 'number'
          or (e ->> 'sets')::numeric not between 1 and 20
          or (e ->> 'rep_min')::numeric not between 0 and 1000
          or (e ->> 'rep_max')::numeric not between 0 and 1000
          or (e ->> 'rest_sec')::numeric not between 0 and 3600
          or coalesce((e ->> 'tempo_up_s')::numeric, 0) not between 0 and 30
          or coalesce((e ->> 'tempo_down_s')::numeric, 0) not between 0 and 30
          or coalesce((e ->> 'tempo_pause_s')::numeric, 0) not between 0 and 30
          or char_length(coalesce(e ->> 'tempo_note', '')) > 300
      )
  ), false);
$$;

create or replace function public.group_workout_wheel_is_valid(p_wheel jsonb)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select coalesce((
    p_wheel is null or jsonb_typeof(p_wheel) = 'null' or (
      jsonb_typeof(p_wheel) = 'object'
      and (p_wheel ->> 'focus') in ('full_body', 'push', 'pull', 'upper_body', 'lower_body', 'hiit')
      and (
        p_wheel -> 'spin' is null or jsonb_typeof(p_wheel -> 'spin') = 'null' or (
          jsonb_typeof(p_wheel -> 'spin') = 'object'
          and jsonb_typeof(p_wheel -> 'spin' -> 'slots') = 'array'
          and jsonb_array_length(p_wheel -> 'spin' -> 'slots') between 1 and 12
          and not exists (
            select 1 from jsonb_array_elements(p_wheel -> 'spin' -> 'slots') as s(v)
            where jsonb_typeof(v) <> 'string' or char_length(v #>> '{}') not between 1 and 64
          )
          and jsonb_typeof(p_wheel -> 'spin' -> 'landing') = 'number'
          and (p_wheel -> 'spin' ->> 'landing')::numeric >= 0
          and (p_wheel -> 'spin' ->> 'landing')::numeric < jsonb_array_length(p_wheel -> 'spin' -> 'slots')
          and jsonb_typeof(p_wheel -> 'spin' -> 'at') = 'string'
          and (p_wheel -> 'spin' ->> 'at')::timestamptz is not null
        )
      )
    )
  ), false);
$$;

create or replace function public.group_workout_state_is_valid(p_state jsonb)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select coalesce((
    jsonb_typeof(p_state) = 'object'
      and pg_column_size(p_state) <= 4096
      and (p_state ->> 'phase') in ('lobby', 'warmup', 'work', 'side_switch', 'rest', 'review')
      and coalesce(p_state ->> 'side', 'left') in ('left', 'right')
      and jsonb_typeof(p_state -> 'position') = 'number'
      and jsonb_typeof(p_state -> 'step') = 'number'
      and jsonb_typeof(p_state -> 'extra_seconds') = 'number'
      and jsonb_typeof(p_state -> 'sound') = 'boolean'
      and jsonb_typeof(p_state -> 'voice') = 'boolean'
      and jsonb_typeof(p_state -> 'anchor') = 'string'
      and coalesce(jsonb_typeof(p_state -> 'paused_at'), 'string') = 'string'
      and (p_state ->> 'position')::numeric between 0 and 1000
      and (p_state ->> 'step')::numeric between 0 and 1000000
      and (p_state ->> 'extra_seconds')::numeric between 0 and 3600
      and (p_state ->> 'anchor')::timestamptz is not null
      and ((p_state ->> 'paused_at') is null or (p_state ->> 'paused_at')::timestamptz is not null)
      and public.group_workout_wheel_is_valid(p_state -> 'wheel')
  ), false);
$$;

create or replace function public.group_workout_set_state(
  p_id uuid,
  p_expected_version integer,
  p_state jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_room public.group_workouts%rowtype;
  v_version integer;
begin
  if v_user is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_state is null or p_expected_version is null or not public.group_workout_state_is_valid(p_state) then
    raise exception 'invalid_state' using errcode = '22023';
  end if;
  select * into v_room from public.group_workouts g where g.id = p_id for update;
  if v_room.id is null or not (
    v_room.host_user_id = v_user
    or (v_room.shared_control and public.group_workout_is_member(p_id, v_user))
  ) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if public.group_workout_is_over(v_room) then
    raise exception 'room_ended' using errcode = 'P0001';
  end if;
  if coalesce(jsonb_array_length(v_room.plan -> 'exercises'), 0) = 0 and p_state ->> 'phase' <> 'lobby' then
    raise exception 'invalid_state' using errcode = '22023';
  end if;
  -- A room leaves its lobby into its warm-up or its first set, never further:
  -- an older phone that never got the workout would otherwise start at the end.
  if v_room.state ->> 'phase' = 'lobby' and not (
    p_state ->> 'phase' in ('lobby', 'warmup')
    or (p_state ->> 'phase' = 'work' and (p_state ->> 'position')::numeric = 0)
  ) then
    raise exception 'invalid_state' using errcode = '22023';
  end if;
  -- An older phone writes its snapshot without the wheel; the wheel it does not know about stays.
  if coalesce(jsonb_array_length(v_room.plan -> 'exercises'), 0) = 0
     and p_state ->> 'phase' = 'lobby' and not (p_state ? 'wheel') and v_room.state ? 'wheel' then
    p_state := p_state || jsonb_build_object('wheel', v_room.state -> 'wheel');
  end if;
  -- A press made against an older state loses; the caller gets the newer one.
  if v_room.state_version <> p_expected_version then
    return jsonb_build_object('accepted', false) || public.group_workout_json(v_room, v_user);
  end if;
  v_version := v_room.state_version + 1;
  update public.group_workouts
  set state = p_state,
      state_version = v_version,
      status = case when p_state ->> 'phase' = 'lobby' then 'scheduled' else 'live' end
  where id = p_id
  returning * into v_room;
  perform realtime.send(
    jsonb_build_object('version', v_version, 'state', p_state, 'shared_control', v_room.shared_control),
    'state', 'group:' || p_id::text, true
  );
  return jsonb_build_object('accepted', true) || public.group_workout_json(v_room, v_user);
end;
$$;

create or replace function public.group_workout_set_plan(p_id uuid, p_plan jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_room public.group_workouts%rowtype;
begin
  if v_user is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_plan is null or not public.group_workout_plan_is_valid(p_plan)
     or jsonb_array_length(p_plan -> 'exercises') = 0 then
    raise exception 'invalid_plan' using errcode = '22023';
  end if;
  select * into v_room from public.group_workouts g where g.id = p_id for update;
  if v_room.id is null or v_room.host_user_id <> v_user then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if public.group_workout_is_over(v_room) then
    raise exception 'room_ended' using errcode = 'P0001';
  end if;
  if coalesce(jsonb_array_length(v_room.plan -> 'exercises'), 0) > 0 or v_room.state ->> 'phase' is distinct from 'lobby' then
    raise exception 'plan_chosen' using errcode = 'P0001';
  end if;
  update public.group_workouts
  set plan = p_plan,
      title = left(coalesce(nullif(btrim(p_plan ->> 'name'), ''), v_room.title), 80),
      state = v_room.state - 'wheel',
      state_version = v_room.state_version + 1
  where id = p_id
  returning * into v_room;
  perform realtime.send(
    jsonb_build_object(
      'version', v_room.state_version, 'state', v_room.state, 'shared_control', v_room.shared_control,
      'plan', v_room.plan, 'title', v_room.title
    ),
    'state', 'group:' || p_id::text, true
  );
  return public.group_workout_json(v_room, v_user);
end;
$$;

notify pgrst, 'reload schema';
