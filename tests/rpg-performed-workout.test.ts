import assert from 'node:assert/strict'
import test from 'node:test'
import { computeEngine } from '../src/lib/rpg.ts'
import { EMPTY_DATA, type AppData, type WorkoutLog, type WorkoutSession } from '../src/lib/types.ts'

const owner = '77777777-aaaa-4bbb-8ccc-777777777777'
const date = '2026-11-02'
const baseline: AppData = {
  ...EMPTY_DATA,
  profile: {
    id: 'profile', user_id: owner, persona: 'constantine', display_name: 'Audit',
    sex: 'male', weight_kg: 80, body_fat_pct: 15, custom_bmr: null, height_cm: 180,
    birthdate: '1990-01-01', activity_level: 'moderate', goal: 'maintain',
    target_kcal: null, target_protein_g: null, target_fat_g: null, target_carbs_g: null,
    training_time: '18:00', baseline_date: '2026-11-01', profile_note: '', seed_version: 1,
    calibration_k: 1, calibration_history: [], updated_at: `${date}T00:00:00Z`,
  },
}

function session(changes: Partial<WorkoutSession> = {}): WorkoutSession {
  return {
    id: 'session', user_id: owner, date, program_day_id: 'custom-day', is_lite: false,
    is_deload: false, is_event_recovery: false, completed: true, quality_score: 1,
    started_at: `${date}T10:00:00Z`, completed_at: `${date}T10:45:00Z`, notes: '', ...changes,
  }
}

function log(changes: Partial<WorkoutLog> = {}): WorkoutLog {
  return {
    id: 'log', user_id: owner, session_id: 'session', exercise_id: null,
    exercise_name: 'Barbell Back Squat', movement_id: 'barbell_back_squat',
    set_no: 1, weight_kg: 80, reps: 10, rir: 2, skipped: false, override_flag: false,
    created_at: `${date}T10:00:00Z`, ...changes,
  }
}

function custom(logs = [log()], sessions = [session()]): AppData {
  return {
    ...baseline,
    program_days: [{
      id: 'custom-day', user_id: owner, program_id: 'custom-program', weekday: 1,
      day_type: 'custom', title: 'Quick Log', estimated_minutes: 45, sort_order: 0,
    }],
    workout_sessions: sessions, workout_logs: logs,
  }
}

function latest(data: AppData, throughDate = date) {
  return computeEngine(data, throughDate).snapshots.at(-1)!
}

test('Quick Log attributes saved squat, push-up, mobility and cardio to their own domains', () => {
  const before = latest(baseline)
  const cases: Array<[Partial<WorkoutLog>, keyof typeof before, number]> = [
    [{}, 'strength_lower', 44],
    [{ movement_id: 'push_up', weight_kg: 0 }, 'strength_upper', 60.9],
    [{ movement_id: 'cat_cow', reps: null, duration_seconds: 120 }, 'flexibility', 41.8],
    [{ movement_id: 'run_outdoor', reps: null, duration_seconds: 1800, distance_meters: 5000 }, 'endurance', 46.9],
  ]
  for (const [facts, domain, expected] of cases) {
    const result = latest(custom([log(facts)]))
    assert.equal(result[domain], expected, `${facts.movement_id ?? 'squat'} credit`)
    for (const other of ['strength_lower', 'strength_upper', 'endurance', 'flexibility'] as const) {
      if (other !== domain) assert.equal(result[other], before[other], `${domain} must not feed ${other}`)
    }
  }
})

test('unknown, skipped, zero-effort, incomplete, foreign and future Quick Logs give no credit', () => {
  const empty = latest(baseline)
  for (const changes of [
    { movement_id: 'unknown' }, { movement_id: null }, { skipped: true }, { reps: 0 },
    { reps: null }, { user_id: 'other' }, { session_id: 'orphan' },
  ]) assert.deepEqual(latest(custom([log(changes)])), empty)
  for (const changes of [
    { completed: false }, { user_id: 'other' }, { date: '2026-11-03' },
  ]) assert.deepEqual(latest(custom([log()], [session(changes)])), empty)
  const backdated = custom([log()], [session({ date: '2026-11-01' })])
  assert.ok(latest(backdated, '2026-11-01').strength_lower > latest(baseline, '2026-11-01').strength_lower)
})

test('repeated sets and sessions cannot multiply a Quick Log domain or an existing planned-day credit', () => {
  const once = custom()
  const repeated = custom(
    [log(), log({ id: 'set2', set_no: 2 }), log({ id: 'other', session_id: 'other' })],
    [session(), session({ id: 'other' })],
  )
  assert.deepEqual(latest(repeated), latest(once))
  const plan = {
    ...once,
    program_days: [...once.program_days, { ...once.program_days[0], id: 'leg-day', day_type: 'legs_a' as const }],
    workout_sessions: [session({ id: 'planned', program_day_id: 'leg-day' })],
    workout_logs: [],
  }
  assert.deepEqual(latest({ ...plan, workout_sessions: [...plan.workout_sessions, session()], workout_logs: [log()] }), latest(plan))
})

test('editing or deleting the Quick Log replays its domain, and linked wearable effort adds no second credit', () => {
  const lower = custom()
  const upper = custom([log({ movement_id: 'push_up' })])
  assert.equal(latest(upper).strength_lower, latest(baseline).strength_lower)
  assert.ok(latest(upper).strength_upper > latest(lower).strength_upper)
  assert.deepEqual(latest({ ...lower, workout_sessions: [], workout_logs: [] }), latest(baseline))
  assert.deepEqual(latest({ ...lower, imported_activities: [{
    id: 'wearable', user_id: owner, date, kind: 'strength', activity: 'Strength Training',
    duration_min: 45, source: 'Apple Watch', apex_workout_session_id: 'session',
  }] }), latest(lower))
})

test('planned receipts with only skipped or empty attempts cannot earn completed-work credit', () => {
  const plan = custom()
  plan.program_days[0] = { ...plan.program_days[0], day_type: 'legs_a' }
  for (const [facts, quality] of [
    [{ skipped: true }, 1],
    [{ reps: 0 }, 0],
    [{ reps: null, weight_kg: null }, 1],
    [{ reps: 10 }, 0],
  ] as Array<[Partial<WorkoutLog>, number]>) {
    const result = { ...plan, workout_sessions: [session({ quality_score: quality })], workout_logs: [log(facts)] }
    assert.deepEqual(latest(result), latest(baseline))
  }
})

test('known mobility completion-only logs retain bounded credit without invented measurements', () => {
  const completion = log({ movement_id: 'cat_cow', reps: null, weight_kg: null })
  const customReceipt = custom([completion])
  const timedReceipt = custom([{ ...completion, duration_seconds: 120 }])
  assert.deepEqual(latest(customReceipt), latest(timedReceipt))
  const mobilityDay = { ...customReceipt, program_days: [{ ...customReceipt.program_days[0], day_type: 'mobility' as const }] }
  assert.deepEqual(latest(mobilityDay), latest(timedReceipt))
  assert.equal(completion.duration_seconds, undefined)
  assert.equal(completion.reps, null)
})

test('legacy no-log completions and explicit external confirmations keep planned-session credit', () => {
  const plan = custom()
  plan.program_days[0] = { ...plan.program_days[0], day_type: 'legs_a' }
  const expected = latest(plan)
  assert.deepEqual(latest({ ...plan, workout_sessions: [session({ quality_score: 0 })], workout_logs: [] }), expected)
  for (const notes of ['Completed externally from the APEX guided player', 'Completed externally from the FITR MAX guided player']) {
    assert.deepEqual(latest({
      ...plan,
      workout_sessions: [session({ notes, quality_score: 0 })],
      workout_logs: [log({ skipped: true })],
    }), expected)
  }
})

test('unfinished or skipped overrides and heavier sets do not alter the fitness index', () => {
  const planned = custom()
  planned.program_days[0] = { ...planned.program_days[0], day_type: 'legs_a' }
  planned.exercises = [{ id: 'exercise', user_id: owner, program_day_id: 'custom-day' } as AppData['exercises'][number]]
  planned.workout_logs = [log({ exercise_id: 'exercise', weight_kg: 60 })]
  planned.workout_sessions = [session({ date: '2026-11-01' })]
  const pending = session({ id: 'pending', completed: false })
  const pendingLog = log({ id: 'pending', session_id: 'pending', exercise_id: 'exercise', weight_kg: 100, override_flag: true })
  assert.deepEqual(latest({ ...planned, workout_sessions: [...planned.workout_sessions, pending], workout_logs: [...planned.workout_logs, pendingLog] }), latest(planned))
  assert.deepEqual(latest({ ...baseline, workout_sessions: [session()], workout_logs: [log({ skipped: true, override_flag: true })] }), latest(baseline))
  const unmapped = {
    ...planned,
    exercises: [{ ...planned.exercises[0], program_day_id: 'unknown-day' }],
    workout_sessions: [...planned.workout_sessions, { ...pending, completed: true }],
  }
  const unmappedLog = { ...pendingLog, override_flag: false }
  assert.deepEqual(
    latest({ ...unmapped, workout_logs: [...planned.workout_logs, unmappedLog] }),
    latest({ ...unmapped, workout_logs: [...planned.workout_logs, { ...unmappedLog, weight_kg: 60 }] }),
  )
})
