import assert from 'node:assert/strict'
import test from 'node:test'
import { buildSeedData } from '../src/data/seed.ts'
import { programDaysForDate } from '../src/lib/plan.ts'
import { dailyGuidedSessions, guidedPlayerDraftKey, guidedPlayerDraftMatches } from '../src/lib/dailyGuidedSessions.ts'
import * as dailySessionModel from '../src/lib/dailyGuidedSessions.ts'
import type { WorkoutSession } from '../src/lib/types.ts'

const owner = '10000000-0000-4000-8000-000000000085'
const date = '2026-11-04'
const data = buildSeedData(owner, 'constantine')
const plans = programDaysForDate(data, 'main', date)
const receipt = (dayID: string, patch: Partial<WorkoutSession> = {}): WorkoutSession => ({
  id: crypto.randomUUID(), user_id: owner, date, program_day_id: dayID,
  is_lite: false, is_deload: false, is_event_recovery: false, completed: true,
  quality_score: 1, started_at: `${date}T07:00:00Z`, completed_at: `${date}T07:30:00Z`, notes: '', ...patch,
})

test('Simple shows every active daily prescription and completing morning does not complete official work', () => {
  assert.equal(plans.length, 3)
  const morning = plans[0].programDay!.id
  const official = plans[1].programDay!.id
  const cardio = plans[2].programDay!.id
  const morningReceipt = receipt(morning)
  const sessions = [morningReceipt, receipt(official, { date: '2026-11-01' }),
    receipt(official, { user_id: 'another-owner' }), receipt(cardio, { completed: false }),
    receipt(data.program_days.find((day) => day.program_id !== plans[0].programDay!.program_id)!.id)]
  const rows = dailyGuidedSessions(plans, sessions, owner, date, new Map([[cardio, true]]))
  assert.deepEqual(rows.map((row) => row.plan.programDay!.name), plans.map((plan) => plan.programDay!.name))
  assert.deepEqual(rows.map((row) => row.status), ['Completed', 'Start', 'Continue'])
  assert.equal(rows[0].completedSessionID, morningReceipt.id)
  assert.equal(rows[2].resumeLite, true)
  assert.equal(rows.every((row) => row.status === 'Completed'), false)
  assert.ok(dailyGuidedSessions(plans, plans.map((plan) => receipt(plan.programDay!.id)), owner, date)
    .every((row) => row.status === 'Completed'))
  assert.ok(dailyGuidedSessions(plans, sessions, owner, '2026-11-03').every((row) => row.status === 'Start'))
})

test('daily chooser excludes empty, inactive, duplicate and foreign prescriptions', () => {
  const first = plans[0]
  const foreign = { ...plans[1], programDay: { ...plans[1].programDay!, user_id: 'another-owner' } }
  const inactive = { ...plans[2], programDay: { ...plans[2].programDay!, is_active: false } }
  assert.equal(dailyGuidedSessions([first, first, foreign, inactive, { ...first, exercises: [] }], [], owner, date).length, 1)
  assert.deepEqual(dailyGuidedSessions(plans, [], undefined, date), [])
})

test('Continue restores only the exact owner, day, date, mode and exercise draft', () => {
  const identity = { ownerId: owner, slug: 'main', date, lite: false,
    programDayId: plans[0].programDay!.id, exerciseIds: plans[0].exercises.map((exercise) => exercise.id) }
  const draft = { ...identity, idx: 1, elapsed: 5, paused: true }
  assert.ok(guidedPlayerDraftMatches(draft, identity))
  for (const changed of [{ ownerId: 'another-owner' }, { date: '2026-11-03' },
    { programDayId: plans[1].programDay!.id }, { lite: true }, { exerciseIds: ['changed'] }]) {
    assert.equal(guidedPlayerDraftMatches(draft, { ...identity, ...changed }), false)
  }
  assert.equal(guidedPlayerDraftMatches({ ...draft, ownerId: undefined }, identity), false)
  assert.notEqual(guidedPlayerDraftKey(identity), guidedPlayerDraftKey({ ...identity, ownerId: 'another-owner' }))
  assert.notEqual(guidedPlayerDraftKey(identity), guidedPlayerDraftKey({ ...identity, programDayId: plans[1].programDay!.id }))
})

test('session previews describe the actual adjusted prescription, including every movement and timed or unilateral work', () => {
  assert.equal(typeof dailySessionModel.guidedSessionPreview, 'function', 'Daily session cards need a factual prescription preview')
  const preview = dailySessionModel.guidedSessionPreview(plans[0])
  assert.equal(preview.exerciseCount, 5)
  assert.equal(preview.plannedSets, 25)
  assert.deepEqual(preview.exercises.map((exercise) => exercise.name), plans[0].exercises.map((exercise) => exercise.name))
  assert.equal(preview.exercises[2].prescription, '5 × 8–12 reps · per side')
  assert.equal(dailySessionModel.guidedSessionPreview(plans[1]).exercises[3].prescription, '3 × 30–45 seconds')
  assert.equal(dailySessionModel.guidedSessionPreview(plans[2]).exercises[0].prescription, '1 × 25 minutes')

  const reduced = { ...plans[0], exercises: [{ ...plans[0].exercises[0], planned_sets: 2 }] }
  assert.equal(dailySessionModel.guidedSessionPreview(reduced).plannedSets, 2, 'Use adjusted planned sets, not the original five-set prescription')
  const translated = dailySessionModel.guidedSessionPreview(reduced, (key) => key === 'reps' ? 'repetări' : key)
  assert.equal(translated.exercises[0].prescription, '2 × 6–15 repetări')
})

test('added tracked custom work has its own launch route and unrelated Quick Logs never complete it', async () => {
  const { simpleWorkoutPlans, workoutPlanRoute } = await import('../src/lib/plan.ts')
  const { manualWorkoutNotes, prescriptionDays } = await import('../src/lib/manualWorkout.ts')
  const parent = { id: 'custom-program', user_id: owner, slug: 'custom' as const, name: 'Custom', description: '' }
  const day = { ...plans[0].programDay!, id: 'added-day', program_id: parent.id, day_type: 'custom' as const,
    name: 'Additional work', session_mode: 'tracked' as const }
  const legacy = { ...day, id: 'old-quick-placeholder', name: 'Manual workout' }
  const custom = { ...data, programs: [...data.programs.filter((p) => p.slug !== 'custom'), parent],
    program_days: [...data.program_days, day, legacy],
    exercises: [...data.exercises, { ...plans[0].exercises[0], id: 'added-exercise', program_day_id: day.id }],
    workout_sessions: [receipt(day.id, { notes: manualWorkoutNotes('Quick work') }), receipt(legacy.id, { notes: manualWorkoutNotes('Old Quick Log') })] }
  const combined = simpleWorkoutPlans(custom, 'main', date, false, true)
  assert.deepEqual(combined.map((plan) => plan.programDay?.id), [...plans.map((plan) => plan.programDay!.id), day.id])
  assert.equal(workoutPlanRoute(custom, combined.at(-1)!, 'main', date), `/log/custom/${date}?day=${day.id}`)
  assert.equal(dailyGuidedSessions(combined, custom.workout_sessions, owner, date).at(-1)?.status, 'Start')
  assert.ok(!prescriptionDays(custom).some((row) => row.id === legacy.id))
  assert.equal(simpleWorkoutPlans(custom, 'main', date, false, false).length, plans.length)
})
