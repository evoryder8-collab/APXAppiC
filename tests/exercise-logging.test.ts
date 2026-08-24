import assert from 'node:assert/strict'
import test from 'node:test'
import { readFileSync } from 'node:fs'
import { CARDIO_MODALITIES, MOVEMENTS } from '../src/data/movements.ts'
import {
  derivePaceSecondsPerKilometre,
  descriptorForExercise,
  isValidExerciseFacts,
  loadedStrengthVolume,
  normalizeExerciseFacts,
  workoutLogFactSummary,
  type ExerciseLoggingKind,
} from '../src/lib/exerciseLogging.ts'
import { compareExerciseProgress, progressForWorkoutLog } from '../src/lib/progression.ts'
import { buildSessionRecords, hasLoggedFact, type SetEntry } from '../src/lib/workoutSession.ts'
import { EMPTY_DATA, type WorkoutLog } from '../src/lib/types.ts'

function log(facts: Partial<WorkoutLog>): WorkoutLog {
  return {
    id: 'log', user_id: 'user', session_id: 'session', exercise_id: null,
    exercise_name: 'Test', set_no: 1, weight_kg: null, reps: null, rir: 2,
    movement_id: null, duration_seconds: null, distance_meters: null, contacts: null,
    rounds: null, work_seconds: null, recovery_seconds: null,
    skipped: false, override_flag: false, created_at: '2026-08-23T08:00:00Z',
    ...facts,
  }
}

test('the supported kinds classify all 549 selectable catalogue rows', () => {
  const counts = new Map<ExerciseLoggingKind, number>()
  for (const movement of MOVEMENTS) {
    const kind = descriptorForExercise({ name: movement.name, movement_id: movement.id }).kind
    counts.set(kind, (counts.get(kind) ?? 0) + 1)
  }
  for (const modality of CARDIO_MODALITIES) {
    const kind = descriptorForExercise({ name: modality.name, movement_id: modality.id }).kind
    counts.set(kind, (counts.get(kind) ?? 0) + 1)
  }
  assert.deepEqual(Object.fromEntries(counts), {
    strength: 242, bodyweight: 132, isometric: 17, carry: 24,
    mobility: 90, interval: 28, circuit: 1, cardio: 15,
  })
  assert.equal([...counts.values()].reduce((sum, count) => sum + count, 0), 549)
})

test('one descriptor drives the facts shown by manual, guided and tracked logging', () => {
  assert.deepEqual(descriptorForExercise({ name: 'Pull-Up' }).fields, ['reps', 'signedLoad', 'rir'])
  assert.deepEqual(descriptorForExercise({ name: 'Box Jump' }).fields, ['contacts'])
  assert.deepEqual(descriptorForExercise({ name: 'Plank' }).fields, ['duration', 'signedLoad'])
  assert.deepEqual(descriptorForExercise({ name: "Farmer's Carry" }).fields, ['duration', 'distance', 'signedLoad'])
  assert.deepEqual(descriptorForExercise({ name: 'Stationary Bike' }).fields, ['duration', 'distance'])
  assert.equal(descriptorForExercise({ name: 'Treadmill Walk' }).kind, 'cardio')
  assert.equal(descriptorForExercise({ name: 'Assault Bike Sprint' }).movementId, 'air_bike')
  assert.deepEqual(descriptorForExercise({ name: 'Couch Stretch' }).fields, ['duration', 'completion'])
  assert.deepEqual(descriptorForExercise({ name: 'Burpee' }).fields, ['rounds', 'work', 'recovery'])
  assert.equal(descriptorForExercise({ name: 'Sun Salutation A' }).supported, false)
})

test('supplementary load and RIR cannot make an otherwise blank set complete', () => {
  const strength = descriptorForExercise({ name: 'Romanian Deadlift' })
  const bodyweight = descriptorForExercise({ name: 'Pull-Up' })
  const carry = descriptorForExercise({ name: "Farmer's Carry" })
  const interval = descriptorForExercise({ name: 'Burpee' })
  const contacts = descriptorForExercise({ name: 'Box Jump' })

  assert.equal(hasLoggedFact({ weight: 80, reps: null, rir: 2 }, strength), false)
  assert.equal(hasLoggedFact({ weight: 80, reps: 8, rir: null }, strength), true)
  assert.equal(hasLoggedFact({ weight: 0, reps: null, rir: null }, bodyweight), false)
  assert.equal(hasLoggedFact({ weight: 0, reps: 8, rir: null }, bodyweight), true)
  assert.equal(hasLoggedFact({ weight: 24, reps: null, rir: null }, carry), false)
  assert.equal(hasLoggedFact({ weight: 24, reps: null, rir: null, distanceMeters: 20 }, carry), true)
  assert.equal(hasLoggedFact({ weight: null, reps: null, rir: null, recoverySeconds: 30 }, interval), false)
  assert.equal(hasLoggedFact({ weight: null, reps: null, rir: null, rounds: 8, workSeconds: 30 }, interval), false)
  assert.equal(hasLoggedFact({ weight: null, reps: null, rir: null, rounds: 8, workSeconds: 30, recoverySeconds: 20 }, interval), true)
  assert.equal(hasLoggedFact({ weight: null, reps: null, rir: null }, contacts), false)
  assert.equal(hasLoggedFact({ weight: null, reps: null, rir: null, contacts: 12 }, contacts), true)
})

test('the shared save boundary requires a complete fact set for each kind', () => {
  const cardio = descriptorForExercise({ name: 'Stationary Bike' })
  const carry = descriptorForExercise({ name: "Farmer's Carry" })
  const interval = descriptorForExercise({ name: 'Burpee' })
  const circuit = descriptorForExercise({ name: 'Sun Salutation A' })

  assert.equal(isValidExerciseFacts({ weight: null, reps: null, rir: null, durationSeconds: 600 }, cardio), false)
  assert.equal(isValidExerciseFacts({ weight: null, reps: null, rir: null, durationSeconds: 600, distanceMeters: 3_000 }, cardio), true)
  assert.equal(isValidExerciseFacts({ weight: 24, reps: null, rir: null, distanceMeters: 20 }, carry), true)
  assert.equal(isValidExerciseFacts({ weight: 24, reps: null, rir: null, durationSeconds: 30 }, carry), true)
  assert.equal(isValidExerciseFacts({ weight: 24, reps: null, rir: null, durationSeconds: 30, distanceMeters: 20 }, carry), false)
  assert.equal(isValidExerciseFacts({ weight: null, reps: null, rir: null, rounds: 8, workSeconds: 30 }, interval), false)
  assert.equal(isValidExerciseFacts({ weight: null, reps: null, rir: null, rounds: 8, workSeconds: 30, recoverySeconds: 20 }, interval), true)
  assert.equal(isValidExerciseFacts({ weight: null, reps: null, rir: null }, circuit), false)

  assert.throws(() => buildSessionRecords({
    sessionId: 'invalid', userId: 'user', date: '2026-08-23', programDayId: 'day',
    isLite: false, isDeload: false, isEventRecovery: false, qualityScore: 0,
    startedAt: '2026-08-23T08:00:00Z', completedAt: '2026-08-23T08:10:00Z',
    exercises: [{
      exerciseId: null, movementId: 'cycle_stationary', name: 'Stationary Bike',
      plannedSets: 1, skipped: false, override: false,
      sets: [{ weight: null, reps: null, rir: null, durationSeconds: 600 }],
    }],
  }), /Incomplete cardio facts/)
})

test('normalization makes bodyweight explicit and skipped facts empty', () => {
  const bodyweight = descriptorForExercise({ name: 'Pull-Up' })
  assert.equal(normalizeExerciseFacts({ weight: null, reps: 8, rir: null }, bodyweight, false).weight, 0)
  assert.deepEqual(
    normalizeExerciseFacts({
      weight: -20, reps: 8, rir: 2, durationSeconds: 30, distanceMeters: 20,
      contacts: 4, rounds: 3, workSeconds: 30, recoverySeconds: 20,
    }, bodyweight, true),
    {
      weight: null, reps: null, rir: null, durationSeconds: null, distanceMeters: null,
      contacts: null, rounds: null, workSeconds: null, recoverySeconds: null,
    },
  )
})

test('loaded volume counts external strength load but never signed bodyweight assistance', () => {
  assert.equal(loadedStrengthVolume([
    log({ exercise_name: 'Bench Press', movement_id: 'bench_press_barbell', weight_kg: 50, reps: 10 }),
    log({ exercise_name: 'Pull-Up', movement_id: 'pull_up', weight_kg: -20, reps: 8 }),
    log({ exercise_name: 'Pull-Up', movement_id: 'pull_up', weight_kg: 10, reps: 5 }),
  ]), 500)
})

test('pace is derived from two measured facts and never persisted', () => {
  assert.equal(derivePaceSecondsPerKilometre(5_000, 1_500), 300)
  assert.equal(derivePaceSecondsPerKilometre(0, 1_500), null)
  assert.equal(derivePaceSecondsPerKilometre(5_000, 0), null)

  const facts: SetEntry = {
    weight: null, reps: null, rir: null, durationSeconds: 1_500, distanceMeters: 5_000,
  }
  const records = buildSessionRecords({
    sessionId: 'session', userId: 'user', date: '2026-08-23', programDayId: 'day',
    isLite: false, isDeload: false, isEventRecovery: false, qualityScore: 1,
    startedAt: '2026-08-23T07:30:00Z', completedAt: '2026-08-23T08:00:00Z',
    exercises: [{
      exerciseId: null, movementId: 'cycle_stationary', name: 'Stationary Bike',
      plannedSets: 1, sets: [facts], skipped: false, override: false,
    }],
  }, () => 'log')
  assert.equal(records.logs[0].distance_meters, 5_000)
  assert.equal(records.logs[0].duration_seconds, 1_500)
  assert.equal('pace' in records.logs[0], false)
  assert.equal('logging_kind' in records.logs[0], false)
  assert.equal(workoutLogFactSummary(records.logs[0]).at(-1), '5:00 /km')
  assert.equal(workoutLogFactSummary(log({
    exercise_name: 'Stationary Bike', movement_id: 'cycle_stationary',
    duration_seconds: 1_799, distance_meters: 5_000,
  })).at(-1), '6:00 /km')
})

test('skipped rows retain correlation but clear every measured fact', () => {
  const records = buildSessionRecords({
    sessionId: 'session', userId: 'user', date: '2026-08-23', programDayId: 'day',
    isLite: false, isDeload: false, isEventRecovery: false, qualityScore: 0,
    startedAt: '2026-08-23T07:30:00Z', completedAt: '2026-08-23T08:00:00Z',
    exercises: [{
      exerciseId: null, movementId: 'farmers_carry', name: "Farmer's Carry",
      plannedSets: 1, skipped: true, override: false,
      sets: [{
        weight: 24, reps: 10, rir: 2, durationSeconds: 30, distanceMeters: 20,
        contacts: 10, rounds: 4, workSeconds: 30, recoverySeconds: 20,
      }],
    }],
  }, () => 'log')
  assert.deepEqual(records.logs[0], {
    id: 'log', user_id: 'user', session_id: 'session', exercise_id: null,
    exercise_name: "Farmer's Carry", set_no: 1, weight_kg: null, reps: null, rir: null,
    movement_id: 'farmers_carry', duration_seconds: null, distance_meters: null,
    contacts: null, rounds: null, work_seconds: null, recovery_seconds: null,
    skipped: true, override_flag: false, created_at: '2026-08-23T08:00:00.000Z',
  })
})

test('progress has an explicit rule for every supported kind', () => {
  assert.equal(compareExerciseProgress(log({ weight_kg: -20, reps: 5 }), log({ weight_kg: -15, reps: 5 }), descriptorForExercise({ name: 'Pull-Up' })), 'improved')
  assert.equal(compareExerciseProgress(log({ weight_kg: 10, duration_seconds: 30 }), log({ weight_kg: 10, duration_seconds: 35 }), descriptorForExercise({ name: 'Plank' })), 'improved')
  assert.equal(compareExerciseProgress(log({ weight_kg: 24, distance_meters: 20 }), log({ weight_kg: 28, distance_meters: 20 }), descriptorForExercise({ name: "Farmer's Carry" })), 'improved')
  assert.equal(compareExerciseProgress(log({ distance_meters: 5_000, duration_seconds: 1_500 }), log({ distance_meters: 5_000, duration_seconds: 1_440 }), descriptorForExercise({ name: 'Stationary Bike' })), 'improved')
  assert.equal(compareExerciseProgress(log({ rounds: 8, work_seconds: 30, recovery_seconds: 30 }), log({ rounds: 8, work_seconds: 35, recovery_seconds: 30 }), descriptorForExercise({ name: 'Burpee' })), 'improved')
  assert.equal(compareExerciseProgress(log({ duration_seconds: 30 }), log({ duration_seconds: 45 }), descriptorForExercise({ name: 'Couch Stretch' })), 'adherence')
  assert.equal(compareExerciseProgress(log({ contacts: 5 }), log({ contacts: 8 }), descriptorForExercise({ name: 'Box Jump' })), 'adherence')
})

test('progress remains conservative when effort or load facts are missing', () => {
  const strength = descriptorForExercise({ name: 'Romanian Deadlift' })
  assert.equal(compareExerciseProgress(
    log({ weight_kg: 80, reps: 8, rir: null }),
    log({ weight_kg: 80, reps: 9, rir: null }),
    strength,
  ), 'incomparable')
  assert.equal(compareExerciseProgress(
    log({ weight_kg: null, reps: 8, rir: 2 }),
    log({ weight_kg: 80, reps: 8, rir: 2 }),
    strength,
  ), 'incomparable')
})

test('cardio progress compares distance and derived pace rather than raw duration', () => {
  const cardio = descriptorForExercise({ name: 'Stationary Bike' })
  assert.equal(compareExerciseProgress(
    log({ distance_meters: 5_000, duration_seconds: 1_800 }),
    log({ distance_meters: 10_000, duration_seconds: 3_000 }),
    cardio,
  ), 'improved')
})

test('the production history path reports cardio progress from the previous matching set', () => {
  const previous = log({
    id: 'old-log', session_id: 'old-session', exercise_name: 'Stationary Bike',
    movement_id: 'cycle_stationary', duration_seconds: 1_500, distance_meters: 5_000,
  })
  const current = log({
    id: 'new-log', session_id: 'new-session', exercise_name: 'Stationary Bike',
    movement_id: 'cycle_stationary', duration_seconds: 1_440, distance_meters: 5_000,
  })
  const sessions = [
    { id: 'old-session', user_id: 'user', date: '2026-08-20', program_day_id: null, is_lite: false, is_deload: false, is_event_recovery: false, completed: true, quality_score: 1, started_at: null, completed_at: null, notes: '' },
    { id: 'new-session', user_id: 'user', date: '2026-08-23', program_day_id: null, is_lite: false, is_deload: false, is_event_recovery: false, completed: true, quality_score: 1, started_at: null, completed_at: null, notes: '' },
  ]

  assert.equal(progressForWorkoutLog({ ...EMPTY_DATA, workout_sessions: sessions, workout_logs: [previous, current] }, current), 'improved')
})

test('production history lazily correlates legacy aliases with canonical movement ids', () => {
  const previous = log({
    id: 'old-alias', session_id: 'old-session', exercise_name: 'Pull Ups (different grip)',
    movement_id: null, weight_kg: 0, reps: 8, rir: 2,
  })
  const current = log({
    id: 'new-canonical', session_id: 'new-session', exercise_name: 'Pull-Up',
    movement_id: 'pull_up', weight_kg: 0, reps: 9, rir: 2,
  })
  const sessions = [
    { id: 'old-session', user_id: 'user', date: '2026-08-20', program_day_id: null, is_lite: false, is_deload: false, is_event_recovery: false, completed: true, quality_score: 1, started_at: null, completed_at: null, notes: '' },
    { id: 'new-session', user_id: 'user', date: '2026-08-23', program_day_id: null, is_lite: false, is_deload: false, is_event_recovery: false, completed: true, quality_score: 1, started_at: null, completed_at: null, notes: '' },
  ]
  assert.equal(progressForWorkoutLog({ ...EMPTY_DATA, workout_sessions: sessions, workout_logs: [previous, current] }, current), 'improved')
})

test('the database stores measured facts, not derived pace, kind or assistance', () => {
  const migration = readFileSync('supabase/migrations/021_exercise_logging_facts.sql', 'utf8')
  for (const column of [
    'movement_id', 'duration_seconds', 'distance_meters', 'contacts',
    'rounds', 'work_seconds', 'recovery_seconds',
  ]) assert.match(migration, new RegExp(`add column if not exists ${column}\\b`))
  assert.doesNotMatch(migration, /pace|logging_kind|assistance/i)
  assert.match(migration, /workout_logs_skipped_facts_empty/)
  assert.match(migration, /skipped\s*=\s*false[\s\S]*weight_kg is null[\s\S]*recovery_seconds is null/)
})

test('Pages refuses to publish the client before the measured-fact schema exists', () => {
  const workflow = readFileSync('.github/workflows/deploy.yml', 'utf8')
  const gate = workflow.indexOf('Verify exercise log schema')
  const build = workflow.indexOf('npm run build')
  assert.ok(gate >= 0 && build > gate)
  for (const column of [
    'movement_id', 'duration_seconds', 'distance_meters', 'contacts',
    'rounds', 'work_seconds', 'recovery_seconds',
  ]) assert.match(workflow, new RegExp(column))
})
