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
import { waterTargetResolver } from '../../../src/lib/dayHydration.ts'
import { computeEngine } from '../../../src/lib/rpg.ts'
import { computeTargets } from '../../../src/lib/nutrition.ts'
import { buildSeedData } from '../../../src/data/seed.ts'
import type {
  AppData,
  DailyLog,
  FitnessEvidenceRecord,
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
    user_id: data.profile!.user_id,
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
      { date: '2026-06-12', source: 'other', sleep_score: null, sleep_pct: null, recovery_pct: 70, updated_at: TS },
      { date: '2026-06-13', source: 'apple', sleep_score: 40, sleep_pct: null, recovery_pct: null, updated_at: TS },
    ],
    meal_rhythm_history: {
      '2026-06-15': rhythmDay('2026-06-15', 'complete_on_time', 92, 100),
      '2026-06-16': rhythmDay('2026-06-16', 'complete_irregular', 55, 100),
      '2026-06-17': rhythmDay('2026-06-17', 'missed_meals', 30, 50),
      '2026-06-18': rhythmDay('2026-06-18', 'no_meals', 0, 0),
    },
  }
  /* a partly logged food day under a training session */
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

/* 6: the server stamped the baseline and a self-check with tomorrow's UTC date */
{
  const d = base('constantine')
  d.profile = { ...d.profile!, baseline_date: addDays(THROUGH, 1) }
  selfCheck(d, 'cardio_capacity_score', 62, 55, `${addDays(THROUGH, 1)}T02:30:00.000Z`)
  scenarios.push({ name: 'stamps_ahead_of_device_date', persona: 'constantine', throughDate: THROUGH, data: d })
}

/* 7: loads and movements that a day's label does not describe */
{
  const d = base('constantine')
  const pullDay = d.program_days.find((p) => p.day_type === 'pull')!
  const pullUp = d.exercises.find((e) => e.program_day_id === pullDay.id && !e.is_lite)!
  /* easing the assistance on a lift is progress */
  log(d, session(d, '2026-06-02', 'pull'), { exercise_name: pullUp.name, exercise_id: pullUp.id, weight_kg: -30 })
  log(d, session(d, '2026-06-09', 'pull'), { exercise_name: pullUp.name, exercise_id: pullUp.id, weight_kg: -20 })
  /* a deload day with two sessions banks its joint credit once */
  session(d, '2026-06-16', 'push', { is_deload: true })
  session(d, '2026-06-16', 'pull', { is_deload: true })
  /* a full-body day typed upper credits the legs it trained, and its leg press progress is lower-body progress */
  const upperDay = d.program_days.find((p) => p.day_type === 'upper')!
  const pressed = d.exercises.find((e) => e.program_day_id === upperDay.id && !e.is_lite)!
  const fullBody = session(d, '2026-06-23', 'upper')
  log(d, fullBody, { exercise_name: 'Leg Press', exercise_id: pressed.id, movement_id: 'leg_press', weight_kg: 100 })
  log(d, fullBody, { exercise_name: 'Machine Chest Press', movement_id: 'machine_chest_press', weight_kg: 40 })
  log(d, session(d, '2026-06-30', 'upper'), {
    exercise_name: 'Leg Press', exercise_id: pressed.id, movement_id: 'leg_press', weight_kg: 110,
  })
  /* a recovery-typed day of strength work earns strength, not flexibility */
  const capacity = session(d, '2026-07-02', 'fix')
  log(d, capacity, { exercise_name: 'Lat Pulldown', movement_id: 'lat_pulldown', weight_kg: 50 })
  log(d, capacity, { exercise_name: 'Dead Bug', movement_id: 'dead_bug' })
  /* an unlisted lift keeps the day's label beside an identified mobility drill */
  const legs = session(d, '2026-07-07', 'legs_a')
  log(d, legs, { exercise_name: 'Unlisted lift', weight_kg: 60 })
  log(d, legs, { exercise_name: 'Cat-Cow', movement_id: 'cat_cow', reps: null, duration_seconds: 120 })
  scenarios.push({ name: 'performed_movements_and_loads', persona: 'constantine', throughDate: THROUGH, data: d })
}

/* 8: self-checks against a score with and without evidence */
{
  const d = base('constantine')
  /* no evidence yet: the first answer sets the estimate, in either direction */
  selfCheck(d, 'flexibility_score', 30, 20, '2026-06-03T08:00:00.000Z')
  /* evidence first, then an answer above it lifts once; repeats and lower answers change nothing */
  session(d, '2026-06-02', 'push')
  selfCheck(d, 'upper_body_strength_score', 77, 70, '2026-06-05T08:00:00.000Z')
  selfCheck(d, 'upper_body_strength_score', 77, 70, '2026-06-12T08:00:00.000Z')
  selfCheck(d, 'upper_body_strength_score', 47, 40, '2026-06-19T08:00:00.000Z')
  /* a higher answer lifts again while the score is still below its band */
  session(d, '2026-06-02', 'legs_a')
  selfCheck(d, 'lower_body_strength_score', 47, 40, '2026-06-05T08:00:00.000Z')
  selfCheck(d, 'lower_body_strength_score', 77, 70, '2026-06-12T08:00:00.000Z')
  scenarios.push({ name: 'self_checks', persona: 'constantine', throughDate: THROUGH, data: d })
}

/* 9: a bespoke profile decays, and a partly logged food day under a strength session costs nothing */
{
  const d = buildSeedData('9a0fffbc-bb02-40ac-834a-d4e339b32574', 'constantine')
  d.profile = {
    ...d.profile!,
    baseline_date: BASELINE,
    updated_at: TS,
    profile_kind: 'bespoke',
    bespoke_protocol_id: 'constantine-v8.5',
  }
  session(d, '2026-06-03', 'legs_a')
  d.settings!.addons = {
    ...d.settings!.addons,
    meal_rhythm_history: { '2026-06-03': rhythmDay('2026-06-03', 'missed_meals', 14, 20) },
  }
  scenarios.push({ name: 'bespoke_partly_logged_day', persona: 'constantine', throughDate: '2026-07-01', data: d })
}

/* 10: answers given while joining never alter chosen starting points, whatever UTC day they carry */
{
  const d = base('constantine')
  d.profile = {
    ...d.profile!,
    avatar_starting_points: { health: 75, joint: 75, flexibility: 45, endurance: 35, strength_upper: 40, strength_lower: 30 },
  }
  const onboarding = 'apex_onboarding_pulse_v1'
  /* an evening west of Greenwich on the baseline day is stamped with the next UTC day */
  selfCheck(d, 'cardio_capacity_score', 77, 70, `${addDays(BASELINE, 1)}T03:00:00.000Z`, onboarding)
  /* a morning east of Greenwich is stamped with the previous UTC day */
  selfCheck(d, 'upper_body_strength_score', 77, 70, `${addDays(BASELINE, -1)}T23:00:00.000Z`, onboarding)
  /* a pulse answered after that is new evidence, from the first UTC day no joining answer can carry */
  selfCheck(d, 'flexibility_score', 62, 55, `${addDays(BASELINE, 2)}T00:30:00.000Z`, onboarding)
  selfCheck(d, 'lower_body_strength_score', 62, 55, '2026-06-05T08:00:00.000Z', onboarding)
  scenarios.push({ name: 'joining_answers_and_chosen_start', persona: 'constantine', throughDate: THROUGH, data: d })
}

function selfCheck(
  data: AppData,
  metric: FitnessEvidenceRecord['metric'],
  value: number,
  lowerBound: number,
  measuredAt: string,
  protocol = 'apex_baseline_calibration_v1',
): void {
  const id = fid()
  data.fitness_evidence.push({
    id,
    user_id: USER,
    metric,
    value,
    unit: 'score_0_100',
    source: 'structured_self_report',
    protocol,
    device: null,
    measured_at: measuredAt,
    imported_at: measuredAt,
    confidence: 'low',
    metadata: { answered_count: 3, lower_bound: lowerBound },
    supersedes_id: null,
    client_idempotency_key: `fixture:${id}`,
  })
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
        hydration_targets: Object.fromEntries(sc.data.daily_logs.filter(d => d.water_l > 0)
          .map(d => [d.date, waterTargetResolver(sc.data)(d.date, sc.throughDate, 0).targetML])),
        health_metrics: sc.data.health_metrics,
        imported_activities: sc.data.imported_activities,
        fitness_evidence: sc.data.fitness_evidence,
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
