import assert from 'node:assert/strict'
import test from 'node:test'
import { selectNextSimpleAction, settingsForUiMode, simpleCompletion, simpleDaySwipeOffset, simpleWaterTargetComplete, toggleSimpleWaterTarget, uiModeFromSettings } from '../src/lib/simpleMode.ts'
import type { Settings } from '../src/lib/types.ts'

const settings: Settings = {
  user_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', voice_on: true, ticks_on: true,
  notifications_on: false, guardian_factor: 1.5,
  addons: { endurance1: true, endurance2: false, endurance3: false },
}

test('existing users stay in Advanced Mode until they explicitly switch', () => {
  assert.equal(uiModeFromSettings(settings), 'advanced')
  const patch = settingsForUiMode(settings, 'simple')
  assert.equal(patch.addons.uiMode, 'simple')
  assert.equal(patch.addons.endurance1, true)
})

test('Simple Mode surfaces the most recently due action or earliest upcoming action', () => {
  const actions = [{ time: 330, id: 'wake' }, { time: 420, id: 'breakfast' }, { time: 750, id: 'lunch' }]
  assert.equal(selectNextSimpleAction(actions, 600)?.id, 'breakfast')
  assert.equal(selectNextSimpleAction(actions, 300)?.id, 'wake')
  assert.equal(selectNextSimpleAction([], 600), null)
})

test('Simple Mode completion is bounded and handles an empty routine', () => {
  assert.equal(simpleCompletion(3, 4), 75)
  assert.equal(simpleCompletion(0, 0), 100)
  assert.equal(simpleCompletion(8, 4), 100)
})

test('Simple Mode water checklist toggles the target instead of adding it twice', () => {
  assert.equal(toggleSimpleWaterTarget(0, 2.5), 2.5)
  assert.equal(simpleWaterTargetComplete(2.5, 2.5), true)
  assert.equal(toggleSimpleWaterTarget(2.5, 2.5), 0)
  assert.equal(toggleSimpleWaterTarget(2.25, 2.5), 0)
})

test('Simple Mode changes days only for a deliberate horizontal swipe', () => {
  assert.equal(simpleDaySwipeOffset({ x: 200, y: 100 }, { x: 120, y: 104 }), 1)
  assert.equal(simpleDaySwipeOffset({ x: 120, y: 100 }, { x: 200, y: 104 }), -1)
  assert.equal(simpleDaySwipeOffset({ x: 200, y: 100 }, { x: 160, y: 104 }), 0)
  assert.equal(simpleDaySwipeOffset({ x: 200, y: 100 }, { x: 120, y: 180 }), 0)
})

test('workout-owned gestures never become Simple Mode day swipes', () => {
  assert.equal(simpleDaySwipeOffset({ x: 200, y: 100 }, { x: 80, y: 100 }, true), 0)
})
