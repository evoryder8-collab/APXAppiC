import assert from 'node:assert/strict'
import test from 'node:test'
import { EMPTY_DATA, type AppData, type WorkoutLog, type WorkoutSession } from '../src/lib/types.ts'
import {
  encodeTreadmillLog,
  manualExerciseTimelineForDate,
  manualWorkoutDeletionPlan,
  manualWorkoutHasAutomaticTitle,
  manualWorkoutEditorDraft,
  manualWorkoutNotes,
  manualSessionsForDate,
  parseTreadmillLog,
  rankManualWorkoutPresets,
  reconcileManualWorkoutLogs,
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

test('repeated same-name exercises remain separate occurrences after reload', () => {
  const savedSession = session('repeat', '2026-07-15', 'Back and arms')
  const rows = [
    { ...log('repeat', 'Hammer Curl', 1), id: 'curl-a-1', created_at: '2026-07-15T10:00:00.000Z', reps: 12 },
    { ...log('repeat', 'Hammer Curl', 2), id: 'curl-a-2', created_at: '2026-07-15T10:00:00.100Z', reps: 10 },
    { ...log('repeat', 'Hammer Curl', 1), id: 'curl-b-1', created_at: '2026-07-15T10:01:00.000Z', reps: 8 },
    { ...log('repeat', 'Hammer Curl', 2), id: 'curl-b-2', created_at: '2026-07-15T10:01:00.100Z', reps: 6 },
  ]
  const data: AppData = { ...EMPTY_DATA, workout_sessions: [savedSession], workout_logs: rows }

  const draft = manualWorkoutEditorDraft(data, savedSession.id)
  assert.deepEqual(draft?.exercises.map((exercise) => exercise.sets.map((set) => set.reps)), [[12, 10], [8, 6]])
  const timeline = manualExerciseTimelineForDate(data, savedSession.date)
  assert.equal(timeline.length, 2)
  assert.deepEqual(timeline.map((entry) => entry.logIds), [['curl-a-1', 'curl-a-2'], ['curl-b-1', 'curl-b-2']])
  assert.notEqual(timeline[0].key, timeline[1].key)
})

test('editing a workout preserves matching set ids and deletes only removed sets', () => {
  const existing = [
    log('editable', 'Seated Cable Row', 1),
    log('editable', 'Seated Cable Row', 2),
    log('editable', 'Hammer Curl', 1),
  ]
  const proposed = [
    { ...log('editable', 'Seated Cable Row', 1), id: 'temporary-1', reps: 12 },
    { ...log('editable', 'Seated Cable Row', 2), id: 'temporary-2', weight_kg: 90 },
    { ...log('editable', 'Seated Cable Row', 3), id: 'temporary-3' },
  ]

  const result = reconcileManualWorkoutLogs(existing, proposed)
  assert.deepEqual(result.logs.map((row) => row.id), [
    existing[0].id,
    existing[1].id,
    'temporary-3',
  ])
  assert.deepEqual(result.staleIds, [existing[2].id])
  assert.equal(result.logs[0].reps, 12)
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

test('exercise order keys remain stable after chronology changes', () => {
  const savedSession = session('stable-order', '2026-07-15', 'A B C')
  const data: AppData = {
    ...EMPTY_DATA,
    workout_sessions: [savedSession],
    workout_logs: [
      { ...log(savedSession.id, 'Exercise A'), id: 'log-a', created_at: '2026-07-15T08:00:00Z' },
      { ...log(savedSession.id, 'Exercise B'), id: 'log-b', created_at: '2026-07-15T08:01:00Z' },
      { ...log(savedSession.id, 'Exercise C'), id: 'log-c', created_at: '2026-07-15T08:02:00Z' },
    ],
  }
  const initial = manualExerciseTimelineForDate(data, '2026-07-15')
  const requested = [initial[1], initial[0], initial[2]]
  const resequenced = resequenceManualWorkoutLogs(data.workout_logs, requested)
  const reloaded = manualExerciseTimelineForDate({ ...data, workout_logs: resequenced }, '2026-07-15')

  assert.deepEqual(reloaded.map((item) => item.canonicalName), ['Exercise B', 'Exercise A', 'Exercise C'])
  assert.deepEqual(reloaded.map((item) => item.key), requested.map((item) => item.key))
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

test('same-weekday fit remains stronger than a frequently used but off-day recent workout', () => {
  const sameDay = session('wednesday', '2026-07-01', 'Wednesday workout')
  const recentSessions = Array.from({ length: 8 }, (_, index) => (
    session(`frequent-${index}`, '2026-07-14', 'Frequent workout')
  ))
  const data: AppData = {
    ...EMPTY_DATA,
    workout_sessions: [sameDay, ...recentSessions],
    workout_logs: [log(sameDay.id, 'Pull-up'), ...recentSessions.map((item) => log(item.id, 'Leg Press'))],
  }

  assert.equal(rankManualWorkoutPresets(data, '2026-07-15')[0]?.title, 'Wednesday workout')
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

test('quick workout ranking returns at most seven persisted workout signatures', () => {
  const workoutSessions = Array.from({ length: 9 }, (_, index) => (
    session(`session-${index}`, `2026-06-${String(index + 1).padStart(2, '0')}`, `Workout ${index + 1}`)
  ))
  const workoutLogs = workoutSessions.map((item, index) => log(item.id, `Exercise ${index + 1}`))
  const data: AppData = { ...EMPTY_DATA, workout_sessions: workoutSessions, workout_logs: workoutLogs }

  const ranked = rankManualWorkoutPresets(data, '2026-07-15')
  assert.equal(ranked.length, 7)
  assert.equal(new Set(ranked.map((preset) => preset.signature)).size, 7)
})

test('preset learning and whole-workout deletion stay inside the active owner and selected date', () => {
  const ownerSession = session('owner-session', '2026-07-15', 'Back day')
  const otherDateSession = session('owner-other-date', '2026-07-14', 'Leg day')
  const foreignSession = { ...session('foreign-session', '2026-07-15', 'Foreign day'), user_id: 'foreign' }
  const ownerLog = log(ownerSession.id, 'Seated Cable Row')
  const otherDateLog = log(otherDateSession.id, 'Leg Press')
  const foreignLog = { ...log(foreignSession.id, 'Machine Chest Press'), user_id: 'foreign' }
  const data: AppData = {
    ...EMPTY_DATA,
    profile: { user_id: 'user' } as NonNullable<AppData['profile']>,
    workout_sessions: [ownerSession, otherDateSession, foreignSession],
    workout_logs: [ownerLog, otherDateLog, foreignLog],
  }

  assert.deepEqual(rankManualWorkoutPresets(data, '2026-07-15').map((preset) => preset.title), ['Leg day'])
  assert.deepEqual(manualWorkoutDeletionPlan(data, '2026-07-15'), {
    sessionIds: [ownerSession.id],
    logIds: [ownerLog.id],
  })
})

test('quick presets never learn from workouts dated after the selected day', () => {
  const past = session('past', '2026-07-08', 'Past workout')
  const future = session('future', '2026-07-22', 'Future workout')
  const data: AppData = {
    ...EMPTY_DATA,
    workout_sessions: [past, future],
    workout_logs: [log(past.id, 'Pull-up'), log(future.id, 'Leg Press')],
  }

  assert.deepEqual(rankManualWorkoutPresets(data, '2026-07-15').map((preset) => preset.title), ['Past workout'])
})

test('quick presets exclude a workout already logged on the selected day', () => {
  const prior = session('prior', '2026-07-08', 'Prior back day')
  const today = session('today', '2026-07-15', 'Already logged today')
  const data: AppData = {
    ...EMPTY_DATA,
    workout_sessions: [prior, today],
    workout_logs: [log(prior.id, 'Pull-up'), log(today.id, 'Leg Press')],
  }

  assert.deepEqual(rankManualWorkoutPresets(data, '2026-07-15').map((preset) => preset.title), ['Prior back day'])
})
