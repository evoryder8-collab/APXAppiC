import assert from 'node:assert/strict'
import test from 'node:test'
import {
  EXERCISE_CATALOG,
  catalogExerciseByName,
  displayExerciseName,
  searchExerciseCatalog,
} from '../src/data/exerciseCatalog.ts'

test('every exercise has Romanian and Thai display names', () => {
  assert.ok(EXERCISE_CATALOG.length >= 80)
  for (const exercise of EXERCISE_CATALOG) {
    assert.ok(displayExerciseName(exercise, 'ro').trim(), `${exercise.id} Romanian name`)
    assert.ok(displayExerciseName(exercise, 'th').trim(), `${exercise.id} Thai name`)
  }
})

test('Romanian partial searches resolve common gym vocabulary', () => {
  assert.ok(searchExerciseCatalog('tra', 'all', 'ro').some((exercise) => exercise.id === 'pull-up'))
  assert.ok(searchExerciseCatalog('fandari', 'all', 'ro').some((exercise) => exercise.id === 'walking-lunge'))
  assert.ok(searchExerciseCatalog('ramat', 'all', 'ro').some((exercise) => exercise.id === 'barbell-row'))
  assert.equal(searchExerciseCatalog('ciocane', 'all', 'ro')[0]?.id, 'hammer-curl')
  assert.deepEqual(
    searchExerciseCatalog('ban', 'all', 'ro').slice(0, 2).map((exercise) => exercise.id).sort(),
    ['treadmill-run', 'treadmill-walk'],
  )
})

test('Thai search and native names resolve to canonical exercises', () => {
  assert.ok(searchExerciseCatalog('ลู่วิ่ง', 'all', 'th').some((exercise) => exercise.id === 'treadmill-run'))
  assert.equal(catalogExerciseByName('เดินบนลู่วิ่ง')?.id, 'treadmill-walk')
  assert.equal(catalogExerciseByName('Tracțiuni la bară')?.id, 'pull-up')
})
