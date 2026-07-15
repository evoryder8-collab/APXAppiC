import test from 'node:test'
import assert from 'node:assert/strict'
import { assessJointCheckin, buildStrengthSeries, checkinDue, sessionStrengthInsights } from '../src/lib/strengthProgress.ts'
import { EMPTY_DATA, type AppData, type JointCheckin } from '../src/lib/types.ts'

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
