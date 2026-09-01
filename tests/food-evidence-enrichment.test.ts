import assert from 'node:assert/strict'
import test from 'node:test'
import * as foodModule from '../src/lib/food.ts'
import {
  mergeExtendedFoodResults,
  type FoodRecord,
} from '../src/lib/food.ts'
import type { NutrientEvidenceObservation } from '../src/lib/nutrientEvidence.ts'

type EnrichLocalFoodsWithNutrientEvidence = (
  localResults: FoodRecord[],
  serverResults: FoodRecord[],
) => FoodRecord[]

const proposedFoodModule = foodModule as typeof foodModule & {
  enrichLocalFoodsWithNutrientEvidence?: EnrichLocalFoodsWithNutrientEvidence
}

function enrichLocalFoodsWithNutrientEvidence(
  localResults: FoodRecord[],
  serverResults: FoodRecord[],
): FoodRecord[] {
  const implementation = proposedFoodModule.enrichLocalFoodsWithNutrientEvidence
  if (typeof implementation !== 'function') {
    assert.fail(
      'src/lib/food.ts must export enrichLocalFoodsWithNutrientEvidence(localResults: FoodRecord[], serverResults: FoodRecord[]): FoodRecord[]',
    )
  }
  return implementation(localResults, serverResults)
}

const vitaminC: NutrientEvidenceObservation = {
  nutrient_code: 'VITC',
  name: 'Vitamin C',
  value_per_100: 58.8,
  unit: 'mg',
  observation_status: 'measured',
  original_value_text: '58.8 mg/100 g',
  derivation_method: null,
  source_key: 'usda-fdc',
  source_reference: '167762',
}

const localVitaminC: NutrientEvidenceObservation = {
  ...vitaminC,
  value_per_100: 60,
  observation_status: 'reported',
  original_value_text: '60 mg/100 g',
  source_key: 'apex-curation',
  source_reference: 'strawberry-review-2026',
}

function localRawStrawberry(overrides: Partial<FoodRecord> = {}): FoodRecord {
  return {
    id: '10000000-0000-4000-8000-000000000046',
    owner_user_id: null,
    name: 'Strawberries, raw',
    names_i18n: { en: 'Strawberries, raw', de: 'Erdbeeren, roh' },
    brand: null,
    barcode: null,
    source: 'apex_cache',
    provider_product_id: 'apex-curated:usda-fdc-167762',
    external_image_url: 'https://images.example.test/local-strawberries.jpg',
    package_quantity: '250 g',
    nutrition_basis: 'per_100g',
    preparation_state: 'as_sold',
    kcal_100: 32,
    protein_100: 0.67,
    carbs_100: 7.68,
    fat_100: 0.3,
    fibre_100: 2,
    sugar_100: 4.89,
    saturated_fat_100: 0.015,
    salt_100: 0.0025,
    water_ml_100: 90.95,
    water_basis: 'provider_reported',
    water_source_id: 'local-curation:strawberry-water',
    serving_amount: 1,
    serving_unit: 'serving',
    serving_grams_or_ml: 150,
    piece_grams_or_ml: 12,
    provider_updated_at: '2026-08-01T00:00:00.000Z',
    confidence: 'provider_verified',
    nutrient_evidence: [],
    created_at: '2026-01-01T00:00:00.000Z',
    updated_at: '2026-08-01T00:00:00.000Z',
    ...overrides,
  }
}

function exactServerStrawberry(overrides: Partial<FoodRecord> = {}): FoodRecord {
  return {
    ...localRawStrawberry(),
    nutrient_evidence: [vitaminC],
    provider_updated_at: '2026-08-31T00:00:00.000Z',
    updated_at: '2026-08-31T00:00:00.000Z',
    ...overrides,
  }
}

test('an exact compatible server copy contributes its whole nutrient evidence', () => {
  const local = localRawStrawberry()
  const enriched = enrichLocalFoodsWithNutrientEvidence([local], [exactServerStrawberry()])[0]

  assert.deepEqual(enriched.nutrient_evidence, [vitaminC])
  assert.notEqual(enriched.nutrient_evidence, exactServerStrawberry().nutrient_evidence)
  assert.deepEqual(
    { id: enriched.id, name: enriched.name, names: enriched.names_i18n, calories: enriched.kcal_100, package: enriched.package_quantity, water: enriched.water_ml_100 },
    { id: local.id, name: local.name, names: local.names_i18n, calories: 32, package: '250 g', water: 90.95 },
  )
})

test('existing target evidence wins whole and donor rows never fill its gaps', () => {
  const enriched = enrichLocalFoodsWithNutrientEvidence(
    [localRawStrawberry({ nutrient_evidence: [localVitaminC] })],
    [exactServerStrawberry({ nutrient_evidence: [vitaminC, { ...vitaminC, nutrient_code: 'FE', name: 'Iron' }] })],
  )[0]

  assert.deepEqual(enriched.nutrient_evidence, [localVitaminC])
})

test('only identical non-empty public ID and provider ID authorize transfer', () => {
  const cases: Array<[string, FoodRecord, FoodRecord]> = [
    ['different food id', localRawStrawberry(), exactServerStrawberry({ id: '20000000-0000-4000-8000-000000000046' })],
    ['different provider id', localRawStrawberry(), exactServerStrawberry({ provider_product_id: 'apex-curated:other-strawberry' })],
    ['empty local provider id', localRawStrawberry({ provider_product_id: null }), exactServerStrawberry({ provider_product_id: null })],
    ['empty server provider id', localRawStrawberry(), exactServerStrawberry({ provider_product_id: null })],
    ['arbitrary similar remote row', localRawStrawberry(), exactServerStrawberry({ id: 'remote-search-result-1', provider_product_id: 'corpus:community-upload:strawberry-1', name: 'Fresh strawberry fruit, raw' })],
  ]

  for (const [label, local, server] of cases) {
    assert.deepEqual(enrichLocalFoodsWithNutrientEvidence([local], [server])[0].nutrient_evidence, [], label)
  }
})

test('basis preparation brand ownership and macro fingerprint mismatches fail closed', () => {
  const cases: Array<[string, FoodRecord, FoodRecord]> = [
    ['different basis', localRawStrawberry(), exactServerStrawberry({ nutrition_basis: 'per_100ml' })],
    ['different preparation', localRawStrawberry(), exactServerStrawberry({ preparation_state: 'cooked' })],
    ['branded local', localRawStrawberry({ brand: 'Example Berry Farm' }), exactServerStrawberry()],
    ['branded server', localRawStrawberry(), exactServerStrawberry({ brand: 'Example Berry Farm' })],
    ['private local', localRawStrawberry({ owner_user_id: '11111111-1111-4111-8111-111111111111', source: 'private' }), exactServerStrawberry()],
    ['non-curated local', localRawStrawberry({ source: 'open_food_facts' }), exactServerStrawberry()],
    ['barcode local', localRawStrawberry({ barcode: '7612345678901' }), exactServerStrawberry()],
    ['macro mismatch', localRawStrawberry(), exactServerStrawberry({ carbs_100: 27.7 })],
  ]

  for (const [label, local, server] of cases) {
    assert.deepEqual(enrichLocalFoodsWithNutrientEvidence([local], [server])[0].nutrient_evidence, [], label)
  }
})

test('mergeExtendedFoodResults enriches the local result before it removes the duplicate server copy', () => {
  const results = mergeExtendedFoodResults('strawberries raw', [localRawStrawberry()], [exactServerStrawberry()])

  assert.equal(results.length, 1)
  assert.equal(results[0].id, '10000000-0000-4000-8000-000000000046')
  assert.deepEqual(results[0].nutrient_evidence, [vitaminC])
})
