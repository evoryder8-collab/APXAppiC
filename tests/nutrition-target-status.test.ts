import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { UI_TRANSLATIONS } from '../src/lib/translations.ts'

const sourceRoot = new URL('../src/', import.meta.url)
const source = (path: string): string => readFileSync(new URL(path, sourceRoot), 'utf8')

const authoredStatusCopy = [
  'Target source',
  'Resting energy',
  'Profile-calculated target',
  'Bespoke authored target',
  'Mifflin-St Jeor estimate',
  'Katch-McArdle estimate',
  'Measured by indirect calorimetry',
  'Earlier entered resting-energy value',
  'Bespoke resting-energy reference',
  'Review recommended',
  'Target unavailable',
  'Add a valid birthdate before APEX calculates an energy target.',
  'Automatic energy targets are available only for adults aged 19 or older.',
  'Review your age, height, weight, sex and activity details before using this target.',
  'Review the resting-energy value before using this target.',
  'A DEXA-estimated BMR is saved as context; APEX used the calculated resting-energy formula instead.',
  'Confirm that this earlier resting-energy value came from indirect calorimetry, or clear it to use the calculated formula.',
  'This calorie target cannot fit the protected protein and fat minimums. Review the inputs before using it.',
] as const

test('target provenance and every review reason have an explicit presentation', async () => {
  const presentation = await import('../src/lib/nutritionTargetPresentation.ts')

  assert.equal(presentation.targetProvenanceLabel('calculated'), 'Profile-calculated target')
  assert.equal(presentation.targetProvenanceLabel('bespoke_authored'), 'Bespoke authored target')
  assert.equal(presentation.restingEnergyProvenanceLabel({ bmrSource: 'mifflin', targetProvenance: 'calculated' }), 'Mifflin-St Jeor estimate')
  assert.equal(presentation.restingEnergyProvenanceLabel({ bmrSource: 'katch', targetProvenance: 'calculated' }), 'Katch-McArdle estimate')
  assert.equal(presentation.restingEnergyProvenanceLabel({ bmrSource: 'custom', targetProvenance: 'measured_indirect_calorimetry' }), 'Measured by indirect calorimetry')
  assert.equal(presentation.restingEnergyProvenanceLabel({ bmrSource: 'custom', targetProvenance: 'legacy_user_entered' }), 'Earlier entered resting-energy value')
  assert.equal(presentation.restingEnergyProvenanceLabel({ bmrSource: 'custom', targetProvenance: 'bespoke_authored' }), 'Bespoke resting-energy reference')

  const expectedReasons = new Set([
    'invalid_birthdate',
    'age_below_19',
    'implausible_demographics',
    'implausible_bmr',
    'dexa_estimated_bmr_ignored',
    'legacy_bmr_needs_review',
    'macro_infeasible',
  ])
  assert.deepEqual(new Set(Object.keys(presentation.TARGET_REVIEW_REASON_LABELS)), expectedReasons)
})

test('target provenance and review copy is authored in every offered web language', () => {
  for (const copy of authoredStatusCopy) {
    assert.ok(UI_TRANSLATIONS[copy]?.ro, `Romanian: ${copy}`)
    assert.ok(UI_TRANSLATIONS[copy]?.th, `Thai: ${copy}`)
  }
})

test('Nutrition and Settings display provenance and review reasons', () => {
  const nutrition = source('pages/Nutrition.tsx')
  const settings = source('pages/Settings.tsx')
  const status = source('components/nutrition/NutritionTargetStatus.tsx')

  assert.match(nutrition, /<NutritionTargetStatus targets=\{targets\} translate=\{tx\}/)
  assert.match(settings, /<NutritionTargetStatus targets=\{targets\} translate=\{t\}/)
  assert.match(status, /targets\.reviewReasons\.map/)
  assert.match(status, /targetProvenanceLabel\(targets\.targetProvenance\)/)
  assert.match(status, /restingEnergyProvenanceLabel\(targets\)/)
})

test('unpublishable targets fail closed at every web goal selector', () => {
  const nutrition = source('pages/Nutrition.tsx')
  const simple = source('pages/SimpleHome.tsx')
  const picker = source('components/nutrition/NutritionGoalPresetPicker.tsx')

  assert.match(nutrition, /<NutritionGoalPresetPicker[\s\S]*?disabled=\{!targets\.isPublishable\}/)
  assert.match(simple, /<NutritionGoalPresetPicker[\s\S]*?disabled=\{!targets\.isPublishable\}/)
  assert.match(picker, /disabled\?: boolean/)
  assert.match(picker, /disabled=\{disabled\}/)
  assert.match(picker, /if \(!disabled\) onSelect\(preset\.goal\)/)
})
