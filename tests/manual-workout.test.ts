import assert from 'node:assert/strict'
import test from 'node:test'
import { EMPTY_DATA, type AppData, type WorkoutLog, type WorkoutSession } from '../src/lib/types.ts'
import {
  encodeTreadmillLog,
  manualExerciseTimelineForDate,
  manualWorkoutHasAutomaticTitle,
  manualWorkoutEditorDraft,
  manualWorkoutNotes,
  manualSessionsForDate,
  parseTreadmillLog,
  rankManualWorkoutPresets,
  resequenceManualWorkoutLogs,
} from '../src/lib/manualWorkout.ts'

function session(id: string, date: string, title: string): WorkoutSession {
  return {
    id, user_id: 'user', date, program_day_id: 'day', is_lite: false, is_deload: false,
    is_event_recovery: false, completed: true, quality_score: 1, started_at: `${date}T10:00:00Z`,
    completed_at: `${date}T11:00:00Z`, notes: manualWorkoutNotes(title),
  }
}

function log(sessionId: string, name: string, setNo = 1): WorkoutLog {
  return {
    id: `${sessionId}-${name}-${setNo}`, user_id: 'user', session_id: sessionId, exercise_id: null,
    exercise_name: name, set_no: setNo, weight_kg: 80, reps: 10, rir: null,
    skipped: false, override_flag: false, created_at: `2026-07-01T10:0${setNo}:00Z`,
  }
}

test('treadmill metrics round trip without becoming strength load', () => {
  const encoded = encodeTreadmillLog('Treadmill Walk', { distanceKm: 4.5, inclineDeg: 13, durationMin: 25 })
  assert.equal(encoded, 'Treadmill Walk · 4.5 km · 13° · 25 min')
  assert.deepEqual(parseTreadmillLog(encoded), {
    name: 'Treadmill Walk',
    metrics: { distanceKm: 4.5, inclineDeg: 13, durationMin: 25 },
  })
})

test('automatic workout titles remain localizable after a language switch', () => {
  const notes = manualWorkoutNotes('')
  assert.equal(manualWorkoutHasAutomaticTitle(notes), true)
})

test('a saved manual workout reopens with its title, exercises, sets and weights', () => {
  const savedSession = session('editable', '2026-07-15', 'Back day')
  const data: AppData = {
    ...EMPTY_DATA,
    workout_sessions: [savedSession],
    workout_logs: [log('editable', 'Seated Cable Row', 1), { ...log('editable', 'Seated Cable Row', 2), weight_kg: 86, reps: 8 }],
  }
  const draft = manualWorkoutEditorDraft(data, savedSession.id)
  assert.equal(draft?.title, 'Back day')
  assert.equal(draft?.exercises[0]?.canonicalName, 'Seated Cable Row')
  assert.deepEqual(draft?.exercises[0]?.sets.map((set) => [set.reps, set.weightKg]), [[10, 80], [8, 86]])
})

test('manual workout exercises read from first performed at the top to last performed at the bottom', () => {
  const early = {
    ...session('early', '2026-07-15', 'Pull-ups'),
    started_at: '2026-07-15T08:00:00Z',
    completed_at: '2026-07-15T08:10:00Z',
  }
  const late = {
    ...session('late', '2026-07-15', 'Hammer curls'),
    started_at: '2026-07-15T09:00:00Z',
    completed_at: '2026-07-15T09:10:00Z',
  }
  const data: AppData = {
    ...EMPTY_DATA,
    workout_sessions: [late, early],
    workout_logs: [
      { ...log('late', 'Hammer Curl'), created_at: '2026-07-15T09:05:00Z' },
      { ...log('early', 'Pull-up'), created_at: '2026-07-15T08:05:00Z' },
    ],
  }

  assert.deepEqual(manualSessionsForDate(data, '2026-07-15').map((item) => item.id), ['early', 'late'])
  assert.deepEqual(manualExerciseTimelineForDate(data, '2026-07-15').map((item) => item.canonicalName), ['Pull-up', 'Hammer Curl'])
})

test('manual exercise reordering persists through workout-log chronology', () => {
  const firstSession = session('first', '2026-07-15', 'Pull-ups')
  const secondSession = session('second', '2026-07-15', 'Rows')
  const data: AppData = {
    ...EMPTY_DATA,
    workout_sessions: [firstSession, secondSession],
    workout_logs: [
      { ...log('first', 'Pull-up'), created_at: '2026-07-15T08:00:00Z' },
      { ...log('second', 'Seated Cable Row'), created_at: '2026-07-15T09:00:00Z' },
    ],
  }
  const reversed = manualExerciseTimelineForDate(data, '2026-07-15').reverse()
  const workoutLogs = resequenceManualWorkoutLogs(data.workout_logs, reversed)
  const reordered = manualExerciseTimelineForDate({ ...data, workout_logs: workoutLogs }, '2026-07-15')

  assert.deepEqual(reordered.map((item) => item.canonicalName), ['Seated Cable Row', 'Pull-up'])
})

test('smart presets prioritize a repeated workout on the same weekday', () => {
  const workoutSessions = [
    session('back-1', '2026-07-01', 'Back'),
    session('legs-1', '2026-07-02', 'Legs'),
    session('back-2', '2026-07-08', 'Back'),
  ]
  const workoutLogs = [
    log('back-1', 'Seated Cable Row'),
    log('legs-1', 'Leg Press'),
    log('back-2', 'Seated Cable Row'),
  ]
  const data: AppData = { ...EMPTY_DATA, workout_sessions: workoutSessions, workout_logs: workoutLogs }
  const ranked = rankManualWorkoutPresets(data, '2026-07-15')
  assert.equal(ranked[0]?.title, 'Back')
  assert.equal(ranked[0]?.sameWeekdayUses, 2)
  assert.equal(ranked[0]?.reason, 'same-weekday')
})

test('smart presets fall back to the workout that followed yesterday in past weeks', () => {
  const workoutSessions = [
    session('push-old', '2026-06-01', 'Push'),
    session('pull-old', '2026-06-02', 'Pull'),
    session('push-yesterday', '2026-07-09', 'Push'),
  ]
  const workoutLogs = [
    log('push-old', 'Machine Chest Press'),
    log('pull-old', 'Seated Cable Row'),
    log('push-yesterday', 'Machine Chest Press'),
  ]
  const data: AppData = { ...EMPTY_DATA, workout_sessions: workoutSessions, workout_logs: workoutLogs }
  const ranked = rankManualWorkoutPresets(data, '2026-07-10')
  assert.equal(ranked[0]?.title, 'Pull')
  assert.equal(ranked[0]?.reason, 'sequence')
})
