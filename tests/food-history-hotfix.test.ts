import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import test from 'node:test'

const webTraining = readFileSync(new URL('../src/pages/WorkoutSection.tsx', import.meta.url), 'utf8')
const nativeTraining = readFileSync(
  new URL('../ios/APEXNative/APEX/Features/Training/TrainingProgramView.swift', import.meta.url),
  'utf8',
)
const webComposer = readFileSync(new URL('../src/components/food/MealComposer.tsx', import.meta.url), 'utf8')
const nativeComposer = readFileSync(
  new URL('../ios/APEXNative/APEX/Features/Nutrition/MealComposerView.swift', import.meta.url),
  'utf8',
)
const webFoodStore = readFileSync(new URL('../src/store/FoodStore.tsx', import.meta.url), 'utf8')

test('Transition and Main phase receipts are scoped to today instead of all-time HealthKit history', () => {
  assert.match(webTraining, /<CompletedWorkoutHistoryCards date=\{today\}/)
  assert.doesNotMatch(webTraining, /<CompletedWorkoutHistoryCards date=\{undefined\}/)
  assert.match(nativeTraining, /CompletedWorkoutHistoryCards\(date: Date\(\)\.apexDateKey/)
  assert.doesNotMatch(nativeTraining, /CompletedWorkoutHistoryCards\(date: nil/)
})

test('saving an existing meal after removing every item deletes it and closes on both clients', () => {
  assert.match(webComposer, /if \(replaceMealId && items\.length === 0\)[\s\S]*?await store\.deleteMeal\(replaceMealId\)[\s\S]*?onClose\(\)/)
  assert.match(webComposer, /items\.length > 0 \|\| Boolean\(replaceMealId\)/)
  assert.match(nativeComposer, /if draft\.items\.isEmpty, let existingMeal = request\.existingMeal[\s\S]*?await session\.deleteLoggedMeal\(existingMeal\)[\s\S]*?dismiss\(\)/)
  assert.match(nativeComposer, /\.disabled\(isSaving \|\| \(draft\.items\.isEmpty && request\.existingMeal == nil\)\)/)
})

test('every hydrated web catalogue path resolves missing food water without overwriting source values', () => {
  assert.match(webFoodStore, /function resolveCatalogFoodWater/)
  assert.match(webFoodStore, /normalizeRemoteFood[\s\S]*?resolveCatalogFoodWater/)
  assert.match(webFoodStore, /mergeFoodCatalog[\s\S]*?resolveCatalogFoodWater/)
})

test('the production hotfix migration carries Swiss McDonald servings, water provenance and fuzzy RPC matching', () => {
  const servingMigration = readFileSync(
    new URL('../supabase/migrations/038_swiss_fast_food_servings.sql', import.meta.url),
    'utf8',
  )
  assert.match(servingMigration, /with fast_food_references/i)
  assert.doesNotMatch(servingMigration, /with references\s*\(/i)

  const migrationURL = new URL('../supabase/migrations/039_food_search_hydration_hotfix.sql', import.meta.url)
  assert.equal(existsSync(migrationURL), true, 'migration 039 must exist')
  const migration = readFileSync(migrationURL, 'utf8')
  for (const product of ['Cheeseburger Royal', 'Big Tasty Single', 'Big Tasty Double', 'McRaclette']) {
    assert.match(migration, new RegExp(product.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'), product)
  }
  assert.match(migration, /water_ml_100/i)
  assert.match(migration, /water_source_id/i)
  assert.match(migration, /serving_grams_or_ml/i)
  assert.match(migration, /regexp_replace[\s\S]*?similarity/i)
  assert.match(migration, /word_similarity\(input\.compact_needle, haystack\.compact_name\)/i)
  assert.match(migration, /on conflict \(id\) do update/i)
})
