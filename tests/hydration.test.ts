import { strict as assert } from 'node:assert'
import { test } from 'node:test'
import {
  estimateWaterContent,
  hydrationBreakdown,
  inferredHydrationTargetMode,
  portionWater,
  resolveHydrationTarget,
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

test('automatic hydration target combines body size with a bounded exercise allowance', () => {
  const target = resolveHydrationTarget({
    sex: 'male',
    weightKg: 80,
    mode: 'automatic',
    customTargetML: 3_800,
    plannedExerciseMinutes: 60,
    recordedExerciseMinutes: 0,
    activeCalories: 0,
    dateRelation: 'today',
    localHour: 10,
  })

  assert.deepEqual(target, {
    mode: 'automatic',
    targetML: 3_250,
    baselineML: 2_850,
    exerciseAdjustmentML: 400,
    wearableAdjustmentML: 0,
  })
})

test('automatic baseline stays inside authoritative sex-specific total-water references', () => {
  assert.equal(resolveHydrationTarget({ sex: 'female', weightKg: 60 }).baselineML, 2_150)
  assert.equal(resolveHydrationTarget({ sex: 'female', weightKg: 35 }).baselineML, 2_000)
  assert.equal(resolveHydrationTarget({ sex: 'male', weightKg: 200 }).baselineML, 3_700)
})

test('late wearable calories are only a small capped corroborating signal', () => {
  const base = {
    sex: 'male' as const,
    weightKg: 80,
    plannedExerciseMinutes: 60,
    recordedExerciseMinutes: 45,
    dateRelation: 'today' as const,
  }
  const beforeCutoff = resolveHydrationTarget({ ...base, activeCalories: 1_600, localHour: 14 })
  const afterCutoff = resolveHydrationTarget({ ...base, activeCalories: 800, localHour: 16 })
  const muchHigherCalories = resolveHydrationTarget({ ...base, activeCalories: 1_600, localHour: 16 })

  assert.equal(beforeCutoff.wearableAdjustmentML, 0)
  assert.equal(afterCutoff.wearableAdjustmentML, 200)
  assert.equal(muchHigherCalories.wearableAdjustmentML, 200)
  assert.equal(afterCutoff.exerciseAdjustmentML, 400, 'planned and recorded exercise must not be summed twice')
  assert.equal(afterCutoff.targetML, 3_450)
})

test('late steps can corroborate activity when HealthKit has no calorie sample', () => {
  const moderate = resolveHydrationTarget({
    sex: 'female', weightKg: 60, steps: 12_000, activeCalories: 0,
    dateRelation: 'today', localHour: 16,
  })
  const high = resolveHydrationTarget({
    sex: 'female', weightKg: 60, steps: 18_000, activeCalories: 0,
    dateRelation: 'today', localHour: 16,
  })

  assert.equal(moderate.wearableAdjustmentML, 100)
  assert.equal(high.wearableAdjustmentML, 200)
})

test('an exact custom target wins without hidden activity changes', () => {
  const target = resolveHydrationTarget({
    sex: 'male', weightKg: 100, mode: 'custom', customTargetML: 3_830,
    plannedExerciseMinutes: 120, recordedExerciseMinutes: 120,
    activeCalories: 2_000, dateRelation: 'past', localHour: 23,
  })
  assert.deepEqual(target, {
    mode: 'custom', targetML: 3_830, baselineML: 3_830,
    exerciseAdjustmentML: 0, wearableAdjustmentML: 0,
  })
})

test('legacy targets preserve genuine custom choices but migrate the old default to automatic', () => {
  assert.equal(inferredHydrationTargetMode(null, 2_750), 'automatic')
  assert.equal(inferredHydrationTargetMode(undefined, 3_800), 'custom')
  assert.equal(inferredHydrationTargetMode('automatic', 3_800), 'automatic')
})
