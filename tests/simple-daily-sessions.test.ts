import assert from 'node:assert/strict'
import test from 'node:test'
import { buildSeedData } from '../src/data/seed.ts'
import { programDaysForDate } from '../src/lib/plan.ts'
import { dailyGuidedSessions, guidedPlayerDraftKey, guidedPlayerDraftMatches } from '../src/lib/dailyGuidedSessions.ts'
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
