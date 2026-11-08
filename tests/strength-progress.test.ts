import test from 'node:test'
import assert from 'node:assert/strict'
import { assessJointCheckin, buildRankedExerciseHistory, buildStrengthSeries, checkinDue, distinctInsightTexts, sessionStrengthInsights } from '../src/lib/strengthProgress.ts'
import { seedProfile } from '../src/data/seed.ts'
import { recommendLoad } from '../src/lib/progression.ts'
import { EMPTY_DATA, type AppData, type Exercise, type JointCheckin } from '../src/lib/types.ts'

function strengthData(): AppData {
  return {
    ...EMPTY_DATA,
    profile: seedProfile('u'),
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

test('tracked history survives regenerated exercise row ids and keeps one point per session', () => {
  const data = strengthData()
  const template = data.workout_logs[0]
  data.workout_logs = [
    { ...template, id: 'front-1a', session_id: 's1', exercise_id: 'front-generation-1', exercise_name: 'Front Lunge', movement_id: 'forward_lunge', set_no: 1, weight_kg: 20, reps: 12 },
    { ...template, id: 'front-1b', session_id: 's1', exercise_id: 'front-generation-1', exercise_name: 'Front Lunge', movement_id: 'forward_lunge', set_no: 2, weight_kg: 20, reps: 12 },
    { ...template, id: 'front-2a', session_id: 's2', exercise_id: 'front-generation-2', exercise_name: 'Front Lunge', movement_id: 'forward_lunge', set_no: 1, weight_kg: 25, reps: 12 },
    { ...template, id: 'front-2b', session_id: 's2', exercise_id: 'front-generation-2', exercise_name: 'Front Lunge', movement_id: 'forward_lunge', set_no: 2, weight_kg: 25, reps: 12 },
  ]

  const series = buildStrengthSeries(data)

  assert.equal(series.length, 1)
  assert.equal(series[0].key, 'movement:forward_lunge')
  assert.deepEqual(series[0].points.map((point) => point.topWeight), [20, 25])
  assert.deepEqual(series[0].points.map((point) => point.volume), [480, 600])
})

test('workout receipt removes repeated strength signal copy', () => {
  assert.deepEqual(
    distinctInsightTexts([
      'First clean baseline recorded.',
      'First clean baseline recorded.',
      'Front Lunge increased by 5 kg.',
      'Calf Raise held steady.',
    ], 3),
    [
      'First clean baseline recorded.',
      'Front Lunge increased by 5 kg.',
      'Calf Raise held steady.',
    ],
  )
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

test('rank all performed sessions, including reps-only sessions, independently of weighted points', () => {
  const data = strengthData()
  const receipt = data.workout_sessions[0]
  const set = data.workout_logs[0]
  data.workout_sessions.push(
    { ...receipt, id: 'old', date: '2020-01-01' },
    { ...receipt, id: 'foreign', user_id: 'other' },
    { ...receipt, id: 'draft', completed: false },
  )
  const press = { ...set, exercise_name: 'Leg Press', movement_id: 'leg_press' }
  const row = { ...set, exercise_name: 'Machine Row', movement_id: 'machine_row' }
  data.workout_logs = [
    { ...row, session_id: 's2', weight_kg: 70 },
    { ...row, session_id: 's1', weight_kg: 65 },
    { ...press, session_id: 'old', weight_kg: 60, reps: 5 },
    { ...press, session_id: 'old', weight_kg: 60, reps: 8, set_no: 2 },
    { ...press, session_id: 's1', weight_kg: null },
    { ...press, session_id: 's2', weight_kg: null },
    { ...set, exercise_name: 'Band or DB Curls', movement_id: 'dumbbell_curl', weight_kg: 80 },
    { ...set, exercise_name: 'Dumbbell Curl', movement_id: 'dumbbell_curl', weight_kg: 8 },
    { ...set, exercise_name: 'Dead Hang', movement_id: 'dead_hang', weight_kg: 85, duration_seconds: 30, reps: null },
    { ...set, exercise_name: 'Custom band exercise', weight_kg: 90 },
    { ...set, exercise_name: 'Skipped', skipped: true },
    { ...set, exercise_name: 'Empty', weight_kg: null, reps: null },
    { ...set, exercise_name: 'Unfinished', session_id: 'draft' },
    { ...set, exercise_name: 'Orphan', session_id: 'missing' },
    { ...set, exercise_name: 'Wrong owner', user_id: 'other' },
    { ...set, exercise_name: 'Wrong receipt owner', session_id: 'foreign' },
    { ...set, exercise_name: 'Invalid load', weight_kg: Infinity, reps: null },
  ]
  const ranked = buildRankedExerciseHistory(data)
  assert.deepEqual(ranked.map((item) => [item.name, item.sessionCount]), [
    ['Leg Press', 3], ['Machine Row', 2], ['Band or DB Curls', 1],
    ['Custom band exercise', 1], ['Dead Hang', 1], ['Dumbbell Curl', 1],
  ])
  const weighted = buildStrengthSeries(data)
  assert.deepEqual(weighted.map((item) => [item.name, item.region, item.points.length]), [
    ['Leg Press', 'lower', 1], ['Machine Row', 'upper', 2], ['Dumbbell Curl', 'upper', 1],
  ])
  assert.deepEqual([weighted[0].points[0].date, weighted[0].points[0].topWeight, weighted[0].points[0].topReps], ['2020-01-01', 60, 8])
  assert.equal(weighted[2].points[0].topWeight, 8)
  assert.deepEqual(buildRankedExerciseHistory({ ...data, profile: null, settings: null }), [])
})

test('legacy treadmill distances count as one movement and never produce a weight curve', () => {
  const data = strengthData()
  const set = data.workout_logs[0]
  data.workout_logs = [
    { ...set, session_id: 's1', exercise_name: 'Treadmill Run · 3 km · 2° · 20 min', weight_kg: null, reps: null },
    { ...set, session_id: 's2', exercise_name: 'Treadmill Run · 5 km · 1° · 30 min', weight_kg: null, reps: null },
  ]
  const history = buildRankedExerciseHistory(data)
  assert.deepEqual(history.map((item) => [item.name, item.sessionCount, item.points.length]), [['Treadmill Run', 2, 0]])
})

test('substitute catalog IDs keep different equipment in distinct load curves', () => {
  const data = strengthData()
  const set = data.workout_logs[0]
  data.workout_logs = [
    { ...set, exercise_name: 'Dumbbell Curl', movement_id: 'dumbbell_curl', weight_kg: 12 },
    { ...set, exercise_name: 'Barbell Curl', movement_id: 'dumbbell_curl', weight_kg: 35, session_id: 's2' },
    { ...set, exercise_name: 'Cable Hip Adduction', movement_id: 'hip_adduction', weight_kg: 10 },
    { ...set, exercise_name: 'Hip Adduction Machine', movement_id: 'hip_adduction', weight_kg: 50, session_id: 's2' },
  ]
  assert.deepEqual(buildStrengthSeries(data).map(({ name, points }) => [name, points.map((point) => point.topWeight)]), [
    ['Barbell Curl', [35]], ['Hip Adduction Machine', [50]], ['Cable Hip Adduction', [10]], ['Dumbbell Curl', [12]],
  ])
})
