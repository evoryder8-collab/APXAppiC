/* Domain model. Every row carries user_id so RLS policies scope to auth.uid(). */

import type { PersonaSlug } from './persona'
import type { ActivityType } from './activity'
import type { MealBlockSettings } from './mealBlocks'

export type ActivityLevel = 'sedentary' | 'light' | 'moderate' | 'very' | 'extra'
export type Goal = 'recomp' | 'maintain' | 'bulk'

export interface CalibrationHistoryEntry {
  applied_at: string
  previous_k: number
  next_k: number
  observed_tdee: number
  predicted_tdee: number
  sample_days: number
}

export interface Profile {
  id: string
  user_id: string
  persona: PersonaSlug
  display_name: string
  sex: 'male' | 'female'
  weight_kg: number
  body_fat_pct: number
  /* Optional measured resting metabolism from a recent DEXA/metabolic test.
     When present it becomes the energy engine's BMR source. */
  custom_bmr?: number | null
  height_cm: number
  birthdate: string // ISO date
  activity_level: ActivityLevel
  goal: Goal
  /* Legacy protocol references retained for existing profile compatibility. */
  target_kcal: number | null
  target_protein_g: number | null
  target_fat_g: number | null
  target_carbs_g: number | null
  training_time: string // 'HH:mm', default anchor for training-relative supplements
  baseline_date: string // ISO date the RPG engine starts from
  profile_note: string
  seed_version: number
  calibration_k: number
  calibration_history: CalibrationHistoryEntry[]
  updated_at: string
}

export interface Meal {
  id: string
  user_id: string
  time: string // 'HH:mm'
  name: string
  foods: string
  kcal: number
  protein_g: number
  fat_g: number
  carbs_g: number
  full_days_only: boolean
  sort_order: number
}

export interface MealLog {
  id: string
  user_id: string
  date: string // ISO date
  meal_id: string
  checked_at: string
}

export type SupplementTiming = 'clock' | 'training'

export interface Supplement {
  id: string
  user_id: string
  name: string
  dose: string
  timing: SupplementTiming
  clock_time: string | null // 'HH:mm' when timing = clock
  offset_min: number | null // minutes relative to training time, e.g. -60, -15, 0 (post)
  group_label: string // 'Wake', 'T-60', 'Post-workout', ...
  training_days_only: boolean
  sort_order: number
}

export interface SupplementLog {
  id: string
  user_id: string
  date: string
  supplement_id: string
  checked_at: string
}

export type ProgramSlug = 'transition' | 'main' | 'custom'

export interface Program {
  id: string
  user_id: string
  slug: ProgramSlug
  name: string
  description: string
}

export type DayType =
  | 'legs_a'
  | 'legs_b'
  | 'push'
  | 'pull'
  | 'upper'
  | 'mobility'
  | 'fix'
  | 't25'
  | 'custom'

export type SessionMode = 'guided' | 'tracked'

export interface ProgramDay {
  id: string
  user_id: string
  program_id: string
  weekday: number // 1 = Monday ... 7 = Sunday (ISO)
  name: string
  day_type: DayType
  est_minutes: number
  warmup_note: string
  sort_order: number
  /* How this day is trained. "guided" runs the follow-along player, which
   * paces the session and counts reps aloud. "tracked" shows the list and
   * lets the lifter enter weight, reps and reps-in-reserve themselves, which
   * is what anyone running their own progressive overload actually wants. */
  session_mode?: SessionMode | null
}

export type RepUnit = 'reps' | 'seconds' | 'minutes' | 'max' | 'check'

export interface Exercise {
  id: string
  user_id: string
  program_day_id: string
  name: string
  sets: number
  rep_min: number
  rep_max: number
  rep_unit: RepUnit
  per_side: boolean
  rest_sec: number
  /* Structured tempo for the cadence engine */
  /* Canonical movement this row performs, where it is known. Programme rows
   * keep their own authored names, so this is what lets the player find the
   * timing, cues and side-switch behaviour behind one. */
  movement_id?: string | null
  tempo_up_s: number
  tempo_down_s: number
  tempo_pause_s: number
  tempo_note: string
  notes: string
  /* +2.5 compounds/backpack, +1 isolations, 0 pure bodyweight/mobility */
  increment_kg: number
  is_lite: boolean // belongs to the Lite variant of the day
  optional: boolean
  sort_order: number
}

export interface WorkoutSession {
  id: string
  user_id: string
  date: string
  program_day_id: string
  is_lite: boolean
  is_deload: boolean
  is_event_recovery: boolean
  completed: boolean
  quality_score: number // 0..1, completed volume vs planned
  started_at: string | null
  completed_at: string | null
  notes: string
}

export interface WorkoutLog {
  id: string
  user_id: string
  session_id: string
  exercise_id: string | null
  exercise_name: string
  set_no: number
  weight_kg: number | null
  reps: number | null
  rir: number | null
  skipped: boolean
  override_flag: boolean
  created_at: string
}

export interface DailyLog {
  id: string
  user_id: string
  date: string
  kcal: number | null
  protein_g: number | null
  fat_g: number | null
  carbs_g: number | null
  water_l: number
  estimated_tdee: number | null
  computed_pal: number | null
  activity_mode: 'quick' | 'precise'
  weight_kg: number | null
  nutrition_source?: 'manual' | 'structured'
  manual_kcal?: number | null
  manual_protein_g?: number | null
  manual_fat_g?: number | null
  manual_carbs_g?: number | null
}

export interface ActivityLog {
  id: string
  user_id: string
  date: string
  type_id: string
  quantity: number
  duration_min: number | null
  distance_km: number | null
  watch_kcal: number | null
  computed_kcal: number
  source: 'manual' | 'workout_module' | 'event_prefill' | 'orbit'
  reconciled: boolean
  created_at: string
  updated_at: string
}

export type EventType = 'filming_championship' | 'travel' | 'other'

export interface CalendarEvent {
  id: string
  user_id: string
  name: string
  type: EventType
  start_date: string
  end_date: string
  notes: string
}

export interface RpgSnapshot {
  id: string
  user_id: string
  date: string
  overall: number
  health: number
  joint: number
  flexibility: number
  endurance: number
  strength: number
  strength_upper: number
  strength_lower: number
}

export interface DeloadMark {
  id: string
  user_id: string
  date: string
}

/* Daily body metrics imported from Apple Health. Absence of a day never
   penalizes anything; these are positive signals only. */
export interface HealthMetric {
  id: string
  user_id: string
  date: string
  weight_kg: number | null
  vo2max: number | null
  resting_hr: number | null
}

export type RecoveryDataSource = 'apple' | 'athlytic'

/* Source-tagged values are retained when the recovery source changes, so
   trends never reinterpret an old Apple Sleep Score as Athlytic Recovery. */
export interface RecoveryCheckin {
  date: string
  source: RecoveryDataSource
  sleep_score: number | null
  sleep_pct: number | null
  recovery_pct: number | null
  updated_at: string
}

/* Watch totals are context for recommending one existing whole-day activity
   mode. They are not added to the calorie target and therefore cannot double
   count a guided APEX workout. */
export interface WatchActivityCheckin {
  date: string
  steps: number
  active_calories: number
  exercise_minutes: number
  suggested_level: ActivityLevel
  selected_level: ActivityLevel
  updated_at: string
}

export type ImportedActivityKind = 'strength' | 'endurance' | 'mobility'

export interface ImportedActivity {
  id: string
  user_id: string
  date: string
  kind: ImportedActivityKind
  activity: string // original HK activity name
  duration_min: number
  source: string
}

export interface Settings {
  user_id: string
  voice_on: boolean
  ticks_on: boolean
  notifications_on: boolean
  guardian_factor: number // spike threshold vs typical increment, default 1.5
  addons: {
    endurance1: boolean
    endurance2: boolean
    endurance3: boolean
    uiMode?: 'simple' | 'advanced'
    /* Stored inside the existing JSON settings record so measured BMR works
       immediately on every deployed database without a blocking schema step. */
    custom_bmr?: number | null
    /* Weekly subjective joint/load-tolerance check-ins. Keeping these in the
       existing per-user JSON record makes the feature deploy-safe while still
       syncing privately across devices. */
    joint_checkins?: JointCheckin[]
    /* Optional onboarding for people starting or returning to resistance
       training. Constantine and June retain their bespoke programmes. */
    newbie_mode?: boolean
    training_induction?: TrainingInductionProfile | null
    /* Start of the current bespoke 12-week prescription. It is independent
       from the RPG baseline so a programme refresh never erases history. */
    training_protocol?: {
      version: 81
      start_date: string
    }
    /* Controls only the shareable progress-photo PNG. Minimal keeps the two
       timestamps and before/after labels; Detailed adds training statistics. */
    comparison_export_mode?: 'minimal' | 'detailed'
    /* Simple Mode is intentionally user-configurable without requiring new
       database columns; settings.addons is already the synced JSON payload. */
    weight_unit?: 'kg' | 'lb'
    simple_show_orbit?: boolean
    simple_show_body_index?: boolean
    simple_show_guided_plan?: boolean
    simple_show_hydration_reminder?: boolean
    simple_show_manual_workout?: boolean
    simple_show_next_action?: boolean
    adhd_mode?: boolean
    /* IANA zone used by the live nutrition dayline and all timing exports.
       When absent, the browser's current zone is used. */
    time_zone?: string
    /* Account-scoped meal moments and preset associations. This stays inside
       the existing synced JSON settings record, so no schema rollout is
       required for reliable cross-device behavior. */
    meal_blocks?: MealBlockSettings
    /* Explicit post-workout eating starts, keyed by workout-session id. The
       existing synced JSON settings record keeps this deploy-safe and private
       while still making the timing signal available across devices. */
    recovery_nutrition?: Record<string, {
      meal_id: string | null
      started_at: string
      updated_at: string
    }>
    /* Legacy eating-start records are retained for backwards-compatible
       account reads. New timing UX records only LoggedMeal.logged_at, the
       explicit meal-finished timestamp. */
    meal_start_times?: Record<string, {
      started_at: string
      updated_at: string
    }>
    /* Long-press movement of a meal-finished marker snaps to this step. */
    meal_timeline_snap_minutes?: 5 | 15 | 30 | 60
    /* Physical spacing of the 24-hour nutrition Dayline. Medium is the
       spacious default, while Long makes two-hour guidance bands especially
       easy to inspect on a phone. */
    meal_dayline_density?: 'compact' | 'medium' | 'long'
    /* Controls which prior meals seed the blank meal composer. Daily learns
       across recent occurrences of the same meal slot. Weekly first learns
       from the same weekday, then falls back when that weekday has no
       history. */
    meal_memory_mode?: 'daily' | 'weekly'
    /* Optional display subtitles for reusable meal-component presets. The
       deployed preset table predates subtitles, so this account-synced map
       adds them without making release deployment depend on a schema change. */
    meal_preset_subtitles?: Record<string, string>
    /* After 19:00 a post-workout meal uses the full dinner guidance instead
       of a snack-only list. Enabled by default and explicitly user-controlled. */
    adaptive_post_workout_dinner?: boolean
    /* One immutable-style summary per local calendar day. Closed days keep a
       verdict even when no meal was logged, while later corrections rebuild
       that day and deterministically replay the Avatar engine. */
    meal_rhythm_history?: Record<string, {
      date: string
      time_zone: string
      finalized: boolean
      expected_meals: number
      logged_meals: number
      scheduled_times: Array<{
        id: string
        slot: 'breakfast' | 'lunch' | 'dinner' | 'snack'
        time: string
      }>
      meal_times: string[]
      first_meal_at: string | null
      last_meal_at: string | null
      completion_score: number
      timing_score: number | null
      rhythm_score: number
      verdict: 'open' | 'complete_on_time' | 'complete_irregular' | 'missed_meals' | 'no_meals'
      updated_at: string
    }>
    recovery_data_source?: RecoveryDataSource
    recovery_history?: RecoveryCheckin[]
    watch_activity_history?: WatchActivityCheckin[]
    /* User-editable meal guidance copied from the athlete protocol. Keys
       include persona, meal slot and goal so switching goals never destroys
       a carefully configured list for another phase. */
    meal_protocol_overrides?: Record<string, string[]>
    /* The scanner intentionally stays rear-camera-only unless a person
       explicitly enables this accessibility fallback for a broken rear lens. */
    food_scanner_front_camera?: boolean
    /* Clean hides coaching prose while Detailed preserves the explanatory
       layer. Functional labels and safety feedback remain visible in both. */
    interface_mode?: 'clean' | 'detailed'
    /* Persisted order for the large Simple Mode blocks. */
    simple_block_order?: string[]
  }
}

export type TrainingInactivity =
  | 'currently_training'
  | 'under_1_month'
  | 'one_to_three_months'
  | 'three_to_six_months'
  | 'six_to_twelve_months'
  | 'over_one_year'

export type TrainingVenue = 'home' | 'gym'
export type TrainingGoal = 'rebuild' | 'muscle' | 'strength'
export type TrainingPainArea =
  | 'shoulders'
  | 'elbows'
  | 'wrists'
  | 'hips'
  | 'knees'
  | 'ankles'

export type TrainingPlanCaution = 'standard' | 'cautious' | 'clearance'

export interface TrainingInductionProfile {
  version: 1
  completed_at: string
  start_date: string
  main_start_date: string
  transition_weeks: 12
  inactivity: TrainingInactivity
  venue: TrainingVenue
  equipment: string[]
  pain_areas: TrainingPainArea[]
  recent_operation: boolean
  chronic_lower_back_pain: boolean
  sessions_per_week: 2 | 3 | 4
  goal: TrainingGoal
  caution: TrainingPlanCaution
  transition_day_ids: string[]
  main_day_ids: string[]
}

export interface JointCheckin {
  id: string
  date: string
  arms: number
  core: number
  legs: number
}

export interface AppData {
  profile: Profile | null
  settings: Settings | null
  meals: Meal[]
  meal_logs: MealLog[]
  supplements: Supplement[]
  supplement_logs: SupplementLog[]
  programs: Program[]
  program_days: ProgramDay[]
  exercises: Exercise[]
  workout_sessions: WorkoutSession[]
  workout_logs: WorkoutLog[]
  activity_types: ActivityType[]
  activity_logs: ActivityLog[]
  daily_logs: DailyLog[]
  events: CalendarEvent[]
  rpg_snapshots: RpgSnapshot[]
  deload_marks: DeloadMark[]
  health_metrics: HealthMetric[]
  imported_activities: ImportedActivity[]
}

export const EMPTY_DATA: AppData = {
  profile: null,
  settings: null,
  meals: [],
  meal_logs: [],
  supplements: [],
  supplement_logs: [],
  programs: [],
  program_days: [],
  exercises: [],
  workout_sessions: [],
  workout_logs: [],
  activity_types: [],
  activity_logs: [],
  daily_logs: [],
  events: [],
  rpg_snapshots: [],
  deload_marks: [],
  health_metrics: [],
  imported_activities: [],
}

export type TableName = keyof Omit<AppData, 'profile' | 'settings'> | 'profile' | 'settings'
