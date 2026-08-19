/*
 * Golden parity fixtures for the native StrengthProgress engine.
 *
 * Runs the REAL web engine (src/lib/strengthProgress.ts) over deterministic
 * histories and freezes inputs plus outputs as JSON. The Swift suite decodes
 * the same inputs and must reproduce every number. Regenerate after any web
 * change:
 *
 *   node --experimental-strip-types ios/APEXNative/Tools/generate-strength-fixtures.mts
 */
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  assessJointCheckin,
  buildStrengthSeries,
  checkinDue,
  estimatedOneRepMax,
  sessionStrengthInsights,
} from '../../../src/lib/strengthProgress.ts'
import type { AppData, JointCheckin, WorkoutLog, WorkoutSession } from '../../../src/lib/types.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
const OUT = join(HERE, '..', 'APEXTests', 'Fixtures', 'strength-parity.json')

const USER = '99999999-0000-4000-8000-000000000001'
const PROGRAM_DAY = '66666666-0000-4000-8000-000000000001'
const BENCH = '66666666-0000-4000-8000-000000000010'
const SQUAT = '66666666-0000-4000-8000-000000000011'

let seq = 0
const fid = (): string => {
  seq += 1
  return `55555555-0000-4000-8000-${String(seq).padStart(12, '0')}`
}

const sessions: WorkoutSession[] = []
const logs: WorkoutLog[] = []

function session(date: string, completed = true): string {
  const id = fid()
  sessions.push({
    id, user_id: USER, date, program_day_id: PROGRAM_DAY,
    is_lite: false, is_deload: false, is_event_recovery: false,
    completed, quality_score: 1, started_at: null, completed_at: null,
credited_kcal: null, created_at: `${date}T12:00:00.000Z`,
  } as unknown as WorkoutSession)
  return id
}

function set(sessionId: string, exerciseId: string | null, name: string, setNo: number, weight: number | null, reps: number | null, skipped = false): void {
  logs.push({
    id: fid(), user_id: USER, session_id: sessionId, exercise_id: exerciseId,
    exercise_name: name, set_no: setNo, weight_kg: weight, reps, rir: null,
    skipped, override_flag: false, created_at: '2026-06-01T12:00:00.000Z',
  } as unknown as WorkoutLog)
}

/* Bench climbs steadily; squat stalls then jumps; one session is abandoned
   and must never reach a series; one exercise is logged by name only. */
const s1 = session('2026-05-04')
set(s1, BENCH, 'Barbell bench press', 1, 60, 8)
set(s1, BENCH, 'Barbell bench press', 2, 60, 8)
set(s1, SQUAT, 'Back squat', 1, 90, 5)

const s2 = session('2026-05-18')
set(s2, BENCH, 'Barbell bench press', 1, 62.5, 8)
set(s2, BENCH, 'Barbell bench press', 2, 62.5, 7)
set(s2, SQUAT, 'Back squat', 1, 90, 5)
set(s2, null, 'Ring dips', 1, 12, 10)

const s3 = session('2026-06-15')
set(s3, BENCH, 'Barbell bench press', 1, 65, 8)
set(s3, SQUAT, 'Back squat', 1, 100, 3)
set(s3, SQUAT, 'Back squat', 2, 100, 3)
set(s3, null, 'Ring dips', 1, 14, 10)

/* An abandoned session, and a skipped set with a weight, both ignored. */
const abandoned = session('2026-06-20', false)
set(abandoned, BENCH, 'Barbell bench press', 1, 70, 8)

const s4 = session('2026-08-10')
set(s4, BENCH, 'Barbell bench press', 1, 67.5, 6)
set(s4, BENCH, 'Barbell bench press', 2, 67.5, 5, true)
set(s4, SQUAT, 'Back squat', 1, 102.5, 3)
set(s4, SQUAT, 'Back squat', 2, null, 3)

const data = { workout_sessions: sessions, workout_logs: logs } as unknown as AppData

const checkins: JointCheckin[] = [
  { id: fid(), date: '2026-07-27', arms: 2, core: 3, legs: 2 },
  { id: fid(), date: '2026-08-03', arms: 5, core: 3, legs: 4 },
  { id: fid(), date: '2026-08-10', arms: 7, core: 3, legs: 4 },
]

const oneRepMaxCases = [
  { weight: 100, reps: 1 }, { weight: 100, reps: null }, { weight: 100, reps: 5 },
  { weight: 100, reps: 15 }, { weight: 100, reps: 30 }, { weight: 0, reps: 5 },
  { weight: 62.5, reps: 8 },
]

const jointCases = [
  { current: { id: 'a', date: '2026-08-10', arms: 1, core: 1, legs: 1 }, previous: null },
  { current: { id: 'b', date: '2026-08-10', arms: 5, core: 2, legs: 2 }, previous: null },
  { current: { id: 'c', date: '2026-08-10', arms: 7, core: 2, legs: 2 }, previous: null },
  { current: { id: 'd', date: '2026-08-10', arms: 7, core: 7, legs: 2 }, previous: null },
  { current: { id: 'e', date: '2026-08-10', arms: 6, core: 6, legs: 2 }, previous: null },
  { current: { id: 'f', date: '2026-08-10', arms: 9, core: 2, legs: 2 }, previous: null },
  { current: { id: 'g', date: '2026-08-10', arms: 4, core: 2, legs: 2 }, previous: { id: 'h', date: '2026-08-03', arms: 1, core: 2, legs: 2 } },
] as Array<{ current: JointCheckin; previous: JointCheckin | null }>

mkdirSync(dirname(OUT), { recursive: true })
writeFileSync(OUT, `${JSON.stringify({
  sessions: sessions.map((value) => ({ id: value.id, date: value.date, completed: value.completed })),
  logs: logs.map((value) => ({
    id: value.id, session_id: value.session_id, exercise_id: value.exercise_id,
    exercise_name: value.exercise_name, set_no: value.set_no,
    weight_kg: value.weight_kg, reps: value.reps, skipped: value.skipped,
  })),
  one_rep_max: oneRepMaxCases.map((value) => ({ ...value, expected: estimatedOneRepMax(value.weight, value.reps) })),
  series: buildStrengthSeries(data).map((value) => ({
    key: value.key, name: value.name,
    points: value.points.map((point) => ({
      session_id: point.sessionId, date: point.date, top_weight: point.topWeight,
      estimated_1rm: point.estimated1rm, volume: point.volume,
    })),
  })),
  insights: [s3, s4].map((id) => ({
    session_id: id,
    rows: sessionStrengthInsights(data, id).map((row) => ({
      key: row.key, name: row.name,
      days_compared: row.daysCompared, load_delta: row.loadDelta,
      estimated_1rm_delta: row.estimated1rmDelta,
    })),
  })),
  joint: jointCases.map((value) => ({
    current: value.current, previous: value.previous,
    expected: assessJointCheckin(value.current, value.previous),
  })),
  checkin_due: [
    { today: '2026-08-17', expected: checkinDue(checkins, '2026-08-17') },
    { today: '2026-08-16', expected: checkinDue(checkins, '2026-08-16') },
    { today: '2026-08-10', expected: checkinDue(checkins, '2026-08-10') },
    { today: '2026-08-17', empty: true, expected: checkinDue([], '2026-08-17') },
  ],
  checkins,
}, null, 2)}\n`)
console.log(`wrote ${OUT}`)
