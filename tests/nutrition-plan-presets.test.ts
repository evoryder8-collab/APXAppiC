import assert from 'node:assert/strict'
import test from 'node:test'
import {
  computeTargets,
  goalPresetsForPlan,
  nutritionPlanContext,
  recommendedGoalForTrainingGoal,
  type NutritionPlanContext,
} from '../src/lib/nutrition.ts'
import type { Profile, TrainingGoal } from '../src/lib/types.ts'

const profile: Profile = {
  id: 'profile', user_id: 'user', persona: 'iulian', display_name: 'Test', sex: 'male',
  weight_kg: 80, body_fat_pct: 20, height_cm: 180, birthdate: '1990-01-01',
  activity_level: 'moderate', goal: 'maintain', target_kcal: null, target_protein_g: null,
  target_fat_g: null, target_carbs_g: null, training_time: '18:00', baseline_date: '2026-01-01',
  profile_note: '', seed_version: 1, calibration_k: 1, calibration_history: [], updated_at: '2026-01-01T00:00:00Z',
}

const expectedLabels: Record<TrainingGoal, string[]> = {
  rebuild: ['Light balance', 'Balanced fitness', 'Fuel progress'],
  muscle: ['Lean recomp', 'Maintain', 'Lean bulk'],
  fat_loss: ['Accelerated cut', 'Steady cut', 'Gentle cut'],
  strength: ['Strength recomp', 'Strength base', 'Power surplus'],
  endurance: ['Light fuel', 'Balanced fuel', 'High-volume fuel'],
}

test('each questionnaire goal resolves three honest plan-aware energy choices', () => {
  for (const [trainingGoal, labels] of Object.entries(expectedLabels) as [TrainingGoal, string[]][]) {
    const presets = goalPresetsForPlan({ trainingGoal, planWeeks: 12 })
    assert.deepEqual(presets.map((preset) => preset.label), labels)
    assert.deepEqual(presets.map((preset) => preset.goal), ['recomp', 'maintain', 'bulk'])
    assert.ok(presets.every((preset) => preset.explanation.length > 20))
    assert.ok(presets.every((preset) => preset.caution.length > 20))
  }
})

test('a short fat-loss block may be more assertive but never becomes crash-diet math', () => {
  const fourWeek = goalPresetsForPlan({ trainingGoal: 'fat_loss', planWeeks: 4 })
  const sixMonth = goalPresetsForPlan({ trainingGoal: 'fat_loss', planWeeks: 26 })

  assert.equal(fourWeek[0].factor, 0.80)
  assert.equal(sixMonth[0].factor, 0.86)
  assert.ok(fourWeek.every((preset) => preset.factor >= 0.80 && preset.factor < 1))
})

test('the selected plan preset drives calories while retaining the recovery floor', () => {
  const context: NutritionPlanContext = { trainingGoal: 'fat_loss', planWeeks: 8 }
  const result = computeTargets({ ...profile, goal: 'maintain' }, context)
  const factor = goalPresetsForPlan(context).find((preset) => preset.goal === 'maintain')!.factor

  assert.equal(result.kcal, Math.round(Math.max(result.activeBmr * 1.05, result.tdee * factor)))
  assert.equal(recommendedGoalForTrainingGoal('fat_loss'), 'maintain')
  assert.equal(recommendedGoalForTrainingGoal('muscle'), 'bulk')
  assert.equal(recommendedGoalForTrainingGoal('strength'), 'maintain')
})

test('a baseline-only first run keeps its mandatory goal usable without inventing a workout plan', () => {
  const context = nutritionPlanContext({ goal: 'fat_loss', plan_weeks: 12 })
  assert.deepEqual(context, { trainingGoal: 'fat_loss', planWeeks: 12 })

  const targets = computeTargets({ ...profile, goal: 'maintain' }, context)
  assert.ok(targets.kcal > 0)
  assert.ok(targets.protein_g > 0)
  assert.ok(targets.fat_g > 0)
  assert.ok(targets.carbs_g > 0)
})
