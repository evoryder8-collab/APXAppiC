import type {
  AppData,
  DayType,
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
import { ACTIVITY_CATALOG } from '../lib/activity.ts'
import { CURRENT_SEED_VERSION } from '../lib/seedRepair.ts'

type FriendPersona = Exclude<PersonaSlug, 'constantine'>

interface ExerciseSpec {
  name: string
  sets: number
  reps: [number, number] | 'max'
  unit?: RepUnit
  perSide?: boolean
  rest?: number
  up?: number
  down?: number
  pause?: number
  note?: string
  tempo?: string
  increment?: number
  optional?: boolean
}

interface DaySpec {
  weekday: number
  name: string
  type: DayType
  minutes: number
  slot?: 'morning' | 'official' | 't25'
  warmup: string
  full: ExerciseSpec[]
  lite: ExerciseSpec[]
}

function hash32(value: string, seed: number): number {
  let hash = seed >>> 0
  for (let i = 0; i < value.length; i += 1) {
    hash ^= value.charCodeAt(i)
    hash = Math.imul(hash, 16777619)
  }
  hash ^= hash >>> 16
  hash = Math.imul(hash, 0x7feb352d)
  hash ^= hash >>> 15
  return hash >>> 0
}

function uuidFor(userId: string, label: string): string {
  const input = `${userId}:${label}`
  const raw = [
    hash32(input, 0x811c9dc5),
    hash32(input, 0x9e3779b9),
    hash32(input, 0x85ebca6b),
    hash32(input, 0xc2b2ae35),
  ].map((part) => part.toString(16).padStart(8, '0')).join('')
  const variant = ((parseInt(raw[16], 16) & 0x3) | 0x8).toString(16)
  return `${raw.slice(0, 8)}-${raw.slice(8, 12)}-4${raw.slice(13, 16)}-${variant}${raw.slice(17, 20)}-${raw.slice(20, 32)}`
}

function today(): string {
  return new Date().toISOString().slice(0, 10)
}

export const LEGACY_JUNE_DAYS: DaySpec[] = [
  {
    weekday: 1, name: 'Glutes A · Partner strength', type: 'legs_a', minutes: 58,
    warmup: '8 bodyweight split squats per side, 10 slow hinges and 10 ankle rocks per side',
    full: [
      { name: 'Bulgarian Split Squat', sets: 3, reps: [8, 12], perSide: true, rest: 120, increment: 2, note: 'Partner-sync block 1 of 3.' },
      { name: 'Dumbbell Romanian Deadlift', sets: 3, reps: [8, 12], rest: 120, increment: 2, note: 'Partner-sync block 2 of 3.' },
      { name: 'Sliding Leg Curl', sets: 2, reps: [10, 15], rest: 90, down: 3, note: 'Partner-sync block 3 of 3.' },
      { name: 'Dumbbell Hip Thrust', sets: 3, reps: [8, 12], rest: 120, pause: 2, increment: 2, tempo: 'Hold the top for 2 seconds', note: 'June-only glute hypertrophy block after the shared work.' },
      { name: 'Band Abduction', sets: 2, reps: [15, 25], rest: 60 },
    ],
    lite: [
      { name: 'Bulgarian Split Squat', sets: 2, reps: [8, 12], perSide: true, rest: 120, increment: 2 },
      { name: 'Dumbbell Romanian Deadlift', sets: 2, reps: [8, 12], rest: 120, increment: 2 },
      { name: 'Dumbbell Hip Thrust', sets: 2, reps: [8, 12], rest: 120, pause: 2, increment: 2 },
    ],
  },
  {
    weekday: 2, name: 'Push A + Focus T25 Core', type: 'push', minutes: 45,
    warmup: '15 band pull-aparts and 2 sets of 8 scapular push-ups',
    full: [
      { name: 'Strict Push-Up', sets: 3, reps: [10, 15], rest: 90 },
      { name: 'Feet-Elevated Push-Up', sets: 2, reps: [8, 12], rest: 90, note: 'Shared second movement. Use a stable height and stop with 2 clean reps available.' },
      { name: 'Diamond or Close-Grip Push-Up', sets: 2, reps: [8, 15], rest: 90 },
      { name: 'Focus T25 · Tuesday core', sets: 1, reps: [1, 1], unit: 'check', rest: 0, note: 'Episode adapts to the current V8.1 block.' },
    ],
    lite: [
      { name: 'Strict Push-Up', sets: 2, reps: [10, 15], rest: 90 },
      { name: 'Feet-Elevated Push-Up', sets: 1, reps: [8, 12], rest: 90 },
      { name: 'Diamond or Close-Grip Push-Up', sets: 1, reps: [8, 15], rest: 90 },
      { name: 'Focus T25 · Tuesday core', sets: 1, reps: [1, 1], unit: 'check', rest: 0, note: 'Episode adapts to the current V8.1 block.' },
    ],
  },
  {
    weekday: 3, name: 'Pull A + Focus T25', type: 'pull', minutes: 48,
    warmup: 'Scapular pull-ups, band rows and one easy assisted set',
    full: [
      { name: 'Band-Assisted Pull-Up', sets: 3, reps: [4, 8], rest: 120 },
      { name: 'Chest-Supported Dumbbell Row', sets: 3, reps: [8, 12], rest: 90, increment: 2 },
      { name: 'Band Face Pull', sets: 2, reps: [15, 20], rest: 60, pause: 2 },
      { name: 'Gimbal Front Hold', sets: 2, reps: [30, 45], unit: 'seconds', rest: 60, note: 'Shared filming-capacity block. Stop before shaking or shoulder pain.' },
      { name: 'Focus T25 · Wednesday lower and speed', sets: 1, reps: [1, 1], unit: 'check', rest: 0, note: 'Episode adapts to the current V8.1 block.' },
    ],
    lite: [
      { name: 'Band-Assisted Pull-Up', sets: 2, reps: [4, 8], rest: 120 },
      { name: 'Chest-Supported Dumbbell Row', sets: 2, reps: [8, 12], rest: 90, increment: 2 },
      { name: 'Gimbal Front Hold', sets: 1, reps: [30, 45], unit: 'seconds', rest: 60 },
      { name: 'Focus T25 · Wednesday lower and speed', sets: 1, reps: [1, 1], unit: 'check', rest: 0, note: 'Episode adapts to the current V8.1 block.' },
    ],
  },
  {
    weekday: 4, name: 'Recovery + Focus T25 Stretch', type: 'mobility', minutes: 34,
    warmup: 'No loaded warm-up. Keep the entire session easy and pain-free.',
    full: [
      { name: 'Focus T25 · Stretch', sets: 1, reps: [1, 1], unit: 'check', rest: 0 },
      { name: 'Bird-Dog', sets: 2, reps: [6, 6], perSide: true, rest: 0, pause: 3, note: 'Two circuit rounds. Pause three seconds.' },
      { name: 'Wall Slide', sets: 2, reps: [10, 10], rest: 0, note: 'Two circuit rounds.' },
      { name: 'Band Pull-Apart', sets: 2, reps: [15, 15], rest: 0, note: 'Two circuit rounds.' },
      { name: 'Side Plank', sets: 2, reps: [20, 30], unit: 'seconds', perSide: true, rest: 0, note: 'Shared posture circuit. Keep breathing normally.' },
      { name: 'Wrist Extensor Isometric', sets: 2, reps: [20, 20], unit: 'seconds', perSide: true, rest: 0, note: 'Two circuit rounds.' },
    ],
    lite: [
      { name: 'Focus T25 · Stretch', sets: 1, reps: [1, 1], unit: 'check', rest: 0 },
      { name: 'Bird-Dog', sets: 2, reps: [6, 6], perSide: true, rest: 0, pause: 3 },
      { name: 'Wall Slide', sets: 2, reps: [10, 10], rest: 0 },
    ],
  },
  {
    weekday: 5, name: 'Glutes B · Partner strength', type: 'legs_b', minutes: 56,
    warmup: '6 reverse lunges per side, 10 slow hinges and 10 ankle rocks per side',
    full: [
      { name: 'Front Lunge', sets: 2, reps: [8, 12], perSide: true, rest: 90, increment: 2, note: 'Partner-sync block 1 of 3.' },
      { name: 'Reverse Lunge', sets: 2, reps: [8, 12], perSide: true, rest: 90, increment: 2, note: 'Partner-sync block 2 of 3.' },
      { name: 'Single-Leg Romanian Deadlift', sets: 2, reps: [8, 12], perSide: true, rest: 90, increment: 2, note: 'Partner-sync block 3 of 3.' },
      { name: 'B-Stance or Single-Leg Hip Thrust', sets: 3, reps: [8, 12], perSide: true, rest: 90, pause: 2, increment: 2, note: 'June-only glute hypertrophy block.' },
      { name: 'Sliding Leg Curl', sets: 2, reps: [10, 15], rest: 90, down: 3, note: 'June-only hamstring finisher.' },
      { name: 'Frog Pump', sets: 1, reps: [25, 35], rest: 60, note: 'June-only glute finisher. Constantin can stop after his own calf work.' },
    ],
    lite: [
      { name: 'Front Lunge', sets: 1, reps: [8, 12], perSide: true, rest: 90, increment: 2 },
      { name: 'Reverse Lunge', sets: 2, reps: [8, 12], perSide: true, rest: 120, increment: 2 },
      { name: 'Single-Leg Romanian Deadlift', sets: 1, reps: [8, 12], perSide: true, rest: 90, increment: 2 },
      { name: 'B-Stance or Single-Leg Hip Thrust', sets: 2, reps: [8, 12], perSide: true, rest: 90, pause: 2, increment: 2 },
    ],
  },
  {
    weekday: 6, name: 'Push B', type: 'push', minutes: 31,
    warmup: 'Band pull-aparts and two progressive push-up sets',
    full: [
      { name: 'Weighted Push-Up', sets: 3, reps: [6, 10], rest: 120, increment: 2 },
      { name: 'Pike Push-Up', sets: 2, reps: [8, 12], rest: 90, note: 'Shared second movement.' },
      { name: 'Dumbbell Overhead Press', sets: 2, reps: [8, 12], rest: 90, increment: 2 },
      { name: 'Band Row', sets: 2, reps: [12, 15], rest: 60 },
    ],
    lite: [
      { name: 'Weighted Push-Up', sets: 2, reps: [6, 10], rest: 120, increment: 2 },
      { name: 'Pike Push-Up', sets: 1, reps: [8, 12], rest: 90 },
      { name: 'Dumbbell Overhead Press', sets: 2, reps: [8, 12], rest: 90, increment: 2 },
    ],
  },
  {
    weekday: 7, name: 'Full Rest', type: 'mobility', minutes: 0,
    warmup: '',
    full: [],
    lite: [],
  },
]

function juneMorning(
  weekday: number,
  hipThrustSets: number,
  abductionSets = 0,
): DaySpec {
  const full: ExerciseSpec[] = [
    { name: 'Weighted Dumbbell Hip Thrust', sets: hipThrustSets, reps: [6, 12], rest: 105, pause: 2, increment: 2, note: 'Separate morning glute exposure.' },
    ...(abductionSets > 0
      ? [{ name: 'Band Abduction', sets: abductionSets, reps: [15, 25] as [number, number], rest: 45, note: 'Separate morning glute exposure.' }]
      : []),
  ]
  return {
    weekday,
    name: 'AM · Hip thrust',
    type: 'legs_a',
    minutes: 18,
    slot: 'morning',
    warmup: 'Short morning glute primer. Keep the pelvis controlled and finish with clean reps in reserve.',
    full,
    lite: full.map((exercise) => ({ ...exercise, sets: Math.min(2, exercise.sets) })),
  }
}

function juneFocusT25(weekday: number, name: string): DaySpec {
  const confirmation: ExerciseSpec = {
    name: `Focus T25 · ${name}`,
    sets: 1,
    reps: [25, 25],
    unit: 'minutes',
    rest: 0,
    note: 'Separate Focus T25 follow-along card. Deload weeks retain Tuesday Core and Thursday Stretch only.',
  }
  return {
    weekday,
    name: `Focus T25 · ${name}`,
    type: 't25',
    minutes: 25,
    slot: 't25',
    warmup: 'Open the matching Focus T25 episode and complete it as its own session.',
    full: [confirmation],
    lite: [confirmation],
  }
}

const JUNE_V84_DAYS: DaySpec[] = [
  {
    weekday: 1, name: 'Glutes A · Strength', type: 'legs_a', minutes: 58, slot: 'official',
    warmup: 'Glute bridges, bodyweight split squats, slow hinges and ankle rocks.',
    full: [
      { name: 'Dumbbell Hip Thrust', sets: 4, reps: [6, 10], rest: 120, pause: 2, increment: 2 },
      { name: 'Bulgarian Split Squat', sets: 3, reps: [8, 12], perSide: true, rest: 120, increment: 2 },
      { name: 'Dumbbell Romanian Deadlift', sets: 3, reps: [8, 12], rest: 120, increment: 2 },
      { name: 'Band Abduction', sets: 2, reps: [15, 25], rest: 60 },
    ],
    lite: [
      { name: 'Dumbbell Hip Thrust', sets: 2, reps: [6, 10], rest: 120, pause: 2, increment: 2 },
      { name: 'Bulgarian Split Squat', sets: 2, reps: [8, 12], perSide: true, rest: 120, increment: 2 },
      { name: 'Dumbbell Romanian Deadlift', sets: 2, reps: [8, 12], rest: 120, increment: 2 },
    ],
  },
  juneMorning(2, 5),
  {
    weekday: 2, name: 'Push A · Strength', type: 'push', minutes: 30, slot: 'official',
    warmup: 'Scapular push-ups, wrist circles and one easy push-up set.',
    full: [
      { name: 'Strict Push-Up', sets: 3, reps: [10, 15], rest: 90 },
      { name: 'Diamond or Close-Grip Push-Up', sets: 2, reps: [8, 15], rest: 90 },
    ],
    lite: [
      { name: 'Strict Push-Up', sets: 2, reps: [10, 15], rest: 90 },
      { name: 'Diamond or Close-Grip Push-Up', sets: 1, reps: [8, 15], rest: 90 },
    ],
  },
  juneFocusT25(2, 'Core'),
  juneMorning(3, 3, 2),
  {
    weekday: 3, name: 'Pull A · Strength', type: 'pull', minutes: 42, slot: 'official',
    warmup: 'Scapular pull-ups, band rows and one easy assisted pull-up set.',
    full: [
      { name: 'Band-Assisted Pull-Up', sets: 3, reps: [4, 8], rest: 120 },
      { name: 'Chest-Supported Dumbbell Row', sets: 3, reps: [8, 12], rest: 90, increment: 2 },
      { name: 'Band Face Pull', sets: 2, reps: [15, 20], rest: 60, pause: 2 },
    ],
    lite: [
      { name: 'Band-Assisted Pull-Up', sets: 2, reps: [4, 8], rest: 120 },
      { name: 'Chest-Supported Dumbbell Row', sets: 2, reps: [8, 12], rest: 90, increment: 2 },
    ],
  },
  juneFocusT25(3, 'Lower Focus and Speed'),
  juneMorning(4, 5),
  {
    weekday: 4, name: 'Recovery · Posture and wrists', type: 'fix', minutes: 18, slot: 'official',
    warmup: 'Easy breathing and pain-free range only.',
    full: [{ name: 'Posture and Wrist Circuit', sets: 2, reps: [1, 1], unit: 'rounds', rest: 45, note: 'Two unhurried rounds.' }],
    lite: [{ name: 'Posture and Wrist Circuit', sets: 1, reps: [1, 1], unit: 'rounds', rest: 45 }],
  },
  juneFocusT25(4, 'Stretch'),
  {
    weekday: 5, name: 'Glutes B · Strength', type: 'legs_b', minutes: 55, slot: 'official',
    warmup: 'Reverse lunges, hip bridges and controlled single-leg hinges.',
    full: [
      { name: 'Reverse Lunge', sets: 3, reps: [8, 12], perSide: true, rest: 105, increment: 2 },
      { name: 'B-Stance or Single-Leg Hip Thrust', sets: 3, reps: [8, 12], perSide: true, rest: 105, pause: 2, increment: 2 },
      { name: 'Sliding Leg Curl', sets: 3, reps: [10, 15], rest: 90, down: 3 },
      { name: 'Frog Pump', sets: 1, reps: [25, 35], rest: 60 },
    ],
    lite: [
      { name: 'Reverse Lunge', sets: 2, reps: [8, 12], perSide: true, rest: 105, increment: 2 },
      { name: 'B-Stance or Single-Leg Hip Thrust', sets: 2, reps: [8, 12], perSide: true, rest: 105, pause: 2, increment: 2 },
      { name: 'Sliding Leg Curl', sets: 2, reps: [10, 15], rest: 90, down: 3 },
    ],
  },
  juneMorning(6, 3, 2),
  {
    weekday: 6, name: 'Push B · Strength', type: 'push', minutes: 38, slot: 'official',
    warmup: 'Scapular push-ups, wrist circles and one easy press set.',
    full: [
      { name: 'Weighted or Feet-Elevated Push-Up', sets: 3, reps: [6, 10], rest: 120, increment: 2 },
      { name: 'Dumbbell Overhead Press', sets: 2, reps: [8, 12], rest: 90, increment: 2 },
      { name: 'Band Row', sets: 2, reps: [12, 15], rest: 60 },
    ],
    lite: [
      { name: 'Weighted or Feet-Elevated Push-Up', sets: 2, reps: [6, 10], rest: 120, increment: 2 },
      { name: 'Band Row', sets: 2, reps: [12, 15], rest: 60 },
    ],
  },
  {
    weekday: 7, name: 'Rest · Full recovery', type: 'mobility', minutes: 0, slot: 'official',
    warmup: 'Full rest. A gentle walk is optional.', full: [], lite: [],
  },
]

const MATTHEW_DAYS: DaySpec[] = [
  {
    weekday: 1, name: 'Morning Strength A', type: 'upper', minutes: 36,
    warmup: '5 minutes: joint circles, squat-to-stand and scapular pull-ups',
    full: [
      { name: 'Weighted Squat', sets: 3, reps: [8, 12], rest: 90, increment: 2.5 },
      { name: 'Push-Up', sets: 3, reps: [10, 20], rest: 75, note: 'Add load only after 3x20 clean' },
      { name: 'Pull-Up', sets: 3, reps: [5, 10], rest: 120, increment: 2.5, note: 'Leave 1-2 reps in reserve' },
      { name: 'Big Hammer Loop', sets: 3, reps: [8, 12], perSide: true, rest: 60, note: 'Smooth orbit; ribs stacked' },
      { name: 'Hollow Body Hold', sets: 3, reps: [20, 40], unit: 'seconds', rest: 45 },
    ],
    lite: [
      { name: 'Weighted Squat', sets: 2, reps: [8, 12], rest: 75, increment: 2.5 },
      { name: 'Push-Up', sets: 2, reps: [10, 20], rest: 60 },
      { name: 'Pull-Up', sets: 2, reps: [5, 10], rest: 90 },
    ],
  },
  {
    weekday: 2, name: 'SkiErg Engine', type: 't25', minutes: 25,
    warmup: '5 easy minutes, then two short pace builds',
    full: [
      { name: 'SkiErg 500 m Interval', sets: 5, reps: [1, 1], rest: 90, note: 'Strong repeatable pace, not an all-out first interval' },
      { name: 'Dead Bug', sets: 3, reps: [8, 12], perSide: true, rest: 30 },
      { name: 'Hip Flexor + Lat Reset', sets: 1, reps: [5, 7], unit: 'minutes', rest: 0 },
    ],
    lite: [
      { name: 'SkiErg 500 m Controlled Challenge', sets: 2, reps: [1, 1], rest: 120 },
      { name: 'Dead Bug', sets: 2, reps: [8, 10], perSide: true, rest: 30 },
    ],
  },
  {
    weekday: 3, name: 'Skill + Pull', type: 'pull', minutes: 34,
    warmup: 'Shoulder prep, false-grip hangs and low rings/bar transitions',
    full: [
      { name: 'Muscle-Up Transition Practice', sets: 5, reps: [2, 4], rest: 120, note: 'Crisp submaximal reps; no grinding' },
      { name: 'Pull-Up', sets: 3, reps: [5, 10], rest: 120, increment: 2.5 },
      { name: 'Inverted Row', sets: 3, reps: [8, 15], rest: 75 },
      { name: 'Big Hammer Loop', sets: 3, reps: [8, 12], perSide: true, rest: 60 },
      { name: 'Hanging Knee Raise', sets: 3, reps: [8, 15], rest: 45 },
    ],
    lite: [
      { name: 'Muscle-Up Transition Practice', sets: 3, reps: [2, 3], rest: 120 },
      { name: 'Pull-Up', sets: 2, reps: [5, 10], rest: 90 },
      { name: 'Hanging Knee Raise', sets: 2, reps: [8, 12], rest: 45 },
    ],
  },
  {
    weekday: 4, name: 'Recovery + Core', type: 'mobility', minutes: 22,
    warmup: 'Keep this restorative; sauna and cold exposure are optional tools, not training',
    full: [
      { name: 'Mobility Flow', sets: 1, reps: [10, 12], unit: 'minutes', rest: 0 },
      { name: 'Side Plank', sets: 3, reps: [25, 45], unit: 'seconds', perSide: true, rest: 30 },
      { name: 'Bird-Dog', sets: 3, reps: [6, 10], perSide: true, rest: 30, pause: 2 },
      { name: 'Easy Nasal Walk', sets: 1, reps: [10, 20], unit: 'minutes', rest: 0, optional: true },
    ],
    lite: [
      { name: 'Mobility Flow', sets: 1, reps: [8, 10], unit: 'minutes', rest: 0 },
      { name: 'Side Plank', sets: 2, reps: [20, 30], unit: 'seconds', perSide: true, rest: 20 },
    ],
  },
  {
    weekday: 5, name: 'Morning Strength B', type: 'legs_b', minutes: 38,
    warmup: 'Reverse lunges, shoulder taps and two light hinge sets',
    full: [
      { name: 'Bulgarian Split Squat', sets: 3, reps: [8, 12], perSide: true, rest: 90, increment: 2.5 },
      { name: 'Pike Push-Up', sets: 3, reps: [6, 12], rest: 90 },
      { name: 'Chin-Up', sets: 3, reps: [5, 10], rest: 120, increment: 2.5 },
      { name: 'Single-Leg Romanian Deadlift', sets: 3, reps: [8, 12], perSide: true, rest: 75, increment: 2.5 },
      { name: 'RKC Plank', sets: 4, reps: [15, 25], unit: 'seconds', rest: 40 },
    ],
    lite: [
      { name: 'Bulgarian Split Squat', sets: 2, reps: [8, 12], perSide: true, rest: 75 },
      { name: 'Pike Push-Up', sets: 2, reps: [6, 12], rest: 75 },
      { name: 'Chin-Up', sets: 2, reps: [5, 10], rest: 90 },
    ],
  },
  {
    weekday: 6, name: 'Team Challenge', type: 't25', minutes: 35,
    warmup: 'Agree on a pace everyone can repeat with clean form',
    full: [
      { name: 'Team Calisthenics Circuit', sets: 5, reps: [1, 1], rest: 75, note: 'Push-ups, squats, rows/pull-ups and carries' },
      { name: 'SkiErg 1 km Challenge', sets: 1, reps: [1, 1], rest: 0, note: 'Even split; finish stronger than you start' },
      { name: 'Suitcase Carry', sets: 3, reps: [30, 45], unit: 'seconds', perSide: true, rest: 45 },
    ],
    lite: [
      { name: 'Team Calisthenics Circuit', sets: 3, reps: [1, 1], rest: 75 },
      { name: 'SkiErg 500 m Smooth Finish', sets: 1, reps: [1, 1], rest: 0 },
    ],
  },
  {
    weekday: 7, name: 'Reset + Long Walk', type: 'mobility', minutes: 30,
    warmup: 'Conversation pace; this day should improve Monday, not compete with it',
    full: [
      { name: 'Brisk Walk', sets: 1, reps: [25, 40], unit: 'minutes', rest: 0 },
      { name: 'Shoulder + Hip Mobility', sets: 1, reps: [8, 12], unit: 'minutes', rest: 0 },
      { name: 'Dead Hang', sets: 2, reps: [20, 40], unit: 'seconds', rest: 45 },
    ],
    lite: [
      { name: 'Easy Walk', sets: 1, reps: [15, 25], unit: 'minutes', rest: 0 },
      { name: 'Mobility Reset', sets: 1, reps: [6, 8], unit: 'minutes', rest: 0 },
    ],
  },
]

/* Iulian-Andrei is an experienced natural bodybuilder who trains in a gym.
   His definitions deliberately share no home or calisthenics fallback with
   Matthew. Transition uses the lite rows; Main Phase uses the full rows. */
const IULIAN_DAYS: DaySpec[] = [
  {
    weekday: 1, name: 'Chest + Delts + Triceps', type: 'push', minutes: 66,
    warmup: 'Five minutes easy cardio, cuff preparation and two progressive incline-press sets',
    full: [
      { name: 'Incline Smith Machine Press', sets: 4, reps: [6, 10], rest: 150, increment: 2.5, note: 'Stop at 1-2 RIR; stable scapulae' },
      { name: 'Machine Chest Press', sets: 3, reps: [8, 12], rest: 105, increment: 2.5 },
      { name: 'Cable Fly', sets: 3, reps: [10, 15], rest: 75, increment: 1 },
      { name: 'Cable Lateral Raise', sets: 4, reps: [12, 20], rest: 60, increment: 1 },
      { name: 'Cable Triceps Extension', sets: 3, reps: [8, 14], rest: 75, increment: 1 },
    ],
    lite: [
      { name: 'Incline Smith Machine Press', sets: 3, reps: [8, 10], rest: 120, increment: 2.5 },
      { name: 'Machine Chest Press', sets: 2, reps: [10, 12], rest: 90, increment: 2.5 },
      { name: 'Cable Lateral Raise', sets: 3, reps: [12, 18], rest: 60, increment: 1 },
    ],
  },
  {
    weekday: 2, name: 'Back + Biceps', type: 'pull', minutes: 68,
    warmup: 'Easy rower, scapular pulldowns and two progressive chest-supported row sets',
    full: [
      { name: 'Chest-Supported T-Bar Row', sets: 4, reps: [6, 10], rest: 150, increment: 2.5 },
      { name: 'Neutral-Grip Lat Pulldown', sets: 3, reps: [8, 12], rest: 105, increment: 2.5 },
      { name: 'Single-Arm Cable Row', sets: 3, reps: [10, 14], perSide: true, rest: 75, increment: 1 },
      { name: 'Reverse Pec Deck', sets: 3, reps: [12, 18], rest: 60, increment: 1 },
      { name: 'Incline Dumbbell Curl', sets: 3, reps: [8, 12], rest: 75, increment: 1 },
    ],
    lite: [
      { name: 'Chest-Supported T-Bar Row', sets: 3, reps: [8, 10], rest: 120, increment: 2.5 },
      { name: 'Neutral-Grip Lat Pulldown', sets: 3, reps: [8, 12], rest: 90, increment: 2.5 },
      { name: 'Incline Dumbbell Curl', sets: 2, reps: [10, 12], rest: 60, increment: 1 },
    ],
  },
  {
    weekday: 3, name: 'Legs A · Quad Bias', type: 'legs_a', minutes: 72,
    warmup: 'Bike, ankle rocks, controlled bodyweight squats and three ramp-up hack-squat sets',
    full: [
      { name: 'Hack Squat', sets: 4, reps: [6, 10], rest: 165, increment: 5 },
      { name: 'Leg Press', sets: 3, reps: [10, 15], rest: 135, increment: 5 },
      { name: 'Leg Extension', sets: 3, reps: [12, 18], rest: 75, increment: 2.5 },
      { name: 'Seated Leg Curl', sets: 3, reps: [8, 12], rest: 90, increment: 2.5 },
      { name: 'Standing Calf Raise Machine', sets: 4, reps: [8, 14], rest: 75, increment: 5 },
    ],
    lite: [
      { name: 'Hack Squat', sets: 3, reps: [8, 10], rest: 135, increment: 5 },
      { name: 'Leg Press', sets: 2, reps: [10, 15], rest: 105, increment: 5 },
      { name: 'Seated Leg Curl', sets: 2, reps: [10, 12], rest: 75, increment: 2.5 },
    ],
  },
  {
    weekday: 4, name: 'Gym Recovery + Mobility', type: 'mobility', minutes: 30,
    warmup: 'Keep the entire session restorative and finish feeling better than you started',
    full: [
      { name: 'Easy Incline Treadmill Walk', sets: 1, reps: [12, 18], unit: 'minutes', rest: 0 },
      { name: 'Cable External Rotation', sets: 3, reps: [12, 18], perSide: true, rest: 45, increment: 0.5 },
      { name: 'Cable Face Pull', sets: 3, reps: [15, 20], rest: 45, increment: 1 },
      { name: '90/90 Hip Mobility', sets: 2, reps: [6, 10], perSide: true, rest: 30 },
      { name: 'Dead Bug', sets: 3, reps: [8, 12], perSide: true, rest: 30 },
    ],
    lite: [
      { name: 'Easy Incline Treadmill Walk', sets: 1, reps: [10, 15], unit: 'minutes', rest: 0 },
      { name: 'Cable Face Pull', sets: 2, reps: [15, 20], rest: 45, increment: 1 },
      { name: '90/90 Hip Mobility', sets: 2, reps: [6, 8], perSide: true, rest: 30 },
    ],
  },
  {
    weekday: 5, name: 'Upper · Hypertrophy', type: 'upper', minutes: 70,
    warmup: 'Shoulder preparation and two controlled ramp-up sets for the first press and row',
    full: [
      { name: 'Flat Dumbbell Press', sets: 3, reps: [8, 12], rest: 120, increment: 2 },
      { name: 'Chest-Supported Machine Row', sets: 3, reps: [8, 12], rest: 120, increment: 2.5 },
      { name: 'Machine Shoulder Press', sets: 3, reps: [8, 12], rest: 105, increment: 2.5 },
      { name: 'Cable Lateral Raise', sets: 4, reps: [12, 20], rest: 60, increment: 1 },
      { name: 'Cable Curl + Rope Pressdown', sets: 3, reps: [10, 15], rest: 75, increment: 1 },
    ],
    lite: [
      { name: 'Flat Dumbbell Press', sets: 3, reps: [8, 12], rest: 105, increment: 2 },
      { name: 'Chest-Supported Machine Row', sets: 3, reps: [8, 12], rest: 105, increment: 2.5 },
      { name: 'Cable Lateral Raise', sets: 3, reps: [12, 18], rest: 60, increment: 1 },
    ],
  },
  {
    weekday: 6, name: 'Legs B · Posterior Chain', type: 'legs_b', minutes: 72,
    warmup: 'Bike, hip airplanes and three gradual Romanian-deadlift warm-up sets',
    full: [
      { name: 'Romanian Deadlift', sets: 4, reps: [6, 10], rest: 165, increment: 5 },
      { name: 'Smith Machine Split Squat', sets: 3, reps: [8, 12], perSide: true, rest: 120, increment: 2.5 },
      { name: 'Lying Leg Curl', sets: 3, reps: [8, 12], rest: 90, increment: 2.5 },
      { name: 'Machine Hip Thrust', sets: 3, reps: [8, 12], rest: 120, increment: 5 },
      { name: 'Seated Calf Raise', sets: 4, reps: [10, 16], rest: 75, increment: 2.5 },
    ],
    lite: [
      { name: 'Romanian Deadlift', sets: 3, reps: [8, 10], rest: 135, increment: 5 },
      { name: 'Smith Machine Split Squat', sets: 2, reps: [8, 10], perSide: true, rest: 105, increment: 2.5 },
      { name: 'Lying Leg Curl', sets: 2, reps: [10, 12], rest: 75, increment: 2.5 },
    ],
  },
  {
    weekday: 7, name: 'Gym Reset + Aerobic Base', type: 'mobility', minutes: 32,
    warmup: 'Conversational effort only; this session protects Monday instead of competing with it',
    full: [
      { name: 'Stationary Bike Zone 2', sets: 1, reps: [15, 22], unit: 'minutes', rest: 0 },
      { name: 'Cable Face Pull', sets: 3, reps: [15, 20], rest: 45, increment: 1 },
      { name: 'Hanging Scapular Depression', sets: 3, reps: [6, 10], rest: 45 },
      { name: 'Hip Flexor Mobility', sets: 2, reps: [45, 60], unit: 'seconds', perSide: true, rest: 20 },
      { name: 'Pallof Press', sets: 3, reps: [8, 12], perSide: true, rest: 45, increment: 1 },
    ],
    lite: [
      { name: 'Stationary Bike Zone 2', sets: 1, reps: [12, 18], unit: 'minutes', rest: 0 },
      { name: 'Cable Face Pull', sets: 2, reps: [15, 20], rest: 45, increment: 1 },
      { name: 'Hip Flexor Mobility', sets: 2, reps: [45, 60], unit: 'seconds', perSide: true, rest: 20 },
    ],
  },
]

function profileFor(userId: string, persona: FriendPersona): Profile {
  if (persona === 'june') {
    return {
      id: uuidFor(userId, 'profile'), user_id: userId, persona, display_name: 'June', sex: 'female',
      profile_kind: 'bespoke', bespoke_protocol_id: 'june-v8.4',
      weight_kg: 41, body_fat_pct: 18, body_fat_source: 'legacy_unverified', body_fat_measured_at: null,
      height_cm: 153, birthdate: '1983-06-19',
      custom_bmr: null,
      activity_level: 'moderate', goal: 'bulk', target_kcal: 2400, target_protein_g: 85,
      target_fat_g: 95, target_carbs_g: 301, training_time: '19:00', baseline_date: today(),
      profile_note: 'Petite, highly muscular massage therapist. Body-fat percentage is a working estimate; protect energy availability and occupational recovery.',
      seed_version: CURRENT_SEED_VERSION,
      calibration_k: 1, calibration_history: [],
      updated_at: new Date().toISOString(),
    }
  }
  if (persona === 'iulian') {
    return {
      id: uuidFor(userId, 'profile'), user_id: userId, persona, display_name: 'Iulian-Andrei', sex: 'male',
      profile_kind: 'bespoke', bespoke_protocol_id: 'iulian-v2',
      weight_kg: 78, body_fat_pct: 13, body_fat_source: 'legacy_unverified', body_fat_measured_at: null,
      custom_bmr: null, height_cm: 177, birthdate: '1997-05-09',
      activity_level: 'moderate', goal: 'maintain', target_kcal: null, target_protein_g: null,
      target_fat_g: null, target_carbs_g: null, training_time: '18:30', baseline_date: today(),
      profile_note: 'Naturally muscular Romanian athlete. Meals begin empty so the nutrition plan can be built entirely from his actual routine.',
      seed_version: CURRENT_SEED_VERSION, calibration_k: 1, calibration_history: [],
      updated_at: new Date().toISOString(),
    }
  }
  return {
    id: uuidFor(userId, 'profile'), user_id: userId, persona, display_name: 'Matthew Hua', sex: 'male',
    profile_kind: 'bespoke', bespoke_protocol_id: 'matthew-v1',
    weight_kg: 78, body_fat_pct: 22, body_fat_source: 'legacy_unverified', body_fat_measured_at: null,
    height_cm: 172, birthdate: '1971-01-01',
    custom_bmr: null,
    activity_level: 'very', goal: 'recomp', target_kcal: 2350, target_protein_g: 155,
    target_fat_g: 80, target_carbs_g: 253, training_time: '07:30', baseline_date: today(),
    profile_note: 'Experienced endurance and calisthenics athlete. Height and birthdate are working estimates; adjust them in Settings when confirmed.',
    seed_version: CURRENT_SEED_VERSION,
    calibration_k: 1, calibration_history: [],
    updated_at: new Date().toISOString(),
  }
}

function settingsFor(userId: string, persona: FriendPersona): Settings {
  return {
    user_id: userId, voice_on: true, ticks_on: true, notifications_on: false,
    guardian_factor: 1.4, addons: { endurance1: false, endurance2: false, endurance3: false, uiMode: 'simple', newbie_mode: false, training_induction: null, training_protocol: persona === 'june' ? { version: 84, start_date: today() } : undefined, comparison_export_mode: 'detailed', weight_unit: 'kg', simple_show_orbit: true, simple_show_body_index: true, simple_show_guided_plan: true, simple_show_hydration_reminder: false, simple_show_manual_workout: false, simple_show_next_action: false, adhd_mode: false, recovery_data_source: 'apple', recovery_history: [], watch_activity_history: [], ...(persona === 'june' ? { meal_blocks: { blocks: [{ id: 'breakfast' as const, kind: 'breakfast' as const, time: '07:00', enabled: true }, { id: 'lunch' as const, kind: 'lunch' as const, time: '13:00', enabled: true }, { id: 'dinner' as const, kind: 'dinner' as const, time: '19:15', enabled: true }, { id: 'snack' as const, kind: 'snack' as const, time: '15:30', enabled: true }, { id: 'post_workout' as const, kind: 'post_workout' as const, time: '21:00', enabled: true }], custom_blocks: [], preset_assignments: {} } } : {}) },
  }
}

function mealsFor(userId: string, persona: FriendPersona): Meal[] {
  if (persona === 'iulian' || persona === 'june') return []
  const rows = [
    ['07:45', 'Power breakfast', '3 eggs + 60 g oats + 30 g whey isolate + berries. Western-style, fast after morning training.', 520, 40, 18, 50],
    ['12:30', 'Chicken performance bowl', '180–200 g chicken + bulgur or rice + banana + seeds + EVOO + vegetables.', 760, 50, 24, 80],
    ['18:30', 'Lean dinner', '250 g sweet potato + lean chicken or fish + cottage cheese + avocado + vegetables.', 700, 45, 26, 70],
    ['21:15', 'Recovery allocation', '30 g casein isolate + fruit + 20 g walnuts; move earlier when sleep feels heavy.', 370, 20, 12, 53],
  ]
  return rows.map(([time, name, foods, kcal, protein, fat, carbs], index) => ({
    id: uuidFor(userId, `meal:${index}`), user_id: userId, time: String(time), name: String(name),
    foods: String(foods), kcal: Number(kcal), protein_g: Number(protein), fat_g: Number(fat),
    carbs_g: Number(carbs), full_days_only: false, sort_order: index,
  }))
}

function supplementsFor(userId: string, persona: FriendPersona): Supplement[] {
  type Row = [string, string, string, string | null, number | null, boolean?]
  const rows: Row[] = persona === 'iulian'
    ? [
        ['Zinc', '30 mg', 'Morning', '07:00', null], ['DIM', '200 mg', 'Morning', '07:00', null],
        ['Vitamin B12', '1000 mg', 'Morning', '07:00', null], ['Folic acid', '5000 mg', 'Morning', '07:00', null],
        ['Vitamin B1', '100 mg', 'Morning', '07:00', null], ['Astaxanthin', '12 mg', 'Morning', '07:00', null],
        ['Alpha-GPC', '300 mg', 'Morning', '07:00', null], ['Vitamin B6', '100 mg', 'Morning', '07:00', null],
        ['Ubiquinol', '100 mg', 'Morning', '07:00', null], ['Red yeast rice', '600 mg', 'Morning', '07:00', null],
        ['Vitamin D3 + K2', '5000 IU · 100 mcg', 'Morning', '07:00', null], ['Citrus bergamot', '250 mg', 'Morning', '07:00', null],
        ['Nattokinase', '100 mg', 'Morning', '07:00', null], ['Wellbutrin', '150 mg', 'Morning', '07:00', null],
        ['Fish oil', '3 capsules', 'Morning', '07:00', null], ['Creatine', '5 g', 'Morning', '07:00', null],
        ['Magnesium', '300 mg', 'Evening', '21:30', null], ['Zinc', '30 mg', 'Evening', '21:30', null],
        ['Red yeast rice', '600 mg', 'Evening', '21:30', null], ['Citrus bergamot', '250 mg', 'Evening', '21:30', null],
        ['Nattokinase', '100 mg', 'Evening', '21:30', null], ['Lipanthyl', '200 mg', 'Evening', '21:30', null],
        ['Ezetimibe', '10 mg', 'Evening', '21:30', null], ['Ubiquinol', '100 mg', 'Evening', '21:30', null],
      ]
    : persona === 'june'
    ? [
        ['Creatine monohydrate', '3 g', 'Daily core', '07:00', null],
        ['Iodised salt', 'Use across meals to taste', 'Daily core', '13:00', null],
        ['Whey isolate', 'Only as needed to close the daily protein gap', 'As needed', '15:30', null],
        ['Casein', 'Normal evening: close the remaining protein gap. Heavy resistance evening: enough powder to provide 40–45 g actual protein.', 'As needed', '21:30', null],
        ['Cluster Dextrin', '20–25 g in 5 g increments when workload or the remaining carbohydrate gap requires it', 'Optional training support', null, -15, true],
        ['Electrolytes', 'Only for heat, high sweat or unusually long sessions', 'Optional training support', null, -15, true],
      ]
    : [
        ['Rhodiola', '', 'Wake', '06:30', null], ['Creatine', '5 g', 'Wake', '06:30', null], ['Taurine', '', 'Wake', '06:30', null],
        ['Whey isolate', '30 g', 'Breakfast', '08:15', null], ['Fish oil', '', 'Breakfast', '08:15', null], ['Vitamin D3 + MK-7', '5000 IU · confirm clinically', 'Breakfast', '08:15', null],
        ['Iodised salt', 'pinch', 'T-15 training drink', null, -15, true], ['Water', 'tolerance-based', 'T-15 training drink', null, -15, true], ['Citrulline Malate', '6–8 g', 'T-15 training drink', null, -15, true],
        ['Zinc bisglycinate', '15 mg', 'Sleep stack', '21:45', null], ['Magnesium bisglycinate', '', 'Sleep stack', '21:45', null],
        ['Phosphatidylserine', '300 mg', 'Sleep stack', '21:45', null], ['Casein isolate', '30 g', 'Sleep stack', '21:45', null],
      ]
  return rows.map(([name, dose, group, clock, offset, trainingOnly], index) => ({
    id: uuidFor(userId, `supplement:${index}`), user_id: userId, name, dose,
    timing: clock ? 'clock' : 'training', clock_time: clock, offset_min: clock ? null : offset,
    group_label: group, training_days_only: trainingOnly ?? false, sort_order: index,
  }))
}

function buildPrograms(userId: string, persona: FriendPersona): Pick<AppData, 'programs' | 'program_days' | 'exercises'> {
  const legacyDays = persona === 'june' ? LEGACY_JUNE_DAYS : persona === 'iulian' ? IULIAN_DAYS : MATTHEW_DAYS
  const mainDays = persona === 'june' ? JUNE_V84_DAYS : legacyDays
  const programs: Program[] = [
    {
      id: uuidFor(userId, 'program:transition'), user_id: userId, slug: 'transition',
      name: persona === 'june' ? 'Growth Minimum' : persona === 'iulian' ? 'Transitional Training' : 'Morning Base',
      description: persona === 'june'
        ? 'Busy-day programme that protects glute growth without demanding the full session.'
        : persona === 'iulian' ? 'For beginners'
        : 'Fast, repeatable morning sessions that establish the cut without draining the day.',
    },
    {
      id: uuidFor(userId, 'program:main'), user_id: userId, slug: 'main',
      name: persona === 'june' ? 'Glute Architecture' : persona === 'iulian' ? 'Main Training' : 'Lean & Ripped 8AM',
      description: persona === 'june'
        ? 'Seven-day home programme with two non-negotiable glute exposures and occupational recovery.'
        : persona === 'iulian' ? 'Bodybuilding'
        : 'Age-aware calisthenics, strength, SkiErg and recovery structured around 07:30 mornings.',
    },
  ]
  const program_days: ProgramDay[] = []
  const exercises: Exercise[] = []

  for (const program of programs) {
    const days = program.slug === 'main' ? mainDays : legacyDays
    for (const day of days) {
      const dayIdentity = day.slot && day.slot !== 'official' ? `${day.weekday}:${day.slot}` : `${day.weekday}`
      const dayId = uuidFor(userId, `day:${program.slug}:${dayIdentity}`)
      program_days.push({
        id: dayId, user_id: userId, program_id: program.id, weekday: day.weekday,
        name: day.name, day_type: day.type,
        est_minutes: program.slug === 'transition' ? Math.max(12, Math.round(day.minutes * 0.65)) : day.minutes,
        warmup_note: day.warmup,
        sort_order: day.weekday * 10 + (day.slot === 'morning' ? 0 : day.slot === 't25' ? 2 : 1),
      })
      const fullSpecs = program.slug === 'transition' ? day.lite : day.full
      const liteSpecs = program.slug === 'transition' ? day.lite.slice(0, Math.max(1, day.lite.length - 1)) : day.lite
      const addSpecs = (specs: ExerciseSpec[], isLite: boolean): void => {
        specs.forEach((spec, index) => {
          const isMax = spec.reps === 'max'
          const repRange: readonly [number, number] =
            typeof spec.reps === 'string' ? [0, 0] : spec.reps
          exercises.push({
            id: uuidFor(userId, `exercise:${program.slug}:${dayIdentity}:${isLite ? 'lite' : 'full'}:${index}`),
            user_id: userId, program_day_id: dayId, name: spec.name, sets: spec.sets,
            rep_min: repRange[0], rep_max: repRange[1],
            rep_unit: spec.unit ?? (isMax ? 'max' : 'reps'), per_side: spec.perSide ?? false,
            rest_sec: spec.rest ?? 60, tempo_up_s: spec.up ?? 1, tempo_down_s: spec.down ?? 2,
            tempo_pause_s: spec.pause ?? 0, tempo_note: spec.tempo ?? '', notes: spec.note ?? '',
            increment_kg: spec.increment ?? 0, is_lite: isLite, optional: spec.optional ?? false,
            sort_order: index,
          })
        })
      }
      addSpecs(fullSpecs, false)
      addSpecs(liteSpecs, true)
    }
  }
  return { programs, program_days, exercises }
}

export function buildFriendSeedData(userId: string, persona: FriendPersona): AppData {
  const programme = buildPrograms(userId, persona)
  return {
    profile: profileFor(userId, persona), settings: settingsFor(userId, persona), meals: mealsFor(userId, persona),
    meal_logs: [], supplements: supplementsFor(userId, persona), supplement_logs: [],
    ...programme, workout_sessions: [], workout_logs: [], activity_types: ACTIVITY_CATALOG,
    activity_logs: [], daily_logs: [], hydration_events: [], hydration_presets: [],
    hydration_preferences: null, events: [],
    rpg_snapshots: [], deload_marks: [], health_metrics: [], imported_activities: [],
  }
}
