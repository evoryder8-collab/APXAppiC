import assert from 'node:assert/strict'
import test from 'node:test'
import {
  EXERCISE_CATALOG,
  catalogExerciseByName,
  displayExerciseName,
  searchExerciseCatalog,
} from '../src/data/exerciseCatalog.ts'
import { UI_TRANSLATIONS } from '../src/lib/translations.ts'

test('every exercise has Romanian and Thai display names', () => {
  assert.ok(EXERCISE_CATALOG.length >= 80)
  for (const exercise of EXERCISE_CATALOG) {
    assert.ok(displayExerciseName(exercise, 'ro').trim(), `${exercise.id} Romanian name`)
    assert.ok(displayExerciseName(exercise, 'th').trim(), `${exercise.id} Thai name`)
  }
})

test('every exercise result subtitle has Romanian and Thai equipment metadata', () => {
  for (const exercise of EXERCISE_CATALOG) {
    assert.ok(UI_TRANSLATIONS[exercise.equipment]?.ro, `${exercise.id} Romanian equipment`)
    assert.ok(UI_TRANSLATIONS[exercise.equipment]?.th, `${exercise.id} Thai equipment`)
  }
  assert.equal(UI_TRANSLATIONS['Leg press']?.ro, 'Presă pentru picioare')
  assert.equal(UI_TRANSLATIONS['Step and dumbbells']?.ro, 'Treaptă și gantere')
  assert.equal(UI_TRANSLATIONS['Leg press']?.th, 'เครื่องเลกเพรส')
  assert.equal(UI_TRANSLATIONS.machine?.ro, 'aparat')
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
  assert.ok(searchExerciseCatalog('gambe', 'all', 'ro').some((exercise) => exercise.id === 'standing-calf-machine'))
  assert.ok(searchExerciseCatalog('gambe', 'all', 'ro').some((exercise) => exercise.id === 'calf-press-leg-press'))
  assert.ok(searchExerciseCatalog('gambe', 'all', 'ro').some((exercise) => exercise.id === 'elevated-calf-raise'))
  assert.ok(searchExerciseCatalog('abdomene', 'all', 'ro').some((exercise) => exercise.id === 'ab-crunch-machine'))
  assert.ok(searchExerciseCatalog('aductori', 'all', 'ro').some((exercise) => exercise.id === 'hip-adduction'))
})

test('exercise discovery tolerates common spelling errors', () => {
  assert.ok(searchExerciseCatalog('gammbe', 'all', 'ro').slice(0, 5).some((exercise) => exercise.id === 'standing-calf-machine'))
  assert.ok(searchExerciseCatalog('abdomeen', 'all', 'ro').some((exercise) => exercise.id === 'ab-crunch-machine'))
  assert.ok(searchExerciseCatalog('adutori', 'all', 'ro').some((exercise) => exercise.id === 'hip-adduction'))
  assert.ok(searchExerciseCatalog('chset', 'all', 'en').some((exercise) => exercise.muscles.includes('chest')))
})

test('Thai search and native names resolve to canonical exercises', () => {
  assert.ok(searchExerciseCatalog('ลู่วิ่ง', 'all', 'th').some((exercise) => exercise.id === 'treadmill-run'))
  assert.equal(catalogExerciseByName('เดินบนลู่วิ่ง')?.id, 'treadmill-walk')
  assert.equal(catalogExerciseByName('Tracțiuni la bară')?.id, 'pull-up')
  assert.ok(searchExerciseCatalog('น่อง', 'all', 'th').some((exercise) => exercise.id === 'standing-calf-machine'))
  assert.ok(searchExerciseCatalog('หน้าท้อง', 'all', 'th').some((exercise) => exercise.id === 'ab-crunch-machine'))
})
