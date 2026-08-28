/*
 * Canonical string values that cross the web/Apple Supabase boundary.
 * Keep this object structurally identical to the native payload fixture: the
 * contract tests compare it as data, so a new spelling cannot ship on only
 * one client.
 */
export const SUPABASE_ENUMS = {
  persona: ['june', 'matthew', 'iulian', 'constantine'],
  activity_level: ['sedentary', 'light', 'moderate', 'very', 'extra'],
  goal: ['recomp', 'maintain', 'bulk'],
  supplement_timing: ['clock', 'training'],
  program_slug: ['transition', 'main', 'custom'],
  day_type: ['legs_a', 'legs_b', 'push', 'pull', 'upper', 'mobility', 'fix', 't25', 'custom'],
  session_mode: ['guided', 'tracked'],
  rep_unit: ['reps', 'seconds', 'minutes', 'metres', 'steps', 'rounds', 'max', 'check'],
  activity_input_style: ['count', 'duration', 'distance', 'steps', 'watch_kcal'],
  daily_activity_mode: ['quick', 'precise'],
  activity_log_source: ['manual', 'workout_module', 'event_prefill', 'orbit'],
  event_type: ['filming_championship', 'travel', 'other'],
  recovery_data_source: ['apple', 'other'],
  imported_activity_kind: ['strength', 'endurance', 'mobility'],
  meal_slot: ['breakfast', 'lunch', 'dinner', 'snack'],
  food_unit: ['g', 'ml', 'serving', 'piece'],
  nutrition_basis: ['per_100g', 'per_100ml'],
  preparation_state: ['dry', 'cooked', 'prepared', 'drained', 'as_sold', 'unknown'],
  food_source: ['open_food_facts', 'private', 'apex_cache'],
  logged_as: ['planned', 'changed', 'custom'],
  adjustment_role: ['carb', 'protein', 'energy', 'none'],
  progress_pose: ['front', 'side', 'back'],
  hydration_kind: ['water', 'coffee', 'tea', 'juice', 'shake', 'other', 'food', 'external', 'legacy'],
  hydration_preset_kind: ['water', 'coffee', 'tea', 'juice', 'shake', 'other'],
  hydration_source: ['iphone', 'watch', 'web', 'food', 'healthkit_external', 'legacy'],
  hydration_target_mode: ['automatic', 'custom'],
  hydration_display_unit: ['liters', 'gallons'],
  hydration_motion_intensity: ['off', 'subtle', 'full'],
  orbit_route_shape: ['loop', 'out_back', 'point_to_point'],
  orbit_route_terrain: ['flat', 'rolling', 'hilly'],
  orbit_route_surface: ['road', 'path', 'trail', 'mixed'],
  orbit_navigation_complexity: ['low', 'moderate', 'high'],
  orbit_induction_outcome: ['ready', 'foundation', 'more_information', 'professional_review'],
  orbit_campaign_family: ['foundation_first', 'first_finish', 'first_performance', 'personal_best', 'hybrid'],
  orbit_campaign_phase: ['foundation', 'aerobic_build', 'durability', 'marathon_specific', 'peak', 'taper', 'race_week', 'post_marathon'],
  orbit_campaign_status: ['active', 'paused', 'completed', 'review_required'],
  orbit_session_status: ['planned', 'completed', 'missed', 'skipped'],
  orbit_run_status: ['completed', 'discarded'],
  orbit_run_mission: [
    'recovery', 'easy', 'aerobic_base', 'long_run', 'run_walk', 'progression',
    'tempo', 'threshold', 'intervals', 'hills', 'marathon_pace', 'exploration',
    'performance_test', 'free_run',
  ],
  orbit_poster_style: ['map', 'constellation', 'elevation', 'minimal'],
} as const satisfies Record<string, readonly string[]>

export type SupabaseEnumName = keyof typeof SUPABASE_ENUMS
export type SupabaseEnumValue<Name extends SupabaseEnumName> = (typeof SUPABASE_ENUMS)[Name][number]
