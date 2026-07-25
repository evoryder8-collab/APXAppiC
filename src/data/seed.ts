/*
 * Seed data straight from Constantin's brief (Appendix A, verbatim exercises).
 * This is the single source of truth: local mode loads it directly and the
 * Supabase path inserts these rows on first sign-in if the tables are empty.
 * Fixed UUIDs keep re-seeding idempotent.
 */
import type {
  AppData,
  Exercise,
  Meal,
  Profile,
  Program,
  ProgramDay,
  RepUnit,
  Settings,
  Supplement,
} from '../lib/types'
import type { PersonaSlug } from '../lib/persona'
import { buildFriendSeedData } from './personaSeeds.ts'
import { ACTIVITY_CATALOG } from '../lib/activity.ts'
import { CURRENT_SEED_VERSION } from '../lib/seedRepair.ts'

const P = '11111111-0000-4000-8000-' // program/day/exercise id prefix
let seq = 0
function sid(): string {
  seq += 1
  return P + String(seq).padStart(12, '0')
}

function today(): string {
  return new Date().toISOString().slice(0, 10)
}

export function seedProfile(userId: string): Profile {
  return {
    id: P + 'aaaaaaaaaaaa',
    user_id: userId,
    persona: 'constantine',
    display_name: 'Constantine',
    sex: 'male',
    weight_kg: 70,
    body_fat_pct: 23,
    custom_bmr: null,
    height_cm: 178,
    birthdate: '1992-07-25',
    activity_level: 'moderate',
    goal: 'recomp',
    target_kcal: 2450,
    target_protein_g: 148,
    target_fat_g: 82,
    target_carbs_g: 280,
    training_time: '19:00',
    baseline_date: today(),
    profile_note: 'Personal recomposition system with balanced strength, mobility and endurance development.',
    seed_version: CURRENT_SEED_VERSION,
    calibration_k: 1,
    calibration_history: [],
    updated_at: new Date().toISOString(),
  }
}

export function seedSettings(userId: string): Settings {
  return {
    user_id: userId,
    voice_on: true,
    ticks_on: true,
    notifications_on: false,
    guardian_factor: 1.5,
    addons: { endurance1: false, endurance2: false, endurance3: false, uiMode: 'simple', newbie_mode: false, training_induction: null, training_protocol: { version: 81, start_date: today() }, comparison_export_mode: 'detailed', weight_unit: 'kg', simple_show_orbit: true, simple_show_body_index: true, simple_show_guided_plan: true, simple_show_hydration_reminder: false, simple_show_manual_workout: false, simple_show_next_action: false, adhd_mode: false },
  }
}

/* ---------------- Meals (section 4b) ---------------- */

export function seedMeals(userId: string): Meal[] {
  void userId
  return []
}

/* ---------------- Supplements (section 4c) ---------------- */

export function seedSupplements(userId: string): Supplement[] {
  type Row = {
    name: string
    dose: string
    group: string
    clock?: string
    offset?: number
    trainingOnly?: boolean
  }
  const rows: Row[] = [
    { name: 'Creatine monohydrate', dose: '3–5 g', group: 'Daily core', clock: '07:00' },
    { name: 'Iodised salt', dose: 'Use across meals to taste', group: 'Daily core', clock: '13:00' },
    { name: 'Whey isolate', dose: 'Only as needed to close the daily protein gap', group: 'As needed', clock: '15:30' },
    { name: 'Casein', dose: '25–30 g only as needed to close the daily protein gap', group: 'As needed', clock: '21:30' },
    { name: 'Citrulline malate', dose: '6–8 g', group: 'Optional training support', offset: -45, trainingOnly: true },
    { name: 'Cluster Dextrin', dose: 'Workload module only when food timing or session demand requires it', group: 'Optional training support', offset: -15, trainingOnly: true },
    { name: 'Collagen + Vitamin C', dose: '10–15 g collagen before tendon-focused work', group: 'Optional training support', offset: -45, trainingOnly: true },
  ]
  return rows.map((r, i) => ({
    id: sid(),
    user_id: userId,
    name: r.name,
    dose: r.dose,
    timing: r.clock ? 'clock' : 'training',
    clock_time: r.clock ?? null,
    offset_min: r.clock ? null : (r.offset ?? 0),
    group_label: r.group,
    training_days_only: r.trainingOnly ?? false,
    sort_order: i,
  }))
}

/* ---------------- Programs (Appendix A, verbatim) ---------------- */

interface ExSpec {
  name: string
  sets: number
  reps: [number, number] | 'max'
  unit?: RepUnit
  perSide?: boolean
  rest: number
  up?: number
  down?: number
  pause?: number
  tempoNote?: string
  notes?: string
  incr?: number
  optional?: boolean
}

interface DaySpec {
  weekday: number
  name: string
  type: ProgramDay['day_type']
  est: number
  warmup?: string
  full: ExSpec[]
  lite: ExSpec[]
}

function ex(spec: ExSpec, dayId: string, userId: string, isLite: boolean, order: number): Exercise {
  const isMax = spec.reps === 'max'
  return {
    id: sid(),
    user_id: userId,
    program_day_id: dayId,
    name: spec.name,
    sets: spec.sets,
    rep_min: isMax ? 0 : (spec.reps as [number, number])[0],
    rep_max: isMax ? 0 : (spec.reps as [number, number])[1],
    rep_unit: spec.unit ?? (isMax ? 'max' : 'reps'),
    per_side: spec.perSide ?? false,
    rest_sec: spec.rest,
    tempo_up_s: spec.up ?? 1,
    tempo_down_s: spec.down ?? 2,
    tempo_pause_s: spec.pause ?? 0,
    tempo_note: spec.tempoNote ?? '',
    notes: spec.notes ?? '',
    increment_kg: spec.incr ?? 0,
    is_lite: isLite,
    optional: spec.optional ?? false,
    sort_order: order,
  }
}

const TRANSITION_DAYS: DaySpec[] = [
  {
    weekday: 1,
    name: 'Legs A',
    type: 'legs_a',
    est: 18,
    warmup: 'Extra warm-up: 8 slow bodyweight hinges',
    full: [
      { name: 'Bulgarian Split Squat (backpack)', sets: 4, reps: [8, 12], perSide: true, rest: 120, incr: 2.5, notes: 'Rest 90-120s' },
      { name: 'Backpack RDL', sets: 3, reps: [8, 10], rest: 120, incr: 2.5, notes: 'Or single-leg RDL if load feels light. Hams at max stretch, flat spine. Rest 90-120s' },
      { name: 'Sliding Leg Curl (towel)', sets: 3, reps: [6, 10], rest: 75, up: 1, down: 3, tempoNote: 'Explode in, 3s eccentric out', notes: 'On back, hips bridged' },
      { name: 'Calf Raises (backpack, off a step)', sets: 3, reps: [15, 25], rest: 60, pause: 2, tempoNote: '2s deep stretch pause every rep', incr: 2.5 },
    ],
    lite: [
      { name: 'Bulgarian Split Squat (backpack)', sets: 4, reps: [8, 12], perSide: true, rest: 90, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Backpack RDL', sets: 3, reps: [8, 10], rest: 90, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
    ],
  },
  {
    weekday: 2,
    name: 'Push',
    type: 'push',
    est: 15,
    full: [
      { name: 'Weighted Pushups (handles, backpack)', sets: 4, reps: [8, 12], rest: 120, incr: 2.5, up: 0.6, down: 1, tempoNote: '1s down, explode up', notes: 'Deep ROM. Rest 90-120s' },
      { name: 'Pike Pushups (feet on chair)', sets: 3, reps: [8, 12], rest: 90, notes: 'Home OHP. Raise feet as you progress' },
      { name: 'Diamond Pushups', sets: 3, reps: 'max', rest: 60 },
    ],
    lite: [
      { name: 'Weighted Pushups (handles, backpack)', sets: 4, reps: [8, 12], rest: 90, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Pike Pushups (feet on chair)', sets: 3, reps: [8, 12], rest: 90, notes: 'Lite: every set 0-1 RIR' },
    ],
  },
  {
    weekday: 3,
    name: 'Pull',
    type: 'pull',
    est: 18,
    full: [
      { name: 'Pull-Ups', sets: 4, reps: [4, 8], rest: 120, incr: 2.5, notes: 'Full dead hang each rep. Add backpack weight once you own 4x8' },
      { name: 'Backpack Row', sets: 3, reps: [8, 12], rest: 90, incr: 2.5, notes: 'Or inverted row under table' },
      { name: 'Band or DB Curls', sets: 3, reps: [8, 12], rest: 60, incr: 1 },
      { name: 'Dead Hangs', sets: 2, reps: 'max', unit: 'max', rest: 45, notes: 'Thoracic decompression' },
    ],
    lite: [
      { name: 'Pull-Ups', sets: 4, reps: [4, 8], rest: 90, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Backpack Row', sets: 3, reps: [8, 12], rest: 90, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
    ],
  },
  {
    weekday: 4,
    name: 'Mobility & Reset',
    type: 'mobility',
    est: 13,
    warmup: 'Recovery day, no load, no grind',
    full: [
      { name: 'Functional stretch flow (saved YouTube favorite)', sets: 1, reps: [7, 15], unit: 'minutes', rest: 0 },
      { name: 'Couch Stretch', sets: 1, reps: [60, 90], unit: 'seconds', perSide: true, rest: 0, notes: 'Reverses editing-chair hip flexor shortening' },
      { name: 'Thoracic Extension over chair edge', sets: 1, reps: [60, 90], unit: 'seconds', rest: 0 },
      { name: 'Band Pull-Aparts (posture closer)', sets: 3, reps: [20, 20], rest: 30 },
      { name: 'Band Face Pulls', sets: 2, reps: [15, 15], rest: 30, pause: 2, tempoNote: '2s hold' },
      { name: 'Dead Hang', sets: 2, reps: 'max', unit: 'max', rest: 45 },
    ],
    lite: [
      { name: 'Couch Stretch', sets: 1, reps: [60, 90], unit: 'seconds', perSide: true, rest: 0 },
      { name: 'Band Pull-Aparts', sets: 3, reps: [20, 20], rest: 30 },
      { name: 'Dead Hang', sets: 1, reps: 'max', unit: 'max', rest: 0 },
    ],
  },
  {
    weekday: 5,
    name: 'Legs B',
    type: 'legs_b',
    est: 18,
    warmup: 'Extra warm-up: 10 bodyweight squats',
    full: [
      { name: 'Heel-Elevated Goblet Squat (backpack)', sets: 4, reps: [8, 12], rest: 120, incr: 2.5, notes: 'Rest 90-120s' },
      { name: 'Walking Lunges (backpack)', sets: 3, reps: [8, 12], perSide: true, rest: 90, incr: 2.5 },
      { name: 'Sliding Leg Curl (towel)', sets: 3, reps: [8, 10], rest: 75, up: 1, down: 3, tempoNote: 'Explode in, slow out' },
      { name: 'Calf Raises (single-leg or backpack)', sets: 3, reps: [25, 30], rest: 60, tempoNote: 'Deep stretch', incr: 2.5 },
    ],
    lite: [
      { name: 'Heel-Elevated Goblet Squat (backpack)', sets: 4, reps: [8, 12], rest: 90, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Walking Lunges (backpack)', sets: 3, reps: [8, 12], perSide: true, rest: 90, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
    ],
  },
  {
    weekday: 6,
    name: 'FocusT25',
    type: 't25',
    est: 25,
    full: [
      { name: 'FocusT25 session (Shaun T), Alpha or Beta cycle', sets: 1, reps: [25, 25], unit: 'minutes', rest: 0, notes: 'The engine. Maps to Endurance XP' },
      { name: 'Band Pull-Aparts (finisher if fresh)', sets: 2, reps: [20, 20], rest: 30, optional: true },
    ],
    lite: [
      { name: 'Any 10-min HIIT video', sets: 1, reps: [10, 10], unit: 'minutes', rest: 0 },
      { name: 'Band Pull-Aparts', sets: 2, reps: [20, 20], rest: 30 },
    ],
  },
  {
    weekday: 7,
    name: 'Upper',
    type: 'upper',
    est: 15,
    full: [
      { name: 'Pull-Ups (different grip than Wed)', sets: 4, reps: [4, 8], rest: 120, incr: 2.5 },
      { name: 'Weighted Pushups', sets: 3, reps: [8, 12], rest: 90, incr: 2.5, notes: 'Or DB OHP' },
      { name: 'Band Face Pulls', sets: 3, reps: [15, 20], rest: 45, pause: 2, tempoNote: '2s hold' },
      { name: 'Hammer or Incline DB Curls', sets: 3, reps: [8, 12], rest: 60, incr: 1 },
    ],
    lite: [
      { name: 'Pull-Ups (different grip than Wed)', sets: 4, reps: [4, 8], rest: 90, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Weighted Pushups', sets: 3, reps: [8, 12], rest: 90, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
    ],
  },
]

const MAIN_DAYS: DaySpec[] = [
  {
    weekday: 1,
    name: 'Legs A · Foundation',
    type: 'legs_a',
    est: 52,
    warmup: '8 bodyweight split squats per side, 10 slow hinges and 10 ankle rocks per side',
    full: [
      { name: 'Bulgarian Split Squat', sets: 4, reps: [8, 12], perSide: true, rest: 120, incr: 2.5, notes: '90–120 seconds. Control every rep.' },
      { name: 'Dumbbell Romanian Deadlift', sets: 3, reps: [8, 10], rest: 120, incr: 2.5 },
      { name: 'Sliding Leg Curl', sets: 3, reps: [10, 15], rest: 90, down: 3 },
      { name: 'Single-Leg Calf Raise', sets: 3, reps: [12, 20], perSide: true, rest: 60 },
    ],
    lite: [
      { name: 'Bulgarian Split Squat', sets: 3, reps: [8, 12], perSide: true, rest: 120, incr: 2.5 },
      { name: 'Dumbbell Romanian Deadlift', sets: 2, reps: [8, 10], rest: 120, incr: 2.5 },
      { name: 'Sliding Leg Curl', sets: 2, reps: [10, 15], rest: 90, down: 3 },
    ],
  },
  {
    weekday: 2,
    name: 'Push A + Focus T25 Core',
    type: 'push',
    est: 61,
    warmup: '15 band pull-aparts, 2 sets of 8 scapular push-ups and one easy set of 8 push-ups',
    full: [
      { name: 'Weighted Push-Up on Handles', sets: 4, reps: [12, 15], rest: 120, incr: 2.5 },
      { name: 'Feet-Elevated Push-Up', sets: 3, reps: [10, 12], rest: 120, incr: 2.5 },
      { name: 'Diamond or Close-Grip Push-Up', sets: 2, reps: [8, 15], rest: 90 },
      { name: 'Focus T25 · Tuesday core', sets: 1, reps: [1, 1], unit: 'check', rest: 0, notes: 'Episode adapts to the current V8.1 block.' },
    ],
    lite: [
      { name: 'Weighted Push-Up on Handles', sets: 3, reps: [12, 15], rest: 120, incr: 2.5 },
      { name: 'Feet-Elevated Push-Up', sets: 2, reps: [10, 12], rest: 120, incr: 2.5 },
      { name: 'Focus T25 · Tuesday core', sets: 1, reps: [1, 1], unit: 'check', rest: 0, notes: 'Episode adapts to the current V8.1 block.' },
    ],
  },
  {
    weekday: 3,
    name: 'Pull A + Gimbal + Focus T25',
    type: 'pull',
    est: 65,
    warmup: 'Scapular pull-ups, band rows and one easy assisted pull-up set',
    full: [
      { name: 'Band-Assisted Pull-Up', sets: 4, reps: [4, 6], rest: 120 },
      { name: 'Chest-Supported Dumbbell Row', sets: 3, reps: [8, 12], rest: 90, incr: 2.5 },
      { name: 'Band Face Pull', sets: 2, reps: [15, 20], rest: 60, pause: 2 },
      { name: 'Gimbal Front Hold', sets: 3, reps: [30, 45], unit: 'seconds', rest: 60 },
      { name: 'Focus T25 · Wednesday lower and speed', sets: 1, reps: [1, 1], unit: 'check', rest: 0, notes: 'Episode adapts to the current V8.1 block.' },
    ],
    lite: [
      { name: 'Band-Assisted Pull-Up', sets: 3, reps: [4, 6], rest: 120 },
      { name: 'Chest-Supported Dumbbell Row', sets: 2, reps: [8, 12], rest: 90, incr: 2.5 },
      { name: 'Gimbal Front Hold', sets: 2, reps: [30, 45], unit: 'seconds', rest: 60 },
      { name: 'Focus T25 · Wednesday lower and speed', sets: 1, reps: [1, 1], unit: 'check', rest: 0, notes: 'Episode adapts to the current V8.1 block.' },
    ],
  },
  {
    weekday: 4,
    name: 'Recovery + Focus T25 Stretch',
    type: 'mobility',
    est: 34,
    warmup: 'No loaded warm-up. Keep the entire session easy and pain-free.',
    full: [
      { name: 'Focus T25 · Stretch', sets: 1, reps: [1, 1], unit: 'check', rest: 0 },
      { name: 'Bird-Dog', sets: 2, reps: [6, 6], perSide: true, rest: 0, pause: 3, notes: 'Two circuit rounds. Pause three seconds.' },
      { name: 'Wall Slide', sets: 2, reps: [10, 10], rest: 0, notes: 'Two circuit rounds.' },
      { name: 'Band Pull-Apart', sets: 2, reps: [15, 15], rest: 0, notes: 'Two circuit rounds.' },
      { name: 'Side Plank', sets: 2, reps: [20, 30], unit: 'seconds', perSide: true, rest: 0, notes: 'Two circuit rounds.' },
    ],
    lite: [
      { name: 'Focus T25 · Stretch', sets: 1, reps: [1, 1], unit: 'check', rest: 0 },
      { name: 'Bird-Dog', sets: 2, reps: [6, 6], perSide: true, rest: 0, pause: 3 },
      { name: 'Wall Slide', sets: 2, reps: [10, 10], rest: 0 },
    ],
  },
  {
    weekday: 5,
    name: 'Legs B + Focus T25',
    type: 'legs_b',
    est: 64,
    warmup: '6 reverse lunges per side, 10 slow hinges and 10 ankle rocks per side',
    full: [
      { name: 'Front Lunge', sets: 2, reps: [8, 12], perSide: true, rest: 90, incr: 2.5 },
      { name: 'Reverse Lunge', sets: 2, reps: [8, 12], perSide: true, rest: 90, incr: 2.5 },
      { name: 'Single-Leg Romanian Deadlift', sets: 3, reps: [8, 12], perSide: true, rest: 90, incr: 2.5 },
      { name: 'Calf Raise', sets: 2, reps: [15, 25], rest: 60, incr: 2.5 },
      { name: 'Focus T25 · Friday conditioning', sets: 1, reps: [1, 1], unit: 'check', rest: 0, notes: 'Episode adapts to the current V8.1 block.' },
    ],
    lite: [
      { name: 'Front Lunge', sets: 2, reps: [8, 12], perSide: true, rest: 90, incr: 2.5 },
      { name: 'Single-Leg Romanian Deadlift', sets: 2, reps: [8, 12], perSide: true, rest: 90, incr: 2.5 },
      { name: 'Focus T25 · Friday conditioning', sets: 1, reps: [1, 1], unit: 'check', rest: 0, notes: 'Episode adapts to the current V8.1 block.' },
    ],
  },
  {
    weekday: 6,
    name: 'Push B',
    type: 'push',
    est: 31,
    warmup: '15 band pull-aparts, 8 scapular push-ups and two progressive push-up sets',
    full: [
      { name: 'Weighted Push-Up', sets: 4, reps: [6, 10], rest: 120, incr: 2.5 },
      { name: 'Pike Push-Up', sets: 2, reps: [8, 12], rest: 90 },
    ],
    lite: [
      { name: 'Weighted Push-Up', sets: 3, reps: [6, 10], rest: 120, incr: 2.5 },
      { name: 'Pike Push-Up', sets: 2, reps: [8, 12], rest: 90 },
    ],
  },
  {
    weekday: 7,
    name: 'Pull B',
    type: 'pull',
    est: 43,
    warmup: 'Scapular pull-ups, band rows and one easy assisted pull-up set',
    full: [
      { name: 'Band-Assisted Pull-Up', sets: 3, reps: [4, 6], rest: 120 },
      { name: 'One-Arm Supported Dumbbell Row', sets: 3, reps: [8, 12], perSide: true, rest: 90, incr: 2.5 },
      { name: 'Gimbal Front Hold', sets: 2, reps: [45, 60], unit: 'seconds', rest: 60 },
      { name: 'Suitcase Hold or March', sets: 2, reps: [30, 45], unit: 'seconds', perSide: true, rest: 60, incr: 2.5 },
    ],
    lite: [
      { name: 'Band-Assisted Pull-Up', sets: 2, reps: [4, 6], rest: 120 },
      { name: 'One-Arm Supported Dumbbell Row', sets: 2, reps: [8, 12], perSide: true, rest: 90, incr: 2.5 },
      { name: 'Gimbal Front Hold', sets: 2, reps: [45, 60], unit: 'seconds', rest: 60 },
    ],
  },
]

export function seedPrograms(userId: string): {
  programs: Program[]
  program_days: ProgramDay[]
  exercises: Exercise[]
} {
  const programs: Program[] = [
    {
      id: sid(),
      user_id: userId,
      slug: 'transition',
      name: 'Transition Phase',
      description: 'Current corrected home program. Every session opens with Band Pull-Aparts 3x20.',
    },
    {
      id: sid(),
      user_id: userId,
      slug: 'main',
      name: 'Main Phase',
      description: 'Elite V6 full version, for after the transition. Every session opens with Band Pull-Aparts 3x20.',
    },
  ]
  const program_days: ProgramDay[] = []
  const exercises: Exercise[] = []

  const specs: Array<[Program, DaySpec[]]> = [
    [programs[0], TRANSITION_DAYS],
    [programs[1], MAIN_DAYS],
  ]
  for (const [program, days] of specs) {
    days.forEach((d, di) => {
      const dayId = sid()
      program_days.push({
        id: dayId,
        user_id: userId,
        program_id: program.id,
        weekday: d.weekday,
        name: d.name,
        day_type: d.type,
        est_minutes: d.est,
        warmup_note: d.warmup ?? '',
        sort_order: di,
      })
      d.full.forEach((s, i) => exercises.push(ex(s, dayId, userId, false, i)))
      d.lite.forEach((s, i) => exercises.push(ex(s, dayId, userId, true, i)))
    })
  }
  return { programs, program_days, exercises }
}

export function buildSeedData(userId: string, persona: PersonaSlug = 'constantine'): AppData {
  if (persona === 'june' || persona === 'matthew' || persona === 'iulian') return buildFriendSeedData(userId, persona)
  seq = 0
  const { programs, program_days, exercises } = seedPrograms(userId)
  return {
    profile: seedProfile(userId),
    settings: seedSettings(userId),
    meals: seedMeals(userId),
    meal_logs: [],
    supplements: seedSupplements(userId),
    supplement_logs: [],
    programs,
    program_days,
    exercises,
    workout_sessions: [],
    workout_logs: [],
    activity_types: ACTIVITY_CATALOG,
    activity_logs: [],
    daily_logs: [],
    events: [],
    rpg_snapshots: [],
    deload_marks: [],
    health_metrics: [],
    imported_activities: [],
  }
}

/* Universal warm-up prepended to every session (Appendix A universal rule) */
export const UNIVERSAL_WARMUP = 'Band Pull-Aparts 3x20, mid-back activation, anti-camera-roll'
