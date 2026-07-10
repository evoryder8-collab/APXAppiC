/* Domain model. Every row carries user_id so RLS policies scope to auth.uid(). */

export type ActivityLevel = 'sedentary' | 'light' | 'moderate' | 'very' | 'extra'
export type Goal = 'recomp' | 'maintain' | 'bulk'

export interface Profile {
  id: string
  user_id: string
  sex: 'male' | 'female'
  weight_kg: number
  body_fat_pct: number
  height_cm: number
  birthdate: string // ISO date
  activity_level: ActivityLevel
  goal: Goal
  training_time: string // 'HH:mm', default anchor for training-relative supplements
  baseline_date: string // ISO date the RPG engine starts from
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

export type ProgramSlug = 'transition' | 'main'

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
}

export type RepUnit = 'reps' | 'seconds' | 'minutes' | 'max'

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
  addons: { endurance1: boolean; endurance2: boolean; endurance3: boolean }
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
  daily_logs: [],
  events: [],
  rpg_snapshots: [],
  deload_marks: [],
  health_metrics: [],
  imported_activities: [],
}

export type TableName = keyof Omit<AppData, 'profile' | 'settings'> | 'profile' | 'settings'
