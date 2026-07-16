import assert from 'node:assert/strict'
import test from 'node:test'
import { canFinishDaySwipe, canPasteSimpleDay, canStartDaySwipe, dayMealCopyIdempotencyKey, daySwipeHasSingleTrackedTouch, floatingActiveDateVisible, parseWaterAmountToLitres, rankSimpleMacroContributors, selectNextSimpleAction, settingsForUiMode, simpleCompletion, simpleDaySwipeOffset, simpleWaterTargetComplete, toggleSimpleWaterTarget, uiModeFromSettings, weightFromKg, weightToKg, weightUnitFromSettings } from '../src/lib/simpleMode.ts'
import type { Settings } from '../src/lib/types.ts'
import { seedSettings } from '../src/data/seed.ts'

const settings: Settings = {
  user_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', voice_on: true, ticks_on: true,
  notifications_on: false, guardian_factor: 1.5,
  addons: { endurance1: true, endurance2: false, endurance3: false },
}

test('Simple Mode is the default while an explicit Advanced choice remains respected', () => {
  assert.equal(uiModeFromSettings(settings), 'simple')
  assert.equal(uiModeFromSettings({ ...settings, addons: { ...settings.addons, uiMode: 'advanced' } }), 'advanced')
  const patch = settingsForUiMode(settings, 'advanced')
  assert.equal(patch.addons.uiMode, 'advanced')
  assert.equal(patch.addons.endurance1, true)
})

test('new Simple Mode profiles keep optional secondary cards hidden', () => {
  const seeded = seedSettings('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
  assert.equal(seeded.addons.uiMode, 'simple')
  assert.equal(seeded.addons.simple_show_hydration_reminder, false)
  assert.equal(seeded.addons.simple_show_manual_workout, false)
  assert.equal(seeded.addons.simple_show_next_action, false)
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

test('day swipe tracking rejects interactive starts and cancels every multi-touch phase', () => {
  assert.equal(canStartDaySwipe(1, false), true)
  assert.equal(canStartDaySwipe(1, true), false)
  assert.equal(canStartDaySwipe(2, false), false)
  assert.equal(daySwipeHasSingleTrackedTouch([7], 7), true)
  assert.equal(daySwipeHasSingleTrackedTouch([7, 8], 7), false)
  assert.equal(daySwipeHasSingleTrackedTouch([8], 7), false)
  assert.equal(canFinishDaySwipe(0, [7], 7), true)
  assert.equal(canFinishDaySwipe(1, [7], 7), false)
  assert.equal(canFinishDaySwipe(0, [7, 8], 7), false)
  assert.equal(canFinishDaySwipe(0, [8], 7), false)
})

test('floating date stays hidden at the top and appears only after scrolling down', () => {
  assert.equal(floatingActiveDateVisible(0), false)
  assert.equal(floatingActiveDateVisible(220), false)
  assert.equal(floatingActiveDateVisible(221), true)
  assert.equal(floatingActiveDateVisible(Number.NaN), false)
})

test('Simple Mode weight preference defaults to metric and converts without changing stored kilograms', () => {
  assert.equal(weightUnitFromSettings(settings), 'kg')
  assert.equal(weightUnitFromSettings({ ...settings, addons: { ...settings.addons, weight_unit: 'lb' } }), 'lb')
  assert.equal(Math.round(weightFromKg(78, 'lb') * 10) / 10, 172)
  assert.equal(Math.round(weightToKg(172, 'lb') * 10) / 10, 78)
})

test('Simple Mode custom water accepts millilitres and litres safely', () => {
  assert.equal(parseWaterAmountToLitres('750 ml'), 0.75)
  assert.equal(parseWaterAmountToLitres('300'), 0.3)
  assert.equal(parseWaterAmountToLitres('0,5 L'), 0.5)
  assert.equal(parseWaterAmountToLitres('7 litres'), null)
  assert.equal(parseWaterAmountToLitres('water'), null)
})

test('copied calendar days highlight only genuinely valid paste targets', () => {
  assert.equal(canPasteSimpleDay('2026-07-15', '2026-07-16'), true)
  assert.equal(canPasteSimpleDay('2026-07-15', '2026-07-15'), false)
  assert.equal(canPasteSimpleDay(null, '2026-07-16'), false)
  assert.equal(canPasteSimpleDay('not-a-date', '2026-07-16'), false)
})

test('Simple and Advanced calendars share one meal-copy idempotency key', () => {
  assert.equal(
    dayMealCopyIdempotencyKey('user', '2026-07-15', '2026-07-16', 'meal'),
    'simple-day-copy:user:2026-07-15:2026-07-16:meal',
  )
})

test('macro details combine duplicate foods and rank their daily contribution', () => {
  const rows = [
    { snapshot_name: 'Chicken', protein_g: 31, carbs_g: 0, fat_g: 3.6 },
    { snapshot_name: 'Oats', protein_g: 10, carbs_g: 60, fat_g: 7 },
    { snapshot_name: 'Chicken', protein_g: 15.5, carbs_g: 0, fat_g: 1.8 },
    { snapshot_name: 'Water', protein_g: 0, carbs_g: 0, fat_g: 0 },
  ]
  assert.deepEqual(rankSimpleMacroContributors(rows, 'protein_g'), [
    { name: 'Chicken', amount: 46.5 },
    { name: 'Oats', amount: 10 },
  ])
  assert.deepEqual(rankSimpleMacroContributors(rows, 'carbs_g', 1), [{ name: 'Oats', amount: 60 }])
})
