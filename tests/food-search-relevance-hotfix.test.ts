import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import test from 'node:test'

const migrationURL = new URL('../supabase/migrations/043_food_search_relevance.sql', import.meta.url)
const edgeURL = new URL('../supabase/functions/food-lookup/index.ts', import.meta.url)

test('production food search globally reranks catalog and corpus rows with strict token coverage', () => {
  assert.equal(existsSync(migrationURL), true, 'migration 043 must install the strict search RPCs')
  const migration = readFileSync(migrationURL, 'utf8')
  const edge = readFileSync(edgeURL, 'utf8')

  assert.match(migration, /create or replace function public\.search_food_catalog/i)
  assert.match(migration, /create or replace function public\.food_corpus_search_catalog/i)
  assert.match(migration, /every_query_token_matches/i)
  assert.doesNotMatch(migration, /similarity\([^)]*,\s*(?:input\.)?needle\)\s*>=\s*0\.18/i)
  assert.match(edge, /rankFoodLookupResults\(rawQuery,\s*\[\.\.\.catalogResults,\s*\.\.\.persistedCorpusResults\]/s)
  assert.ok(
    edge.indexOf('rankFoodLookupResults(rawQuery') < edge.indexOf('.slice(0, 25)'),
    'the edge function must globally rerank before applying its result limit',
  )
})

test('production migration adds distinct authoritative broccoli aliases without destructive data changes', () => {
  assert.equal(existsSync(migrationURL), true, 'migration 043 must exist')
  const migration = readFileSync(migrationURL, 'utf8')
  for (const term of ['Broccoli rabe', 'Rapini', 'Wild broccoli', 'Broccolini', 'Thin-stem broccoli', '170381', 'F001909']) {
    assert.match(migration, new RegExp(term, 'i'), term)
  }
  assert.doesNotMatch(migration, /\b(?:delete\s+from|truncate|drop\s+table)\b/i)
})
