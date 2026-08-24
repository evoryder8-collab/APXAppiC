-- Restore the owner-supplied June V8 and Constantine V8.3 plans without
-- changing seed defaults for any other account. This is intentionally a
-- maintenance transaction, not an automatically-applied migration.
begin;

do $restore$
declare
  constantine_user constant uuid := '9a0fffbc-bb02-40ac-834a-d4e339b32574';
  june_user constant uuid := 'f1cc8158-0480-47c9-a2f1-bd03890182f9';
  constantine_main constant uuid := '11111111-0000-4000-8000-000000000002';
  june_main constant uuid := 'c56fa7ce-bee6-4e09-b431-2d0568aeb493';
  constantine_archive_program uuid;
  june_archive_program uuid;
  other_programs_before text;
  other_days_before text;
  other_exercises_before text;
  target_sessions_before text;
  target_logs_before text;
begin
  if (select count(*) from public.profile where user_id = constantine_user and persona = 'constantine') <> 1 then
    raise exception 'Constantine account identity is not unique';
  end if;
  if (select count(*) from public.profile where user_id = june_user and persona = 'june') <> 1 then
    raise exception 'June account identity is not unique';
  end if;
  if not exists (select 1 from public.programs where id = constantine_main and user_id = constantine_user and slug = 'main') then
    raise exception 'Constantine main programme slot is missing';
  end if;
  if not exists (select 1 from public.programs where id = june_main and user_id = june_user and slug = 'main') then
    raise exception 'June main programme slot is missing';
  end if;

  select md5(coalesce(string_agg(to_jsonb(p)::text, '|' order by p.id), ''))
    into other_programs_before
    from public.programs p where p.user_id not in (constantine_user, june_user);
  select md5(coalesce(string_agg(to_jsonb(d)::text, '|' order by d.id), ''))
    into other_days_before
    from public.program_days d where d.user_id not in (constantine_user, june_user);
  select md5(coalesce(string_agg(to_jsonb(e)::text, '|' order by e.id), ''))
    into other_exercises_before
    from public.exercises e where e.user_id not in (constantine_user, june_user);
  select md5(coalesce(string_agg(to_jsonb(s)::text, '|' order by s.id), ''))
    into target_sessions_before
    from public.workout_sessions s where s.user_id in (constantine_user, june_user);
  select md5(coalesce(string_agg(to_jsonb(l)::text, '|' order by l.id), ''))
    into target_logs_before
    from public.workout_logs l where l.user_id in (constantine_user, june_user);

  -- Generic questionnaire state must not hide bespoke account programmes.
  update public.settings
  set addons = jsonb_set(
    addons - 'training_induction',
    '{training_protocol}',
    coalesce(addons -> 'training_protocol', '{}'::jsonb) || jsonb_build_object('version', 83),
    true
  )
  where user_id = constantine_user;

  update public.settings
  set addons = jsonb_set(
    addons - 'training_induction',
    '{training_protocol}',
    coalesce(addons -> 'training_protocol', '{}'::jsonb) || jsonb_build_object('version', 80),
    true
  )
  where user_id = june_user;

  update public.programs
  set name = 'Constantin Training V8.3',
      description = '12-week home strength and Focus T25 plan for leg growth, push-up performance, first pull-ups, conditioning and filming resilience.'
  where id = constantine_main and user_id = constantine_user;

  update public.programs
  set name = 'June Glute Training V8',
      description = '12-week home plan with two glute-focused strength days, three Focus T25 slots and occupational recovery.'
  where id = june_main and user_id = june_user;

  -- Keep obsolete definitions referenced by workout history, but move them out
  -- of the selectable main programme instead of nulling historical FKs.
  insert into public.programs (id, user_id, slug, name, description)
  values ('83000000-0000-4000-8000-000000000010', constantine_user, 'history-archive', 'Workout history archive', 'Non-selectable definitions retained for historical workout-log integrity.')
  on conflict (user_id, slug) do update set name = excluded.name, description = excluded.description
  returning id into constantine_archive_program;

  insert into public.programs (id, user_id, slug, name, description)
  values ('80000000-0000-4000-8000-000000000010', june_user, 'history-archive', 'Workout history archive', 'Non-selectable definitions retained for historical workout-log integrity.')
  on conflict (user_id, slug) do update set name = excluded.name, description = excluded.description
  returning id into june_archive_program;

  insert into public.program_days (id, user_id, program_id, weekday, name, day_type, est_minutes, warmup_note, sort_order, session_mode)
  values ('83000000-0000-4000-8000-000000000011', constantine_user, constantine_archive_program, 0, 'Archived definitions', 'mobility', 0, '', 999, 'tracked')
  on conflict (id) do update set program_id = excluded.program_id, user_id = excluded.user_id;

  insert into public.program_days (id, user_id, program_id, weekday, name, day_type, est_minutes, warmup_note, sort_order, session_mode)
  values ('80000000-0000-4000-8000-000000000011', june_user, june_archive_program, 0, 'Archived definitions', 'mobility', 0, '', 999, 'tracked')
  on conflict (id) do update set program_id = excluded.program_id, user_id = excluded.user_id;

  update public.exercises
  set program_day_id = '83000000-0000-4000-8000-000000000011'
  where user_id = constantine_user and id = '11111111-0000-4000-8000-000000000097';

  update public.exercises
  set program_day_id = '80000000-0000-4000-8000-000000000011'
  where user_id = june_user and id in (
    '473300c8-50e3-4aa1-a8b8-42e0e2b8aef7',
    '01259233-e78b-411d-a24f-7e0c7d1d2c39'
  );

  -- Delete only interrupted-induction days that have never held a session or
  -- an exercise. The seven historical bespoke day IDs remain unchanged.
  if exists (
    select 1 from public.workout_sessions where program_day_id in (
      '05f05857-68b4-4dab-aceb-290a3e7ff506',
      '0d927331-7826-425d-9315-71d426a2451f',
      '11111111-0000-4000-8000-000000000084'
    )
  ) or exists (
    select 1 from public.exercises where program_day_id in (
      '05f05857-68b4-4dab-aceb-290a3e7ff506',
      '0d927331-7826-425d-9315-71d426a2451f',
      '11111111-0000-4000-8000-000000000084'
    )
  ) then
    raise exception 'Refusing to delete a generated day that has history';
  end if;

  delete from public.program_days
  where user_id = constantine_user and id in (
    '05f05857-68b4-4dab-aceb-290a3e7ff506',
    '0d927331-7826-425d-9315-71d426a2451f',
    '11111111-0000-4000-8000-000000000084'
  );

  update public.program_days d
  set weekday = v.weekday,
      name = v.name,
      day_type = v.day_type,
      est_minutes = v.est_minutes,
      warmup_note = v.warmup_note,
      sort_order = v.weekday - 1
  from (values
    ('11111111-0000-4000-8000-000000000052'::uuid, 1, 'Legs A · heavy base', 'legs_a', 45, '8 bodyweight split squats per side, 10 slow hinges and 10 ankle rocks per side.'),
    ('11111111-0000-4000-8000-000000000062'::uuid, 2, 'Push A · rep capacity + Focus T25', 'push', 45, '15 band pull-aparts and 2 sets of 8 scapular push-ups.'),
    ('11111111-0000-4000-8000-000000000069'::uuid, 3, 'Pull A + gimbal capacity + Focus T25', 'pull', 55, '15 pull-aparts and 2 sets of 6 scapular pulldowns. Optional pain-free dead hang: 2 x 20-30 seconds.'),
    ('11111111-0000-4000-8000-000000000077'::uuid, 4, 'Recovery + posture', 'mobility', 33, 'No loaded warm-up. Focus T25 Stretch is recovery, not a flexibility test.'),
    ('52429d97-dea9-49af-b4bc-f678ad447417'::uuid, 5, 'Legs B · lunge day + Focus T25', 'legs_b', 60, '6 reverse lunges per side, 10 hinges and 10 ankle rocks per side.'),
    ('11111111-0000-4000-8000-000000000095'::uuid, 6, 'Push B · weighted strength', 'push', 25, '15 band pull-aparts and 2 sets of 6 easy push-ups.'),
    ('11111111-0000-4000-8000-000000000102'::uuid, 7, 'Pull B · filming resilience', 'pull', 30, 'If a hard ride longer than 60 minutes falls on the weekend, use only 2 sets each of chin-ups and rows.')
  ) as v(id, weekday, name, day_type, est_minutes, warmup_note)
  where d.id = v.id and d.user_id = constantine_user and d.program_id = constantine_main;

  update public.program_days d
  set weekday = v.weekday,
      name = v.name,
      day_type = v.day_type,
      est_minutes = v.est_minutes,
      warmup_note = v.warmup_note,
      sort_order = v.weekday - 1
  from (values
    ('7e4651e2-59cf-4ef4-b89b-7a451a8c220b'::uuid, 1, 'Glutes A · heavy tension', 'legs_a', 45, '8 bodyweight glute bridges, 6 reverse lunges per side and 10 slow hinges.'),
    ('411f4f19-12bf-41ec-aec1-229fe8712603'::uuid, 2, 'Push A · capacity + Focus T25', 'push', 43, '15 band pull-aparts and 2 sets of 8 scapular push-ups.'),
    ('1cb7f1d2-ce9d-4c51-b33b-43a6be21e3a0'::uuid, 3, 'Pull A + Focus T25', 'pull', 55, 'Scapular pull-ups, band rows and one easy assisted pull-up set.'),
    ('c0612b35-da03-4b4d-8410-16e570bc71c9'::uuid, 4, 'Recovery + massage-worker posture', 'mobility', 33, 'No loaded warm-up. Focus T25 Stretch is recovery, not a flexibility test.'),
    ('59a496e3-3cda-4d73-806a-b940eace1878'::uuid, 5, 'Glutes B', 'legs_b', 45, '6 reverse lunges per side, 10 hinges and 10 ankle rocks per side.'),
    ('808d17fa-4b8f-4550-8e9c-1379e0fc677d'::uuid, 6, 'Push B', 'push', 22, '15 band pull-aparts and 2 sets of 6 easy push-ups.'),
    ('fa9ea127-023a-4e10-b48d-5eed854deacc'::uuid, 7, 'Full rest · optional walk', 'mobility', 0, '')
  ) as v(id, weekday, name, day_type, est_minutes, warmup_note)
  where d.id = v.id and d.user_id = june_user and d.program_id = june_main;

  -- Remove unlogged duplicate definitions left by interrupted seed repair.
  if exists (
    select 1 from public.workout_logs where exercise_id in (
      '8c6750eb-eed8-488c-a561-a257229f1032',
      'aef994c2-e6a8-4287-8f81-47a76c3fceca',
      '755b6733-2b60-448a-bcdd-9bf4aa88ea6b',
      '515334cc-2a3b-4158-b057-5167bde8b06d',
      'd01a21b7-225c-452d-8fc7-2c1038a32ecb',
      '4338acf5-1cd9-43e2-9316-abb463fe7435',
      '11111111-0000-4000-8000-000000000101'
    )
  ) then
    raise exception 'Refusing to delete a duplicate exercise referenced by history';
  end if;

  delete from public.exercises where id in (
    '8c6750eb-eed8-488c-a561-a257229f1032',
    'aef994c2-e6a8-4287-8f81-47a76c3fceca',
    '755b6733-2b60-448a-bcdd-9bf4aa88ea6b',
    '515334cc-2a3b-4158-b057-5167bde8b06d',
    'd01a21b7-225c-452d-8fc7-2c1038a32ecb',
    '4338acf5-1cd9-43e2-9316-abb463fe7435',
    '11111111-0000-4000-8000-000000000101'
  );

  -- June V8 full prescription. Existing IDs are retained for logged rows.
  update public.exercises e
  set name = v.name, sets = v.sets, rep_min = v.rep_min, rep_max = v.rep_max,
      rep_unit = v.rep_unit, per_side = v.per_side, rest_sec = v.rest_sec,
      notes = v.notes, increment_kg = v.increment_kg, optional = false,
      sort_order = v.sort_order, movement_id = v.movement_id,
      is_lite = false, work_group_id = null, work_group_position = null
  from (values
    ('5243eb0d-ad88-45e8-b7dd-7f98a2f9f339'::uuid, 'Dumbbell Hip Thrust', 4, 6, 10, 'reps', false, 120, 'V8: use 90-120 seconds rest; finish with a controlled lockout.', 2::numeric, 0, 'hip_thrust_dumbbell'),
    ('0b86e50d-6d21-4d8a-afd5-ec44ae45d13a'::uuid, 'Bulgarian Split Squat', 3, 8, 12, 'reps', true, 120, 'V8: use 90-120 seconds rest per leg; keep a stable front foot.', 2::numeric, 1, 'bulgarian_split_squat'),
    ('70f50bae-8f27-49b9-b18c-fa6f8f4fca13'::uuid, 'Dumbbell Romanian Deadlift', 3, 8, 12, 'reps', false, 120, 'V8: use 90-120 seconds rest; stop where hamstrings, not the lower back, limit range.', 2::numeric, 2, 'dumbbell_romanian_deadlift'),
    ('29936504-1b6b-4b1c-96fe-473067453c1a'::uuid, 'Band Abduction', 2, 15, 25, 'reps', false, 60, 'V8: use 45-60 seconds rest.', 0::numeric, 3, 'hip_abduction'),
    ('0b2a8b8b-f0d5-4450-af17-f8488c80640b'::uuid, 'Strict Push-Up', 3, 10, 15, 'reps', false, 90, 'Stop with 1-2 clean repetitions in reserve.', 0::numeric, 0, 'push_up'),
    ('55797d5e-050c-4cc2-ad8c-a2c859e69cfe'::uuid, 'Diamond or Close-Grip Push-Up', 2, 8, 15, 'reps', false, 90, 'V8 prescribes 1-2 sets; use knees or an incline before full-range quality breaks.', 0::numeric, 1, 'diamond_push_up'),
    ('9a976990-60bd-4c71-afeb-8f03221936b9'::uuid, 'Focus T25 · Tuesday core', 1, 1, 1, 'check', false, 0, 'Episode follows the 12-week V8 map.', 0::numeric, 2, null::text),
    ('f3c00cfb-abac-407c-ac45-0923129fac0e'::uuid, 'Band-Assisted Pull-Up', 3, 4, 8, 'reps', false, 120, 'Use a band that leaves controlled reps in reserve; no kip.', 0::numeric, 0, 'band_assisted_pull_up'),
    ('976be07a-793f-49d7-a50c-f932dd6ff772'::uuid, 'Chest-Supported Dumbbell Row', 3, 8, 12, 'reps', false, 90, 'Keep the chest supported so the mid-back remains the limiter.', 2::numeric, 1, 'chest_supported_row'),
    ('de2b24bb-ed7b-498d-abf3-19cda69c7495'::uuid, 'Band Face Pull', 2, 15, 20, 'reps', false, 60, 'Smooth external rotation; no neck shrug.', 0::numeric, 2, 'band_face_pull'),
    ('7d47e773-9177-4316-8e24-5c4cee2d2c75'::uuid, 'Focus T25 · Wednesday lower and speed', 1, 1, 1, 'check', false, 0, 'Episode follows the 12-week V8 map.', 0::numeric, 3, null::text),
    ('30cd5121-4432-473e-8217-829be50e978f'::uuid, 'Focus T25 · Stretch', 1, 1, 1, 'check', false, 0, '25 minutes; treat this as recovery, not a flexibility test.', 0::numeric, 0, null::text),
    ('cb85518d-b52b-4328-b71c-42af60399c7c'::uuid, 'Bird-Dog', 2, 6, 6, 'reps', true, 0, 'Two circuit rounds with a 3-second pause.', 0::numeric, 1, 'bird_dog'),
    ('cc976974-2f40-43f8-8431-2f852d5aff56'::uuid, 'Wall Slide', 2, 10, 10, 'reps', false, 0, 'Two circuit rounds.', 0::numeric, 2, 'wall_slide'),
    ('3db89b53-c880-4168-a2cc-b6584ba4e3b0'::uuid, 'Band Pull-Apart', 2, 15, 15, 'reps', false, 0, 'Two circuit rounds.', 0::numeric, 3, 'band_pull_apart'),
    ('674d5e81-e87c-4e39-885a-3971c1e9eb79'::uuid, 'Wrist Extensor Isometric', 2, 20, 20, 'seconds', true, 0, 'Two circuit rounds; 20 seconds per side.', 0::numeric, 4, null::text),
    ('7a908887-e3bc-4410-9c8b-4d33e87576f3'::uuid, 'Reverse Lunge', 3, 8, 12, 'reps', true, 120, 'Use 90-120 seconds rest per leg.', 2::numeric, 0, 'reverse_lunge'),
    ('2ea1361e-b0fa-4d56-bbfb-820c632effb5'::uuid, 'B-Stance or Single-Leg Hip Thrust', 3, 8, 12, 'reps', true, 90, 'Choose one stable variation and keep it consistent for progression.', 2::numeric, 1, 'b_stance_hip_thrust'),
    ('8af7748d-0465-4507-b1d7-b27ea07dc9ed'::uuid, 'Sliding Leg Curl', 3, 10, 15, 'reps', false, 90, 'Keep hips lifted; shorten range before form breaks.', 0::numeric, 2, 'sliding_leg_curl'),
    ('17648217-685d-49b8-9485-c8a3649b317c'::uuid, 'Frog Pump', 1, 25, 35, 'reps', false, 60, 'Controlled glute finisher.', 0::numeric, 3, 'frog_pump'),
    ('33929745-cac1-4da5-889a-655da8a7c670'::uuid, 'Weighted or Feet-Elevated Push-Up', 3, 6, 10, 'reps', false, 120, 'Use one progression consistently and stop with 1-2 clean reps available.', 2::numeric, 0, 'weighted_push_up'),
    ('7af12750-c115-4b9e-897d-67e4f17e6cc9'::uuid, 'Dumbbell Overhead Press', 2, 8, 12, 'reps', false, 90, 'Controlled range; stop before shoulder irritation.', 2::numeric, 1, 'dumbbell_overhead_press'),
    ('86e19e43-55f2-4fc2-abda-dc4c436e3342'::uuid, 'Band Row', 2, 12, 15, 'reps', false, 60, 'Keep the torso quiet and finish with the shoulder blades.', 0::numeric, 2, 'band_row')
  ) as v(id, name, sets, rep_min, rep_max, rep_unit, per_side, rest_sec, notes, increment_kg, sort_order, movement_id)
  where e.id = v.id and e.user_id = june_user;

  -- Constantine V8.3 full prescription.
  update public.exercises e
  set name = v.name, sets = v.sets, rep_min = v.rep_min, rep_max = v.rep_max,
      rep_unit = v.rep_unit, per_side = v.per_side, rest_sec = v.rest_sec,
      notes = v.notes, increment_kg = v.increment_kg, optional = false,
      sort_order = v.sort_order, movement_id = v.movement_id,
      is_lite = false, work_group_id = null, work_group_position = null
  from (values
    ('11111111-0000-4000-8000-000000000053'::uuid, 'Bulgarian Split Squat', 4, 8, 12, 'reps', true, 120, 'Long stride, stable front foot and controlled depth. Dumbbells or a loaded backpack.', 2.5::numeric, 0, 'bulgarian_split_squat'),
    ('11111111-0000-4000-8000-000000000054'::uuid, 'Romanian Deadlift', 3, 8, 10, 'reps', false, 120, 'Hips back; stop where hamstrings, not the lower back, limit range.', 2.5::numeric, 1, 'dumbbell_romanian_deadlift'),
    ('11111111-0000-4000-8000-000000000055'::uuid, 'Sliding Leg Curl', 3, 10, 15, 'reps', false, 90, 'Keep hips lifted; shorten range before form breaks.', 0::numeric, 2, 'sliding_leg_curl'),
    ('11111111-0000-4000-8000-000000000056'::uuid, 'Single-Leg Calf Raise', 3, 12, 20, 'reps', true, 60, 'Full comfortable stretch and a one-second pause at the top.', 2.5::numeric, 3, 'single_leg_calf_raise'),
    ('21724251-bd48-4f45-a094-0d58981d4c29'::uuid, 'Strict Bodyweight Push-Up', 4, 0, 0, 'reps', false, 90, 'Stop every set with about 2 clean reps available; do not calculate fresh max minus two.', 0::numeric, 0, 'push_up'),
    ('11111111-0000-4000-8000-000000000065'::uuid, 'Diamond or Close-Grip Push-Up', 2, 8, 15, 'reps', false, 90, 'Stop 1-2 reps before failure; use knees or an incline when full-range quality drops.', 0::numeric, 1, 'diamond_push_up'),
    ('11111111-0000-4000-8000-000000000066'::uuid, 'Focus T25 · Tuesday core', 1, 1, 1, 'check', false, 0, 'Episode follows the V8.3 month map.', 0::numeric, 2, null::text),
    ('11111111-0000-4000-8000-000000000070'::uuid, 'Band-Assisted Pull-Up', 4, 4, 6, 'reps', false, 120, 'Full controlled bottom position, chin over bar and no kip. Choose a band that leaves 2 RIR.', 0::numeric, 0, 'band_assisted_pull_up'),
    ('11111111-0000-4000-8000-000000000071'::uuid, 'Chest-Supported Row', 3, 8, 12, 'reps', false, 90, 'Dumbbells, backpack or bands; keep the chest supported.', 2.5::numeric, 1, 'chest_supported_row'),
    ('11111111-0000-4000-8000-000000000072'::uuid, 'Band Face Pull', 2, 15, 20, 'reps', false, 60, 'Smooth external rotation; no neck shrug.', 0::numeric, 2, 'band_face_pull'),
    ('11111111-0000-4000-8000-000000000073'::uuid, 'Gimbal Front Hold', 3, 30, 45, 'seconds', false, 60, 'Hold 2.5-4 kg at rig height; stop before shaking or back pain.', 0::numeric, 3, null::text),
    ('69087eed-6339-4ce2-a6cf-f7a138a78b5e'::uuid, 'Focus T25 · Wednesday lower and speed', 1, 1, 1, 'check', false, 0, 'Episode follows the V8.3 month map.', 0::numeric, 4, null::text),
    ('11111111-0000-4000-8000-000000000078'::uuid, 'Focus T25 · Stretch', 1, 1, 1, 'check', false, 0, '25 minutes; treat this as recovery, not a flexibility test.', 0::numeric, 0, null::text),
    ('11111111-0000-4000-8000-000000000079'::uuid, 'Bird-Dog', 2, 6, 6, 'reps', true, 0, 'Two circuit rounds with a 3-second pause.', 0::numeric, 1, 'bird_dog'),
    ('11111111-0000-4000-8000-000000000080'::uuid, 'Wall Slide', 2, 10, 10, 'reps', false, 0, 'Two circuit rounds.', 0::numeric, 2, 'wall_slide'),
    ('11111111-0000-4000-8000-000000000081'::uuid, 'Band Pull-Apart', 2, 15, 15, 'reps', false, 0, 'Two circuit rounds.', 0::numeric, 3, 'band_pull_apart'),
    ('1396588a-de38-46c2-9def-a52e23aa545a'::uuid, 'Side Plank', 2, 20, 30, 'seconds', true, 0, 'Two circuit rounds; breathe normally.', 0::numeric, 4, 'side_plank'),
    ('b7c7012a-dfcc-4829-9dbb-8e3bddfaefa2'::uuid, 'Front Lunge', 2, 8, 12, 'reps', true, 90, 'Controlled knee travel; stay tall enough to keep a quad bias.', 2.5::numeric, 0, 'forward_lunge'),
    ('f4c7aca5-f891-479d-a25b-29692271c628'::uuid, 'Reverse Lunge', 2, 8, 12, 'reps', true, 90, 'Slight forward torso lean; drive through the whole front foot.', 2.5::numeric, 1, 'reverse_lunge'),
    ('0064e28d-eca7-41dc-ad7a-189a086091b7'::uuid, 'Single-Leg Romanian Deadlift', 3, 8, 12, 'reps', true, 90, 'Use support for balance so hamstrings and glutes remain the limiter.', 2.5::numeric, 2, 'single_leg_romanian_deadlift'),
    ('73f6712a-7720-47c2-ab9a-a12e23e7274b'::uuid, 'Calf Raise', 2, 15, 25, 'reps', false, 60, 'Straight or slightly bent knee; use a full controlled range.', 2.5::numeric, 3, 'standing_calf_raise'),
    ('e20864ff-daaa-4058-862e-fd8666d167f3'::uuid, 'Focus T25 · Friday conditioning', 1, 1, 1, 'check', false, 0, 'Complete strength first; a later separate T25 session is preferred.', 0::numeric, 4, null::text),
    ('11111111-0000-4000-8000-000000000096'::uuid, 'Weighted Push-Up', 4, 6, 10, 'reps', false, 120, 'Secure the backpack high on the torso; add 1-2 kg only after 10,10,10,10 with 1-2 RIR.', 2.5::numeric, 0, 'weighted_push_up'),
    ('11111111-0000-4000-8000-000000000103'::uuid, 'Band-Assisted Chin-Up', 3, 4, 6, 'reps', false, 120, 'Palms toward you; use one level more assistance than Wednesday if needed.', 0::numeric, 0, 'chin_up'),
    ('11111111-0000-4000-8000-000000000104'::uuid, 'One-Arm Supported Row', 3, 8, 12, 'reps', true, 90, 'Support the free hand on a bench or chair and keep the torso quiet.', 2.5::numeric, 1, 'one_arm_dumbbell_row'),
    ('11111111-0000-4000-8000-000000000105'::uuid, 'Gimbal Front Hold', 2, 45, 60, 'seconds', false, 60, 'Use the actual rig only when safe; stop at RPE 6-7.', 0::numeric, 2, null::text),
    ('11111111-0000-4000-8000-000000000106'::uuid, 'Suitcase Hold or March', 2, 30, 45, 'seconds', true, 60, 'One-sided load, level shoulders and slow breathing.', 2.5::numeric, 3, 'suitcase_hold')
  ) as v(id, name, sets, rep_min, rep_max, rep_unit, per_side, rest_sec, notes, increment_kg, sort_order, movement_id)
  where e.id = v.id and e.user_id = constantine_user;

  insert into public.exercises (
    id, user_id, program_day_id, name, sets, rep_min, rep_max, rep_unit,
    per_side, rest_sec, tempo_up_s, tempo_down_s, tempo_pause_s, tempo_note,
    notes, increment_kg, is_lite, optional, sort_order, movement_id
  ) values
    ('83000000-0000-4000-8000-000000000001', constantine_user, '11111111-0000-4000-8000-000000000095', 'Lateral Raise', 3, 12, 25, 'reps', false, 90, 1, 2, 0, '', 'Band, dumbbells or water bottles; arms slightly forward, no shrug and lower under control.', 1, false, false, 1, 'lateral_raise'),
    ('83000000-0000-4000-8000-000000000002', constantine_user, '11111111-0000-4000-8000-000000000095', 'Lateral Raise', 2, 12, 25, 'reps', false, 90, 1, 2, 0, '', 'Light option.', 1, true, false, 1, 'lateral_raise'),
    ('83000000-0000-4000-8000-000000000003', constantine_user, '52429d97-dea9-49af-b4bc-f678ad447417', 'Focus T25 · Friday conditioning', 1, 1, 1, 'check', false, 0, 1, 2, 0, '', 'Complete strength first; a later separate T25 session is preferred.', 0, true, false, 3, null)
  on conflict (id) do update set
    user_id = excluded.user_id, program_day_id = excluded.program_day_id,
    name = excluded.name, sets = excluded.sets, rep_min = excluded.rep_min,
    rep_max = excluded.rep_max, rep_unit = excluded.rep_unit,
    per_side = excluded.per_side, rest_sec = excluded.rest_sec,
    notes = excluded.notes, increment_kg = excluded.increment_kg,
    is_lite = excluded.is_lite, optional = excluded.optional,
    sort_order = excluded.sort_order, movement_id = excluded.movement_id;

  -- Keep the existing native/web light alternatives aligned where V8.3
  -- changed the movement family.
  update public.exercises
  set name = 'Band-Assisted Chin-Up', movement_id = 'chin_up', notes = 'Light option with one additional level of assistance.'
  where id = '11111111-0000-4000-8000-000000000107' and user_id = constantine_user;

  if (select count(*) from public.program_days where program_id = constantine_main and user_id = constantine_user) <> 7
     or (select count(distinct weekday) from public.program_days where program_id = constantine_main and user_id = constantine_user and weekday between 1 and 7) <> 7 then
    raise exception 'Constantine main programme is not exactly seven weekdays';
  end if;
  if (select count(*) from public.program_days where program_id = june_main and user_id = june_user) <> 7
     or (select count(distinct weekday) from public.program_days where program_id = june_main and user_id = june_user and weekday between 1 and 7) <> 7 then
    raise exception 'June main programme is not exactly seven weekdays';
  end if;
  if (select count(*) from public.exercises e join public.program_days d on d.id = e.program_day_id where d.program_id = constantine_main and e.user_id = constantine_user and not e.is_lite) <> 28 then
    raise exception 'Constantine V8.3 full prescription does not contain 28 rows';
  end if;
  if (select count(*) from public.exercises e join public.program_days d on d.id = e.program_day_id where d.program_id = june_main and e.user_id = june_user and not e.is_lite) <> 23 then
    raise exception 'June V8 full prescription does not contain 23 rows';
  end if;
  if exists (select 1 from public.settings where user_id in (constantine_user, june_user) and addons ? 'training_induction') then
    raise exception 'A generic induction filter still hides a bespoke plan';
  end if;
  if exists (
    select 1 from public.program_days d join public.programs p on p.id = d.program_id where d.user_id <> p.user_id
  ) or exists (
    select 1 from public.exercises e join public.program_days d on d.id = e.program_day_id where e.user_id <> d.user_id
  ) then
    raise exception 'Plan ownership invariant failed';
  end if;

  if other_programs_before <> (select md5(coalesce(string_agg(to_jsonb(p)::text, '|' order by p.id), '')) from public.programs p where p.user_id not in (constantine_user, june_user))
     or other_days_before <> (select md5(coalesce(string_agg(to_jsonb(d)::text, '|' order by d.id), '')) from public.program_days d where d.user_id not in (constantine_user, june_user))
     or other_exercises_before <> (select md5(coalesce(string_agg(to_jsonb(e)::text, '|' order by e.id), '')) from public.exercises e where e.user_id not in (constantine_user, june_user)) then
    raise exception 'A non-target account plan changed';
  end if;
  if target_sessions_before <> (select md5(coalesce(string_agg(to_jsonb(s)::text, '|' order by s.id), '')) from public.workout_sessions s where s.user_id in (constantine_user, june_user))
     or target_logs_before <> (select md5(coalesce(string_agg(to_jsonb(l)::text, '|' order by l.id), '')) from public.workout_logs l where l.user_id in (constantine_user, june_user)) then
    raise exception 'Workout history changed during plan restoration';
  end if;
end
$restore$;

commit;
