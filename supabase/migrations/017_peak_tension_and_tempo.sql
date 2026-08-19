-- Where along its range a movement actually loads the muscle, and whether
-- timing a rep means anything at all.
--
-- The popular cue is "squeeze hard at the top". For a hip thrust that is right:
-- peak hip-extension torque occurs at lockout, so the top is the hardest part
-- of the lift. For a squat, a row or a pull-up the top is the rest position and
-- pausing there loads nothing. The current evidence (Maeo 2021, Pedrosa 2022,
-- Kassiano 2023) points the other way for most movements -- long muscle lengths
-- drive more hypertrophy -- so the pause that earns its place is usually the
-- one in the stretched position. Which means the pause position is a property
-- of the movement, and the library has to carry it.
--
-- `tempo_applies` is the other half. A depth jump lives or dies on a short
-- ground contact, an Olympic lift is caught rather than lowered, and a plank
-- has no rep to time. Printing "3-1-1" on any of those would be worse than
-- printing nothing.

alter table public.movement_library
  add column if not exists peak_tension text not null default 'lengthened',
  add column if not exists tempo_applies boolean not null default false;

alter table public.movement_library
  drop constraint if exists movement_library_peak_tension_check;
alter table public.movement_library
  add constraint movement_library_peak_tension_check
    check (peak_tension in ('lengthened', 'mid', 'shortened', 'held'));

-- Anything held rather than repped has no loaded position to pause in.
update public.movement_library set peak_tension = 'held'
where entity_type in ('resistance_isometric', 'balance_drill', 'skill_drill',
                      'mobility_drill', 'yoga_pose', 'movement_sequence',
                      'breathing_recovery');

-- Hip extension against a horizontal load, abduction and adduction away from
-- neutral, and raises whose lever is longest near the top.
update public.movement_library set peak_tension = 'shortened'
where id in (
  'hip_thrust_barbell','hip_thrust_dumbbell','machine_hip_thrust','hip_thrust_smith',
  'b_stance_hip_thrust','glute_bridge','single_leg_glute_bridge','frog_pump',
  'bridge_pose','cable_kickback','cable_pull_through','back_extension',
  'back_extension_machine','hip_abduction','hip_adduction','lateral_raise',
  'cable_lateral_raise','band_lateral_raise','machine_lateral_raise','front_raise',
  'band_pull_apart','face_pull','band_face_pull','reverse_pec_deck',
  'leg_extension','shrug','svend_press','prone_floor_row');

-- Constant-tension cable and band work, and elbow flexion, peak around mid range.
update public.movement_library set peak_tension = 'mid'
where id in (
  'dumbbell_curl','hammer_curl','cable_curl','band_curl','preacher_curl_machine',
  'triceps_pushdown','cable_row','single_arm_cable_row','band_row',
  'band_bent_over_row','cable_fly','pec_deck','straight_arm_pulldown',
  'pallof_press','cable_chop','cable_lift','upright_row','wrist_roller');

-- A tempo is only meaningful on a dynamic, non-ballistic, rep-counted movement.
update public.movement_library
set tempo_applies = (entity_type = 'resistance_dynamic'
                     and not is_ballistic
                     and rep_unit = 'reps');

notify pgrst, 'reload schema';
