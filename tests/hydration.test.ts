import { strict as assert } from 'node:assert'
import { test } from 'node:test'
import {
  estimateWaterContent,
  hydrationBreakdown,
  portionWater,
  waterDisclosure,
  waterByDifference,
} from '../src/lib/hydration.ts'
import { COMMON_FOODS } from '../src/data/foodSeeds.ts'

test('curated catalogue foods all carry a water value', () => {
  const missing = COMMON_FOODS.filter((food) => food.water_ml_100 == null)
  assert.deepEqual(missing.map((food) => food.name), [])
  const missingProvenance = COMMON_FOODS.filter((food) => !food.water_basis)
  assert.deepEqual(missingProvenance.map((food) => food.name), [])
})

test('curated water values match the researched references', () => {
  const expected: Record<string, number> = {
    'Rolled oats': 8.7,            // Swiss FSVO, Oat flakes
    'Broccoli, cooked': 90.4,      // Swiss FSVO, Broccoli, steamed
    'Chicken breast, cooked': 65.3, // USDA FDC 171477
    'Avocado, raw': 73.2,          // USDA FDC 171705
    'Walnuts': 4.0,                // Swiss FSVO, Walnut
  }
  for (const [name, water] of Object.entries(expected)) {
    const food = COMMON_FOODS.find((value) => value.name === name)
    assert.ok(food, `${name} missing from the catalogue`)
    assert.equal(food?.water_ml_100, water, name)
  }
})

test('water content and macros never sum past the whole food', () => {
  for (const food of COMMON_FOODS) {
    const solids = (food.protein_100 ?? 0) + (food.carbs_100 ?? 0) + (food.fat_100 ?? 0)
    assert.ok(
      solids + (food.water_ml_100 ?? 0) <= 104,
      `${food.name}: ${solids} g of macros plus ${food.water_ml_100} g water exceeds 100 g`,
    )
  }
})

test('a dense food derives little water and a lean one derives much', () => {
  const oil = waterByDifference({ protein_100: 0, carbs_100: 0, fat_100: 100 })
  assert.ok(oil != null && oil <= 1, `oil should be dry, got ${oil}`)
  const cucumber = waterByDifference({ protein_100: 0.7, carbs_100: 3.6, fat_100: 0.1 })
  assert.ok(cucumber != null && cucumber > 90, `cucumber should be wet, got ${cucumber}`)
})

test('a named whole food beats derivation, and a powder is never named', () => {
  assert.equal(estimateWaterContent({ name: 'Cucumber, raw' })?.basis, 'name')
  assert.equal(estimateWaterContent({ name: 'Watermelon' })?.water_ml_100, 91.5)
  /* "Milk protein powder" must not be treated as milk. */
  const powder = estimateWaterContent({
    name: 'Milk protein powder', protein_100: 80, carbs_100: 6, fat_100: 1.5,
  })
  assert.equal(powder?.basis, 'difference')
  assert.ok((powder?.water_ml_100 ?? 100) < 15)
})

test('a measured value always wins', () => {
  const measured = estimateWaterContent({ name: 'Cucumber', protein_100: 0.7, carbs_100: 3.6, fat_100: 0.1 }, 95.2)
  assert.equal(measured?.water_ml_100, 95.2)
  assert.equal(measured?.basis, 'measured')
})

test('only measured water is presented as exact', () => {
  assert.deepEqual(waterDisclosure('measured'), { isEstimated: false, prefix: '', label: 'Measured water' })
  for (const basis of ['provider_reported', 'reference', 'name', 'difference', 'legacy', null]) {
    assert.deepEqual(
      waterDisclosure(basis),
      { isEstimated: true, prefix: '≈', label: 'Estimated water' },
      String(basis),
    )
  }
})

test('portion water scales with the amount eaten', () => {
  assert.equal(portionWater(90.4, 200), 180.8)
  assert.equal(portionWater(null, 200), null)
  assert.equal(portionWater(90.4, 0), 0)
})

test('food water is reported beside drinks, never inside them', () => {
  const breakdown = hydrationBreakdown(1.5, 620)
  assert.equal(breakdown.drinkL, 1.5, 'the drink figure must not absorb food water')
  assert.equal(breakdown.foodL, 0.62)
  assert.equal(breakdown.totalL, 2.12)
})
