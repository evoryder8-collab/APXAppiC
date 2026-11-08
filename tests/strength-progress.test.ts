import test from 'node:test'
import assert from 'node:assert/strict'
import { assessJointCheckin, buildExerciseFamilies, buildStrengthSeries, checkinDue, distinctInsightTexts, sessionStrengthInsights, totalRecordedWork } from '../src/lib/strengthProgress.ts'
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
  ].map((log, index) => ({ ...log, id: 'set-' + index }))
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
  ].map((log, index) => ({ ...log, id: 'set-' + index }))
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
  ].map((log, index) => ({ ...log, id: 'set-' + index }))
  assert.deepEqual(buildStrengthSeries(data).map(({ name, points }) => [name, points.map((point) => point.topWeight)]), [
    ['Barbell Curl', [35]], ['Dumbbell Curl', [12]], ['Hip Adduction Machine', [50]], ['Cable Hip Adduction', [10]],
  ])
})

test('June’s exercise families count distinct receipts across aliases and morning/evening workouts on one date', () => {
  const data = strengthData()
  const set = data.workout_logs[0]
  data.workout_sessions = ['morning','evening','other'].map((id, index) => ({
    ...data.workout_sessions[0], id, date: index === 2 ? '2026-07-15' : '2026-07-14',
    started_at: index === 0 ? '2026-07-14T08:00:00Z' : index === 1 ? '2026-07-14T18:00:00Z' : '2026-07-15T08:00:00Z',
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
  ].map((log, index) => ({ ...log, id: 'set-' + index }))
  const families = buildExerciseFamilies(data)
  assert.deepEqual(families.slice(0,2).map(f => [f.key,f.region,f.sessionCount,f.variants.length]), [
    ['family:hip_thrust','lower',3,2], ['family:push_up','upper',2,3],
  ])
  assert.deepEqual(families[0].variants.map(v => [v.name, v.points.map(p => p.topWeight)]), [
    ['B-Stance or Single-Leg Hip Thrust', [10,12]],
    ['Dumbbell Hip Thrust', [24,22]],
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

test('lifetime work sums actual external kg × measured reps from each eligible set once', () => {
  const data = strengthData()
  const set = data.workout_logs[0]
  const lift = (name: string, movement_id: string | null, reps: number | null, weight_kg: number | null) =>
    ({ ...set, exercise_name: name, movement_id, reps, weight_kg })
  data.workout_logs = [
    lift('Dumbbell Hip Thrust','hip_thrust_dumbbell',8,50),
    { ...lift('Dumbbell Hip Thrust','hip_thrust_dumbbell',5,60), set_no: 2 },
    lift('Weighted Dumbbell Hip Thrust',null,4,null),
    lift('Weighted Dumbbell Hip Thrust',null,null,20),
    lift('B-Stance or Single-Leg Hip Thrust','b_stance_hip_thrust',6,30),
    { ...lift('Dumbbell Hip Thrust','hip_thrust_dumbbell',8,150), skipped:true },
    { ...lift('Dumbbell Hip Thrust','hip_thrust_dumbbell',8,150), user_id:'foreign' },
    lift('Push-Up','push_up',10,0),
    lift('Weighted Push-Up','weighted_push_up',6,10),
    lift('Weighted or Feet-Elevated Push-Up',null,8,20),
    lift('Pull-Up','pull_up',8,-20),
    lift('Band-Assisted Pull-Up','band_assisted_pull_up',6,30),
    lift('Assisted Pull-Up Machine','assisted_pull_up_machine',10,40),
    lift('Band Row','band_row',12,30),
    { ...lift('Treadmill Run',null,180,80), duration_seconds:180, distance_meters:500 },
    lift('Wrist Roller','wrist_roller',3,10),
  ].map((log, index) => ({ ...log, id: 'set-' + index }))
  data.workout_logs.push({ ...data.workout_logs[0] })
  const families = buildExerciseFamilies(data)
  const hip = families.find(f => f.name === 'Hip Thrust')!
  assert.equal(hip.sessionCount,1)
  assert.deepEqual(hip.work,{sets:5, recordedReps:23, liftedKg:880, loadedReps:19, missingReps:true, missingVolume:true})
  assert.deepEqual(hip.variants.find(v => v.name === 'Dumbbell Hip Thrust')?.work,
    {sets:4, recordedReps:17, liftedKg:700, loadedReps:13, missingReps:true, missingVolume:true})
  const unilateral = hip.variants.find(v => v.name.startsWith('B-Stance'))!
  assert.equal(unilateral.work.liftedKg,180)
  assert.deepEqual(unilateral.points.map(p => p.topWeight),[30])
  assert.deepEqual(families.find(f => f.name === 'Push-Up')?.work,
    {sets:3, recordedReps:24, liftedKg:60, loadedReps:6, missingReps:false, missingVolume:false})
  assert.deepEqual(families.find(f => f.name === 'Pull-Up')?.work,
    {sets:3, recordedReps:24, liftedKg:null, loadedReps:0, missingReps:false, missingVolume:false})
  assert.equal(families.find(f => f.name === 'Row')?.work.recordedReps,12)
  assert.equal(families.find(f => f.name === 'Row')?.work.liftedKg,null)
  for (const name of ['Treadmill Run','Wrist Roller']) {
    assert.equal(families.find(f => f.name === name)?.work.recordedReps,null)
    assert.equal(families.find(f => f.name === name)?.work.liftedKg,null)
  }
  assert.deepEqual(totalRecordedWork(families), {
    sets: 14, recordedReps: 83, liftedKg: 940, loadedReps: 25, missingReps: true, missingVolume: true,
  })
})

test('family charts aggregate variations per completed session and keep same-day workouts separate', () => {
  const data = strengthData()
  data.workout_sessions = ['pm', 'am'].map(id => ({
    ...data.workout_sessions[0], id, started_at: '2026-04-15T' + (id === 'am' ? '06' : '18') + ':00:00Z',
  }))
  const exercise = progressionData(2).exercise
  data.exercises = [{ ...exercise, id: 'bulgarian', name: 'Bulgarian Split Squats', per_side: true }]
  const set = data.workout_logs[0]
  data.workout_logs = [
    { ...set, session_id:'pm', exercise_name:'Strict Push-Up', reps:9, weight_kg:null },
    { ...set, session_id:'am', exercise_name:'Strict Push-Up', reps:12, weight_kg:null },
    { ...set, session_id:'am', exercise_name:'Hindu Push-Up', movement_id:'hindu_push_up', reps:6, weight_kg:null },
    { ...set, session_id:'am', exercise_name:'Bulgarian Split Squats', exercise_id:'bulgarian', reps:8, weight_kg:14 },
    { ...set, session_id:'am', exercise_name:'Walking Lunges', reps:10, weight_kg:7 },
    { ...set, session_id:'pm', exercise_name:'Bulgarian Split Squats', exercise_id:'bulgarian', reps:null, weight_kg:15 },
  ].map((log,i) => ({ ...log, id:'set-' + i }))
  const history = buildExerciseFamilies(data)
  const pushUp = history.find(family => family.name === 'Push-Up')!
  assert.deepEqual(pushUp.sessions.map(s => [s.sessionId,s.work.recordedReps]), [['am',18],['pm',9]])
  const splitSquat = history.find(family => family.name === 'Split Squat')!
  assert.deepEqual(splitSquat.sessions.map(s => [s.work.liftedKg,s.work.missingVolume]), [[112,false],[null,true]])
  assert.equal(history.find(family => family.name === 'Lunge')?.work.liftedKg,70)
  assert.equal(totalRecordedWork(history).liftedKg,182)
})

test('legacy holds, checkmarks and timed prescriptions count as sets without contributing reps or load', () => {
  const data = strengthData()
  const exercise = progressionData(2).exercise
  data.exercises = [
    { ...exercise, id:'side', name:'Side Plank', rep_unit:'seconds' },
    { ...exercise, id:'new', name:'Cable hold practice', rep_unit:'seconds' },
    { ...exercise, id:'foreign', name:'Cable hold practice', user_id:'foreign', rep_unit:'reps' },
  ]
  const set = data.workout_logs[0]
  data.workout_logs = [
    ...Array.from({length:4}, () => ({ ...set, exercise_id:null, exercise_name:'Dead Hang', reps:30 })),
    ...Array.from({length:2}, () => ({ ...set, exercise_id:'side', exercise_name:'Side Plank', reps:25 })),
    { ...set, exercise_id:'deleted', exercise_name:'Cable hold practice', reps:12 },
    { ...set, exercise_id:null, exercise_name:'Focus T25 · Stretch', reps:1 },
    { ...set, exercise_id:null, exercise_name:'FocusT25 session (Shaun T), Alpha or Beta cycle', reps:25 },
    { ...set, exercise_id:null, exercise_name:'Dead Hang', reps:999, duration_seconds:0 },
    { ...set, exercise_id:null, exercise_name:'Dead Hang', reps:null, duration_seconds:15 },
    { ...set, exercise_id:null, exercise_name:'Dead Hang', reps:35, skipped:true },
    { ...set, exercise_id:null, exercise_name:'Custom set', reps:8, weight_kg:10 },
  ].map((log,i) => ({ ...log, id:'set-' + i }))
  const families = buildExerciseFamilies(data)
  assert.equal(families.find(f => f.name === 'Dead Hang')?.work.sets,5)
  assert.equal(families.find(f => f.name === 'Side Plank')?.work.sets,2)
  assert.equal(families.find(f => f.name === 'Cable hold practice')?.work.recordedReps,null)
  assert.deepEqual(totalRecordedWork(families), {
    sets:11, recordedReps:8, liftedKg:80, loadedReps:8, missingReps:false, missingVolume:false,
  })
})

test('training profile compares equal-rep session peaks across inclusive halves and ignores skipped, future and timed reps', async () => {
  const { trainingProfile,trainingProfileLines,athleteTitle } = await import('../src/lib/trainingProfile.ts')
  const data = strengthData()
  data.workout_sessions = ['2026-08-11','2026-09-01','2026-10-01','2026-11-08','2026-08-10','2026-11-09'].map((date,i) =>
    ({...data.workout_sessions[0], id: 's'+i, date}))
  const set = data.workout_logs[0]
  data.workout_logs = [[0,8,40],[0,8,50],[1,8,60],[2,8,60],[2,6,90],[3,8,70],[4,8,100],[5,8,100]].map(([i,reps,weight],idx)=>
    ({...set,id:'w'+idx,exercise_name:'Dumbbell Hip Thrust',movement_id:'hip_thrust_dumbbell',session_id:'s'+i,reps,weight_kg:weight}))
  data.workout_logs.push({...data.workout_logs[4]}, {...set,id:'x',session_id:'s2',movement_id:'wrist_roller',reps:400},
    {...set,id:'y',session_id:'s1',skipped:true,weight_kg:1000})
  const result = trainingProfile(data,[],'2026-11-08')
  const scoped = trainingProfile(data, [], '2026-10-01', '2026-09-01')
  assert.equal(scoped.workouts,2)
  assert.deepEqual(scoped.period,{ from:'2026-09-01', split:'2026-09-16', to:'2026-10-01', days:31 })
  const scopedLines = trainingProfileLines(scoped,'en',s=>s).join(' ')
  assert.match(scopedLines,/Earlier period · 2026-09-01 – 2026-09-15/)
  assert.match(scopedLines,/Later period · 2026-09-16 – 2026-10-01/)
  assert.equal(result.focus,'Resistance-focused')
  assert.equal(athleteTitle(result), 'Strength athlete')
  assert.equal(athleteTitle({ ...result, muscleGrowthGoal: true }), 'Bodybuilder')
  assert.equal(athleteTitle({ ...result, focus: 'Mixed training', muscleGrowthGoal: true }), 'All-rounder')
  assert.equal(result.workouts,4)
  assert.equal(result.medianReps,11)
  assert.deepEqual(result.comparison,{name:'Dumbbell Hip Thrust',reps:8,previous:55,recent:65})
  assert.match(trainingProfileLines(result,'en',s=>s).join(' '),/Workouts per week 0.3/)
})

test('training profile deduplicates Health and Orbit, skips unknown and hidden copies, and counts mixed receipts once', async () => {
  const { trainingProfile } = await import('../src/lib/trainingProfile.ts')
  const data = strengthData()
  data.workout_sessions = [{...data.workout_sessions[0],id:'s',date:'2026-11-06'}]
  data.workout_logs = [{...data.workout_logs[0],session_id:'s',exercise_name:'Weighted Dumbbell Hip Thrust',weight_kg:null}]
  const imported = { user_id:'u',source:'Watch',kind:'endurance' as const,activity:'Running',date:'2026-11-06',duration_min:20 }
  data.imported_activities = [
    {...imported,id:'1',healthkit_workout_id:'hk-1',apex_workout_session_id:'s',started_at:'2026-11-06T09:00:00Z'},
    {...imported,id:'2',healthkit_workout_id:'hk-1'},
    {...imported,id:'3',healthkit_workout_id:'hk-3',hidden_at:'2026-11-06'},
    {...imported,id:'4',healthkit_workout_id:'hk-3'},
    {...imported,id:'5',workout_name_key:'health.workout.unknown',activity:'Apple Health Workout',kind:'mobility'},
    {...imported,id:'6',apex_workout_session_id:'missing'},
    {...imported,id:'7',user_id:'someone-else'},
    {...imported,id:'8',source_bundle_id:'ch.apexperformance.APEX'},
  ]
  const orbit = (id:string,date:string,time:string) => ({
    id,user_id:'u',client_idempotency_key:id,local_date:date,started_at:date+'T'+time+':00Z',ended_at:date+'T12:00:00Z',
    metrics:{distance_m:3300},status:'completed' as const,
  })
  const runs = [orbit('duplicate','2026-11-06','09:01'),orbit('second','2026-11-07','10:00'),orbit('third','2026-11-08','10:00')]
  const result = trainingProfile(data,runs,'2026-11-08')
  assert.deepEqual(result.counts,{Resistance:1,Cardio:3,Mobility:0})
  assert.equal(result.workouts,3)
  assert.equal(result.focus,'Running-focused')
  assert.equal(trainingProfile(data,[],'2026-11-08').focus,'Limited history')
})
