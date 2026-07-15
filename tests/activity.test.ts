import test from 'node:test'
import assert from 'node:assert/strict'
import {
  ACTIVITY_BY_ID,
  activityBmr,
  activityLevelForPal,
  calibrateActivityK,
  championshipPrefill,
  emptyActivityBlock,
  estimateActivityDay,
  netKcalForBlock,
  type ActivityBlock,
} from '../src/lib/activity.ts'
import { buildTargetMealPlan, computeTargets, type Targets } from '../src/lib/nutrition.ts'

const baseProfile = {
  weight_kg: 70,
  height_cm: 175,
  birthdate: '1992-07-25',
  sex: 'male' as const,
  body_fat_pct: 20,
  goal: 'recomp' as const,
  calibration_k: 1,
}

function closeTo(actual: number, expected: number, tolerance = 0.01): void {
  assert.ok(Math.abs(actual - expected) <= tolerance, `${actual} was not within ${tolerance} of ${expected}`)
}

function block(typeId: string, patch: Partial<ActivityBlock> = {}): ActivityBlock {
  const type = ACTIVITY_BY_ID.get(typeId)
  assert.ok(type, `Missing catalog type ${typeId}`)
  return { ...emptyActivityBlock(type, `${typeId}-test`), ...patch }
}

test('zero-block day starts at the 1.2 floor, maps sedentary, applies recomp, and respects safety floor', () => {
  const estimate = estimateActivityDay(baseProfile, [])
  const bmr = activityBmr(baseProfile)
  assert.equal(estimate.floorKcal, Math.round(bmr * 1.2))
  assert.equal(estimate.tdee, estimate.floorKcal)
  assert.equal(estimate.level, 'sedentary')
  assert.equal(estimate.targetKcal, Math.round(Math.max(bmr * 1.05, bmr * 1.2 * 0.89)))
  assert.ok(estimate.targetKcal >= estimate.safetyFloorKcal)
})

test('Quick Mode uses the selected multiplier before applying the goal factor', () => {
  const targets = computeTargets({ ...baseProfile, activity_level: 'sedentary' })
  const bmr = activityBmr(baseProfile)
  assert.equal(targets.tdee, Math.round(bmr * 1.2))
  assert.equal(targets.kcal, Math.round(Math.max(bmr * 1.05, targets.tdee * 0.89)))
})

test('a measured BMR becomes the authoritative source for TDEE and targets', () => {
  const targets = computeTargets({
    ...baseProfile,
    activity_level: 'moderate',
    goal: 'maintain',
    custom_bmr: 1840,
  })

  assert.equal(targets.bmrSource, 'custom')
  assert.equal(targets.activeBmr, 1840)
  assert.equal(targets.tdee, Math.round(1840 * 1.55))
  assert.equal(targets.kcal, targets.tdee)
  assert.notEqual(targets.bmrKatch, targets.activeBmr)
})

test('massage, supermarket, and incidental steps add only net energy above the floor', () => {
  const blocks = [
    block('massage-session', { quantity: 2, durationMin: 60 }),
    block('supermarket-trip', { quantity: 1, durationMin: 25 }),
    block('incidental-steps', { steps: 8000 }),
  ]
  closeTo(netKcalForBlock(blocks[0], 70), 392)
  closeTo(netKcalForBlock(blocks[1], 70), 52.5)
  closeTo(netKcalForBlock(blocks[2], 70), 308)
  const estimate = estimateActivityDay(baseProfile, blocks)
  assert.equal(estimate.rawBlockKcal, 753)
  assert.ok(Math.abs(estimate.tdee - (estimate.floorKcal + estimate.rawBlockKcal)) <= 1)
  assert.equal(estimate.level, activityLevelForPal(estimate.tdee / estimate.bmr))
})

test('run distance and discounted watch calories dedupe with max instead of sum', () => {
  const run = block('jog-run', { distanceKm: 5, watchKcal: 420 })
  closeTo(netKcalForBlock(run, 70), 350)
  assert.notEqual(netKcalForBlock(run, 70), 686)
})

test('championship prefill reaches extra active without manual blocks', () => {
  let index = 0
  const estimate = estimateActivityDay(baseProfile, championshipPrefill(() => `event-${index++}`))
  assert.equal(estimate.level, 'extra')
  assert.ok(estimate.pal >= 2)
})

test('goal changes flex calories and carbs while protein remains pinned', () => {
  const blocks = [block('full-gym', { durationMin: 60 })]
  const recomp = estimateActivityDay({ ...baseProfile, goal: 'recomp' }, blocks)
  const maintain = estimateActivityDay({ ...baseProfile, goal: 'maintain' }, blocks)
  const bulk = estimateActivityDay({ ...baseProfile, goal: 'bulk' }, blocks)
  assert.equal(recomp.proteinG, maintain.proteinG)
  assert.equal(maintain.proteinG, bulk.proteinG)
  assert.ok(recomp.targetKcal < maintain.targetKcal)
  assert.ok(maintain.targetKcal < bulk.targetKcal)
  assert.ok(recomp.carbsG < maintain.carbsG)
  assert.ok(maintain.carbsG < bulk.carbsG)

  const meals = [
    { id: 'oats', user_id: 'user', time: '08:00', name: 'Oat Jar', foods: 'Oats', kcal: 700, protein_g: 45, fat_g: 18, carbs_g: 95, full_days_only: false, sort_order: 0 },
    { id: 'dinner', user_id: 'user', time: '18:30', name: 'Dinner', foods: 'Dinner', kcal: 700, protein_g: 50, fat_g: 20, carbs_g: 120, full_days_only: false, sort_order: 1 },
    { id: 'casein', user_id: 'user', time: '21:00', name: 'Casein shake', foods: 'Casein', kcal: 180, protein_g: 35, fat_g: 2, carbs_g: 4, full_days_only: false, sort_order: 2 },
  ]
  const asTargets = (estimate: typeof recomp): Targets => ({
    bmrMifflin: estimate.bmr,
    bmrKatch: estimate.bmr,
    tdee: estimate.tdee,
    kcal: estimate.targetKcal,
    protein_g: estimate.proteinG,
    fat_g: estimate.fatG,
    carbs_g: estimate.carbsG,
    water_l: 2.75,
  })
  const recompMeals = buildTargetMealPlan(meals, asTargets(recomp), 'Sedentary')
  const bulkMeals = buildTargetMealPlan(meals, asTargets(bulk), 'Very active')
  assert.equal(
    recompMeals.reduce((sum, meal) => sum + meal.protein_g, 0),
    bulkMeals.reduce((sum, meal) => sum + meal.protein_g, 0),
  )
  assert.notEqual(recompMeals[0].foods, bulkMeals[0].foods)
  assert.match(recompMeals[0].portionNote, /oats .* instead of 80 g/i)
})

test('two weeks of stable weight and higher observed intake nudges calibration upward', () => {
  const days = Array.from({ length: 14 }, (_, index) => ({
    date: `2026-07-${String(index + 1).padStart(2, '0')}`,
    intakeKcal: 2300,
    morningWeightKg: 70,
    predictedTdee: 2100,
  }))
  const result = calibrateActivityK(days, 1)
  assert.equal(result.eligible, true)
  assert.equal(result.observedTdee, 2300)
  assert.equal(result.predictedTdee, 2100)
  closeTo(result.nextK, 1 + 0.2 * (200 / 2100), 0.0001)
  assert.ok(result.nextK <= 1.15)
})

test('the same shared activity scales to each viewing profile weight', () => {
  const massage = block('massage-session', { quantity: 1, durationMin: 60 })
  const seventyKg = netKcalForBlock(massage, 70)
  const fiftyEightKg = netKcalForBlock(massage, 58)
  closeTo(seventyKg, 196)
  closeTo(fiftyEightKg, 162.4)
  assert.ok(seventyKg > fiftyEightKg)
})

test('catalog MET edits are honored without changing application code', () => {
  const massage = block('massage-session', { quantity: 1, durationMin: 60 })
  const original = ACTIVITY_BY_ID.get('massage-session')!
  const editedCatalog = new Map(ACTIVITY_BY_ID)
  editedCatalog.set('massage-session', { ...original, met: 5 })
  closeTo(netKcalForBlock(massage, 70, editedCatalog), 266)
})

test('PAL thresholds map exactly to the intelligent labels', () => {
  assert.equal(activityLevelForPal(1.39), 'sedentary')
  assert.equal(activityLevelForPal(1.4), 'light')
  assert.equal(activityLevelForPal(1.55), 'moderate')
  assert.equal(activityLevelForPal(1.75), 'very')
  assert.equal(activityLevelForPal(2), 'extra')
})
