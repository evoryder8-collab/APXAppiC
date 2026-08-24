import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import {
  EXERCISE_CATEGORIES,
  EXERCISE_CATALOG,
  catalogExerciseByName,
  displayExerciseName,
  searchExerciseCatalog,
} from '../src/data/exerciseCatalog.ts'
import { CARDIO_MODALITIES, MOVEMENTS } from '../src/data/movements.ts'
import { UI_TRANSLATIONS } from '../src/lib/translations.ts'

test('the workout studio exposes every canonical movement exactly once', () => {
  const expected = new Set([
    ...MOVEMENTS.map((movement) => movement.id),
    ...CARDIO_MODALITIES.map((modality) => modality.id),
  ])
  const offered = new Set(EXERCISE_CATALOG.map((exercise) => exercise.id))

  assert.equal(EXERCISE_CATALOG.length, 549)
  assert.equal(offered.size, 549)
  assert.deepEqual(offered, expected)
})

test('the workout studio exposes the canonical sport and training filters', () => {
  const offered = new Set(EXERCISE_CATEGORIES.map((category) => category.id))
  for (const category of [
    'hyrox', 'crossfit', 'olympic_weightlifting', 'powerlifting',
    'kettlebell_sport', 'strongman', 'mobility',
  ]) {
    assert.ok(offered.has(category as never), `${category} is missing from the workout studio`)
  }

  const expectedCounts = {
    hyrox: 8,
    crossfit: 40,
    olympic_weightlifting: 7,
    powerlifting: 4,
    kettlebell_sport: 6,
    strongman: 9,
    mobility: 54,
  }
  for (const [category, count] of Object.entries(expectedCounts)) {
    assert.equal(searchExerciseCatalog('', category as never).length, count, category)
  }

  assert.deepEqual(
    searchExerciseCatalog('', 'hyrox' as never).map((exercise) => exercise.id),
    [
      'ski_erg', 'sled_push', 'sled_pull', 'burpee_broad_jump',
      'row_erg', 'kettlebell_farmers_walk', 'sandbag_lunge', 'wall_ball',
    ],
    'the HYROX shelf follows the official station order from SkiErg to Wall Balls',
  )
  assert.deepEqual(
    new Set(searchExerciseCatalog('', 'olympic_weightlifting' as never).map((exercise) => exercise.id)),
    new Set([
      'power_clean', 'power_snatch', 'clean_and_jerk',
      'snatch_grip_romanian_deadlift', 'barbell_split_jerk',
      'barbell_push_jerk', 'barbell_power_jerk',
    ]),
  )
  assert.deepEqual(
    new Set(searchExerciseCatalog('', 'powerlifting' as never).map((exercise) => exercise.id)),
    new Set(['barbell_back_squat', 'barbell_bench_press', 'conventional_deadlift', 'barbell_rack_pull']),
  )
})

test('workout pickers do not silently truncate the canonical library', () => {
  const webBuilder = readFileSync('src/components/CustomWorkoutBuilder.tsx', 'utf8')
  const nativeBuilder = readFileSync('ios/APEXNative/APEX/Features/Training/CustomWorkoutBuilder.swift', 'utf8')
  const nativeManual = readFileSync('ios/APEXNative/APEX/Features/Training/ManualWorkoutLoggerView.swift', 'utf8')

  assert.doesNotMatch(webBuilder, /searchExerciseCatalog\([^\n]+\.slice\(/)
  assert.doesNotMatch(nativeBuilder, /results\.prefix\(/)
  assert.doesNotMatch(nativeManual, /ExerciseCatalog\.search\([^\n]+\.prefix\(/)
})

test('every exercise has Romanian and Thai display names', () => {
  assert.ok(EXERCISE_CATALOG.length >= 80)
  for (const exercise of EXERCISE_CATALOG) {
    assert.ok(displayExerciseName(exercise, 'ro').trim(), `${exercise.id} Romanian name`)
    assert.ok(displayExerciseName(exercise, 'th').trim(), `${exercise.id} Thai name`)
  }
})

test('every exercise result subtitle has readable equipment metadata', () => {
  for (const exercise of EXERCISE_CATALOG) {
    assert.ok(exercise.equipment.trim(), `${exercise.id} equipment`)
    assert.doesNotMatch(exercise.equipment, /_/, `${exercise.id} exposes a storage key`)
  }
  assert.equal(UI_TRANSLATIONS['Leg press']?.ro, 'Presă pentru picioare')
  assert.equal(UI_TRANSLATIONS['Step and dumbbells']?.ro, 'Treaptă și gantere')
  assert.equal(UI_TRANSLATIONS['Leg press']?.th, 'เครื่องเลกเพรส')
  assert.equal(UI_TRANSLATIONS.machine?.ro, 'aparat')
})

test('alternative equipment is never presented as bodyweight', () => {
  const byID = new Map(EXERCISE_CATALOG.map((exercise) => [exercise.id, exercise]))
  assert.equal(byID.get('pallof_press')?.equipment, 'Bands or Cable Stack')
  assert.equal(byID.get('cable_external_rotation')?.equipment, 'Bands or Cable Stack')
  assert.equal(byID.get('hip_abduction')?.equipment, 'Abduction Machine or Bands')
})

test('Romanian partial searches resolve common gym vocabulary', () => {
  assert.ok(searchExerciseCatalog('tra', 'all', 'ro').some((exercise) => exercise.id === 'pull_up'))
  assert.ok(searchExerciseCatalog('fandari', 'all', 'ro').some((exercise) => exercise.id === 'walking_lunge'))
  assert.ok(searchExerciseCatalog('ramat', 'all', 'ro').some((exercise) => exercise.id === 'barbell_row'))
  assert.equal(searchExerciseCatalog('ciocane', 'all', 'ro')[0]?.id, 'hammer_curl')
  assert.ok(searchExerciseCatalog('banda', 'all', 'ro').some((exercise) => exercise.id === 'treadmill'))
  assert.ok(searchExerciseCatalog('gambe', 'all', 'ro').some((exercise) => exercise.id === 'standing_calf_raise'))
  assert.ok(searchExerciseCatalog('gambe', 'all', 'ro').some((exercise) => exercise.id === 'calf_press_leg_press'))
  assert.ok(searchExerciseCatalog('abdomene', 'all', 'ro').some((exercise) => exercise.id === 'machine_crunch'))
  assert.ok(searchExerciseCatalog('aductori', 'all', 'ro').some((exercise) => exercise.id === 'hip_adduction'))
})

test('exercise discovery tolerates common spelling errors', () => {
  assert.ok(searchExerciseCatalog('gammbe', 'all', 'ro').slice(0, 5).some((exercise) => exercise.id === 'standing_calf_raise'))
  assert.ok(searchExerciseCatalog('abdomeen', 'all', 'ro').some((exercise) => exercise.id === 'machine_crunch'))
  assert.ok(searchExerciseCatalog('adutori', 'all', 'ro').some((exercise) => exercise.id === 'hip_adduction'))
  assert.ok(searchExerciseCatalog('chset', 'all', 'en').some((exercise) => exercise.muscles.includes('chest')))
})

test('Thai search and native names resolve to canonical exercises', () => {
  assert.ok(searchExerciseCatalog('ลู่วิ่ง', 'all', 'th').some((exercise) => exercise.id === 'treadmill'))
  assert.equal(catalogExerciseByName('เดินบนลู่วิ่ง')?.id, 'treadmill')
  assert.equal(catalogExerciseByName('Tracțiuni la bară')?.id, 'pull_up')
  assert.ok(searchExerciseCatalog('น่อง', 'all', 'th').some((exercise) => exercise.id === 'standing_calf_raise'))
  assert.ok(searchExerciseCatalog('หน้าท้อง', 'all', 'th').some((exercise) => exercise.id === 'machine_crunch'))
})
