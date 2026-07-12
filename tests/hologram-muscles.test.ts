import assert from 'node:assert/strict'
import test from 'node:test'
import { musclesForWorkout } from '../src/components/hologram/muscleMap.ts'

test('hologram derives primary muscles from the actual workout exercises', () => {
  const pull = musclesForWorkout('pull', ['Pull-ups', 'Chest-supported dumbbell rows', 'Hammer curls'])
  assert.ok(pull.includes('lats'))
  assert.ok(pull.includes('upperBack'))
  assert.ok(pull.includes('biceps'))
  assert.ok(pull.includes('forearms'))

  const legs = musclesForWorkout('legs_a', ['Bulgarian split squats', 'Dumbbell Romanian deadlifts', 'Hip thrusts'])
  assert.ok(legs.includes('glutes'))
  assert.ok(legs.includes('hamstrings'))
  assert.ok(legs.includes('quads'))
  assert.ok(legs.includes('lowerBack'))
})

test('hologram falls back to an anatomically useful day map when exercises are unavailable', () => {
  assert.deepEqual(musclesForWorkout('push'), ['chest', 'frontDelts', 'sideDelts', 'triceps'])
  assert.ok(musclesForWorkout('fix').includes('rearDelts'))
  assert.ok(musclesForWorkout('t25').includes('quads'))
})
