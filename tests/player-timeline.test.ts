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
    warmup: 'Warm up', badges: [], isDeload: false, isEventDay: false, isRecoveryMicro: false, taperFactor: 1, legsBlocked: false, layoffDeload: false,
  }
  const rests = buildTimeline(plan).filter((block) => block.kind === 'rest')
  assert.deepEqual(rests.filter((block) => block.captureLoad).map((block) => [block.exIdx, block.afterSet]), [[0, 1], [0, 2], [1, 1], [1, 2]])
  assert.equal(rests.find((block) => block.exIdx === 0 && block.afterSet === 3)?.captureLoad, false)
})

test('bodyweight exercises do not ask for a meaningless kilogram entry', () => {
  const plan: PlannedDay = {
    programDay: null,
    exercises: [exercise({ increment_kg: 0, name: 'Push-ups' })],
    warmup: 'Warm up', badges: [], isDeload: false, isEventDay: false, isRecoveryMicro: false, taperFactor: 1, legsBlocked: false, layoffDeload: false,
  }
  const rests = buildTimeline(plan).filter((block) => block.kind === 'rest')
  assert.ok(rests.every((block) => !block.captureLoad))
})
