import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { COMMON_FOODS } from '../src/data/foodSeeds.ts'
import type { LoggedFoodEntry, LoggedMeal, MealPreset } from '../src/lib/food.ts'
import {
  loggedMealEditorState,
  mealRowSwipeOffset,
  rankMealHistoryRecommendations,
} from '../src/lib/mealExperience.ts'
import { createCustomMealBlock, normalizeMealBlockSettings } from '../src/lib/mealBlocks.ts'

function meal(patch: Partial<LoggedMeal> = {}): LoggedMeal {
  return {
    id: crypto.randomUUID(), user_id: 'user-1', local_date: '2026-07-09', meal_slot: 'lunch',
    display_name: 'Chicken lunch', source_preset_id: 'preset-lunch', source_planned_meal_id: null,
    logged_at: '2026-07-09T13:05:00.000Z', client_idempotency_key: 'meal|apex-meal-block=lunch',
    logged_as: 'custom', total_kcal: 500, total_protein_g: 40, total_carbs_g: 50, total_fat_g: 14,
    created_at: '2026-07-09T13:05:00.000Z', updated_at: '2026-07-09T13:05:00.000Z',
    ...patch,
  }
}

function entry(mealId: string, foodId: string): LoggedFoodEntry {
  const food = COMMON_FOODS.find((candidate) => candidate.id === foodId)!
  return {
    id: crypto.randomUUID(), meal_id: mealId, user_id: 'user-1', food_id: food.id, sort_order: 0,
    snapshot_name: food.name, snapshot_brand: food.brand, snapshot_preparation_state: food.preparation_state,
    snapshot_nutrition_basis: food.nutrition_basis, snapshot_kcal_100: food.kcal_100 ?? 0,
    snapshot_protein_100: food.protein_100 ?? 0, snapshot_carbs_100: food.carbs_100 ?? 0,
    snapshot_fat_100: food.fat_100 ?? 0, snapshot_fibre_100: food.fibre_100,
    snapshot_sugar_100: food.sugar_100, snapshot_saturated_fat_100: food.saturated_fat_100,
    snapshot_salt_100: food.salt_100, quantity: 100, unit: 'g', equivalent_amount: 100,
    kcal: food.kcal_100 ?? 0, protein_g: food.protein_100 ?? 0, carbs_g: food.carbs_100 ?? 0,
    fat_g: food.fat_100 ?? 0, fibre_g: food.fibre_100, sugar_g: food.sugar_100,
    saturated_fat_g: food.saturated_fat_100, salt_g: food.salt_100, created_at: '2026-07-09T13:05:00.000Z',
  }
}

test('meal row gestures own horizontal deletion without producing day offsets', () => {
  assert.equal(mealRowSwipeOffset({ x: 220, y: 100 }, { x: 140, y: 104 }), -104)
  assert.equal(mealRowSwipeOffset({ x: 220, y: 100 }, { x: 210, y: 180 }), 0)
  assert.equal(mealRowSwipeOffset({ x: 140, y: 100 }, { x: 200, y: 104 }, true), 0)
  assert.equal(mealRowSwipeOffset({ x: 140, y: 100 }, { x: 142, y: 102 }, true), -104)

  const source = readFileSync(new URL('../src/components/food/ActualFoodTracker.tsx', import.meta.url), 'utf8')
  assert.match(source, /data-nutrition-local-gesture/)
  assert.match(source, /data-meal-row-gesture/)
  assert.match(source, /event\.stopPropagation\(\)/)
  assert.match(source, /tabIndex=\{open \? 0 : -1\}/)
  assert.match(source, /standaloneLoggedBlockStatuses/)
  assert.doesNotMatch(source, /confirmDelete/)
})

test('meal completion callbacks are invalidated at the account boundary', () => {
  const source = readFileSync(new URL('../src/store/FoodStore.tsx', import.meta.url), 'utf8')
  assert.match(source, /userIdRef\.current = null/)
  assert.match(source, /The meal was kept for its original account/)
})

test('logged meal editor state always replaces the selected snapshot meal', () => {
  const saved = meal({ id: 'meal-to-replace', source_planned_meal_id: 'planned-1', display_name: 'Renamed meal' })
  assert.deepEqual(loggedMealEditorState(saved, 'lunch', '13:00'), {
    slot: 'lunch', blockId: 'lunch', mealIdentity: 'lunch', title: 'Renamed meal', plannedMealId: 'planned-1',
    replaceMealId: 'meal-to-replace', targetTime: '13:00',
  })
})

test('custom meal blocks normalize safely inside synced settings JSON', () => {
  const created = createCustomMealBlock({ label: '  Second   lunch  ', time: '15:30', slot: 'snack' }, () => 'ABC-12345')
  assert.deepEqual(created, { id: 'custom:abc-12345', label: 'Second lunch', time: '15:30', slot: 'snack', enabled: true })

  const normalized = normalizeMealBlockSettings({
    custom_blocks: [created, created, { id: 'custom:no', label: '', slot: 'wrong', time: '91:00' }],
  })
  assert.deepEqual(normalized.custom_blocks, [created])
  assert.equal(normalized.blocks.length, 5, 'canonical blocks remain compatible with existing clients')

  const customMeal = meal({ client_idempotency_key: `saved|apex-meal-block=${created.id}` })
  assert.equal(loggedMealEditorState(customMeal).mealIdentity, created.id)
})

test('blank composer history prioritizes same block, weekday, hour and sequence', () => {
  const chicken = COMMON_FOODS[0]
  const oats = COMMON_FOODS[1]
  const sameMoment = meal({ id: 'same-moment' })
  const recentWrongSlot = meal({
    id: 'wrong-slot', local_date: '2026-07-15', meal_slot: 'breakfast', display_name: 'Recent breakfast',
    source_preset_id: null, logged_at: '2026-07-15T07:00:00.000Z', client_idempotency_key: 'breakfast',
  })
  const olderLunch = meal({
    id: 'older-lunch', local_date: '2026-07-02', source_preset_id: null,
    logged_at: '2026-07-02T16:30:00.000Z', client_idempotency_key: 'lunch',
  })
  const preset: MealPreset = {
    id: 'preset-lunch', user_id: 'user-1', name: 'Reliable lunch', meal_slot: 'lunch',
    source_planned_meal_id: null, archived: false, version: 1,
    created_at: '2026-06-01T00:00:00.000Z', updated_at: '2026-07-09T00:00:00.000Z',
  }
  const ranked = rankMealHistoryRecommendations({
    context: { date: '2026-07-16', slot: 'lunch', blockId: 'lunch', targetTime: '13:00', sequenceIndex: 0 },
    meals: [recentWrongSlot, olderLunch, sameMoment],
    entries: [entry(sameMoment.id, chicken.id), entry(recentWrongSlot.id, oats.id)],
    foods: COMMON_FOODS,
    presets: [preset],
  })
  assert.equal(ranked.meals[0]?.id, sameMoment.id)
  assert.equal(ranked.foods[0]?.id, chicken.id)
  assert.equal(ranked.presets[0]?.id, preset.id)
})
