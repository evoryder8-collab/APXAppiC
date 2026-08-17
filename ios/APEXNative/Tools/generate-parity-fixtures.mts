/*
 * Golden parity fixtures for the native FitnessBrainEngine.
 *
 * Runs the REAL web engine (src/lib/rpg.ts and friends) over deterministic
 * scenarios and freezes inputs + outputs as JSON. The Swift XCTest suite
 * decodes the same inputs, runs the Swift port, and must reproduce every
 * snapshot number and synergy event exactly. Regenerate after any web
 * engine change:
 *
 *   node --experimental-strip-types ios/APEXNative/Tools/generate-parity-fixtures.mts
 */
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { computeEngine } from '../../../src/lib/rpg.ts'
import { computeTargets } from '../../../src/lib/nutrition.ts'
import { buildSeedData } from '../../../src/data/seed.ts'
import type {
  AppData,
  DailyLog,
  HealthMetric,
  ImportedActivity,
  WorkoutLog,
  WorkoutSession,
} from '../../../src/lib/types.ts'
import type { PersonaSlug } from '../../../src/lib/persona.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
const OUT = join(HERE, '..', 'APEXTests', 'Fixtures', 'engine-parity.json')

const USER = '99999999-0000-4000-8000-000000000001'
const BASELINE = '2026-06-01'
const THROUGH = '2026-08-10'
const TS = '2026-06-01T12:00:00.000Z' // frozen timestamp for metadata fields

let idSeq = 0
function fid(): string {
  idSeq += 1
  return `88888888-0000-4000-8000-${String(idSeq).padStart(12, '0')}`
}

function base(persona: PersonaSlug): AppData {
  const data = buildSeedData(USER, persona)
  if (!data.profile) throw new Error('seed produced no profile')
  data.profile = { ...data.profile, baseline_date: BASELINE, updated_at: TS }
  return data
}

function session(
  data: AppData,
  date: string,
  dayType: string,
  opts: Partial<WorkoutSession> = {},
): WorkoutSession {
  const day = data.program_days.find((d) => d.day_type === dayType)
  if (!day) throw new Error(`no program day of type ${dayType}`)
  const s: WorkoutSession = {
    id: fid(),
    user_id: USER,
    date,
    program_day_id: day.id,
    is_lite: false,
    is_deload: false,
    is_event_recovery: false,
    completed: true,
    quality_score: 1,
    started_at: null,
    completed_at: null,
    notes: '',
    ...opts,
  }
  data.workout_sessions.push(s)
  return s
}

function log(
  data: AppData,
  s: WorkoutSession,
  opts: Partial<WorkoutLog> & { exercise_name: string },
): WorkoutLog {
  const l: WorkoutLog = {
    id: fid(),
    user_id: USER,
    session_id: s.id,
    exercise_id: null,
    set_no: 1,
    weight_kg: null,
    reps: 10,
    rir: 1,
    skipped: false,
    override_flag: false,
    created_at: TS,
    ...opts,
  }
  data.workout_logs.push(l)
  return l
}

function daily(data: AppData, date: string, opts: Partial<DailyLog>): void {
  const d: DailyLog = {
    id: fid(),
    user_id: USER,
    date,
    kcal: null,
    protein_g: null,
    fat_g: null,
    carbs_g: null,
    water_l: 0,
    estimated_tdee: null,
    computed_pal: null,
    activity_mode: 'quick',
    weight_kg: null,
    ...opts,
  }
  data.daily_logs.push(d)
}

function metric(data: AppData, date: string, opts: Partial<HealthMetric>): void {
  const m: HealthMetric = {
    id: fid(),
    user_id: USER,
    date,
    weight_kg: null,
    vo2max: null,
    resting_hr: null,
    ...opts,
  }
  data.health_metrics.push(m)
}

function imported(
  data: AppData,
  date: string,
  kind: ImportedActivity['kind'],
  minutes: number,
): void {
  data.imported_activities.push({
    id: fid(),
    user_id: USER,
    date,
    kind,
    activity: 'Fixture',
    duration_min: minutes,
    source: 'Fixture',
  })
}

interface Scenario {
  name: string
  persona: PersonaSlug
  throughDate: string
  data: AppData
}

const scenarios: Scenario[] = []

/* 1: pure decay + age drag, no activity at all */
scenarios.push({ name: 'baseline_decay', persona: 'constantine', throughDate: THROUGH, data: base('constantine') })

/* 2: the training + nutrition synergy battery */
{
  const d = base('constantine')
  const targets = computeTargets(d.profile!)
  /* legs day with protein hit -> protein_strength fires, leg boost applies */
  session(d, '2026-06-02', 'legs_a')
  daily(d, '2026-06-02', { kcal: targets.kcal, protein_g: Math.ceil(targets.protein_g), water_l: 2.75 })
  /* upper day in deep deficit -> deficit_strength */
  session(d, '2026-06-03', 'push')
  daily(d, '2026-06-03', { kcal: Math.round(targets.kcal * 0.7), protein_g: 80, water_l: 1 })
  /* mobility the day after legs -> mobility_after_legs */
  session(d, '2026-06-04', 'mobility')
  /* t25 with hydration -> hydration_endurance */
  session(d, '2026-06-07', 't25')
  daily(d, '2026-06-07', { water_l: 3 })
  /* deload honored */
  session(d, '2026-06-09', 'pull', { is_deload: true })
  /* event recovery micro-session */
  session(d, '2026-06-11', 'upper', { is_event_recovery: true })
  /* quality scaling */
  session(d, '2026-06-13', 'legs_b', { quality_score: 0.5 })
  /* progressive overload: same exercise id rising across two sessions + one override */
  const ex = d.exercises.find((e) => e.increment_kg > 0 && !e.is_lite)!
  const dayType = d.program_days.find((p) => p.id === ex.program_day_id)!.day_type
  const s1 = session(d, '2026-06-16', dayType)
  log(d, s1, { exercise_name: ex.name, exercise_id: ex.id, weight_kg: 10 })
  const s2 = session(d, '2026-06-23', dayType)
  log(d, s2, { exercise_name: ex.name, exercise_id: ex.id, weight_kg: 12.5, override_flag: true })
  /* Focus T25 conditioning detected from a log name inside another session */
  const s3 = session(d, '2026-06-25', 'upper')
  log(d, s3, { exercise_name: 'Focus T25 Alpha: Cardio', exercise_id: null })
  scenarios.push({ name: 'training_synergies', persona: 'constantine', throughDate: THROUGH, data: d })
}

/* 3: imports, vo2 anchoring, recovery check-ins, meal rhythm verdicts */
{
  const d = base('constantine')
  /* pre-baseline history informs the starting point */
  metric(d, '2026-05-20', { vo2max: 40.25 })
  imported(d, '2026-05-15', 'strength', 38)
  imported(d, '2026-05-18', 'endurance', 27)
  imported(d, '2026-05-25', 'mobility', 20)
  /* post-baseline imports feed stats at reduced credit */
  imported(d, '2026-06-05', 'endurance', 45)
  imported(d, '2026-06-06', 'strength', 30)
  imported(d, '2026-06-08', 'mobility', 15)
  /* in-window vo2 anchor + resting hr series */
  metric(d, '2026-07-01', { vo2max: 41.5, resting_hr: 52 })
  for (let i = 0; i < 12; i++) {
    metric(d, addDays('2026-07-02', i), { resting_hr: 52 + (i > 8 ? 6 : 0) })
  }
  /* recovery check-ins: apple strong, apple normal, athlytic strong, low ignored */
  const settings = d.settings!
  settings.addons = {
    ...settings.addons,
    recovery_history: [
      { date: '2026-06-10', source: 'apple', sleep_score: 88, sleep_pct: null, recovery_pct: null, updated_at: TS },
      { date: '2026-06-11', source: 'apple', sleep_score: 70, sleep_pct: null, recovery_pct: null, updated_at: TS },
      { date: '2026-06-12', source: 'athlytic', sleep_score: null, sleep_pct: null, recovery_pct: 70, updated_at: TS },
      { date: '2026-06-13', source: 'apple', sleep_score: 40, sleep_pct: null, recovery_pct: null, updated_at: TS },
    ],
    meal_rhythm_history: {
      '2026-06-15': rhythmDay('2026-06-15', 'complete_on_time', 92, 100),
      '2026-06-16': rhythmDay('2026-06-16', 'complete_irregular', 55, 100),
      '2026-06-17': rhythmDay('2026-06-17', 'missed_meals', 30, 50),
      '2026-06-18': rhythmDay('2026-06-18', 'no_meals', 0, 0),
    },
  }
  /* meal completion tempering strength on a training day */
  session(d, '2026-06-17', 'push')
  scenarios.push({ name: 'imports_recovery_rhythm', persona: 'constantine', throughDate: THROUGH, data: d })
}

/* 4 + 5: persona baselines with light activity */
for (const persona of ['june', 'matthew'] as PersonaSlug[]) {
  const d = base(persona)
  const anyDay = d.program_days[0]
  if (anyDay) {
    d.workout_sessions.push({
      id: fid(), user_id: USER, date: '2026-06-05', program_day_id: anyDay.id,
      is_lite: false, is_deload: false, is_event_recovery: false, completed: true,
      quality_score: 1, started_at: null, completed_at: null, notes: '',
    })
  }
  scenarios.push({ name: `persona_${persona}`, persona, throughDate: '2026-07-01', data: d })
}

function rhythmDay(date: string, verdict: string, rhythm: number, completion: number) {
  return {
    date,
    time_zone: 'Europe/Zurich',
    finalized: true,
    expected_meals: 4,
    logged_meals: verdict === 'no_meals' ? 0 : verdict === 'missed_meals' ? 2 : 4,
    scheduled_times: [
      { id: 'breakfast', slot: 'breakfast', time: '07:00' },
      { id: 'lunch', slot: 'lunch', time: '13:00' },
      { id: 'snack', slot: 'snack', time: '15:30' },
      { id: 'dinner', slot: 'dinner', time: '19:15' },
    ],
    meal_times: verdict === 'no_meals' ? [] : ['07:10', '13:05'],
    first_meal_at: verdict === 'no_meals' ? null : '07:10',
    last_meal_at: verdict === 'no_meals' ? null : '19:20',
    completion_score: completion,
    timing_score: rhythm,
    rhythm_score: rhythm,
    verdict,
    updated_at: TS,
  }
}

function addDays(iso: string, days: number): string {
  const d = new Date(iso + 'T12:00:00')
  d.setDate(d.getDate() + days)
  return d.toISOString().slice(0, 10)
}

/* ---- run the real engine and freeze everything ---- */
const out = {
  generated_note: 'Do not edit by hand. Regenerate with generate-parity-fixtures.mts',
  generated_on: new Date().toISOString().slice(0, 10),
  scenarios: scenarios.map((sc) => {
    const result = computeEngine(sc.data, sc.throughDate)
    const targets = computeTargets(sc.data.profile!)
    return {
      name: sc.name,
      persona: sc.persona,
      through_date: sc.throughDate,
      input: {
        profile: sc.data.profile,
        settings_addons: sc.data.settings?.addons ?? null,
        program_days: sc.data.program_days.map((p) => ({ id: p.id, day_type: p.day_type })),
        exercises: sc.data.exercises.map((e) => ({ id: e.id, program_day_id: e.program_day_id })),
        workout_sessions: sc.data.workout_sessions,
        workout_logs: sc.data.workout_logs,
        daily_logs: sc.data.daily_logs,
        health_metrics: sc.data.health_metrics,
        imported_activities: sc.data.imported_activities,
      },
      expected: {
        targets,
        snapshot_count: result.snapshots.length,
        first_snapshot: result.snapshots[0] ?? null,
        last_snapshot: result.snapshots[result.snapshots.length - 1] ?? null,
        /* every 7th snapshot keeps the file small while pinning the whole curve */
        sampled_snapshots: result.snapshots.filter((_, i) => i % 7 === 0),
        synergies: result.synergies,
      },
    }
  }),
}

mkdirSync(dirname(OUT), { recursive: true })
writeFileSync(OUT, JSON.stringify(out, null, 1))
console.log(`wrote ${OUT}`)
for (const sc of out.scenarios) {
  console.log(
    `${sc.name}: ${sc.expected.snapshot_count} snapshots, ${sc.expected.synergies.length} synergies, last overall ${sc.expected.last_snapshot?.overall}`,
  )
}
