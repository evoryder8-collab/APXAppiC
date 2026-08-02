import assert from 'node:assert/strict'
import test from 'node:test'
import { workoutLogsInPerformedOrder } from '../src/lib/workoutLogOrder.ts'
import { EMPTY_DATA, type WorkoutLog } from '../src/lib/types.ts'

function log(id: string, name: string, setNo: number, createdAt: string, exerciseId: string | null = null): WorkoutLog {
  return {
    id,
    user_id: 'user',
    session_id: 'session',
    exercise_id: exerciseId,
    exercise_name: name,
    set_no: setNo,
    weight_kg: 10,
    reps: 8,
    rir: 2,
    skipped: false,
    override_flag: false,
    created_at: createdAt,
  }
}

const session = {
  id: 'session',
  user_id: 'user',
  date: '2026-08-01',
  program_day_id: 'day',
  is_lite: false,
  is_deload: false,
  is_event_recovery: false,
  completed: true,
  quality_score: 1,
  started_at: null,
  completed_at: null,
  notes: '',
}

test('completed workout stats show the first performed exercise first', () => {
  const data = {
    ...EMPTY_DATA,
    workout_sessions: [session],
    workout_logs: [
      log('last-2', 'Pike Push-up', 2, '2026-08-02T00:45:00.004Z'),
      log('first-2', 'Weighted Push-up', 2, '2026-08-02T00:30:00.002Z'),
      log('last-1', 'Pike Push-up', 1, '2026-08-02T00:45:00.003Z'),
      log('first-1', 'Weighted Push-up', 1, '2026-08-02T00:30:00.001Z'),
    ],
  }

  assert.deepEqual(
    workoutLogsInPerformedOrder(data, 'session').map((row) => `${row.exercise_name}:${row.set_no}`),
    ['Weighted Push-up:1', 'Weighted Push-up:2', 'Pike Push-up:1', 'Pike Push-up:2'],
  )
})

test('legacy logs sharing a timestamp fall back to planned exercise order', () => {
  const shared = '2026-08-02T00:30:00.000Z'
  const data = {
    ...EMPTY_DATA,
    workout_sessions: [session],
    exercises: [
      { id: 'first', user_id: 'user', program_day_id: 'day', name: 'Weighted Push-up', sets: 1, rep_min: 8, rep_max: 8, rep_unit: 'reps' as const, per_side: false, rest_sec: 90, tempo_up_s: 1, tempo_down_s: 2, tempo_pause_s: 0, tempo_note: '', notes: '', increment_kg: 1, is_lite: false, optional: false, sort_order: 0 },
      { id: 'second', user_id: 'user', program_day_id: 'day', name: 'Pike Push-up', sets: 1, rep_min: 8, rep_max: 8, rep_unit: 'reps' as const, per_side: false, rest_sec: 90, tempo_up_s: 1, tempo_down_s: 2, tempo_pause_s: 0, tempo_note: '', notes: '', increment_kg: 1, is_lite: false, optional: false, sort_order: 1 },
    ],
    workout_logs: [
      log('second-log', 'Pike Push-up', 1, shared, 'second'),
      log('first-log', 'Weighted Push-up', 1, shared, 'first'),
    ],
  }

  assert.deepEqual(
    workoutLogsInPerformedOrder(data, 'session').map((row) => row.exercise_name),
    ['Weighted Push-up', 'Pike Push-up'],
  )
})
