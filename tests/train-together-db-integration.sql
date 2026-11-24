-- Train together rooms, access and the paid switch. Everything rolls back.
begin;

create temporary table tt_users(label text primary key, id uuid not null) on commit drop;
insert into tt_users values
  ('host', 'a1111111-1111-4111-8111-111111111111'),
  ('friend', 'b2222222-2222-4222-8222-222222222222'),
  ('locked', 'c3333333-3333-4333-8333-333333333333'),
  ('coach', 'd4444444-4444-4444-8444-444444444444'),
  ('client', 'e5555555-5555-4555-8555-555555555555'),
  ('devclient', 'f6666666-6666-4666-8666-666666666666'),
  ('devcoach', 'a7777777-7777-4777-8777-777777777777'),
  ('founder', 'b8888888-8888-4888-8888-888888888888'),
  ('payer', 'c9999999-9999-4999-8999-999999999999');
insert into tt_users
select 'crowd' || n, ('0a000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
from generate_series(1, 9) as n;

insert into auth.users(id, email)
select id, label || '@train-together.invalid' from tt_users;
insert into public.profile(id, user_id, display_name)
select gen_random_uuid(), id, initcap(label) || ' Example' from tt_users;

update public.account_entitlements set state = 'locked'
where user_id = (select id from tt_users where label = 'locked');
update public.account_entitlements set source = 'founding', expires_at = null
where user_id = (select id from tt_users where label = 'founder');
update public.account_entitlements set source = 'app_store'
where user_id = (select id from tt_users where label = 'payer');
insert into public.coach_profiles(user_id, display_name, status)
select id, 'Coach Example', 'active' from tt_users where label = 'coach';
insert into public.coach_profiles(user_id, display_name, status)
select id, 'Dev Coach', 'development' from tt_users where label = 'devcoach';
insert into public.coach_relationships(coach_user_id, client_user_id, offered_scopes, consented_scopes)
select (select id from tt_users where label = 'coach'), (select id from tt_users where label = 'client'),
       array['workouts'], array['workouts'];
insert into public.coach_relationships(coach_user_id, client_user_id, offered_scopes, consented_scopes)
select (select id from tt_users where label = 'devcoach'), (select id from tt_users where label = 'devclient'),
       array['workouts'], array['workouts'];

create or replace function pg_temp.act_as(p_label text) returns void language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', (select id from tt_users where label = p_label), 'role', 'authenticated')::text,
    true
  ), set_config('request.jwt.claim.sub', (select id::text from tt_users where label = p_label), true);
$$;

create or replace function pg_temp.fails(p_sql text, p_message text) returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  if sqlerrm <> p_message then
    raise exception 'expected "%" from %, got "%"', p_message, p_sql, sqlerrm;
  end if;
  return true;
end;
$$;

-- The room rule agrees with get_my_app_access for every account.
do $$
declare
  r record;
  envelope record;
begin
  for r in select user_id from public.account_entitlements loop
    perform set_config('request.jwt.claims', json_build_object('sub', r.user_id, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', r.user_id::text, true);
    select * into envelope from public.get_my_app_access('ios', 100000);
    if (envelope.state = 'granted' or envelope.sponsored_seat_active)
       is distinct from public.train_together_allowed(r.user_id) then
      raise exception 'train_together_allowed (switch off) disagrees with get_my_app_access for %', r.user_id;
    end if;
  end loop;
end$$;

do $$
declare
  plan jsonb := '{"name":"Full body","exercises":[{"name":"Goblet squat","movement_id":"goblet-squat","sets":3,"rep_min":8,"rep_max":12,"rest_sec":60}]}';
  lobby jsonb := '{"phase":"lobby","position":0,"step":0,"extra_seconds":0,"sound":true,"voice":false,"anchor":"2026-11-23T12:00:00.000Z"}';
  work jsonb := '{"phase":"work","position":0,"step":1,"extra_seconds":0,"sound":true,"voice":false,"anchor":"2026-11-23T12:00:05.000Z"}';
  room jsonb;
  class_room jsonb;
  reply jsonb;
begin
  -- Switch off: anyone the app lets in may host and join.
  if public.train_together_paid_only() then raise exception 'switch must start off'; end if;
  perform pg_temp.act_as('host');
  if not (public.train_together_my_access() ->> 'allowed')::boolean then raise exception 'host should be allowed in the beta'; end if;
  room := public.group_workout_create('friends', 'Push day', now(), plan, lobby);
  if room ->> 'code' !~ '^[A-HJKMNP-Z2-9]{6}$' then raise exception 'bad code %', room ->> 'code'; end if;
  if not (room ->> 'shared_control')::boolean then raise exception 'friends rooms share control'; end if;
  if room ->> 'host_name' <> 'Host' then raise exception 'host first name, got %', room ->> 'host_name'; end if;
  perform set_config('tt.room', room ->> 'id', true);
  perform set_config('tt.code', room ->> 'code', true);

  perform pg_temp.act_as('locked');
  if not pg_temp.fails(format('select public.group_workout_join(%L)', room ->> 'code'), 'premium_required') then
    raise exception 'a locked account joined';
  end if;
  if not pg_temp.fails($q$select public.group_workout_create('friends', 'x', now(), '{"exercises":[{}]}', '{}')$q$, 'premium_required') then
    raise exception 'a locked account hosted';
  end if;
  perform pg_temp.act_as('friend');
  if (public.group_workout_join('ZZZZZZ') ->> 'error') <> 'room_not_found' then
    raise exception 'a wrong code must be answered, not raised';
  end if;
  if (select count(*) from public.group_workout_join_attempts where user_id = (select id from tt_users where label = 'friend')) <> 1 then
    raise exception 'a wrong code must count against the join limit';
  end if;
  perform pg_temp.act_as('host');
  if not pg_temp.fails(format('select public.group_workout_set_state(%L::uuid, 1, %L::jsonb)', room ->> 'id', work || '{"extra_seconds":9223372036854775807}'), 'invalid_state') then
    raise exception 'an out-of-range state was stored';
  end if;
  if not pg_temp.fails($q$select public.group_workout_create('friends', 'x', now(), '{"exercises":[{"name":"x","sets":1000000000000000,"rep_min":1,"rep_max":1,"rest_sec":1}]}', '{}')$q$, 'invalid_plan') then
    raise exception 'an out-of-range plan was stored';
  end if;

  perform pg_temp.act_as('friend');
  reply := public.group_workout_join(lower(room ->> 'code'));
  if (reply ->> 'is_host')::boolean or (reply ->> 'member_count')::int <> 1 then raise exception 'friend join %', reply; end if;
  if not public.group_workout_can_listen('group:' || (room ->> 'id')) then raise exception 'member cannot listen'; end if;
  if public.group_workout_can_broadcast('group:' || (room ->> 'id')) then raise exception 'member can broadcast'; end if;
  reply := public.group_workout_set_state((room ->> 'id')::uuid, 1, work);
  if not (reply ->> 'accepted')::boolean or (reply ->> 'version')::int <> 2 then raise exception 'shared control write %', reply; end if;
  reply := public.group_workout_set_state((room ->> 'id')::uuid, 1, work || '{"phase":"rest"}');
  if (reply ->> 'accepted')::boolean or reply -> 'state' ->> 'phase' <> 'work' then raise exception 'stale press must lose %', reply; end if;
  if (public.group_workout_roster((room ->> 'id')::uuid) -> 'members' -> 0 ->> 'first_name') <> 'Friend' then
    raise exception 'friends see first names';
  end if;

  perform pg_temp.act_as('host');
  perform public.group_workout_set_shared_control((room ->> 'id')::uuid, false);
  perform pg_temp.act_as('friend');
  if not pg_temp.fails(format('select public.group_workout_set_state(%L::uuid, 3, %L::jsonb)', room ->> 'id', work), 'not_allowed') then
    raise exception 'a member controlled a room set to only the host';
  end if;

  perform pg_temp.act_as('payer');
  if public.group_workout_can_listen('group:' || (room ->> 'id')) then raise exception 'outsider can listen'; end if;

  -- Ten people at most in a room with friends: the host and nine.
  for n in 2..8 loop
    perform pg_temp.act_as('crowd' || n);
    perform public.group_workout_join(room ->> 'code');
  end loop;
  perform pg_temp.act_as('crowd9');
  perform public.group_workout_join(room ->> 'code');
  perform pg_temp.act_as('crowd1');
  if not pg_temp.fails(format('select public.group_workout_join(%L)', room ->> 'code'), 'room_full') then
    raise exception 'an eleventh person joined';
  end if;

  -- A class: only a coach hosts it, only the host controls it, members see a count.
  perform pg_temp.act_as('host');
  if not pg_temp.fails($q$select public.group_workout_create('class', 'Class', now(), '{"exercises":[{}]}', '{}')$q$, 'class_not_allowed') then
    raise exception 'a non-coach hosted a class';
  end if;
  perform pg_temp.act_as('coach');
  class_room := public.group_workout_create('class', 'Tuesday class', now() + interval '1 day', plan, lobby);
  if (class_room ->> 'shared_control')::boolean or class_room ->> 'host_name' <> 'Coach Example' then raise exception 'class room %', class_room; end if;
  perform set_config('tt.class', class_room ->> 'id', true);
  perform set_config('tt.class_code', class_room ->> 'code', true);
  if not public.group_workout_can_broadcast('group:' || (class_room ->> 'id')) then raise exception 'host cannot broadcast'; end if;
  perform pg_temp.act_as('friend');
  perform public.group_workout_join(class_room ->> 'code');
  if not pg_temp.fails(format('select public.group_workout_set_state(%L::uuid, 1, %L::jsonb)', class_room ->> 'id', work), 'not_allowed') then
    raise exception 'a class member controlled the class';
  end if;
  if jsonb_array_length(public.group_workout_roster((class_room ->> 'id')::uuid) -> 'members') <> 0 then
    raise exception 'class members must not see names';
  end if;
  perform pg_temp.act_as('coach');
  if jsonb_array_length(public.group_workout_roster((class_room ->> 'id')::uuid) -> 'members') <> 1 then
    raise exception 'the class host sees names';
  end if;
end$$;

-- Switch on: only paid accounts get in, and anyone already inside stays in.
update public.feature_access_policy set paid_only = true where feature = 'train_together';
do $$
declare
  code text := current_setting('tt.class_code');
begin
  perform pg_temp.act_as('crowd1');
  if (public.train_together_my_access() ->> 'allowed')::boolean then raise exception 'the TestFlight grant counted as paid'; end if;
  if not pg_temp.fails(format('select public.group_workout_join(%L)', code), 'premium_required') then
    raise exception 'an unpaid account joined';
  end if;
  perform pg_temp.act_as('devclient');
  if not pg_temp.fails(format('select public.group_workout_join(%L)', code), 'premium_required') then
    raise exception 'a client of a development coach counted as paid';
  end if;
  -- A client of an active coach, a founding account, an App Store subscriber,
  -- and someone who was already in the room before the switch.
  perform pg_temp.act_as('client');
  perform public.group_workout_join(code);
  perform pg_temp.act_as('founder');
  perform public.group_workout_join(code);
  perform pg_temp.act_as('payer');
  perform public.group_workout_join(code);
  perform pg_temp.act_as('friend');
  perform public.group_workout_join(code);
  perform pg_temp.act_as('host');
  if not pg_temp.fails($q$select public.group_workout_create('friends', 'x', now(), '{"exercises":[{}]}', '{}')$q$, 'premium_required') then
    raise exception 'an unpaid account hosted';
  end if;
  if (public.group_workout_preview(code) ->> 'paid_only')::boolean is not true then raise exception 'preview must show the switch'; end if;
end$$;

-- Ending a room closes it for everyone, including those already inside.
do $$
begin
  perform pg_temp.act_as('coach');
  perform public.group_workout_end(current_setting('tt.class')::uuid);
  perform pg_temp.act_as('friend');
  if not pg_temp.fails(format('select public.group_workout_join(%L)', current_setting('tt.class_code')), 'room_ended') then
    raise exception 'joined an ended room';
  end if;
end$$;

do $$
begin
  if has_function_privilege('anon', 'public.group_workout_join(text)', 'execute') then raise exception 'anon can join'; end if;
  if not has_function_privilege('anon', 'public.group_workout_preview(text)', 'execute') then raise exception 'anon cannot preview'; end if;
  if has_function_privilege('authenticated', 'public.train_together_allowed(uuid)', 'execute') then raise exception 'paid rule is callable'; end if;
  if has_table_privilege('authenticated', 'public.group_workouts', 'select') then raise exception 'rooms readable'; end if;
end$$;

-- A room opened without a workout: it cannot start, its wheel is bounded,
-- and the host chooses the workout once.
do $$
declare
  lobby jsonb := '{"phase":"lobby","position":0,"step":0,"extra_seconds":0,"sound":true,"voice":false,"anchor":"2026-11-24T08:00:00.000Z"}';
  plan jsonb := '{"name":"Push-up ladder","warmup_text":"","warmup_duration":180,"exercises":[{"name":"Push-Up","movement_id":"push_up","sets":3,"rep_min":10,"rep_max":10,"rest_sec":60}]}';
  room jsonb;
  reply jsonb;
begin
  update public.feature_access_policy set paid_only = false where feature = 'train_together';
  perform pg_temp.act_as('founder');
  room := public.group_workout_create('friends', 'Group workout', now(), '{"name":"Group workout","exercises":[]}', lobby);
  if jsonb_array_length(room -> 'plan' -> 'exercises') <> 0 then raise exception 'room should open without a workout'; end if;
  if not pg_temp.fails(format('select public.group_workout_set_state(%L::uuid, 1, %L::jsonb)', room ->> 'id',
      lobby || '{"phase":"warmup","step":1}'), 'invalid_state') then
    raise exception 'a room without a workout started';
  end if;
  reply := public.group_workout_set_state((room ->> 'id')::uuid, 1, lobby || '{"wheel":{"focus":"push","spin":{"at":"2026-11-24T08:01:00.000Z","slots":["push-up-ladder","shoulder-burner"],"landing":1}}}');
  if not (reply ->> 'accepted')::boolean or reply -> 'state' -> 'wheel' ->> 'focus' <> 'push' then raise exception 'spin refused %', reply; end if;
  if not pg_temp.fails(format('select public.group_workout_set_state(%L::uuid, 2, %L::jsonb)', room ->> 'id',
      lobby || '{"wheel":{"focus":"push","spin":{"at":"2026-11-24T08:01:00.000Z","slots":["a"],"landing":3}}}'), 'invalid_state') then
    raise exception 'a landing outside the wheel was stored';
  end if;
  if not pg_temp.fails(format('select public.group_workout_set_state(%L::uuid, 2, %L::jsonb)', room ->> 'id',
      lobby || '{"wheel":{"focus":"legs"}}'), 'invalid_state') then
    raise exception 'an unknown focus was stored';
  end if;
  perform pg_temp.act_as('payer');
  perform public.group_workout_join(room ->> 'code');
  if not pg_temp.fails(format('select public.group_workout_set_plan(%L::uuid, %L::jsonb)', room ->> 'id', plan), 'not_allowed') then
    raise exception 'a member chose the workout';
  end if;
  perform pg_temp.act_as('founder');
  if not pg_temp.fails(format('select public.group_workout_set_plan(%L::uuid, %L::jsonb)', room ->> 'id',
      '{"name":"x","exercises":[]}'), 'invalid_plan') then
    raise exception 'an empty workout was chosen';
  end if;
  reply := public.group_workout_set_plan((room ->> 'id')::uuid, plan);
  if reply ->> 'title' <> 'Push-up ladder' or jsonb_array_length(reply -> 'plan' -> 'exercises') <> 1
     or reply -> 'state' ? 'wheel' or (reply ->> 'version')::int <> 3 then
    raise exception 'choosing the workout %', reply;
  end if;
  if not pg_temp.fails(format('select public.group_workout_set_plan(%L::uuid, %L::jsonb)', room ->> 'id', plan), 'plan_chosen') then
    raise exception 'the workout was chosen twice';
  end if;
  reply := public.group_workout_set_state((room ->> 'id')::uuid, 3, lobby || '{"phase":"warmup","step":1}');
  if not (reply ->> 'accepted')::boolean then raise exception 'the chosen workout did not start %', reply; end if;
  if (public.group_workout_preview(room ->> 'code') ->> 'title') <> 'Push-up ladder' then raise exception 'preview title'; end if;
end$$;

-- Hardening: validators answer false, an older phone's switch keeps the wheel,
-- and a room leaves its lobby only into its warm-up or first set.
do $$
declare
  lobby jsonb := '{"phase":"lobby","position":0,"step":0,"extra_seconds":0,"sound":true,"voice":false,"anchor":"2026-11-24T08:00:00.000Z"}';
  plan jsonb := '{"name":"Push-up ladder","warmup_text":"","warmup_duration":180,"exercises":[{"name":"Push-Up","sets":3,"rep_min":10,"rep_max":10,"rest_sec":60},{"name":"Plank","sets":3,"rep_min":30,"rep_max":30,"rest_sec":30}]}';
  room jsonb;
  reply jsonb;
begin
  if public.group_workout_state_is_valid(lobby - 'sound') is distinct from false then raise exception 'a state missing sound must be false'; end if;
  if public.group_workout_state_is_valid(lobby || '{"wheel":{}}') is distinct from false then raise exception 'an empty wheel must be false'; end if;
  if public.group_workout_plan_is_valid('{"name":"x"}') is distinct from false then raise exception 'a plan without exercises must be false'; end if;
  perform pg_temp.act_as('founder');
  room := public.group_workout_create('friends', 'Group workout', now(), '{"name":"Group workout","exercises":[]}', lobby);
  if not pg_temp.fails(format('select public.group_workout_set_state(%L::uuid, 1, %L::jsonb)', room ->> 'id', lobby - 'sound'), 'invalid_state') then
    raise exception 'a state without sound was stored';
  end if;
  reply := public.group_workout_set_state((room ->> 'id')::uuid, 1, lobby || '{"wheel":{"focus":"pull"}}');
  reply := public.group_workout_set_state((room ->> 'id')::uuid, 2, lobby || '{"sound":false}');
  if reply -> 'state' -> 'wheel' ->> 'focus' is distinct from 'pull' then raise exception 'the wheel was wiped %', reply; end if;
  reply := public.group_workout_set_plan((room ->> 'id')::uuid, plan);
  if not pg_temp.fails(format('select public.group_workout_set_state(%L::uuid, 4, %L::jsonb)', room ->> 'id',
      lobby || '{"phase":"review","step":1}'), 'invalid_state') then
    raise exception 'an older phone started the room at its end';
  end if;
  reply := public.group_workout_set_state((room ->> 'id')::uuid, 4, lobby || '{"phase":"warmup","step":1}');
  if not (reply ->> 'accepted')::boolean then raise exception 'the warm-up start was refused'; end if;
end$$;

select 'train together checks passed' as result;
rollback;
