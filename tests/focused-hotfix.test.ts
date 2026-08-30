import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import { COMMON_FOODS } from '../src/data/foodSeeds.ts'
import { beginFoodSelection, calculatePortion, rankFoods } from '../src/lib/food.ts'

const source = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8')

test('Workout Insights follows Finished Workouts in every home and programme surface', () => {
  const surfaces = [
    source('../src/pages/SimpleHome.tsx'),
    source('../src/pages/WorkoutSection.tsx'),
    source('../ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift'),
    source('../ios/APEXNative/APEX/Features/Training/TrainingProgramView.swift'),
  ]

  for (const surface of surfaces) {
    const finished = surface.indexOf('CompletedWorkoutHistoryCards')
    const insights = surface.indexOf('WorkoutInsightsCard', finished)
    assert.ok(finished >= 0 && insights > finished, 'Finished Workouts must render before Workout Insights')
  }
})

test('Workout Insights exporters use a bright safe-area design with adaptive text', () => {
  const web = source('../src/lib/workoutInsightsCard.ts')
  const native = source('../ios/APEXNative/APEX/Features/Training/WorkoutInsightsCard.swift')

  assert.match(web, /fitText/)
  assert.match(web, /wrapText/)
  assert.match(web, /SAFE_INSET/)
  assert.match(web, /#fff(?:8|a|b|c|d|e|f)/i)
  assert.doesNotMatch(web, /slice\(0,\s*\d+\).*…/)

  assert.doesNotMatch(native, /minimumScaleFactor/)
  assert.match(native, /fixedSize\(horizontal:\s*false,\s*vertical:\s*true\)/)
  assert.doesNotMatch(native, /lineLimit\(1\)/)
  assert.match(native, /strokeBorder/)
  assert.match(native, /Color\(red:\s*0\.9\d/)
})

const officialFastFoods = [
  ['fsvo-v5.3:10675', 207, 529.92],
  ['burger-king-ch:whopper', 281.2, 640.1],
  ['burger-king-ch:big-king', 242.7, 613.6],
  ['burger-king-ch:cheeseburger', 124.5, 335.2],
  ['kfc-ch:double-crispy-classic', 167, 399],
  ['kfc-ch:classic-original', 205, 494],
  ['popeyes-ch:item_54262', 254, 831],
  ['popeyes-ch:item_55735', 308, 931],
] as const

test('Swiss fast-food references default to one verified whole-item serving and retain grams', () => {
  for (const [providerProductId, grams, portionKcal] of officialFastFoods) {
    const food = COMMON_FOODS.find((candidate) => candidate.provider_product_id === providerProductId)
    assert.ok(food, providerProductId)
    assert.equal(food.serving_unit, 'serving', providerProductId)
    assert.equal(food.serving_amount, 1, providerProductId)
    assert.equal(food.serving_grams_or_ml, grams, providerProductId)
    assert.deepEqual(beginFoodSelection(food), { food, quantity: 1, unit: 'serving' }, providerProductId)
    const portion = calculatePortion(food, 1, 'serving')
    assert.ok(portion, providerProductId)
    assert.ok(Math.abs(portion.kcal - portionKcal) < 1.1, providerProductId)
  }
})

test('regional Swiss fast-food names are searchable without an online provider', () => {
  assert.equal(rankFoods('cheeseburger royal', COMMON_FOODS, [], 'lunch')[0]?.provider_product_id, 'fsvo-v5.3:10675')
  assert.match(rankFoods('mcraclette', COMMON_FOODS, [], 'lunch')[0]?.provider_product_id ?? '', /mcraclette/)
  assert.equal(rankFoods('popeyes classic chicken sandwich', COMMON_FOODS, [], 'lunch')[0]?.provider_product_id, 'popeyes-ch:item_54262')
  assert.equal(rankFoods('burger king whopper', COMMON_FOODS, [], 'lunch')[0]?.provider_product_id, 'burger-king-ch:whopper')
})
