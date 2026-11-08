import test from 'node:test'
import assert from 'node:assert/strict'
import { assessJointCheckin, buildExerciseFamilies, buildStrengthSeries, checkinDue, distinctInsightTexts, sessionStrengthInsights } from '../src/lib/strengthProgress.ts'
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
  const ranked = buildExerciseFamilies(data)
  assert.deepEqual(ranked.map((item) => [item.name, item.sessionCount]), [
    ['Leg Press', 3], ['Row', 2], ['Biceps Curl', 1],
    ['Custom band exercise', 1], ['Dead Hang', 1],
  ])
  const weighted = buildStrengthSeries(data)
  assert.deepEqual(weighted.map((item) => [item.name, item.region, item.points.length]), [
    ['Leg Press', 'lower', 1], ['Machine Row', 'upper', 2], ['Dumbbell Curl', 'upper', 1],
  ])
  assert.deepEqual([weighted[0].points[0].date, weighted[0].points[0].topWeight, weighted[0].points[0].topReps], ['2020-01-01', 60, 8])
  assert.equal(weighted[2].points[0].topWeight, 8)
  assert.deepEqual(buildExerciseFamilies({ ...data, profile: null, settings: null }), [])
})

test('legacy treadmill distances count as one movement and never produce a weight curve', () => {
  const data = strengthData()
  const set = data.workout_logs[0]
  data.workout_logs = [
    { ...set, session_id: 's1', exercise_name: 'Treadmill Run · 3 km · 2° · 20 min', weight_kg: null, reps: null },
    { ...set, session_id: 's2', exercise_name: 'Treadmill Run · 5 km · 1° · 30 min', weight_kg: null, reps: null },
  ]
  const history = buildExerciseFamilies(data)
  assert.deepEqual(history.map((item) => [item.name, item.sessionCount, item.variants[0].points.length]), [['Treadmill Run', 2, 0]])
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
    ['Barbell Curl', [35]], ['Dumbbell Curl', [12]], ['Hip Adduction Machine', [50]], ['Cable Hip Adduction', [10]],
  ])
})

test('June’s exercise families count distinct receipts across aliases and morning/evening workouts on one date', () => {
  const data = strengthData()
  const set = data.workout_logs[0]
  data.workout_sessions = ['morning','evening','other'].map((id, index) => ({
    ...data.workout_sessions[0], id, date: index === 2 ? '2026-07-15' : '2026-07-14',
  }))
  const performed = (name: string, session_id: string, movement_id: string | null, weight_kg: number | null) =>
    ({ ...set, session_id, exercise_name: name, movement_id, weight_kg })
  data.workout_logs = [
    performed('Weighted Dumbbell Hip Thrust','morning',null,24),
    performed('Weighted Dumbbell Hip Thrust','morning',null,24),
    performed('Dumbbell Hip Thrust','evening','hip_thrust_dumbbell',22),
    performed('B-Stance or Single-Leg Hip Thrust','evening','b_stance_hip_thrust',10),
    performed('B-Stance or Single-Leg Hip Thrust','other','b_stance_hip_thrust',12),
    performed('Strict Push-Up','morning','push_up',null),
    performed('Diamond or Close-Grip Push-Up','morning',null,null),
    performed('Weighted or Feet-Elevated Push-Up','evening',null,null),
    performed('Glute Bridge','morning','glute_bridge',null),
    { ...performed('Gimbal Front Hold','morning','plank',null), duration_seconds: 25 },
    { ...performed('Plank','evening','plank',null), duration_seconds: 30 },
    performed('Pike Push-Up','morning','pike_push_up',null),
    performed('Cable Curl + Rope Pressdown','morning','cable_curl',10),
    performed('Cable Curl','evening','cable_curl',12),
  ]
  const families = buildExerciseFamilies(data)
  assert.deepEqual(families.slice(0,2).map(f => [f.key,f.region,f.sessionCount,f.variants.length]), [
    ['family:hip_thrust','lower',3,3], ['family:push_up','upper',2,3],
  ])
  assert.deepEqual(families[0].variants.map(v => [v.name, v.points.map(p => p.topWeight)]), [
    ['B-Stance or Single-Leg Hip Thrust', []],
    ['Dumbbell Hip Thrust', [22]], ['Weighted Dumbbell Hip Thrust', [24]],
  ])
  assert.ok(families.some(f => f.name === 'Glute Bridge'))
  assert.equal(families.find(f => f.name === 'Gimbal Front Hold')?.sessionCount, 1)
  assert.equal(families.find(f => f.name === 'Plank')?.sessionCount, 1)
  assert.ok(families.some(f => f.name === 'Pike Push-Up'))
  assert.ok(families.some(f => f.name === 'Cable Curl + Rope Pressdown'))
  assert.equal(families.find(f => f.name === 'Biceps Curl')?.sessionCount, 1)
})

test('calendar ticks and chart points share the elapsed-day scale, with repeated dates at the same position', async () => {
  const { datedChartAxis } = await import('../src/lib/datedChartAxis.ts')
  const axis = datedChartAxis(['2026-09-01','2026-09-02','2026-09-02','2026-09-11'], 'en')
  assert.deepEqual(axis.positions,[0,0.1,0.1,1])
  assert.deepEqual(axis.ticks.map(t => t.fraction), [0,0.3,0.7,1])
  assert.equal(datedChartAxis(['2026-09-01','2026-09-01'], 'ro').ticks.length,1)
})
