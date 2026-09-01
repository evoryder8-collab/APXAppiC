import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import {
  foodNutrientEvidence,
  nutritionFactSections,
  nutrientWindow,
  summarizeNutrientIntake,
  type NutrientEvidenceObservation,
} from '../src/lib/nutrientEvidence.ts'
import {
  composerItemFromSelection,
  snapshotEntry,
  type FoodRecord,
  type LoggedFoodEntry,
  type LoggedMeal,
} from '../src/lib/food.ts'
import { normalizeOpenFoodFactsProduct } from '../shared/openFoodFacts.ts'

const evidence = (
  nutrient_code: string,
  name: string,
  value_per_100: number | null,
  unit: string,
  observation_status: NutrientEvidenceObservation['observation_status'] = 'measured',
): NutrientEvidenceObservation => ({
  nutrient_code,
  name,
  value_per_100,
  unit,
  observation_status,
  original_value_text: value_per_100 == null ? 'tr' : String(value_per_100),
  derivation_method: null,
  source_key: 'fixture-source',
  source_reference: 'fixture-reference',
})

const food = (nutrient_evidence: NutrientEvidenceObservation[]): FoodRecord => ({
  id: 'food-1', owner_user_id: null, name: 'Evidence food', names_i18n: {}, brand: null,
  barcode: null, source: 'apex_cache', provider_product_id: 'corpus:fixture:food-1',
  external_image_url: null, package_quantity: null, nutrition_basis: 'per_100g',
  preparation_state: 'as_sold', kcal_100: 120, protein_100: 3, carbs_100: 20,
  fat_100: 2, fibre_100: 4, sugar_100: 6, saturated_fat_100: 1, salt_100: 0.4,
  water_ml_100: 60, serving_amount: null, serving_unit: null, serving_grams_or_ml: null,
  piece_grams_or_ml: null, provider_updated_at: null, confidence: 'provider_verified',
  created_at: '2026-09-01T00:00:00Z', updated_at: '2026-09-01T00:00:00Z',
  nutrient_evidence,
})

test('detail evidence preserves trace and missing states while adding only reported fallback facts', () => {
  const rows = foodNutrientEvidence(food([
    evidence('VITA', 'Vitamin A', null, 'µg', 'trace'),
    evidence('FE', 'Iron', null, 'mg', 'not_measured'),
  ]))

  assert.equal(rows.find((row) => row.nutrient_code === 'VITA')?.observation_status, 'trace')
  assert.equal(rows.find((row) => row.nutrient_code === 'VITA')?.value_per_100, null)
  assert.equal(rows.find((row) => row.nutrient_code === 'FE')?.observation_status, 'not_measured')
  assert.equal(rows.find((row) => row.nutrient_code === 'SUGAR')?.value_per_100, 6)
  assert.equal(rows.filter((row) => row.nutrient_code === 'SUGAR').length, 1)
  assert.ok(!rows.some((row) => row.value_per_100 === 0 && row.original_value_text === 'tr'))
})

test('nutrition facts keep totals attached to their indented details in familiar label order', () => {
  const sections = nutritionFactSections([
    evidence('SUGAR', 'Total sugars', 4.1, 'g'),
    evidence('VITC', 'Vitamin C', 26.2, 'mg'),
    evidence('FAPU', 'Polyunsaturated fat', 0.2, 'g'),
    evidence('CHOAVL', 'Carbohydrate', 12, 'g'),
    evidence('FIBT', 'Dietary fibre', 3.7, 'g'),
    evidence('FAT', 'Fat', 0.6, 'g'),
    evidence('FASAT', 'Saturated fat', 0.1, 'g'),
    evidence('ENERC_KCAL', 'Energy', 34, 'kcal'),
    evidence('PROT', 'Protein', 1.2, 'g'),
    evidence('FE', 'Iron', 0.7, 'mg'),
  ])

  assert.deepEqual(sections.map((section) => section.kind), ['facts', 'vitamins', 'minerals'])
  assert.deepEqual(
    sections[0].rows.map((row) => [row.observation.nutrient_code, row.label, row.depth]),
    [
      ['ENERC_KCAL', 'Calories', 0],
      ['FAT', 'Total fat', 0],
      ['FASAT', 'Saturated fat', 1],
      ['FAPU', 'Polyunsaturated fat', 1],
      ['CHOAVL', 'Total carbs', 0],
      ['FIBT', 'Dietary fibre', 1],
      ['SUGAR', 'Total sugars', 1],
      ['PROT', 'Protein', 0],
    ],
  )
})

test('immutable logging snapshots every available source fact, not only extended evidence', () => {
  const traceVitamin = evidence('VITA', 'Vitamin A', null, 'µg', 'trace')
  const selected = composerItemFromSelection({ food: food([traceVitamin]), quantity: 100, unit: 'g' }, 0, 'item-1')
  const entry = snapshotEntry(
    selected,
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
  )

  assert.ok(entry)
  assert.equal(entry.snapshot_nutrient_evidence?.find((row) => row.nutrient_code === 'SUGAR')?.value_per_100, 6)
  assert.equal(entry.snapshot_nutrient_evidence?.find((row) => row.nutrient_code === 'FIBT')?.value_per_100, 4)
  assert.equal(entry.snapshot_nutrient_evidence?.find((row) => row.nutrient_code === 'FASAT')?.value_per_100, 1)
  assert.equal(entry.snapshot_nutrient_evidence?.find((row) => row.nutrient_code === 'VITA')?.observation_status, 'trace')
})

test('Open Food Facts modifiers preserve trace and below-detection instead of importing zero', () => {
  const normalized = normalizeOpenFoodFactsProduct({
    status: 1,
    code: '3017620422003',
    product: {
      product_name: 'Modifier fixture',
      nutriments: {
        'energy-kcal_100g': 120,
        proteins_100g: 3,
        carbohydrates_100g: 20,
        fat_100g: 2,
        'vitamin-c_100g': 0,
        'vitamin-c_value': 0,
        'vitamin-c_unit': 'g',
        'vitamin-c_modifier': '~',
        'iron_100g': 0.0001,
        'iron_value': 0.0001,
        'iron_unit': 'g',
        'iron_modifier': '<',
        'calcium_100g': 0.01,
        'calcium_value': 0.01,
        'calcium_unit': 'g',
        'trans-fat_100g': 0,
        'trans-fat_value': 0,
        'trans-fat_unit': 'g',
      },
    },
  }, '3017620422003')

  assert.ok(normalized)
  const vitaminC = normalized.nutrient_evidence.find((row) => row.nutrient_code === 'VITC')
  const iron = normalized.nutrient_evidence.find((row) => row.nutrient_code === 'FE')
  const calcium = normalized.nutrient_evidence.find((row) => row.nutrient_code === 'CA')
  const transFat = normalized.nutrient_evidence.find((row) => row.nutrient_code === 'FATRN')
  assert.deepEqual([vitaminC?.observation_status, vitaminC?.value_per_100], ['trace', null])
  assert.match(vitaminC?.original_value_text ?? '', /~/)
  assert.deepEqual([iron?.observation_status, iron?.value_per_100], ['below_detection', null])
  assert.match(iron?.original_value_text ?? '', /^</)
  assert.deepEqual([calcium?.observation_status, calcium?.value_per_100], ['reported', 10])
  assert.deepEqual([transFat?.observation_status, transFat?.value_per_100], ['reported', 0])
})

test('observed nutrient averages scale immutable portions, isolate accounts, and disclose coverage', () => {
  const owner = '11111111-1111-4111-8111-111111111111'
  const other = '22222222-2222-4222-8222-222222222222'
  const meals = [
    { id: 'meal-a', user_id: owner, local_date: '2026-08-30' },
    { id: 'meal-b', user_id: owner, local_date: '2026-08-31' },
    { id: 'meal-c', user_id: owner, local_date: '2026-08-31' },
    { id: 'meal-other', user_id: other, local_date: '2026-08-31' },
  ] as LoggedMeal[]
  const entries = [
    { meal_id: 'meal-a', user_id: owner, equivalent_amount: 200, snapshot_nutrient_evidence: [evidence('VITC', 'Vitamin C', 50, 'mg'), evidence('FE', 'Iron', 2, 'mg')] },
    { meal_id: 'meal-b', user_id: owner, equivalent_amount: 100, snapshot_nutrient_evidence: [evidence('VITC', 'Vitamin C', 50, 'mg'), evidence('VITA', 'Vitamin A', null, 'µg', 'trace')] },
    { meal_id: 'meal-c', user_id: owner, equivalent_amount: 100, snapshot_nutrient_evidence: [] },
    { meal_id: 'meal-other', user_id: other, equivalent_amount: 10_000, snapshot_nutrient_evidence: [evidence('VITC', 'Vitamin C', 500, 'mg')] },
  ] as LoggedFoodEntry[]

  const summary = summarizeNutrientIntake({ meals, entries, userId: owner, anchorDate: '2026-08-31', period: 'week' })
  const vitaminC = summary.rows.find((row) => row.nutrient_code === 'VITC' && row.unit === 'mg')
  assert.equal(summary.calendarDays, 7)
  assert.equal(summary.observedDays, 2)
  assert.equal(summary.totalFoodEntries, 3)
  assert.equal(summary.evidenceFoodEntries, 2)
  assert.equal(summary.coverage, 2 / 3)
  assert.equal(vitaminC?.total, 150)
  assert.equal(vitaminC?.averagePerObservedDay, 75)
  assert.ok(!summary.rows.some((row) => row.nutrient_code === 'VITA'))
})

test('period bounds are local-date deterministic and incompatible units never merge', () => {
  assert.deepEqual(nutrientWindow('2026-09-01', 'day'), { start: '2026-09-01', end: '2026-09-01', calendarDays: 1 })
  assert.deepEqual(nutrientWindow('2026-09-01', 'week'), { start: '2026-08-26', end: '2026-09-01', calendarDays: 7 })
  assert.deepEqual(nutrientWindow('2026-09-15', 'month'), { start: '2026-09-01', end: '2026-09-15', calendarDays: 15 })

  const owner = '11111111-1111-4111-8111-111111111111'
  const summary = summarizeNutrientIntake({
    userId: owner,
    anchorDate: '2026-09-01',
    period: 'day',
    meals: [{ id: 'meal', user_id: owner, local_date: '2026-09-01' } as LoggedMeal],
    entries: [{
      meal_id: 'meal', user_id: owner, equivalent_amount: 100,
      snapshot_nutrient_evidence: [evidence('VITD', 'Vitamin D', 10, 'µg'), evidence('VITD', 'Vitamin D', 2, 'IU')],
    } as LoggedFoodEntry],
  })
  assert.equal(summary.rows.filter((row) => row.nutrient_code === 'VITD').length, 2)
})

test('storage and amount surfaces carry immutable nutrient evidence', async () => {
  const migration = await readFile(new URL('../supabase/migrations/044_nutrient_evidence_and_patterns.sql', import.meta.url), 'utf8')
  assert.match(migration, /nutrient_evidence jsonb/i)
  assert.match(migration, /snapshot_nutrient_evidence jsonb/i)
  assert.match(migration, /jsonb_typeof\([^)]*\) = 'array'/i)
  assert.match(migration, /log_structured_meal/i)
  assert.match(migration, /observation_status/i)
  assert.match(migration, /octet_length\(p_value::text\)\s*<=\s*65536/i)
  assert.match(migration, /jsonb_object_keys\([\s\S]*?observation/i)
  assert.match(migration, /original_value_text[\s\S]*?not between 0 and 180/i)
  assert.ok((migration.match(/batch\.status\s*=\s*'active'/gi) ?? []).length >= 3)

  const nativeAmount = await readFile(new URL('../ios/APEXNative/APEX/Features/Nutrition/FoodAmountSheet.swift', import.meta.url), 'utf8')
  const webAmount = await readFile(new URL('../src/components/food/MealComposer.tsx', import.meta.url), 'utf8')
  const nativePatterns = await readFile(new URL('../ios/APEXNative/APEX/Features/Nutrition/NutritionView.swift', import.meta.url), 'utf8')
  const webPatterns = await readFile(new URL('../src/pages/Nutrition.tsx', import.meta.url), 'utf8')
  const nativeTerms = await readFile(new URL('../ios/APEXNative/APEX/Features/Onboarding/InductionView.swift', import.meta.url), 'utf8')
  assert.match(nativeAmount, /food-nutrient-info/)
  assert.match(nativeAmount, /FoodNutrientDetailSheet/)
  assert.match(nativeAmount, /Image\(systemName: "info\.circle"\)/)
  assert.match(nativeAmount, /accessibilityIdentifier\("food-nutrient-info"\)/)
  assert.match(nativeAmount, /Nutrition facts/)
  assert.match(nativeAmount, /nutritionFactSections/)
  assert.doesNotMatch(nativeAmount, /Source and product notice/)
  assert.doesNotMatch(nativeAmount, /Original source value/)
  assert.doesNotMatch(nativeAmount, /case \.fats:\s*"drop\.fill"/)
  assert.match(webAmount, /food-nutrient-info/)
  assert.match(webAmount, /NutrientDetailDialog/)
  assert.match(webAmount, /event\.key === 'Escape'/)
  assert.match(webAmount, /event\.key === 'Tab'/)
  assert.match(webAmount, /setAttribute\('inert'/)
  assert.match(webAmount, /Nutrition facts/)
  assert.match(webAmount, /nutritionFactSections/)
  assert.doesNotMatch(webAmount, /Source and product notice/)
  assert.doesNotMatch(webAmount, /Original source value/)
  assert.doesNotMatch(webAmount, /title: 'Fat details'/)
  assert.match(nativeTerms, /Food and nutrition data/)
  assert.match(nativeTerms, /preserves unavailable and trace values instead of turning them into zero/)
  assert.doesNotMatch(nativePatterns, /prefix\(16\)/)
  assert.doesNotMatch(webPatterns, /slice\(0,\s*16\)/)
  assert.match(nativePatterns, /summary\.calendarDays/)
  assert.match(webPatterns, /summary\.calendarDays/)
  assert.match(nativePatterns, /accessibilityReduceMotion/)
  assert.match(webPatterns, /useReducedMotion/)
})

test('detailed corpus search prunes candidates through the existing trigram index before fuzzy scoring', async () => {
  const migration = await readFile(new URL('../supabase/migrations/044_nutrient_evidence_and_patterns.sql', import.meta.url), 'utf8')
  assert.match(migration, /create or replace function public\.food_corpus_search_catalog\s*\(/i)
  assert.match(migration, /search\.search_text like '%' \|\| query\.value \|\| '%'/i)
  assert.match(migration, /search\.search_text %> query\.value/i)
  assert.match(migration, /food_search_every_query_token_matches\(query\.value, normalized\.value\)/i)
})
