import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import test from 'node:test'
import { normalizeFoodCorpusSearchResult } from '../shared/foodCorpus.ts'

const edgeFunctionPath = new URL('../supabase/functions/food-lookup/index.ts', import.meta.url)
const activationMigrationPath = new URL(
  '../supabase/migrations/035_food_corpus_batch_activation.sql',
  import.meta.url,
)
const servingProjectionMigrationPath = new URL(
  '../supabase/migrations/037_food_corpus_serving_projection.sql',
  import.meta.url,
)

test('corpus search evidence maps to a decodable Food without inventing values', () => {
  const normalized = normalizeFoodCorpusSearchResult({
    record_id: '716ed368-cabf-5a42-b17e-72a20a8397bf',
    source_key: 'ca-cnf',
    source_record_id: '571',
    name: 'Chicken, broiler, giblets, raw',
    names_i18n: { en: 'Chicken, broiler, giblets, raw' },
    aliases: ['Broiler giblets'],
    brand: null,
    barcode: null,
    market: 'Canada',
    basis_kind: 'per_100g',
    preparation_state: 'raw',
    kcal: 124,
    protein_g: 17.88,
    carbs_g: 1.8,
    fat_g: 4.47,
    fibre_g: null,
    sugar_g: 0,
    saturated_fat_g: 1.36,
    salt_g: null,
    water_g: 74.87,
  })

  assert.ok(normalized)
  assert.equal(normalized.id, '716ed368-cabf-5a42-b17e-72a20a8397bf')
  assert.equal(normalized.provider_product_id, 'corpus:ca-cnf:571')
  assert.equal(normalized.nutrition_basis, 'per_100g')
  assert.equal(normalized.preparation_state, 'unknown')
  assert.equal(normalized.kcal_100, 124)
  assert.equal(normalized.fibre_100, null)
  assert.equal(normalized.sugar_100, 0)
  assert.equal(normalized.water_ml_100, 74.87, 'one gram of food water projects to one millilitre of hydration')
  assert.equal(normalized.water_basis, 'provider_reported')
  assert.equal(normalized.water_source_id, 'corpus:ca-cnf:571:WATER')
  assert.equal(normalized.confidence, 'provider_verified')
})

test('serving evidence uses its published gram weight without pretending the serving is 100 g', () => {
  const normalized = normalizeFoodCorpusSearchResult({
    record_id: '95bd0b7e-15ed-50e1-b8b0-a05616d9b6a5',
    source_key: 'wingstop-official',
    source_record_id: 'classic-bone-in-wings-atomic-1ea-39g',
    name: 'Wingstop Atomic Classic (Bone-In) Wings',
    names_i18n: { en: 'Wingstop Atomic Classic (Bone-In) Wings' },
    aliases: [],
    brand: 'Wingstop',
    barcode: null,
    market: 'United States',
    basis_kind: 'per_serving',
    basis_amount: 1,
    basis_unit: 'serving',
    source_metadata: { published_serving: '1ea (39g)' },
    preparation_state: 'as_sold',
    kcal: '90',
    protein_g: '10',
    carbs_g: '1',
    fat_g: '5',
    fibre_g: '0',
    sugar_g: '0',
    saturated_fat_g: '1.5',
    salt_g: null,
    water_g: null,
  })

  assert.ok(normalized)
  assert.equal(normalized.nutrition_basis, 'per_100g')
  assert.equal(normalized.serving_amount, 1)
  assert.equal(normalized.serving_unit, 'serving')
  assert.equal(normalized.serving_grams_or_ml, 39)
  assert.ok(Math.abs(normalized.kcal_100 * 0.39 - 90) < 0.000001)
  assert.ok(Math.abs(normalized.protein_100 * 0.39 - 10) < 0.000001)
  assert.equal(normalized.salt_100, null)
})

test('client food projection rejects unsupported or unweighted bases instead of mixing units', () => {
  assert.equal(
    normalizeFoodCorpusSearchResult({
      record_id: '716ed368-cabf-5a42-b17e-72a20a8397bf',
      source_key: 'example',
      source_record_id: 'one-serving',
      name: 'Serving-only evidence',
      names_i18n: {},
      aliases: [],
      brand: null,
      barcode: null,
      market: null,
      basis_kind: 'per_portion',
      basis_amount: 1,
      basis_unit: 'portion',
      source_metadata: {},
      preparation_state: null,
      kcal: 200,
      protein_g: null,
      carbs_g: null,
      fat_g: null,
      fibre_g: null,
      sugar_g: null,
      saturated_fat_g: null,
      salt_g: null,
      water_g: null,
    }),
    null,
  )
})

test('Food Lookup merges the local catalogue and canonical corpus before the public provider', () => {
  const edge = readFileSync(edgeFunctionPath, 'utf8')
  assert.match(edge, /food_corpus_search_catalog/)
  assert.match(edge, /normalizeFoodCorpusSearchResult/)
  assert.match(edge, /Promise\.all/)
  assert.match(
    edge,
    /admin\s*\.from\(['"]foods['"]\)\s*\.upsert/,
    'canonical search results must exist in foods before a meal can reference them',
  )
})

test('serving projection adds source basis evidence without replacing the original search RPC', () => {
  assert.equal(existsSync(servingProjectionMigrationPath), true)
  const migration = readFileSync(servingProjectionMigrationPath, 'utf8')
  assert.match(migration, /food_corpus_search_catalog_v2/i)
  assert.match(migration, /basis_amount/i)
  assert.match(migration, /basis_unit/i)
  assert.match(migration, /source_metadata/i)
  assert.doesNotMatch(migration, /drop\s+function|drop\s+table|truncate\s+table|delete\s+from/i)
})

test('only the active validated source batch is readable and searchable', () => {
  const migration = readFileSync(activationMigrationPath, 'utf8')
  assert.match(migration, /alter policy food_corpus_records_authenticated_read/i)
  assert.match(migration, /food_corpus_batches/i)
  assert.match(migration, /batch\.status = 'active'/i)
  assert.match(migration, /record\.batch_id = batch\.id/i)
  assert.doesNotMatch(migration, /\bdelete\s+from\b|\btruncate\b|\bdrop\s+(?:table|column)\b/i)
})

test('search ranks complete macro evidence ahead of source priority without deriving blanks', () => {
  const migration = readFileSync(activationMigrationPath, 'utf8')
  const completenessOrder = migration.indexOf(
    'when search.kcal is not null and search.protein_g is not null and search.carbs_g is not null and search.fat_g is not null then 0',
  )
  const sourcePriorityOrder = migration.indexOf('search.source_priority')

  assert.notEqual(completenessOrder, -1)
  assert.ok(completenessOrder < sourcePriorityOrder)
  assert.doesNotMatch(migration, /(?:kcal|protein_g|carbs_g|fat_g)\s*=\s*coalesce\([^)]*,\s*0\)/i)
})
