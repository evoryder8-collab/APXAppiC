import assert from 'node:assert/strict'
import test from 'node:test'
import {
  mealBlockIdempotencyKey,
  normalizeMealBlockSettings,
  resolveMealBlockStatuses,
} from '../src/lib/mealBlocks.ts'
import type { LoggedMeal } from '../src/lib/food.ts'
import { dayMealCopyIdempotencyKey } from '../src/lib/simpleMode.ts'

function loggedMeal(patch: Partial<LoggedMeal> = {}): LoggedMeal {
  return {
    id: crypto.randomUUID(), user_id: crypto.randomUUID(), local_date: '2026-07-16',
    meal_slot: 'breakfast', display_name: 'Saved breakfast', source_preset_id: crypto.randomUUID(),
    source_planned_meal_id: null, logged_at: '2026-07-16T07:10:00.000Z',
    client_idempotency_key: crypto.randomUUID(), logged_as: 'custom', total_kcal: 500,
    total_protein_g: 30, total_carbs_g: 50, total_fat_g: 20,
    created_at: '2026-07-16T07:10:00.000Z', updated_at: '2026-07-16T07:10:00.000Z',
    ...patch,
  }
}

test('default meal setup stays meaningful when a profile has no legacy plan', () => {
  const settings = normalizeMealBlockSettings(undefined)
  const statuses = resolveMealBlockStatuses({ settings, loggedMeals: [], plannedMeals: [] })
  assert.equal(statuses.length, 5)
  assert.deepEqual(statuses.map((status) => status.block.id), ['breakfast', 'lunch', 'dinner', 'snack', 'post_workout'])
  assert.equal(statuses.filter((status) => status.completed).length, 0)
})

test('an older saved breakfast preset counts in the Breakfast block by its durable slot', () => {
  const settings = normalizeMealBlockSettings(undefined)
  const statuses = resolveMealBlockStatuses({ settings, loggedMeals: [loggedMeal()] })
  assert.equal(statuses.find((status) => status.block.id === 'breakfast')?.completed, true)
  assert.equal(statuses.filter((status) => status.completed).length, 1)
})

test('explicit post-workout identity survives a regenerated copy key', () => {
  const settings = normalizeMealBlockSettings(undefined)
  const original = loggedMeal({
    meal_slot: 'snack',
    display_name: 'Whey isolate',
    client_idempotency_key: mealBlockIdempotencyKey('original', 'post_workout'),
  })
  const copied = loggedMeal({
    ...original,
    id: crypto.randomUUID(),
    client_idempotency_key: mealBlockIdempotencyKey(
      dayMealCopyIdempotencyKey(original.user_id, '2026-07-16', '2026-07-17', original.id),
      'post_workout',
    ),
  })
  const statuses = resolveMealBlockStatuses({ settings, loggedMeals: [copied] })
  assert.equal(statuses.find((status) => status.block.id === 'post_workout')?.loggedMeal?.id, copied.id)
  assert.equal(statuses.find((status) => status.block.id === 'snack')?.completed, false)
})

test('preset assignment disambiguates Snack from Post-workout across devices', () => {
  const presetId = crypto.randomUUID()
  const settings = normalizeMealBlockSettings({
    blocks: normalizeMealBlockSettings(undefined).blocks,
    preset_assignments: { [presetId]: 'post_workout' },
  })
  const meal = loggedMeal({ meal_slot: 'snack', source_preset_id: presetId })
  const statuses = resolveMealBlockStatuses({ settings, loggedMeals: [meal] })
  assert.equal(statuses.find((status) => status.block.id === 'post_workout')?.completed, true)
  assert.equal(statuses.find((status) => status.block.id === 'snack')?.completed, false)
})

test('a stale block marker cannot double-count one planned meal', () => {
  const settings = normalizeMealBlockSettings(undefined)
  const snack = { id: crypto.randomUUID(), name: 'Snack', time: '16:00' }
  const postWorkout = { id: crypto.randomUUID(), name: 'Post-workout recovery', time: '21:00' }
  const meal = loggedMeal({
    meal_slot: 'snack',
    source_planned_meal_id: snack.id,
    client_idempotency_key: mealBlockIdempotencyKey('stale-client', 'post_workout'),
  })
  const statuses = resolveMealBlockStatuses({
    settings,
    loggedMeals: [meal],
    plannedMeals: [snack, postWorkout],
    checkedPlannedMealIds: new Set([snack.id]),
  })
  assert.equal(statuses.find((status) => status.block.id === 'snack')?.loggedMeal?.id, meal.id)
  assert.equal(statuses.find((status) => status.block.id === 'post_workout')?.completed, false)
  assert.equal(statuses.filter((status) => status.completed).length, 1)
})

test('ordinary snacks never spill into the Post-workout block', () => {
  const settings = normalizeMealBlockSettings(undefined)
  const firstSnack = loggedMeal({ id: crypto.randomUUID(), meal_slot: 'snack', source_preset_id: null, display_name: 'Fruit' })
  const secondSnack = loggedMeal({ id: crypto.randomUUID(), meal_slot: 'snack', source_preset_id: null, display_name: 'Nuts', logged_at: '2026-07-16T17:00:00.000Z' })
  const statuses = resolveMealBlockStatuses({ settings, loggedMeals: [firstSnack, secondSnack] })
  assert.equal(statuses.find((status) => status.block.id === 'snack')?.completed, true)
  assert.equal(statuses.find((status) => status.block.id === 'post_workout')?.completed, false)
  assert.equal(statuses.filter((status) => status.completed).length, 1)
})

test('an ordinary snack does not become Post-workout when Snack is disabled', () => {
  const settings = normalizeMealBlockSettings({
    blocks: normalizeMealBlockSettings(undefined).blocks.map((block) => block.id === 'snack' ? { ...block, enabled: false } : block),
  })
  const statuses = resolveMealBlockStatuses({
    settings,
    loggedMeals: [loggedMeal({ meal_slot: 'snack', source_preset_id: null, display_name: 'Fruit' })],
  })
  assert.equal(statuses.find((status) => status.block.id === 'post_workout')?.completed, false)
  assert.equal(statuses.filter((status) => status.completed).length, 0)
})

test('meal block settings sanitize clocks and never allow an empty setup', () => {
  const settings = normalizeMealBlockSettings({
    blocks: normalizeMealBlockSettings(undefined).blocks.map((block) => ({ ...block, enabled: false, time: '99:99' })),
    preset_assignments: { bad: 'invalid' },
  })
  assert.equal(settings.blocks.find((block) => block.id === 'breakfast')?.enabled, true)
  assert.equal(settings.blocks.find((block) => block.id === 'breakfast')?.time, '07:00')
  assert.deepEqual(settings.preset_assignments, {})
})
