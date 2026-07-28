import assert from 'node:assert/strict'
import test from 'node:test'
import { mealMacroStatus } from '../src/lib/mealMacroGuidance.ts'

test('meal macro guidance always reports actual overage and flags material excess', () => {
  assert.deepEqual(
    mealMacroStatus(45, 50, 'carbs', 'constantine', 'recomp').state,
    'reached',
  )
  const modest = mealMacroStatus(55, 50, 'carbs', 'constantine', 'recomp')
  assert.equal(modest.state, 'above')
  assert.equal(modest.overBy, 5)
  const high = mealMacroStatus(60, 50, 'carbs', 'constantine', 'recomp')
  assert.equal(high.state, 'high')
  assert.equal(high.overBy, 10)
})

test('June lean-bulk meal distribution deliberately permits a wider range', () => {
  assert.equal(mealMacroStatus(65, 50, 'carbs', 'june', 'bulk').state, 'above')
  assert.equal(mealMacroStatus(71, 50, 'carbs', 'june', 'bulk').state, 'high')
})
