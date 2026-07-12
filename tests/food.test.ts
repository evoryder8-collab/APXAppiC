import assert from 'node:assert/strict'
import test from 'node:test'
import { COMMON_FOODS } from '../src/data/foodSeeds.ts'
import {
  calculatePortion,
  mergeMealsIdempotently,
  parseDecimalInput,
  rankFoods,
  snapshotEntry,
  suggestPresetAdaptation,
  type ComposerFoodItem,
  type FoodPreference,
  type LoggedMeal,
} from '../src/lib/food.ts'
import { normalizeBarcode, normalizeOpenFoodFactsProduct } from '../shared/openFoodFacts.ts'

function item(foodIndex = 0, quantity = 100): ComposerFoodItem {
  return {
    id: crypto.randomUUID(), food: COMMON_FOODS[foodIndex], quantity, unit: 'g', sort_order: 0,
    optional: false, locked: false, adjustable: true, minimum_amount: 20, maximum_amount: 200,
    step_amount: 5, adjustment_role: 'carb',
  }
}

test('food portions distinguish dry, cooked, piece and decimal-comma inputs', () => {
  assert.equal(calculatePortion(COMMON_FOODS[1], 100, 'g')?.kcal, 360)
  assert.equal(calculatePortion(COMMON_FOODS[2], 100, 'g')?.kcal, 130)
  assert.equal(calculatePortion(COMMON_FOODS[6], 2, 'piece')?.equivalent_amount, 116)
  assert.equal(parseDecimalInput('1,5'), 1.5)
  assert.equal(parseDecimalInput('1.234,5'), 1234.5)
})

test('personal aliases, favourites and recent slot use rank before generic foods', () => {
  const preference: FoodPreference = {
    id: crypto.randomUUID(), user_id: crypto.randomUUID(), food_id: COMMON_FOODS[4].id,
    personal_name: 'golden grains', aliases: ['my lunch'], favourite: true, usual_amount: 150,
    usual_unit: 'g', usage_count: 8, last_used_at: new Date().toISOString(), hidden: false,
    slot_usage: { lunch: 7 }, version: 1, updated_at: new Date().toISOString(),
  }
  assert.equal(rankFoods('my lunch', COMMON_FOODS, [preference], 'lunch')[0].id, COMMON_FOODS[4].id)
})

test('logged entries are immutable nutrition snapshots', () => {
  const original = item(0, 80)
  const snapshot = snapshotEntry(original, crypto.randomUUID(), crypto.randomUUID())!
  const oldCalories = snapshot.kcal
  original.food.kcal_100 = 999
  assert.equal(snapshot.kcal, oldCalories)
  assert.notEqual(snapshot.snapshot_kcal_100, original.food.kcal_100)
})

test('adaptive suggestions respect locked items, bounds and explicit apply', () => {
  const locked = { ...item(0, 60), id: 'locked', locked: true }
  const adjustable = { ...item(1, 50), id: 'flex', maximum_amount: 80 }
  const before = adjustable.quantity
  const suggestions = suggestPresetAdaptation([locked, adjustable], {
    target: { kcal: 900, protein_g: 45, carbs_g: 120, fat_g: 25 },
    consumed: { kcal: 200, protein_g: 30, carbs_g: 20, fat_g: 10 },
    activityLabel: 'Very active', trainingToday: true,
  })
  assert.equal(adjustable.quantity, before, 'suggestions must never silently mutate a preset')
  assert.equal(suggestions[0].item_id, 'flex')
  assert.ok(suggestions[0].proposed_quantity <= 80)
})

test('meal merge is idempotent by user and client key', () => {
  const base: LoggedMeal = {
    id: crypto.randomUUID(), user_id: crypto.randomUUID(), local_date: '2026-07-12', meal_slot: 'lunch',
    display_name: 'Lunch', source_preset_id: null, source_planned_meal_id: null,
    logged_at: new Date().toISOString(), client_idempotency_key: 'same', logged_as: 'custom',
    total_kcal: 500, total_protein_g: 30, total_carbs_g: 55, total_fat_g: 15,
    created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
  }
  assert.equal(mergeMealsIdempotently([base], [{ ...base, id: crypto.randomUUID() }]).length, 1)
})

test('Open Food Facts normalization validates barcodes, converts kJ and preserves missing fields', () => {
  assert.equal(normalizeBarcode('4006381333931'), '4006381333931')
  assert.equal(normalizeBarcode('4006381333932'), null)
  const food = normalizeOpenFoodFactsProduct({
    status: 1,
    product: {
      code: '4006381333931', product_name_en: 'Test oats', brands: 'Test',
      nutriments: { 'energy-kj_100g': 418.4, proteins_100g: 3, carbohydrates_100g: 20, fat_100g: 1 },
    },
  } as never, '4006381333931')
  assert.equal(food?.kcal_100, 100)
  assert.equal(food?.fibre_100, null)
})
