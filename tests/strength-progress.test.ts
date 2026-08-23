import test from 'node:test'
import assert from 'node:assert/strict'
import { assessJointCheckin, buildStrengthSeries, checkinDue, sessionStrengthInsights } from '../src/lib/strengthProgress.ts'
import { recommendLoad } from '../src/lib/progression.ts'
import { EMPTY_DATA, type AppData, type Exercise, type JointCheckin } from '../src/lib/types.ts'

function strengthData(): AppData {
  return {
    ...EMPTY_DATA,
    workout_sessions: [
      { id: 's1', user_id: 'u', date: '2026-04-15', program_day_id: 'd', is_lite: false, is_deload: false, is_event_recovery: false, completed: true, quality_score: 1, started_at: null, completed_at: null, notes: '' },
      { id: 's2', user_id: 'u', date: '2026-07-14', program_day_id: 'd', is_lite: false, is_deload: false, is_event_recovery: false, completed: true, quality_score: 1, started_at: null, completed_at: null, notes: '' },
    ],
    workout_logs: [
      { id: 'l1', user_id: 'u', session_id: 's1', exercise_id: 'bench', exercise_name: 'Bench Press', set_no: 1, weight_kg: 80, reps: 8, rir: 2, skipped: false, override_flag: false, created_at: '' },
      { id: 'l2', user_id: 'u', session_id: 's2', exercise_id: 'bench', exercise_name: 'Bench Press', set_no: 1, weight_kg: 85, reps: 8, rir: 2, skipped: false, override_flag: false, created_at: '' },
      { id: 'l3', user_id: 'u', session_id: 's2', exercise_id: 'bench', exercise_name: 'Bench Press', set_no: 2, weight_kg: 82.5, reps: 9, rir: 1, skipped: false, override_flag: false, created_at: '' },
    ],
  }
}

function progressionData(rir: number | null): { data: AppData; exercise: Exercise } {
  const exercise: Exercise = {
    id: 'bench', user_id: 'u', program_day_id: 'd', name: 'Bench Press', sets: 1,
    rep_min: 8, rep_max: 12, rep_unit: 'reps', per_side: false, rest_sec: 120,
    tempo_up_s: 1, tempo_down_s: 2, tempo_pause_s: 0, tempo_note: '', notes: '',
    increment_kg: 2.5, is_lite: false, optional: false, sort_order: 0,
  }
  return {
    exercise,
    data: {
      ...EMPTY_DATA,
      workout_sessions: [{
        id: 's1', user_id: 'u', date: '2026-08-20', program_day_id: 'd',
        is_lite: false, is_deload: false, is_event_recovery: false, completed: true,
        quality_score: 1, started_at: null, completed_at: null, notes: '',
      }],
      workout_logs: [{
        id: 'l1', user_id: 'u', session_id: 's1', exercise_id: 'bench',
        exercise_name: 'Bench Press', set_no: 1, weight_kg: 60, reps: 12, rir,
        skipped: false, override_flag: false, created_at: '2026-08-20T10:00:00Z',
      }],
    },
  }
}

test('progression requires explicit reserve at or above the two-RIR target', () => {
  for (const [rir, expected] of [[null, 60], [0, 60], [1, 60], [2, 62.5], [5, 62.5]] as const) {
    const { data, exercise } = progressionData(rir)
    assert.equal(recommendLoad(data, exercise).weight, expected, `RIR ${rir}`)
  }
})

test('a revisioned exercise keeps same-account movement progression without borrowing another account', () => {
  const { data, exercise } = progressionData(2)
  const rebuilt = { ...exercise, id: 'bench-generation-2' }

  assert.equal(recommendLoad(data, rebuilt).weight, 62.5)
  assert.equal(recommendLoad(data, { ...rebuilt, user_id: 'other-user' }).weight, null)
})

test('strength series uses per-set loads and creates an honest 90-day comparison', () => {
  const data = strengthData()
  const series = buildStrengthSeries(data)
  assert.equal(series.length, 1)
  assert.deepEqual(series[0].points[1].setWeights, { 1: 85, 2: 82.5 })
  const insight = sessionStrengthInsights(data, 's2')[0]
  assert.equal(insight.loadDelta, 5)
  assert.equal(insight.daysCompared, 90)
  assert.ok((insight.estimated1rmDelta ?? 0) > 0)
})

test('legacy strength insights exclude signed bodyweight load', () => {
  const data = strengthData()
  data.workout_logs.push({
    id: 'pull-up', user_id: 'u', session_id: 's2', exercise_id: 'pull-up',
    exercise_name: 'Pull-Up', set_no: 1, weight_kg: 10, reps: 8, rir: 2,
    movement_id: 'pull_up', duration_seconds: null, distance_meters: null, contacts: null,
    rounds: null, work_seconds: null, recovery_seconds: null,
    skipped: false, override_flag: false, created_at: '',
  })

  assert.deepEqual(buildStrengthSeries(data).map((series) => series.name), ['Bench Press'])
})

test('joint check-in separates isolated load reduction from whole-body deload signals', () => {
  const base: JointCheckin = { id: 'a', date: '2026-07-01', arms: 3, core: 3, legs: 3 }
  assert.equal(assessJointCheckin({ ...base, id: 'b', arms: 8 }).state, 'regional_deload')
  assert.equal(assessJointCheckin({ ...base, id: 'c', arms: 7, legs: 7 }).state, 'whole_deload')
  assert.equal(assessJointCheckin({ ...base, id: 'd', core: 9 }).state, 'stop_and_review')
  assert.equal(assessJointCheckin({ ...base, id: 'e', arms: 5 }, base).state, 'watch')
})

test('joint check-in becomes due once a full week has elapsed', () => {
  const latest: JointCheckin = { id: 'a', date: '2026-07-08', arms: 2, core: 2, legs: 2 }
  assert.equal(checkinDue([latest], '2026-07-14'), false)
  assert.equal(checkinDue([latest], '2026-07-15'), true)
})
