import test from 'node:test'
import assert from 'node:assert/strict'
import { buildTimeline } from '../src/lib/playerTimeline.ts'
import type { PlannedDay, PlannedExercise } from '../src/lib/plan.ts'

function exercise(patch: Partial<PlannedExercise> = {}): PlannedExercise {
  return {
    id: 'bench', user_id: 'u', program_day_id: 'd', name: 'Bench Press', sets: 3, planned_sets: 3,
    rep_min: 8, rep_max: 10, rep_unit: 'reps', per_side: false, rest_sec: 90,
    tempo_up_s: 1, tempo_down_s: 2, tempo_pause_s: 0, tempo_note: '', notes: '', increment_kg: 2.5,
    is_lite: false, optional: false, sort_order: 0, swapped: false, ...patch,
  }
}

test('weighted sets request per-set load during rests but not between exercises', () => {
  const plan: PlannedDay = {
    programDay: null,
    exercises: [exercise(), exercise({ id: 'row', name: 'Row' })],
    warmup: 'Warm up', warmupDuration: 180, badges: [], isDeload: false, isEventDay: false, isRecoveryMicro: false, taperFactor: 1, legsBlocked: false, layoffDeload: false,
  }
  const rests = buildTimeline(plan).filter((block) => block.kind === 'rest')
  assert.deepEqual(rests.filter((block) => block.captureLoad).map((block) => [block.exIdx, block.afterSet]), [[0, 1], [0, 2], [1, 1], [1, 2]])
  assert.equal(rests.find((block) => block.exIdx === 0 && block.afterSet === 3)?.captureLoad, false)
  assert.equal(rests.find((block) => block.exIdx === 0 && block.afterSet === 3)?.reviewExercise, true)
  const transitionRestIndex = buildTimeline(plan).findIndex((block) => block.kind === 'rest' && block.exIdx === 0 && block.afterSet === 3)
  assert.ok(transitionRestIndex >= 0)
  assert.notEqual(buildTimeline(plan)[transitionRestIndex - 1]?.kind, 'log')
})

test('bodyweight exercises do not ask for a meaningless kilogram entry', () => {
  const plan: PlannedDay = {
    programDay: null,
    exercises: [exercise({ increment_kg: 0, name: 'Push-ups' })],
    warmup: 'Warm up', warmupDuration: 180, badges: [], isDeload: false, isEventDay: false, isRecoveryMicro: false, taperFactor: 1, legsBlocked: false, layoffDeload: false,
  }
  const rests = buildTimeline(plan).filter((block) => block.kind === 'rest')
  assert.ok(rests.every((block) => !block.captureLoad))
})

test('every single-sided exercise gets a leg-change block sized to the movement', () => {
  const plan: PlannedDay = {
    programDay: null,
    exercises: [exercise({ name: 'Bulgarian Split Squat', planned_sets: 1, sets: 1, per_side: true })],
    warmup: '', warmupDuration: 0, badges: [], isDeload: false, isEventDay: false, isRecoveryMicro: false, taperFactor: 1, legsBlocked: false, layoffDeload: false,
  }
  const timeline = buildTimeline(plan)
  const left = timeline.findIndex((block) => block.kind === 'set' && block.side === 'left')
  assert.equal(timeline[left + 1]?.kind, 'side_switch')
  const duration = timeline[left + 1]?.kind === 'side_switch' ? timeline[left + 1].duration : 0
  // Three seconds was the old fixed guess for every switch. Resetting a rear
  // foot on a bench takes longer than that on its own, and a split squat also
  // leaves most people needing a breath before the second leg is worth
  // training at all.
  assert.ok(duration >= 20, `a split squat leg change was given ${duration}s`)
  assert.equal(timeline[left + 2]?.kind === 'set' ? timeline[left + 2].side : null, 'right')

  // The block used to fire only for exercises whose name matched a regex for
  // split squats, so every other single-sided movement had no switch at all.
  const rowPlan: PlannedDay = {
    ...plan,
    exercises: [exercise({ name: 'One-Arm Dumbbell Row', planned_sets: 1, sets: 1, per_side: true })],
  }
  const rowTimeline = buildTimeline(rowPlan)
  const rowLeft = rowTimeline.findIndex((block) => block.kind === 'set' && block.side === 'left')
  assert.equal(rowTimeline[rowLeft + 1]?.kind, 'side_switch',
    'a single-arm row sent the follower straight from one side to the other')
})
