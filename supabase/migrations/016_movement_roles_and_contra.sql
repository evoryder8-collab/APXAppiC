-- Two corrections the plan generator exposed, plus the field that fixes the
-- second one properly.
--
-- The contraindication vocabulary had grown synonyms: later movements were
-- tagged "low_back_flexion" and "knee_flexion" where the originals used
-- "lumbar_flexion" and "knee_deep_flexion". A near-duplicate tag does not
-- throw, it just quietly fails to match, so a user who flagged their lower
-- back was still handed the bent-over dumbbell row.
--
-- Worse, the intake asks about six body areas and the library only carried
-- tags for four. Anyone reporting hip or ankle pain was filtered on nothing at
-- all -- a question that looks answered and does nothing.
--
-- And the generator, asked for a vertical pull, chose a dumbbell pullover over
-- a pull-up for someone who owns a bar. It was right by the data and wrong by
-- any coaching standard, because nothing recorded that a pullover is an
-- accessory living inside that pattern rather than the movement the pattern is
-- about. Hence `role`.

alter table public.movement_library
  add column if not exists role text not null default 'primary';

alter table public.movement_library
  drop constraint if exists movement_library_role_check;
alter table public.movement_library
  add constraint movement_library_role_check check (role in ('primary', 'accessory'));

-- Collapse the synonyms onto the tag that was already carrying the meaning.
update public.movement_library
set contraindications = (
  select array_agg(distinct case
    when c = 'low_back_flexion' then 'lumbar_flexion'
    when c = 'knee_flexion' then 'knee_deep_flexion'
    else c end)
  from unnest(contraindications) c)
where contraindications && array['low_back_flexion', 'knee_flexion'];

-- Hip and ankle tags, derived from what the movement does rather than set by
-- hand, so they stay consistent as the library grows.
update public.movement_library
set contraindications = (
  select array_agg(distinct c) from unnest(contraindications || array['hip_deep_flexion']) c)
where id in (
  'barbell_back_squat','barbell_front_squat','goblet_squat','pistol_squat',
  'shrimp_squat','cossack_squat','garland_pose','overhead_squat',
  'heel_elevated_goblet_squat','hack_squat','leg_press','pendulum_squat',
  'bodyweight_squat','wall_ball','thruster','sit_to_stand');

update public.movement_library
set contraindications = (
  select array_agg(distinct c) from unnest(contraindications || array['hip_end_range']) c)
where id in (
  'pigeon_pose','lizard_pose','happy_baby','butterfly_stretch','ninety_ninety_hip',
  'figure_four_stretch','low_lunge','couch_stretch','garland_pose','eagle_pose',
  'seated_forward_fold');

update public.movement_library
set contraindications = (
  select array_agg(distinct c) from unnest(contraindications || array['ankle_dorsiflexion']) c)
where id in (
  'barbell_back_squat','barbell_front_squat','goblet_squat','pistol_squat',
  'shrimp_squat','cossack_squat','garland_pose','overhead_squat',
  'bodyweight_squat','downward_dog','wall_ball','thruster');

-- Anything that lands, hops or skips loads the ankle on impact, whatever else
-- it is filed under.
update public.movement_library
set contraindications = (
  select array_agg(distinct c)
  from unnest(contraindications || array['ankle_impact', 'knee_impact']) c)
where entity_type = 'plyometric' or impact_level = 'high' or id in (
  'single_under','double_under','jumping_jack','high_knees','burpee',
  'burpee_broad_jump','bounding','mountain_climber');

-- Calf work taken to end range is the other ankle provocation.
update public.movement_library
set contraindications = (
  select array_agg(distinct c) from unnest(contraindications || array['ankle_loaded']) c)
where pattern = 'calf';

update public.movement_library set role = 'accessory'
where id in (
  -- Straight-arm lat work: loads the pattern, does not train the pull.
  'floor_pullover','dumbbell_pullover','band_lat_pullover','straight_arm_pulldown',
  'towel_door_pulldown','band_straight_arm_pulldown','pullover_machine','prone_floor_row',
  -- Single-joint or very light work sitting inside a compound pattern.
  'frog_pump','glute_bridge','svend_press','front_raise','band_pull_apart',
  'scapular_pull_up','dead_hang','wall_sit','neck_isometric','chin_tuck',
  'plate_pinch','towel_hang','wrist_roller','tibialis_raise','heel_walk',
  'short_foot','dumbbell_side_bend','shrug','upright_row')
or pattern like 'isolation\_%'
or pattern in ('calf', 'mobility', 'yoga_pose');

notify pgrst, 'reload schema';
