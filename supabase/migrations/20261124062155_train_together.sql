-- Train together: live rooms in which one phone's guided workout drives every
-- phone in the room. Each phone saves its own person's sets through the normal
-- save path; nothing here touches anyone's workout rows.
--
-- Additive only. Build 402 never calls any of this, and get_my_app_access is
-- left exactly as it is.

-- Where an account's access came from. Only founding accounts and App Store
-- subscriptions are paid; the free TestFlight grant never is.
alter table public.account_entitlements
  add column if not exists source text not null default 'testflight';
alter table public.account_entitlements
  drop constraint if exists account_entitlements_source_allowed;
alter table public.account_entitlements
  add constraint account_entitlements_source_allowed
  check (source in ('founding', 'testflight', 'app_store'));
-- The bespoke accounts are the ones granted with no expiry.
update public.account_entitlements
set source = 'founding'
where expires_at is null and source = 'testflight';

-- One row per paid feature. While paid_only is false the feature is open to
-- every account that may use the app (the TestFlight beta).
create table if not exists public.feature_access_policy (
  feature text primary key,
  paid_only boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.feature_access_policy enable row level security;
revoke all on table public.feature_access_policy from public, anon, authenticated;
insert into public.feature_access_policy (feature, paid_only)
values ('train_together', false)
on conflict (feature) do nothing;

create table if not exists public.group_workouts (
  id uuid primary key default gen_random_uuid(),
  host_user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('friends', 'class')),
  shared_control boolean not null default false,
  code text not null unique check (code ~ '^[A-HJKMNP-Z2-9]{6}$'),
  title text not null check (char_length(btrim(title)) between 1 and 80),
  host_name text not null default '',
  starts_at timestamptz not null,
  plan jsonb not null,
  state jsonb not null,
  state_version integer not null default 1,
  status text not null default 'scheduled' check (status in ('scheduled', 'live', 'ended')),
  max_members integer not null check (max_members between 1 and 500),
  created_at timestamptz not null default now(),
  ended_at timestamptz,
  constraint group_workouts_shared_control_friends check (kind = 'friends' or not shared_control)
);
create index if not exists group_workouts_open_by_host
  on public.group_workouts (host_user_id) where status <> 'ended';

create table if not exists public.group_workout_members (
  group_workout_id uuid not null references public.group_workouts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  first_name text not null default '',
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (group_workout_id, user_id)
);
create index if not exists group_workout_members_by_user
  on public.group_workout_members (user_id);

create table if not exists public.group_workout_join_attempts (
  user_id uuid not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now()
);
create index if not exists group_workout_join_attempts_recent
  on public.group_workout_join_attempts (user_id, attempted_at);

alter table public.group_workouts enable row level security;
alter table public.group_workout_members enable row level security;
alter table public.group_workout_join_attempts enable row level security;
revoke all on table public.group_workouts from public, anon, authenticated;
revoke all on table public.group_workout_members from public, anon, authenticated;
revoke all on table public.group_workout_join_attempts from public, anon, authenticated;

-- Access ----------------------------------------------------------------

create or replace function public.train_together_paid_only()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select paid_only from public.feature_access_policy where feature = 'train_together'),
    false
  );
$$;

-- Switch off: the rule get_my_app_access applies (tests/train-together-db-integration.sql
-- keeps the two equal). Switch on: only paid access counts, meaning a founding
-- account, an App Store subscription (its free trial included, the owner's call
-- of 2026-11-23), or a seat under a coach whose status is active. Phase 6 must
-- keep a coach active only while their subscription is paid.
create or replace function public.train_together_allowed(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.account_entitlements e
    where e.user_id = p_user
      and e.state = 'granted'
      and (e.expires_at is null or e.expires_at > statement_timestamp())
      and (not public.train_together_paid_only() or e.source in ('founding', 'app_store'))
  ) or exists (
    select 1 from public.coach_relationships r
    where r.client_user_id = p_user
      and r.status = 'active'
      and r.seat_state = 'active'
      and (not public.train_together_paid_only() or exists (
        select 1 from public.coach_profiles c
        where c.user_id = r.coach_user_id and c.status = 'active'
      ))
  );
$$;

create or replace function public.train_together_first_name(p_user uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select nullif(split_part(btrim(coalesce(p.display_name, '')), ' ', 1), '')
    from public.profile p
    where p.user_id = p_user
    order by p.updated_at desc nulls last
    limit 1
  ), '');
$$;

-- Rooms -----------------------------------------------------------------

-- A room's plan and state are read by every phone in it, so their numbers are
-- bounded here: one person must not be able to send a value that breaks the others.
create or replace function public.group_workout_plan_is_valid(p_plan jsonb)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select jsonb_typeof(p_plan) = 'object'
    and pg_column_size(p_plan) <= 65536
    and jsonb_typeof(p_plan -> 'exercises') = 'array'
    and jsonb_array_length(p_plan -> 'exercises') between 1 and 40
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
    );
$$;

create or replace function public.group_workout_state_is_valid(p_state jsonb)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select jsonb_typeof(p_state) = 'object'
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
    and ((p_state ->> 'paused_at') is null or (p_state ->> 'paused_at')::timestamptz is not null);
$$;

create or replace function public.group_workout_is_over(p_room public.group_workouts)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  -- No workout runs twelve hours, so a forgotten room closes itself.
  select p_room.status = 'ended' or p_room.starts_at < statement_timestamp() - interval '12 hours';
$$;

create or replace function public.group_workout_status(p_room public.group_workouts)
returns text
language sql
stable
set search_path = public, pg_temp
as $$
  select case when public.group_workout_is_over(p_room) then 'ended' else p_room.status end;
$$;

create or replace function public.group_workout_member_count(p_room_id uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select count(*)::integer from public.group_workout_members m
  where m.group_workout_id = p_room_id and m.left_at is null;
$$;

create or replace function public.group_workout_is_member(p_room_id uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.group_workout_members m
    where m.group_workout_id = p_room_id and m.user_id = p_user and m.left_at is null
  );
$$;

create or replace function public.group_workout_json(p_room public.group_workouts, p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'id', p_room.id,
    'code', p_room.code,
    'kind', p_room.kind,
    'title', p_room.title,
    'host_user_id', p_room.host_user_id,
    'host_name', p_room.host_name,
    'is_host', p_room.host_user_id = p_user,
    'starts_at', p_room.starts_at,
    'plan', p_room.plan,
    'state', p_room.state,
    'version', p_room.state_version,
    'shared_control', p_room.shared_control,
    'status', public.group_workout_status(p_room),
    'member_count', public.group_workout_member_count(p_room.id),
    'server_now', clock_timestamp()
  );
$$;

create or replace function public.train_together_server_now()
returns timestamptz
language sql
volatile
set search_path = public, pg_temp
as $$
  select clock_timestamp();
$$;

create or replace function public.train_together_my_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'allowed', public.train_together_allowed(v_user),
    'paid_only', public.train_together_paid_only(),
    'can_host_class', exists (
      select 1 from public.coach_profiles c
      where c.user_id = v_user and c.status in ('development', 'active')
    )
  );
end;
$$;

create or replace function public.group_workout_create(
  p_kind text,
  p_title text,
  p_starts_at timestamptz,
  p_plan jsonb,
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
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
  v_bytes bytea;
  v_old uuid;
  v_room public.group_workouts%rowtype;
  v_host_name text;
  v_count integer;
begin
  if v_user is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('friends', 'class') then
    raise exception 'invalid_kind' using errcode = '22023';
  end if;
  if p_kind = 'class' and not exists (
    select 1 from public.coach_profiles c
    where c.user_id = v_user and c.status in ('development', 'active')
  ) then
    raise exception 'class_not_allowed' using errcode = 'P0001';
  end if;
  if not public.train_together_allowed(v_user) then
    raise exception 'premium_required' using errcode = 'P0001';
  end if;
  if p_title is null or char_length(btrim(p_title)) not between 1 and 80 then
    raise exception 'invalid_title' using errcode = '22023';
  end if;
  if p_starts_at is null
     or p_starts_at < statement_timestamp() - interval '1 hour'
     or p_starts_at > statement_timestamp() + interval '60 days' then
    raise exception 'invalid_start' using errcode = '22023';
  end if;
  if p_plan is null or not public.group_workout_plan_is_valid(p_plan) then
    raise exception 'invalid_plan' using errcode = '22023';
  end if;
  if p_state is null or not public.group_workout_state_is_valid(p_state) then
    raise exception 'invalid_state' using errcode = '22023';
  end if;
  select count(*) into v_count from public.group_workouts g
  where g.host_user_id = v_user and not public.group_workout_is_over(g);
  if v_count >= 10 then
    raise exception 'too_many_rooms' using errcode = 'P0001';
  end if;

  -- A host runs one workout at a time: one already under way closes, so
  -- nobody keeps following it. Rooms scheduled for later stay open.
  for v_old in
    select g.id from public.group_workouts g
    where g.host_user_id = v_user and g.status = 'live'
    for update
  loop
    update public.group_workouts
    set status = 'ended', ended_at = statement_timestamp()
    where id = v_old;
    perform realtime.send('{}'::jsonb, 'ended', 'group:' || v_old::text, true);
  end loop;

  loop
    v_bytes := extensions.gen_random_bytes(6);
    select string_agg(substr(v_alphabet, 1 + (get_byte(v_bytes, i) % 31), 1), '' order by i)
    into v_code
    from generate_series(0, 5) as i;
    exit when not exists (select 1 from public.group_workouts g where g.code = v_code);
  end loop;

  v_host_name := case
    when p_kind = 'class' then coalesce(
      (select c.display_name from public.coach_profiles c where c.user_id = v_user), ''
    )
    else public.train_together_first_name(v_user)
  end;

  insert into public.group_workouts (
    host_user_id, kind, shared_control, code, title, host_name, starts_at,
    plan, state, max_members
  ) values (
    v_user, p_kind, p_kind = 'friends', v_code, btrim(p_title), v_host_name, p_starts_at,
    p_plan, p_state, case when p_kind = 'friends' then 9 else 50 end
  )
  returning * into v_room;

  return public.group_workout_json(v_room, v_user);
end;
$$;

create or replace function public.group_workout_preview(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_room public.group_workouts%rowtype;
begin
  select * into v_room from public.group_workouts g
  where g.code = upper(btrim(coalesce(p_code, '')));
  if v_room.id is null then
    return null;
  end if;
  return jsonb_build_object(
    'kind', v_room.kind,
    'title', v_room.title,
    'host_name', v_room.host_name,
    'starts_at', v_room.starts_at,
    'status', public.group_workout_status(v_room),
    'member_count', public.group_workout_member_count(v_room.id),
    'exercises', coalesce((
      select jsonb_agg(jsonb_build_object('name', e ->> 'name', 'movement_id', e ->> 'movement_id') order by ord)
      from jsonb_array_elements(v_room.plan -> 'exercises') with ordinality as x(e, ord)
    ), '[]'::jsonb),
    'paid_only', public.train_together_paid_only()
  );
end;
$$;

create or replace function public.group_workout_join(p_code text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_room public.group_workouts%rowtype;
  v_known boolean;
  v_count integer;
begin
  if v_user is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if (
    select count(*) from public.group_workout_join_attempts a
    where a.user_id = v_user and a.attempted_at > statement_timestamp() - interval '10 minutes'
  ) >= 30 then
    raise exception 'too_many_attempts' using errcode = 'P0001';
  end if;
  insert into public.group_workout_join_attempts (user_id) values (v_user);
  delete from public.group_workout_join_attempts
  where attempted_at < statement_timestamp() - interval '1 day';

  select * into v_room from public.group_workouts g
  where g.code = upper(btrim(coalesce(p_code, '')))
  for update;
  -- Answered rather than raised: a raise would roll back the attempt just
  -- recorded, and wrong guesses would never count against the limit.
  if v_room.id is null then
    return jsonb_build_object('error', 'room_not_found');
  end if;
  if public.group_workout_is_over(v_room) then
    raise exception 'room_ended' using errcode = 'P0001';
  end if;
  if v_room.host_user_id = v_user then
    return public.group_workout_json(v_room, v_user);
  end if;

  select exists (
    select 1 from public.group_workout_members m
    where m.group_workout_id = v_room.id and m.user_id = v_user
  ) into v_known;
  -- Someone already in this room comes back without being asked to pay again.
  if v_known then
    update public.group_workout_members
    set left_at = null
    where group_workout_id = v_room.id and user_id = v_user;
    return public.group_workout_json(v_room, v_user);
  end if;

  if not public.train_together_allowed(v_user) then
    raise exception 'premium_required' using errcode = 'P0001';
  end if;
  select count(*) into v_count from public.group_workout_members m
  where m.group_workout_id = v_room.id;
  if v_count >= v_room.max_members then
    raise exception 'room_full' using errcode = 'P0001';
  end if;
  insert into public.group_workout_members (group_workout_id, user_id, first_name)
  values (v_room.id, v_user, public.train_together_first_name(v_user));
  return public.group_workout_json(v_room, v_user);
end;
$$;

create or replace function public.group_workout_fetch(p_id uuid)
returns jsonb
language plpgsql
stable
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
  select * into v_room from public.group_workouts g where g.id = p_id;
  if v_room.id is null
     or not (v_room.host_user_id = v_user or public.group_workout_is_member(p_id, v_user)) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  return public.group_workout_json(v_room, v_user);
end;
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

create or replace function public.group_workout_set_shared_control(p_id uuid, p_on boolean)
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
  select * into v_room from public.group_workouts g where g.id = p_id for update;
  if v_user is null or v_room.id is null or v_room.host_user_id <> v_user then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if v_room.kind <> 'friends' then
    raise exception 'invalid_kind' using errcode = '22023';
  end if;
  update public.group_workouts
  set shared_control = coalesce(p_on, false), state_version = state_version + 1
  where id = p_id
  returning * into v_room;
  perform realtime.send(
    jsonb_build_object('version', v_room.state_version, 'state', v_room.state, 'shared_control', v_room.shared_control),
    'state', 'group:' || p_id::text, true
  );
  return public.group_workout_json(v_room, v_user);
end;
$$;

create or replace function public.group_workout_leave(p_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  update public.group_workout_members
  set left_at = statement_timestamp()
  where group_workout_id = p_id and user_id = auth.uid() and left_at is null;
end;
$$;

create or replace function public.group_workout_end(p_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_room public.group_workouts%rowtype;
begin
  select * into v_room from public.group_workouts g where g.id = p_id for update;
  if auth.uid() is null or v_room.id is null or v_room.host_user_id <> auth.uid() then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if v_room.status <> 'ended' then
    update public.group_workouts
    set status = 'ended', ended_at = statement_timestamp()
    where id = p_id;
    perform realtime.send('{}'::jsonb, 'ended', 'group:' || p_id::text, true);
  end if;
end;
$$;

-- Names: in a room with friends everyone sees everyone's first name; in a
-- class only the host does, and members get the head count.
create or replace function public.group_workout_roster(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_room public.group_workouts%rowtype;
  v_is_host boolean;
begin
  select * into v_room from public.group_workouts g where g.id = p_id;
  if v_user is null or v_room.id is null then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  v_is_host := v_room.host_user_id = v_user;
  if not v_is_host and not public.group_workout_is_member(p_id, v_user) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'host_user_id', v_room.host_user_id,
    'host_name', v_room.host_name,
    'count', public.group_workout_member_count(p_id),
    'members', case
      when v_is_host or v_room.kind = 'friends' then coalesce((
        select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'first_name', m.first_name) order by m.joined_at)
        from public.group_workout_members m
        where m.group_workout_id = p_id and m.left_at is null
      ), '[]'::jsonb)
      else '[]'::jsonb
    end
  );
end;
$$;

-- Realtime authorization for the private channel "group:<room id>" ---------

create or replace function public.group_workout_topic_room(p_topic text)
returns uuid
language sql
immutable
set search_path = public, pg_temp
as $$
  select case
    when p_topic ~ '^group:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then substr(p_topic, 7)::uuid
  end;
$$;

create or replace function public.group_workout_can_listen(p_topic text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.group_workouts g
    where g.id = public.group_workout_topic_room(p_topic)
      and (g.host_user_id = auth.uid() or public.group_workout_is_member(g.id, auth.uid()))
  );
$$;

-- Only a class host sends broadcasts from the phone (the lobby's synced card).
-- Every state change goes through group_workout_set_state instead.
create or replace function public.group_workout_can_broadcast(p_topic text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.group_workouts g
    where g.id = public.group_workout_topic_room(p_topic)
      and g.host_user_id = auth.uid()
  );
$$;

drop policy if exists "train together members listen" on realtime.messages;
create policy "train together members listen"
  on realtime.messages for select to authenticated
  using (public.group_workout_can_listen(realtime.topic()));

drop policy if exists "train together members send" on realtime.messages;
create policy "train together members send"
  on realtime.messages for insert to authenticated
  with check (
    (realtime.messages.extension = 'presence' and public.group_workout_can_listen(realtime.topic()))
    or (realtime.messages.extension = 'broadcast' and public.group_workout_can_broadcast(realtime.topic()))
  );

-- Grants ------------------------------------------------------------------

revoke all on function public.train_together_paid_only() from public, anon, authenticated;
revoke all on function public.train_together_allowed(uuid) from public, anon, authenticated;
revoke all on function public.train_together_first_name(uuid) from public, anon, authenticated;
revoke all on function public.group_workout_is_over(public.group_workouts) from public, anon, authenticated;
revoke all on function public.group_workout_status(public.group_workouts) from public, anon, authenticated;
revoke all on function public.group_workout_member_count(uuid) from public, anon, authenticated;
revoke all on function public.group_workout_plan_is_valid(jsonb) from public, anon, authenticated;
revoke all on function public.group_workout_state_is_valid(jsonb) from public, anon, authenticated;
revoke all on function public.group_workout_is_member(uuid, uuid) from public, anon, authenticated;
revoke all on function public.group_workout_json(public.group_workouts, uuid) from public, anon, authenticated;
revoke all on function public.group_workout_topic_room(text) from public, anon;
revoke all on function public.group_workout_can_listen(text) from public, anon;
revoke all on function public.group_workout_can_broadcast(text) from public, anon;
grant execute on function public.group_workout_topic_room(text) to authenticated;
grant execute on function public.group_workout_can_listen(text) to authenticated;
grant execute on function public.group_workout_can_broadcast(text) to authenticated;

revoke all on function public.train_together_server_now() from public, anon;
revoke all on function public.train_together_my_access() from public, anon;
revoke all on function public.group_workout_create(text, text, timestamptz, jsonb, jsonb) from public, anon;
revoke all on function public.group_workout_join(text) from public, anon;
revoke all on function public.group_workout_fetch(uuid) from public, anon;
revoke all on function public.group_workout_set_state(uuid, integer, jsonb) from public, anon;
revoke all on function public.group_workout_set_shared_control(uuid, boolean) from public, anon;
revoke all on function public.group_workout_leave(uuid) from public, anon;
revoke all on function public.group_workout_end(uuid) from public, anon;
revoke all on function public.group_workout_roster(uuid) from public, anon;
grant execute on function public.train_together_server_now() to authenticated;
grant execute on function public.train_together_my_access() to authenticated;
grant execute on function public.group_workout_create(text, text, timestamptz, jsonb, jsonb) to authenticated;
grant execute on function public.group_workout_join(text) to authenticated;
grant execute on function public.group_workout_fetch(uuid) to authenticated;
grant execute on function public.group_workout_set_state(uuid, integer, jsonb) to authenticated;
grant execute on function public.group_workout_set_shared_control(uuid, boolean) to authenticated;
grant execute on function public.group_workout_leave(uuid) to authenticated;
grant execute on function public.group_workout_end(uuid) to authenticated;
grant execute on function public.group_workout_roster(uuid) to authenticated;

revoke all on function public.group_workout_preview(text) from public;
grant execute on function public.group_workout_preview(text) to anon, authenticated;

notify pgrst, 'reload schema';
