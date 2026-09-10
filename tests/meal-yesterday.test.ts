import assert from 'node:assert/strict'
import test from 'node:test'
import { yesterdayMealItems } from '../src/lib/mealYesterday.ts'
import type { LoggedMeal, LoggedFoodEntry } from '../src/lib/food.ts'

test('yesterday shortcut preserves fractional portions and isolates day, slot and owner', () => {
  const meal = { id: 'meal', user_id: 'owner', local_date: '2026-08-31', meal_slot: 'lunch', logged_at: '2026-08-31T12:00:00Z' } as LoggedMeal
  const entry = { id: 'entry', meal_id: 'meal', user_id: 'owner', sort_order: 0, food_id: null, snapshot_name: 'Apple', snapshot_nutrition_basis: 'per_100g', snapshot_preparation_state: 'as_sold', snapshot_kcal_100: 52, snapshot_protein_100: 0.3, snapshot_carbs_100: 14, snapshot_fat_100: 0.2, quantity: 0.5, unit: 'serving', equivalent_amount: 90 } as LoggedFoodEntry
  const copy = yesterdayMealItems('2026-09-01', 'lunch', 'owner', [meal], [entry])
  assert.equal(copy.length, 1)
  assert.notEqual(copy[0].id, entry.id)
  assert.equal(copy[0].quantity, 0.5)
  assert.equal(copy[0].food.serving_grams_or_ml, 180)
  assert.deepEqual(yesterdayMealItems('2026-09-02', 'lunch', 'owner', [meal], [entry]), [])
  assert.deepEqual(yesterdayMealItems('2026-09-01', 'breakfast', 'owner', [meal], [entry]), [])
  assert.deepEqual(yesterdayMealItems('2026-09-01', 'lunch', 'other', [meal], [entry]), [])
  assert.equal(entry.quantity, 0.5)
})
