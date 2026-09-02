import assert from 'node:assert/strict'
import { Buffer } from 'node:buffer'
import test from 'node:test'
import { COMMON_FOODS } from '../src/data/foodSeeds.ts'
import { mergeExtendedFoodResults, type FoodRecord } from '../src/lib/food.ts'
import {
  naturalFoodEvidenceBundle,
  overlayNaturalFoodEvidence,
  type NaturalFoodEvidenceBundle,
} from '../src/lib/naturalFoodEvidence.ts'
import {
  nutritionFactSections,
  type NutrientEvidenceObservation,
} from '../src/lib/nutrientEvidence.ts'

const strawberryID = '10000000-0000-4000-8000-000000000046'
const oatsID = '10000000-0000-4000-8000-000000000001'
const chickenID = '10000000-0000-4000-8000-000000000013'

function catalogueFood(id: string): FoodRecord {
  const food = COMMON_FOODS.find((candidate) => candidate.id === id)
  assert.ok(food, `missing catalogue fixture ${id}`)
  return structuredClone(food)
}

const explicitEvidence: NutrientEvidenceObservation = {
  nutrient_code: 'VITC', name: 'Explicit vitamin C', value_per_100: 60, unit: 'mg',
  observation_status: 'reported', original_value_text: '60', derivation_method: null,
  source_key: 'apex-curation', source_reference: 'explicit:strawberry',
}

test('canonical resource contains 111 unique reviewed targets across all nine categories', () => {
  assert.equal(naturalFoodEvidenceBundle.schema_version, 1)
  assert.equal(naturalFoodEvidenceBundle.targets.length, 111)
  assert.equal(new Set(naturalFoodEvidenceBundle.targets.map((entry) => (
    `${entry.target.id}\u0000${entry.target.provider_product_id}`
  ))).size, 111)
  assert.deepEqual([...new Set(naturalFoodEvidenceBundle.targets.map((entry) => entry.category))].sort(), [
    'egg', 'fish_shellfish', 'fruit', 'grain_starch', 'legume',
    'meat_poultry', 'nut_seed', 'plain_dairy', 'vegetable_leaf',
  ])
  for (const entry of naturalFoodEvidenceBundle.targets) {
    assert.ok(entry.evidence.length > 0 && entry.evidence.length <= 96, entry.target.name)
    assert.ok(Buffer.byteLength(JSON.stringify(entry.evidence), 'utf8') <= 65_536, entry.target.name)
    assert.equal(new Set(entry.evidence.map((row) => row.source_key)).size, 1, entry.target.name)
    assert.equal(entry.evidence.every((row) => row.source_reference !== null && row.source_reference.length > 0), true, entry.target.name)
  }
})

test('strawberry has source-backed Vitamins and Minerals while oats retains Frida biotin and iodine', () => {
  const strawberry = naturalFoodEvidenceBundle.targets.find((entry) => entry.target.id === strawberryID)
  assert.ok(strawberry)
  assert.deepEqual(
    strawberry.evidence.find((row) => row.nutrient_code === 'VITC'),
    {
      derivation_method: null,
      name: 'Vitamin C, total ascorbic acid', nutrient_code: 'VITC',
      observation_status: 'measured', original_value_text: '58.8',
      source_key: 'usda-sr-legacy', source_reference: 'food_nutrient:1303228',
      unit: 'mg', value_per_100: 58.8,
    },
  )
  assert.equal(strawberry.evidence.some((row) => row.nutrient_code === 'FE'), true)
  assert.deepEqual(nutritionFactSections(strawberry.evidence).map((section) => section.kind), [
    'facts', 'vitamins', 'minerals',
  ])

  const oats = naturalFoodEvidenceBundle.targets.find((entry) => entry.target.id === oatsID)
  assert.ok(oats)
  assert.equal(oats.donor.source_key, 'dk-frida')
  assert.equal(oats.donor.source_record_id, '59')
  assert.equal(oats.evidence.find((row) => row.nutrient_code === 'VITB7')?.value_per_100, 19)
  assert.equal(oats.evidence.find((row) => row.nutrient_code === 'I')?.value_per_100, 0.5)
})

test('reviewed representatives cover every natural-food category with whole official evidence', () => {
  const representatives = new Map([
    ['fruit', strawberryID],
    ['vegetable_leaf', '20000000-0000-4000-8000-000000000332'],
    ['grain_starch', oatsID],
    ['legume', '20000000-0000-4000-8000-000000000032'],
    ['nut_seed', '10000000-0000-4000-8000-000000000012'],
    ['plain_dairy', '10000000-0000-4000-8000-000000000006'],
    ['egg', '10000000-0000-4000-8000-000000000030'],
    ['meat_poultry', chickenID],
    ['fish_shellfish', '20000000-0000-4000-8000-000000000077'],
  ])
  for (const [category, id] of representatives) {
    const entry = naturalFoodEvidenceBundle.targets.find((candidate) => candidate.target.id === id)
    assert.ok(entry, category)
    assert.equal(entry.category, category)
    assert.equal(entry.evidence.length > 0, true)
    assert.equal(new Set(entry.evidence.map((row) => row.source_key)).size, 1)
  }
})

test('Foundation chicken energy uses nutrient 2047 regardless of staged row order', () => {
  const chicken = naturalFoodEvidenceBundle.targets.find((entry) => entry.target.id === chickenID)
  assert.ok(chicken)
  const energy = chicken.evidence.find((row) => row.nutrient_code === 'ENERC_KCAL')
  assert.equal(energy?.name, 'Energy (Atwater General Factors)')
  assert.equal(energy?.value_per_100, 106.034)
  assert.equal(energy?.source_reference, 'food_nutrient:33295327')
})

test('exact target alias receives one cloned whole evidence record before duplicate removal', () => {
  const local = catalogueFood(strawberryID)
  const entry = naturalFoodEvidenceBundle.targets.find((candidate) => candidate.target.id === strawberryID)
  assert.ok(entry)
  const enriched = overlayNaturalFoodEvidence([local])[0]

  assert.deepEqual(enriched.nutrient_evidence, entry.evidence)
  assert.notEqual(enriched.nutrient_evidence, entry.evidence)
  assert.notEqual(enriched.nutrient_evidence?.[0], entry.evidence[0])
  assert.equal(enriched.name, local.name)
  assert.equal(enriched.kcal_100, local.kcal_100)

  const merged = mergeExtendedFoodResults('strawberries', [local], [{ ...local, name: 'Server copy' }])
  assert.equal(merged.length, 1)
  assert.deepEqual(merged[0].nutrient_evidence, entry.evidence)
})

test('search merge prefers an exact compatible server record over bundled fallback evidence', () => {
  const local = catalogueFood(strawberryID)
  const serverEvidence: NutrientEvidenceObservation = {
    ...explicitEvidence,
    name: 'Server vitamin C',
    value_per_100: 61,
    original_value_text: '61',
    source_key: 'server-official',
    source_reference: 'server:strawberry',
  }
  const server: FoodRecord = {
    ...local,
    name: 'Exact server strawberry',
    nutrient_evidence: [serverEvidence],
  }

  const merged = mergeExtendedFoodResults('strawberries', [local], [server])

  assert.equal(merged.length, 1)
  assert.deepEqual(merged[0].nutrient_evidence, [serverEvidence])
})

test('search merge preserves explicit local evidence ahead of server and bundled evidence', () => {
  const local = catalogueFood(strawberryID)
  local.nutrient_evidence = [explicitEvidence]
  const server: FoodRecord = {
    ...local,
    nutrient_evidence: [{ ...explicitEvidence, source_reference: 'server:strawberry' }],
  }

  assert.deepEqual(
    mergeExtendedFoodResults('strawberries', [local], [server])[0].nutrient_evidence,
    [explicitEvidence],
  )
})

test('exact corpus donor alias is independently authorized against its stored donor fingerprint', () => {
  const entry = naturalFoodEvidenceBundle.targets.find((candidate) => candidate.target.id === strawberryID)
  assert.ok(entry)
  const alias = entry.aliases.find((candidate) => candidate.kind === 'donor')
  assert.ok(alias)
  const donor: FoodRecord = {
    ...catalogueFood(strawberryID),
    id: alias.id,
    name: 'Publisher donor display name may vary',
    provider_product_id: alias.provider_product_id,
    nutrition_basis: alias.nutrition_basis,
    preparation_state: alias.preparation_state,
    ...alias.fingerprint,
    nutrient_evidence: [],
  }
  assert.deepEqual(overlayNaturalFoodEvidence([donor])[0].nutrient_evidence, entry.evidence)
})

test('existing target evidence wins whole and is never gap-filled from the bundle', () => {
  const target = catalogueFood(strawberryID)
  target.nutrient_evidence = [explicitEvidence]
  assert.deepEqual(overlayNaturalFoodEvidence([target])[0].nutrient_evidence, [explicitEvidence])
})

test('runtime overlay fails closed for privacy, brand, barcode, basis, preparation, identity, and macro drift', () => {
  const target = catalogueFood(strawberryID)
  const cases: Array<[string, FoodRecord]> = [
    ['owner', { ...target, owner_user_id: '11111111-1111-4111-8111-111111111111' }],
    ['brand', { ...target, brand: 'Nearby berry brand' }],
    ['barcode', { ...target, barcode: '7612345678901' }],
    ['source', { ...target, source: 'private' }],
    ['basis', { ...target, nutrition_basis: 'per_100ml' }],
    ['preparation', { ...target, preparation_state: 'cooked' }],
    ['id', { ...target, id: '20000000-0000-4000-8000-000000000046' }],
    ['provider', { ...target, provider_product_id: 'apex-curated:near-neighbour' }],
    ['missing provider', { ...target, provider_product_id: null }],
    ['kcal', { ...target, kcal_100: 35 }],
    ['protein', { ...target, protein_100: 1 }],
    ['carbs', { ...target, carbs_100: 9 }],
    ['fat', { ...target, fat_100: 0.6 }],
    ['nonfinite', { ...target, kcal_100: Number.NaN }],
  ]
  for (const [label, candidate] of cases) {
    assert.deepEqual(overlayNaturalFoodEvidence([candidate])[0].nutrient_evidence ?? [], [], label)
  }
})

test('a matching name alone never authorizes a rejected near-neighbour', () => {
  const strawberry = catalogueFood(strawberryID)
  const nearNeighbour = {
    ...strawberry,
    id: '99999999-9999-4999-8999-999999999999',
    provider_product_id: 'apex-curated:not-reviewed',
    name: strawberry.name,
  }
  assert.deepEqual(overlayNaturalFoodEvidence([nearNeighbour])[0].nutrient_evidence ?? [], [])
})

test('malformed or oversized resource evidence fails closed at the runtime boundary', () => {
  const target = catalogueFood(strawberryID)
  const malformed = structuredClone(naturalFoodEvidenceBundle)
  const entry = malformed.targets.find((candidate) => candidate.target.id === strawberryID)
  assert.ok(entry)
  entry.evidence[0].source_reference = null
  assert.deepEqual(
    overlayNaturalFoodEvidence([target], malformed as NaturalFoodEvidenceBundle)[0].nutrient_evidence ?? [],
    [],
  )

  const oversized = structuredClone(naturalFoodEvidenceBundle)
  const oversizedEntry = oversized.targets.find((candidate) => candidate.target.id === strawberryID)
  assert.ok(oversizedEntry)
  oversizedEntry.evidence[0].original_value_text = 'x'.repeat(66_000)
  assert.deepEqual(overlayNaturalFoodEvidence([target], oversized)[0].nutrient_evidence ?? [], [])
})

test('runtime evidence accepts only values inside the inclusive zero-to-one-trillion domain', () => {
  const target = catalogueFood(strawberryID)
  for (const invalidValue of [-1, 1_000_000_000_001]) {
    const malformed = structuredClone(naturalFoodEvidenceBundle)
    const entry = malformed.targets.find((candidate) => candidate.target.id === strawberryID)
    assert.ok(entry)
    entry.evidence[0].value_per_100 = invalidValue
    assert.deepEqual(
      overlayNaturalFoodEvidence([target], malformed)[0].nutrient_evidence ?? [],
      [],
    )
  }

  for (const boundaryValue of [0, 1_000_000_000_000]) {
    const valid = structuredClone(naturalFoodEvidenceBundle)
    const entry = valid.targets.find((candidate) => candidate.target.id === strawberryID)
    assert.ok(entry)
    entry.evidence[0].value_per_100 = boundaryValue
    assert.equal(
      overlayNaturalFoodEvidence([target], valid)[0].nutrient_evidence?.[0].value_per_100,
      boundaryValue,
    )
  }
})

test('a resource with more than 256 targets is rejected before valid targets are indexed', () => {
  const target = catalogueFood(strawberryID)
  const excessive = structuredClone(naturalFoodEvidenceBundle)
  const filler = structuredClone(excessive.targets.find((entry) => entry.target.id !== strawberryID))
  assert.ok(filler)
  while (excessive.targets.length <= 256) excessive.targets.push(structuredClone(filler))

  assert.deepEqual(overlayNaturalFoodEvidence([target], excessive)[0].nutrient_evidence ?? [], [])
})

test('a resource larger than four MiB is rejected before valid targets are indexed', () => {
  const target = catalogueFood(strawberryID)
  const oversized = structuredClone(naturalFoodEvidenceBundle)
  oversized.sources = [{ key: 'oversized-padding', padding: 'x'.repeat(4_194_305) }]

  assert.deepEqual(overlayNaturalFoodEvidence([target], oversized)[0].nutrient_evidence ?? [], [])
})
