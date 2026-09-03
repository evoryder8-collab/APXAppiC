/* Domain model. Every row carries user_id so RLS policies scope to auth.uid(). */

import type { PersonaSlug } from './persona'
import type { ActivityType } from './activity'
import type { MealBlockSettings } from './mealBlocks'
import type { HydrationEvent, HydrationPreferences, HydrationPreset } from './hydrationLedger'
import type { SUPABASE_ENUMS } from './supabaseEnums'
import type { BespokeProtocolID, BodyFatSource, ProfileKind } from './profilePolicy'
import type {
  FitnessEvidenceConfidence,
  FitnessEvidenceMetric,
  FitnessEvidenceSource,
} from './fitnessEvidence'

export type ActivityLevel = (typeof SUPABASE_ENUMS.activity_level)[number]
export type Goal = (typeof SUPABASE_ENUMS.goal)[number]

export type AccountEntitlementState = 'granted' | 'locked' | 'revoked' | 'expired' | 'missing'

/** Server-owned answer returned by get_my_app_access for one authenticated account. */
export interface AccountAccessEnvelope {
  user_id: string
  state: AccountEntitlementState
  expires_at: string | null
  entitlement_updated_at: string | null
  server_now: string
  sponsored_seat_active: boolean
  minimum_build: number
  update_required: boolean
  web_beta_codes_enabled: boolean
}

export type AccountAccessResolution =
  | {
      status: 'pending'
      owner_user_id: string | null
      envelope: null
      source: null
      resolved_at: null
      error: null
    }
  | {
      status: 'resolved'
      owner_user_id: string
      envelope: AccountAccessEnvelope
      source: 'server' | 'cache' | 'local'
      resolved_at: string
      /** Highest local wall-clock instant observed while evaluating bounded access. */
      clock_observed_at: string
      /** Elapsed duration already accrued when this runtime's monotonic anchor was captured. */
      elapsed_anchor_ms: number
      /** Runtime-only monotonic anchor; null only where no elapsed clock is available. */
      monotonic_anchor_ms: number | null
      error: null
    }
  | {
      status: 'failed'
      owner_user_id: string
      envelope: null
      source: null
      resolved_at: null
      error: string
    }

export type CustomBmrSource =
  | 'indirect_calorimetry'
  | 'dexa_report_estimate'
  | 'legacy_user_entered'

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
  profile_kind?: ProfileKind | null
  bespoke_protocol_id?: BespokeProtocolID | null
  display_name: string
  sex: 'male' | 'female'
  weight_kg: number
  body_fat_pct: number | null
  body_fat_source?: BodyFatSource | null
  body_fat_measured_at?: string | null
  /* Optional resting-energy input. Only indirect calorimetry is treated as a
     measured value; a DEXA report estimate remains contextual evidence. */
  custom_bmr?: number | null
  custom_bmr_source?: CustomBmrSource | null
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
  founding_member?: boolean | null
  beta_code_redeemed?: boolean | null
  subscription_tier?: 'premium' | 'coach' | null
  subscription_expires_at?: string | null
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

export type SupplementTiming = (typeof SUPABASE_ENUMS.supplement_timing)[number]

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
  archived?: boolean
}

export interface SupplementLog {
  id: string
  user_id: string
  date: string
  supplement_id: string
  checked_at: string
}

export type ProgramSlug = (typeof SUPABASE_ENUMS.program_slug)[number]

export interface Program {
  id: string
  user_id: string
  slug: ProgramSlug
  name: string
  description: string
}

export type DayType = (typeof SUPABASE_ENUMS.day_type)[number]

export type SessionMode = (typeof SUPABASE_ENUMS.session_mode)[number]

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
  is_active?: boolean
  coach_plan_version_id?: string | null
  /** Exact-date add-ons never repeat as a weekly prescription. */
  scheduled_date?: string | null
  recovery_plan_id?: string | null
  recovery_target?: 'joint' | 'flexibility' | null
  recovery_source?: 'guided' | 'external' | null
}

export type RepUnit = (typeof SUPABASE_ENUMS.rep_unit)[number]

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
  /* A nullable membership, not a separate superset/circuit shape. Members with
   * the same id are performed in position order once per round; set_no is the
   * completed round in history. A two-member group is a superset and a larger
   * group can become a circuit without another representation. */
  work_group_id?: string | null
  work_group_position?: number | null
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
  movement_id?: string | null
  duration_seconds?: number | null
  distance_meters?: number | null
  contacts?: number | null
  rounds?: number | null
  work_seconds?: number | null
  recovery_seconds?: number | null
  skipped: boolean
  override_flag: boolean
  created_at: string
}

export type DailyActivityMode = (typeof SUPABASE_ENUMS.daily_activity_mode)[number]

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
  activity_mode: DailyActivityMode
  weight_kg: number | null
  nutrition_source?: 'manual' | 'structured'
  manual_kcal?: number | null
  manual_protein_g?: number | null
  manual_fat_g?: number | null
  manual_carbs_g?: number | null
}

export type ActivityLogSource = (typeof SUPABASE_ENUMS.activity_log_source)[number]

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
  source: ActivityLogSource
  reconciled: boolean
  created_at: string
  updated_at: string
}

export type EventType = (typeof SUPABASE_ENUMS.event_type)[number]

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

export interface FitnessEvidenceRecord {
  id: string
  user_id: string
  metric: FitnessEvidenceMetric
  value: number
  unit: string
  source: FitnessEvidenceSource
  protocol: string | null
  device: string | null
  measured_at: string
  imported_at: string
  confidence: FitnessEvidenceConfidence
  metadata: Record<string, unknown>
  supersedes_id: string | null
  client_idempotency_key: string
}

export type RecoveryDataSource = (typeof SUPABASE_ENUMS.recovery_data_source)[number]

/* Source-tagged values are retained when the recovery source changes, so
   trends never reinterpret an old Apple Sleep Score as Recovery score. */
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

export type ImportedActivityKind = (typeof SUPABASE_ENUMS.imported_activity_kind)[number]

export interface ImportedActivity {
  id: string
  user_id: string
  date: string
  kind: ImportedActivityKind
  activity: string // original HK activity name
  duration_min: number
  source: string
  healthkit_workout_id?: string | null
  started_at?: string | null
  ended_at?: string | null
  workout_name_key?: string | null
  distance_km?: number | null
  active_energy_kcal?: number | null
  source_bundle_id?: string | null
  activity_type_raw?: number | null
  apex_workout_session_id?: string | null
  hidden_at?: string | null
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
    fitness_plan_intro_seen?: boolean
    /* Stored inside the existing JSON settings record so resting-energy
       evidence works without a blocking profile-table migration. */
    custom_bmr?: number | null
    custom_bmr_source?: CustomBmrSource | null
    /* Weekly subjective joint/load-tolerance check-ins. Keeping these in the
       existing per-user JSON record makes the feature deploy-safe while still
       syncing privately across devices. */
    joint_checkins?: JointCheckin[]
    /* Optional onboarding for people starting or returning to resistance
       training. Constantine and June retain their bespoke programmes. */
    newbie_mode?: boolean
    training_induction?: TrainingInductionProfile | null
    training_induction_baseline?: {
      goal: TrainingGoal
      plan_weeks?: TrainingPlanWeeks
    } | null
    legal_acceptance?: {
      terms_version: string
      privacy_version: string
      accepted_at: string
    }
    training_induction_skipped?: boolean
    training_induction_archived_day_ids?: string[]
    training_induction_protected_original_day_ids?: string[]
    training_induction_pending_day_ids?: string[]
    training_induction_generation_revision?: number
    /* Start of the current bespoke 12-week prescription. It is independent
       from the RPG baseline so a programme refresh never erases history. */
    training_protocol?: {
      version: number
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

export type TrainingVenue = 'home' | 'gym' | 'outdoors'
export type TrainingGoal = 'rebuild' | 'muscle' | 'fat_loss' | 'strength' | 'endurance'
export type TrainingPainArea =
  | 'shoulders'
  | 'elbows'
  | 'wrists'
  | 'hips'
  | 'knees'
  | 'ankles'

export type TrainingPlanCaution = 'standard' | 'cautious' | 'clearance'
export type TrainingSessionsPerWeek = 2 | 3 | 4 | 5 | 6 | 7
export type TrainingPlanWeeks = 4 | 8 | 12 | 26

export interface TrainingInductionProfile {
  version: 1
  completed_at: string
  start_date: string
  main_start_date: string
  end_date?: string
  plan_weeks?: TrainingPlanWeeks
  transition_weeks: number
  inactivity: TrainingInactivity
  venue: TrainingVenue
  equipment: string[]
  pain_areas: TrainingPainArea[]
  recent_operation: boolean
  chronic_lower_back_pain: boolean
  acute_symptoms?: boolean
  sessions_per_week: TrainingSessionsPerWeek
  goal: TrainingGoal
  caution: TrainingPlanCaution
  weekly_load_strategy?: 'standard' | 'distributed' | 'distributed_with_recovery'
  hard_set_cap?: number
  transition_day_ids: string[]
  main_day_ids: string[]
  generation_revision?: number
  available_minutes?: number
  baseline_assessment?: {
    version: 1
    activity_pattern: string
    movement: {
      cardiorespiratory: string
      upper_strength: string
      lower_strength: string
      mobility: string
    }
  }
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
  hydration_events: HydrationEvent[]
  hydration_presets: HydrationPreset[]
  hydration_preferences: HydrationPreferences | null
  events: CalendarEvent[]
  rpg_snapshots: RpgSnapshot[]
  deload_marks: DeloadMark[]
  health_metrics: HealthMetric[]
  fitness_evidence: FitnessEvidenceRecord[]
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
  hydration_events: [],
  hydration_presets: [],
  hydration_preferences: null,
  events: [],
  rpg_snapshots: [],
  deload_marks: [],
  health_metrics: [],
  fitness_evidence: [],
  imported_activities: [],
}

export type TableName = keyof Omit<AppData, 'profile' | 'settings' | 'hydration_preferences'>
  | 'profile' | 'settings' | 'hydration_preferences'
