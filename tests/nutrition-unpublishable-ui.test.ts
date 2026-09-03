import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const sourceRoot = new URL('../src/', import.meta.url)
const source = (path: string): string => readFileSync(new URL(path, sourceRoot), 'utf8')

type PrescriptionInput = {
  isPublishable: boolean
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
}

test('the presentation boundary withholds blocked or invalid prescriptions', async () => {
  const presentation = await import('../src/lib/nutritionTargetPresentation.ts')
  const publishableNutritionPrescription = (presentation as typeof presentation & {
    publishableNutritionPrescription?: (targets: PrescriptionInput) => Omit<PrescriptionInput, 'isPublishable'> | null
  }).publishableNutritionPrescription

  assert.equal(typeof publishableNutritionPrescription, 'function')
  if (!publishableNutritionPrescription) return

  const valid = { isPublishable: true, kcal: 2_200, protein_g: 150, carbs_g: 250, fat_g: 70 }
  assert.deepEqual(publishableNutritionPrescription(valid), {
    kcal: 2_200,
    protein_g: 150,
    carbs_g: 250,
    fat_g: 70,
  })

  assert.equal(publishableNutritionPrescription({ ...valid, isPublishable: false }), null)
  assert.equal(publishableNutritionPrescription({ ...valid, kcal: 0 }), null)
  assert.equal(publishableNutritionPrescription({ ...valid, protein_g: Number.NaN }), null)
})

test('Nutrition and SimpleHome consume only the nullable published prescription', () => {
  const nutrition = source('pages/Nutrition.tsx')
  const simple = source('pages/SimpleHome.tsx')

  for (const page of [nutrition, simple]) {
    assert.match(page, /publishableNutritionPrescription\(targets\)/)
    assert.match(page, /<NutritionTargetStatus targets=\{targets\}/)
    assert.doesNotMatch(page, /targets\.(?:kcal|protein_g|carbs_g|fat_g)/)
  }

  assert.match(nutrition, /<ActualFoodTracker[\s\S]*?target=\{nutritionPrescription\}/)
  assert.match(simple, /<NutritionGlance[\s\S]*?target=\{nutritionPrescription\}/)
})

test('the glance hides unavailable goals without hiding real zero observations', () => {
  const glance = source('components/food/NutritionGlance.tsx')
  const tracker = source('components/food/ActualFoodTracker.tsx')

  assert.match(glance, /target: MealTotals \| null/)
  assert.match(tracker, /target: MealTotals \| null/)
  assert.match(glance, /t\('Target unavailable'\)/)
  assert.match(glance, /Math\.round\(consumed\.kcal\)/)
  assert.match(glance, /Math\.round\(burnedKcal\)/)
  assert.match(glance, /goal == null/)
})

test('Nutrition does not turn a blocked quick target into a zero TDEE display', () => {
  const nutrition = source('pages/Nutrition.tsx')
  const activities = source('components/TodaysActivities.tsx')

  assert.match(nutrition, /quickTdee=\{targets\.isPublishable \? quickTargets\.tdee : null\}/)
  assert.match(activities, /quickTdee: number \| null/)
  assert.match(activities, /t\('Target unavailable'\)/)
})
