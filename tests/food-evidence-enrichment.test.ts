import assert from 'node:assert/strict'
import test from 'node:test'
import {
  enrichLocalFoodsWithNutrientEvidence,
  mergeExtendedFoodResults,
  type FoodRecord,
} from '../src/lib/food.ts'
import type { NutrientEvidenceObservation } from '../src/lib/nutrientEvidence.ts'

const vitaminC: NutrientEvidenceObservation = {
  nutrient_code: 'VITC', name: 'Vitamin C', value_per_100: 58.8, unit: 'mg',
  observation_status: 'measured', original_value_text: '58.8 mg/100 g',
  derivation_method: null, source_key: 'usda-fdc', source_reference: '167762',
}
const iron: NutrientEvidenceObservation = {
  nutrient_code: 'FE', name: 'Iron', value_per_100: 0.41, unit: 'mg',
  observation_status: 'measured', original_value_text: '0.41 mg/100 g',
  derivation_method: null, source_key: 'usda-fdc', source_reference: '167762',
}
const localVitaminC: NutrientEvidenceObservation = {
  ...vitaminC, value_per_100: 60, observation_status: 'reported',
  original_value_text: '60 mg/100 g', source_key: 'apex-curation', source_reference: 'strawberry-review-2026',
}
const donorEvidence = [vitaminC, iron]

function localFood(overrides: Partial<FoodRecord> = {}): FoodRecord {
  return {
    id: '10000000-0000-4000-8000-000000000046', owner_user_id: null,
    name: 'Strawberries, raw', names_i18n: { en: 'Strawberries, raw', de: 'Erdbeeren, roh' },
    brand: null, barcode: null, source: 'apex_cache', provider_product_id: 'apex-curated:usda-fdc-167762',
    external_image_url: 'https://images.example.test/local-strawberries.jpg', package_quantity: '250 g',
    nutrition_basis: 'per_100g', preparation_state: 'as_sold',
    kcal_100: 32, protein_100: 0.67, carbs_100: 7.68, fat_100: 0.3,
    fibre_100: 2, sugar_100: 4.89, saturated_fat_100: 0.015, salt_100: 0.0025,
    water_ml_100: 90.95, water_basis: 'provider_reported', water_source_id: 'local-curation:strawberry-water',
    serving_amount: 1, serving_unit: 'serving', serving_grams_or_ml: 150, piece_grams_or_ml: 12,
    provider_updated_at: '2026-08-01T00:00:00.000Z', confidence: 'provider_verified', nutrient_evidence: [],
    created_at: '2026-01-01T00:00:00.000Z', updated_at: '2026-08-01T00:00:00.000Z',
    ...overrides,
  }
}

function serverFood(overrides: Partial<FoodRecord> = {}): FoodRecord {
  return {
    ...localFood(), name: 'USDA composition entry 167762', names_i18n: { en: 'USDA composition entry 167762' },
    nutrient_evidence: donorEvidence, provider_updated_at: '2026-08-31T00:00:00.000Z',
    updated_at: '2026-08-31T00:00:00.000Z', ...overrides,
  }
}

function assertNoTransfer(label: string, local: FoodRecord, server: FoodRecord): void {
  assert.deepEqual(enrichLocalFoodsWithNutrientEvidence([local], [server])[0].nutrient_evidence, [], label)
}

test('an exact compatible server copy clones its whole evidence array despite a different display name', () => {
  const local = localFood()
  const donor = serverFood()
  const enriched = enrichLocalFoodsWithNutrientEvidence([local], [donor])[0]

  assert.deepEqual(enriched.nutrient_evidence, donor.nutrient_evidence)
  assert.notEqual(enriched.nutrient_evidence, donor.nutrient_evidence)
  assert.notEqual(enriched.nutrient_evidence?.[0], donor.nutrient_evidence?.[0])
  assert.equal(donor.name, 'USDA composition entry 167762')
  assert.equal(enriched.name, local.name)
  assert.deepEqual(enriched.names_i18n, local.names_i18n)
  assert.equal(enriched.kcal_100, local.kcal_100)
  assert.equal(enriched.package_quantity, local.package_quantity)
})

test('existing target evidence wins whole and donor rows never fill gaps', () => {
  const enriched = enrichLocalFoodsWithNutrientEvidence(
    [localFood({ nutrient_evidence: [localVitaminC] })], [serverFood()],
  )[0]
  assert.deepEqual(enriched.nutrient_evidence, [localVitaminC])
})

test('empty and whitespace public and provider identifiers reject transfer on either side', () => {
  const cases: Array<[string, FoodRecord, FoodRecord]> = [
    ['empty matching ids', localFood({ id: '' }), serverFood({ id: '' })],
    ['whitespace matching ids', localFood({ id: '  ' }), serverFood({ id: '  ' })],
    ['missing matching providers', localFood({ provider_product_id: null }), serverFood({ provider_product_id: null })],
    ['empty matching providers', localFood({ provider_product_id: '' }), serverFood({ provider_product_id: '' })],
    ['whitespace matching providers', localFood({ provider_product_id: '  ' }), serverFood({ provider_product_id: '  ' })],
    ['empty remote id', localFood(), serverFood({ id: '' })],
    ['empty remote provider', localFood(), serverFood({ provider_product_id: '' })],
  ]
  for (const [label, local, server] of cases) assertNoTransfer(label, local, server)
})

test('identity and public-curated eligibility reject target and remote ownership barcode source and brand mismatches', () => {
  const donor = serverFood()
  const cases: Array<[string, FoodRecord, FoodRecord]> = [
    ['different id', localFood(), serverFood({ id: '20000000-0000-4000-8000-000000000046' })],
    ['different provider', localFood(), serverFood({ provider_product_id: 'apex-curated:other' })],
    ['target ownership', localFood({ owner_user_id: '11111111-1111-4111-8111-111111111111' }), donor],
    ['remote ownership', localFood(), serverFood({ owner_user_id: '11111111-1111-4111-8111-111111111111' })],
    ['target barcode', localFood({ barcode: '7612345678901' }), donor],
    ['remote barcode', localFood(), serverFood({ barcode: '7612345678901' })],
    ['target source', localFood({ source: 'open_food_facts' }), donor],
    ['remote source', localFood(), serverFood({ source: 'open_food_facts' })],
    ['target brand', localFood({ brand: 'Example Berry Farm' }), donor],
    ['remote brand', localFood(), serverFood({ brand: 'Example Berry Farm' })],
  ]
  for (const [label, local, server] of cases) assertNoTransfer(label, local, server)
})

test('basis and preparation matrix rejects raw cooked dry cooked and oil no-oil links', () => {
  const cases: Array<[string, FoodRecord, FoodRecord]> = [
    ['basis', localFood(), serverFood({ nutrition_basis: 'per_100ml' })],
    ['raw cooked', localFood({ preparation_state: 'as_sold' }), serverFood({ preparation_state: 'cooked' })],
    ['dry cooked', localFood({ preparation_state: 'dry' }), serverFood({ preparation_state: 'cooked' })],
    ['oil no-oil', localFood({ name: 'Potatoes, cooked without oil', preparation_state: 'cooked' }), serverFood({ name: 'Potatoes, cooked in oil', preparation_state: 'prepared' })],
  ]
  for (const [label, local, server] of cases) assertNoTransfer(label, local, server)
})

test('every macro fingerprint field independently rejects missing non-finite and materially different values', () => {
  const cases: Array<[string, FoodRecord, FoodRecord]> = [
    ['missing target kcal', localFood({ kcal_100: null }), serverFood()],
    ['missing remote protein', localFood(), serverFood({ protein_100: null })],
    ['missing target carbs', localFood({ carbs_100: null }), serverFood()],
    ['missing remote fat', localFood(), serverFood({ fat_100: null })],
    ['nonfinite target kcal', localFood({ kcal_100: Number.NaN }), serverFood()],
    ['nonfinite remote protein', localFood(), serverFood({ protein_100: Number.POSITIVE_INFINITY })],
    ['nonfinite target carbs', localFood({ carbs_100: Number.NEGATIVE_INFINITY }), serverFood()],
    ['nonfinite remote fat', localFood(), serverFood({ fat_100: Number.NaN })],
    ['kcal mismatch', localFood(), serverFood({ kcal_100: 35 })],
    ['protein mismatch', localFood(), serverFood({ protein_100: 1 })],
    ['carbs mismatch', localFood(), serverFood({ carbs_100: 9 })],
    ['fat mismatch', localFood(), serverFood({ fat_100: 0.6 })],
  ]
  for (const [label, local, server] of cases) assertNoTransfer(label, local, server)
})

test('exact inclusive two-percent macro fingerprint boundaries transfer for every field', () => {
  const cases: Array<[string, FoodRecord, FoodRecord]> = [
    ['kcal', localFood({ kcal_100: 100 }), serverFood({ kcal_100: 102 })],
    ['protein', localFood({ protein_100: 10 }), serverFood({ protein_100: 10.2 })],
    ['carbs', localFood({ carbs_100: 10 }), serverFood({ carbs_100: 10.2 })],
    ['fat', localFood({ fat_100: 10 }), serverFood({ fat_100: 10.2 })],
  ]
  for (const [label, local, server] of cases) {
    assert.deepEqual(enrichLocalFoodsWithNutrientEvidence([local], [server])[0].nutrient_evidence, donorEvidence, label)
  }
})

test('exact inclusive absolute macro fingerprint floors transfer for every field', () => {
  const cases: Array<[string, FoodRecord, FoodRecord]> = [
    ['kcal', localFood(), serverFood({ kcal_100: 33 })],
    ['protein', localFood(), serverFood({ protein_100: 0.72 })],
    ['carbs', localFood(), serverFood({ carbs_100: 7.73 })],
    ['fat', localFood(), serverFood({ fat_100: 0.35 })],
  ]
  for (const [label, local, server] of cases) {
    assert.deepEqual(enrichLocalFoodsWithNutrientEvidence([local], [server])[0].nutrient_evidence, donorEvidence, label)
  }
})

test('ambiguous multiple compatible donors fail closed', () => {
  assert.deepEqual(enrichLocalFoodsWithNutrientEvidence([localFood()], [serverFood(), serverFood()])[0].nutrient_evidence, [])
})

test('mergeExtendedFoodResults enriches the local result before it removes the duplicate server copy', () => {
  const local = localFood()
  const donor = serverFood()
  const results = mergeExtendedFoodResults('strawberries raw', [local], [donor])
  assert.equal(results.length, 1)
  assert.equal(results[0].id, local.id)
  assert.equal(results[0].name, local.name)
  assert.deepEqual(results[0].nutrient_evidence, donorEvidence)
})
