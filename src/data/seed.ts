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
    height_cm: 178,
    birthdate: '1992-07-25',
    activity_level: 'moderate',
    goal: 'recomp',
    target_kcal: null,
    target_protein_g: null,
    target_fat_g: null,
    target_carbs_g: null,
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
    addons: { endurance1: false, endurance2: false, endurance3: false, uiMode: 'advanced' },
  }
}

/* ---------------- Meals (section 4b) ---------------- */

export function seedMeals(userId: string): Meal[] {
  const rows: Array<
    [string, string, string, number, number, number, number, boolean]
  > = [
    [
      '07:00',
      'Breakfast',
      '4 eggs + 35 g nut mix. Zero carbs, dopamine-protected morning.',
      510, 31, 39, 8, false,
    ],
    [
      '13:00',
      'Oat Jar',
      'Oats + milk + berries + banana + kiwi + magerquark or chicken hearts + seed mix + EVOO.',
      900, 48, 26, 105, false,
    ],
    [
      '15:30',
      'Bulgur Snack',
      'Bulgur + cottage cheese + veggies. Full days only.',
      440, 30, 10, 52, true,
    ],
    [
      '18:30',
      'Dinner',
      'Sweet potato + protein (pollock airfryer / chicken) + avocado + veggies.',
      650, 45, 17, 65, false,
    ],
    ['21:45', 'Casein shake', 'Casein isolate 45 g in water.', 170, 38, 1, 3, false],
  ]
  return rows.map(([time, name, foods, kcal, p, f, c, fullOnly], i) => ({
    id: sid(),
    user_id: userId,
    time,
    name,
    foods,
    kcal,
    protein_g: p,
    fat_g: f,
    carbs_g: c,
    full_days_only: fullOnly,
    sort_order: i,
  }))
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
    { name: 'Taurine', dose: '3 g', group: 'Wake', clock: '05:30' },
    { name: 'Tyrosine', dose: '', group: 'Wake', clock: '05:30' },
    { name: 'Rhodiola', dose: '500 mg', group: 'Wake', clock: '05:30' },
    { name: 'Fish oil, high concentration', dose: '', group: 'Breakfast', clock: '07:00' },
    { name: 'Tongkat Ali', dose: '', group: 'Breakfast', clock: '07:00' },
    { name: 'Vitamin D3 + MK-7', dose: '', group: 'Breakfast', clock: '07:00' },
    { name: 'Boron', dose: '', group: 'Breakfast', clock: '07:00' },
    { name: 'Vitamin C, low dose', dose: '', group: 'T-60', offset: -60 },
    { name: 'Pure bovine collagen', dose: '15 g', group: 'T-60', offset: -60 },
    { name: 'Alpha-GPC', dose: '600 mg', group: 'T-45', offset: -45 },
    { name: 'EAA', dose: '10 g', group: 'T-15 training drink', offset: -15 },
    { name: 'Glycerol', dose: '25 g', group: 'T-15 training drink', offset: -15 },
    { name: 'L-Citrulline Malate', dose: '6-8 g', group: 'T-15 training drink', offset: -15 },
    { name: 'Iodised sodium', dose: 'pinch', group: 'T-15 training drink', offset: -15 },
    { name: 'Cluster Dextrin', dose: '40 g', group: 'T-15 training drink', offset: -15 },
    { name: 'L-Theanine', dose: '200 mg', group: 'Post-workout', offset: 75 },
    { name: 'Whey isolate shake', dose: '~30 g', group: 'Post-workout', offset: 75 },
    { name: 'Casein isolate', dose: '45 g', group: 'Evening', clock: '21:45' },
    {
      name: 'Collagen + Vitamin C',
      dose: '',
      group: 'Evening',
      clock: '21:45',
      trainingOnly: true,
    },
    { name: 'Zinc bisglycinate', dose: '15 mg', group: 'Sleep stack', clock: '22:30' },
    { name: 'Magnesium bisglycinate', dose: '200 mg', group: 'Sleep stack', clock: '22:30' },
    { name: 'L-Theanine', dose: '', group: 'Sleep stack', clock: '22:30' },
    {
      name: 'Sunflower Phosphatidylserine',
      dose: '300 mg',
      group: 'Sleep stack',
      clock: '22:30',
    },
    { name: 'Glycine', dose: '3-5 g', group: 'Sleep stack', clock: '22:30' },
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
    name: 'Legs A',
    type: 'legs_a',
    est: 45,
    warmup: 'Glute + ham focus',
    full: [
      { name: 'Bulgarian Split Squats', sets: 4, reps: [8, 12], perSide: true, rest: 120, incr: 2.5 },
      { name: 'Romanian Deadlift', sets: 3, reps: [6, 10], rest: 120, incr: 2.5 },
      { name: 'Seated Leg Curls', sets: 4, reps: [10, 12], rest: 75, incr: 1, up: 0.6, down: 3, tempoNote: 'Explode up, 3s down' },
      { name: 'Standing Calf Raises', sets: 3, reps: [15, 25], rest: 60, pause: 2, tempoNote: '2s deep stretch pause', incr: 2.5 },
      { name: 'Abs finisher', sets: 3, reps: [10, 15], rest: 45, notes: 'Hanging leg raises / weighted crunches' },
      { name: 'Hip Thrusts', sets: 3, reps: [8, 12], rest: 90, incr: 2.5, optional: true, notes: 'Partner priority, 1-2 sets for me or stretch' },
    ],
    lite: [
      { name: 'Bulgarian Split Squats', sets: 4, reps: [8, 12], perSide: true, rest: 120, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Romanian Deadlift', sets: 3, reps: [6, 10], rest: 120, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Seated Leg Curls', sets: 4, reps: [10, 12], rest: 75, incr: 1, notes: 'Lite: every set 0-1 RIR' },
    ],
  },
  {
    weekday: 2,
    name: 'Push A',
    type: 'push',
    est: 40,
    warmup: 'Calisthenics volume',
    full: [
      { name: 'Weighted Pushups (handles)', sets: 4, reps: [15, 15], rest: 120, incr: 2.5 },
      { name: 'Feet-Elevated Weighted Pushups', sets: 3, reps: [12, 12], rest: 120, incr: 2.5 },
      { name: 'Diamond Pushups', sets: 3, reps: 'max', rest: 60, notes: 'To failure' },
      { name: 'Face Pulls', sets: 3, reps: [15, 20], rest: 45, pause: 2, tempoNote: 'Pinkies up, external rotate, 2s hold', incr: 1 },
    ],
    lite: [
      { name: 'Weighted Pushups (handles)', sets: 4, reps: 'max', rest: 90, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Diamond Pushups', sets: 3, reps: 'max', rest: 60, notes: 'Lite: every set 0-1 RIR' },
    ],
  },
  {
    weekday: 3,
    name: 'Pull A',
    type: 'pull',
    est: 40,
    warmup: 'Heavy pull',
    full: [
      { name: 'Pull-Ups', sets: 4, reps: [4, 8], rest: 120, incr: 2.5, notes: '1-2 RIR, add weight at 4x8' },
      { name: 'Chest-Supported Row', sets: 3, reps: [8, 12], rest: 90, incr: 2.5 },
      { name: 'Incline DB Curls (45 degrees)', sets: 3, reps: [8, 12], rest: 60, incr: 1 },
      { name: 'Dead Hangs', sets: 3, reps: [20, 40], unit: 'seconds', rest: 45 },
    ],
    lite: [
      { name: 'Pull-Ups', sets: 4, reps: [4, 8], rest: 120, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Chest-Supported Row', sets: 3, reps: [8, 12], rest: 90, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Hammer Curls', sets: 3, reps: [8, 12], rest: 60, incr: 1, notes: 'Lite: every set 0-1 RIR' },
    ],
  },
  {
    weekday: 4,
    name: 'Fix',
    type: 'fix',
    est: 20,
    warmup: 'Corrective work, never to failure',
    full: [
      { name: 'Face Pulls (5s hold)', sets: 3, reps: [15, 20], rest: 30, pause: 5, tempoNote: '5s hold', incr: 1 },
      { name: 'Prone Y-Raises', sets: 3, reps: [10, 15], rest: 30, incr: 1, notes: '2-3 kg max, lower trap' },
      { name: 'Bird-Dogs (pause)', sets: 3, reps: [6, 8], perSide: true, rest: 30, pause: 2 },
      { name: 'Dead Hangs', sets: 3, reps: [20, 40], unit: 'seconds', rest: 45 },
    ],
    lite: [
      { name: 'Face Pulls (5s hold)', sets: 3, reps: [15, 20], rest: 30, pause: 5, incr: 1, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Bird-Dogs (pause)', sets: 3, reps: [6, 8], perSide: true, rest: 30, pause: 2, notes: 'Lite' },
    ],
  },
  {
    weekday: 5,
    name: 'Legs B',
    type: 'legs_b',
    est: 45,
    warmup: 'Quad priority',
    full: [
      { name: 'Leg Press / Hack Squat', sets: 3, reps: [6, 10], rest: 120, incr: 2.5 },
      { name: 'Walking Lunges', sets: 3, reps: [8, 12], perSide: true, rest: 90, incr: 2.5 },
      { name: 'Seated Leg Curls', sets: 4, reps: [10, 12], rest: 75, incr: 1 },
      { name: 'Leg Extensions', sets: 3, reps: [12, 15], rest: 60, incr: 1, notes: 'Last 2 sets to failure' },
      { name: 'Abs finisher', sets: 3, reps: [10, 15], rest: 45, notes: 'Different variation than Mon' },
      { name: 'Bent-Knee Calf Raises', sets: 3, reps: [25, 30], rest: 60, notes: 'Soleus, 25-30+' },
      { name: 'Hip Thrusts', sets: 3, reps: [8, 12], rest: 90, incr: 2.5, optional: true },
    ],
    lite: [
      { name: 'Leg Press', sets: 4, reps: [6, 10], rest: 120, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Walking Lunges', sets: 3, reps: [8, 12], perSide: true, rest: 90, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Seated Leg Curls', sets: 4, reps: [10, 12], rest: 75, incr: 1, notes: 'Lite: every set 0-1 RIR' },
    ],
  },
  {
    weekday: 6,
    name: 'Push B',
    type: 'push',
    est: 40,
    warmup: 'Strength focus',
    full: [
      { name: 'Weighted Pushups', sets: 3, reps: [6, 10], rest: 120, incr: 2.5, notes: 'Heavy' },
      { name: 'Overhead Press', sets: 3, reps: [6, 10], rest: 120, incr: 2.5, notes: 'Strict, only OHP day' },
      { name: 'Lateral Raises', sets: 3, reps: [15, 20], rest: 60, incr: 1 },
      { name: 'OH Tricep Extension', sets: 3, reps: [10, 12], rest: 60, incr: 1 },
    ],
    lite: [
      { name: 'Weighted Pushups', sets: 4, reps: [6, 10], rest: 120, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Overhead Press', sets: 3, reps: [6, 10], rest: 120, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
    ],
  },
  {
    weekday: 7,
    name: 'Pull B',
    type: 'pull',
    est: 40,
    warmup: 'Heavy pull 2',
    full: [
      { name: 'Pull-Ups (different grip than Wed)', sets: 4, reps: [4, 8], rest: 120, incr: 2.5 },
      { name: 'Chest-Supported Row (different implement than Wed)', sets: 3, reps: [8, 12], rest: 90, incr: 2.5 },
      { name: 'Preacher Curls', sets: 3, reps: [10, 15], rest: 60, incr: 1, pause: 2, tempoNote: '2s squeeze at top' },
      { name: 'Hammer Curls', sets: 3, reps: [10, 15], rest: 60, incr: 1 },
    ],
    lite: [
      { name: 'Pull-Ups (different grip than Wed)', sets: 4, reps: [4, 8], rest: 120, incr: 2.5, notes: 'Lite: every set 0-1 RIR' },
      { name: 'Incline DB Curls', sets: 3, reps: [8, 12], rest: 60, incr: 1, notes: 'Lite: every set 0-1 RIR' },
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
  if (persona === 'june' || persona === 'matthew') return buildFriendSeedData(userId, persona)
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
