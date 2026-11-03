import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { recommendActivityMode } from '../src/lib/personalProtocol.ts'

test('nutrition assessment and Burned ring share the owner/date activity resolver', () => {
  const ring = readFileSync('ios/APEXNative/APEX/Features/Nutrition/NutritionParityViews.swift', 'utf8')
  const nutrition = readFileSync('ios/APEXNative/APEX/Features/Nutrition/NutritionView.swift', 'utf8')
  const assessment = nutrition.slice(nutrition.indexOf('private struct BodyAssessmentCard'))
  assert.ok(ring.includes('NutritionRecordedActivity.resolve('), 'Ring uses the daily resolver')
  assert.ok(assessment.includes('NutritionRecordedActivity.resolve('), 'Assessment uses the daily resolver')
  assert.doesNotMatch(assessment, /language\.lowercased\(targets\.level\.title\)/)
  assert.match(assessment, /Your logged activity is %@\. Your plan target remains %d kcal\./)
  assert.doesNotMatch(assessment, /Today's energy model places you/)
})

test('web daily recommendation is informational and agrees with the June activity example', () => {
  const daily = recommendActivityMode('june', { steps: 8_000, activeCalories: 800, exerciseMinutes: 30 })
  assert.equal(daily.level, 'extra')
  assert.equal(daily.shouldAutoApply, false)
  assert.equal(recommendActivityMode('june', { steps: 7_000, activeCalories: 350, exerciseMinutes: 25 }).level, 'moderate')
})
