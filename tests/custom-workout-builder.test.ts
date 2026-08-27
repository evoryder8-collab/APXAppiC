import assert from 'node:assert/strict'
import test from 'node:test'

import {
  customWorkoutGroupAssignments,
  customWorkoutTargetLabel,
  moveCustomWorkoutSelection,
  removeCustomWorkoutSelection,
  type CustomWorkoutSelection,
} from '../src/lib/customWorkout.ts'

function selection(id: string, linkedToNext = false): CustomWorkoutSelection {
  return { id, sets: 3, target: 10, rest: 60, linkedToNext }
}

test('custom workout targets name distance and time honestly', () => {
  assert.equal(customWorkoutTargetLabel('reps'), 'Repetitions')
  assert.equal(customWorkoutTargetLabel('seconds'), 'Seconds')
  assert.equal(customWorkoutTargetLabel('minutes'), 'Minutes')
  assert.equal(customWorkoutTargetLabel('metres'), 'Distance (m)')
  assert.equal(customWorkoutTargetLabel('steps'), 'Steps')
  assert.equal(customWorkoutTargetLabel('rounds'), 'Rounds')
})

test('custom movements reorder without losing their prescriptions', () => {
  const moved = moveCustomWorkoutSelection([
    selection('first'),
    { ...selection('second'), target: 12, rest: 75 },
    { ...selection('third'), sets: 2, target: 40, rest: 90 },
  ], 2, -1)

  assert.deepEqual(moved.map(({ id, sets, target, rest }) => ({ id, sets, target, rest })), [
    { id: 'first', sets: 3, target: 10, rest: 60 },
    { id: 'third', sets: 2, target: 40, rest: 90 },
    { id: 'second', sets: 3, target: 12, rest: 75 },
  ])
  assert.equal(moveCustomWorkoutSelection(moved, 0, -1), moved)
})

test('adjacent links become one reusable round group and leave other rows independent', () => {
  const assignments = customWorkoutGroupAssignments([
    selection('first', true),
    selection('second'),
    selection('third'),
  ], () => 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee')

  assert.deepEqual(assignments, [
    { workGroupId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', workGroupPosition: 1, label: 'A1' },
    { workGroupId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', workGroupPosition: 2, label: 'A2' },
    { workGroupId: null, workGroupPosition: null, label: null },
  ])
})

test('removing a grouped row never silently links its former neighbours', () => {
  const remaining = removeCustomWorkoutSelection([
    selection('first', true),
    selection('second', true),
    selection('third'),
  ], 'second')

  assert.deepEqual(remaining.map(({ id, linkedToNext }) => ({ id, linkedToNext })), [
    { id: 'first', linkedToNext: false },
    { id: 'third', linkedToNext: false },
  ])
})
