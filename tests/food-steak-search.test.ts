import assert from 'node:assert/strict'
import test from 'node:test'
import { COMMON_FOODS } from '../src/data/foodSeeds.ts'
import { rankFoods, mergeExtendedFoodResults } from '../src/lib/food.ts'
import { rankFoodLookupResults } from '../shared/foodSearchRanking.ts'

test('plain steak finds existing beef cuts offline, including raw and cooked choices', () => {
  const results = rankFoods('steak', COMMON_FOODS, [], 'dinner')
  assert.match(results[0]?.provider_product_id ?? '', /:beef-sirloin-/)
  for (const preparation of ['raw', 'cooked']) {
    assert.ok(results.some(food => food.provider_product_id === `apex-protocol:generic:beef-sirloin-${preparation}`))
  }
  assert.deepEqual(mergeExtendedFoodResults('steak', results, []).map(food => food.id), results.map(food => food.id))
})

test('provider aliases survive both web search filtering passes without admitting unrelated foods', () => {
  const remote = {
    ...COMMON_FOODS[0], id: 'remote-entrecote', provider_product_id: 'corpus:test:entrecote',
    name: 'Entrecôte', names_i18n: {}, search_aliases: ['steak', 'beef steak'],
  }
  const unrelated = { ...remote, id: 'unrelated', provider_product_id: 'corpus:test:extract', name: 'Beef extract', search_aliases: [] }
  const serverResults = rankFoodLookupResults('steak', [remote, unrelated])
  assert.equal(serverResults.length, 1)
  const widerResults = mergeExtendedFoodResults('steak', [], serverResults)
  assert.deepEqual(widerResults.map(food => food.id), ['remote-entrecote'])
  assert.deepEqual(mergeExtendedFoodResults('steak', [], widerResults).map(food => food.id), ['remote-entrecote'])
  assert.deepEqual(mergeExtendedFoodResults('steak', [], [unrelated]), [])
})

test('a small steak typo still finds beef, while a specific fish query stays specific', () => {
  assert.ok(rankFoods('steakk', COMMON_FOODS, [], 'dinner').some(food => food.provider_product_id?.includes(':beef-sirloin-')))
  const fish = rankFoods('swordfish steak', COMMON_FOODS, [], 'dinner')
  assert.ok(fish.length > 0)
  assert.ok(fish.every(food => !food.provider_product_id?.includes(':beef-sirloin-')))
})
