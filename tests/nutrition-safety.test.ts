import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import {
  ACTIVITY_BY_ID,
  emptyActivityBlock,
  estimateActivityDay,
  type ActivityBlock,
  type ActivityEstimate,
} from '../src/lib/activity.ts'
import * as activityPolicy from '../src/lib/activity.ts'
import {
  ACTIVITY_MULTIPLIERS,
  GOALS,
  buildTargetMealPlan,
  computeTargets,
  goalPresetForPlan,
  goalPresetsForPlan,
  nutritionPlanContext,
  type Targets,
} from '../src/lib/nutrition.ts'
import * as nutritionPolicy from '../src/lib/nutrition.ts'
import { personalTargetFor } from '../src/lib/personalProtocol.ts'
import type { ActivityLevel, Goal, Profile, TrainingGoal } from '../src/lib/types.ts'

const asOf = new Date('2026-09-02T12:00:00Z')
const nativeSettingsSource = readFileSync(
  new URL('../ios/APEXNative/APEX/Features/Settings/SettingsView.swift', import.meta.url),
  'utf8',
)
const nutritionPageSource = readFileSync(
  new URL('../src/pages/Nutrition.tsx', import.meta.url),
  'utf8',
)
const simpleHomeSource = readFileSync(
  new URL('../src/pages/SimpleHome.tsx', import.meta.url),
  'utf8',
)

function profile(overrides: Partial<Profile> = {}): Profile {
  return {
    id: 'profile', user_id: 'user', persona: 'iulian', display_name: 'Test', sex: 'male',
    weight_kg: 80, body_fat_pct: null, height_cm: 180, birthdate: '1990-01-01',
    activity_level: 'moderate', goal: 'maintain', target_kcal: null, target_protein_g: null,
    target_fat_g: null, target_carbs_g: null, training_time: '18:00', baseline_date: '2026-01-01',
    profile_note: '', seed_version: 1, calibration_k: 1, calibration_history: [], updated_at: '2026-01-01T00:00:00Z',
    ...overrides,
  }
}

function activityBlock(typeId: string, patch: Partial<ActivityBlock> = {}): ActivityBlock {
  const type = ACTIVITY_BY_ID.get(typeId)
  assert.ok(type)
  return { ...emptyActivityBlock(type, `${typeId}-safety`), ...patch }
}

test('blocked targets never produce a portioned meal prescription', () => {
  const blocked = computeTargets(profile({ birthdate: 'not-a-date' }), undefined, { asOf })
  const meals = [{
    id: 'meal', user_id: 'user', time: '12:00', name: 'Lunch', foods: 'Rice and chicken',
    kcal: 700, protein_g: 45, fat_g: 20, carbs_g: 85, full_days_only: false, sort_order: 0,
  }]

  assert.equal(blocked.isPublishable, false)
  assert.deepEqual(buildTargetMealPlan(meals, blocked), [])
})

test('persisted training-goal aliases and malformed plan durations normalize at the nutrition boundary', () => {
  assert.deepEqual(
    nutritionPlanContext({ goal: 'general', plan_weeks: 6 }),
    { trainingGoal: 'rebuild', planWeeks: 12 },
  )
  assert.deepEqual(
    nutritionPlanContext({ goal: 'hypertrophy', plan_weeks: Number.NaN }),
    { trainingGoal: 'muscle', planWeeks: 12 },
  )
  assert.deepEqual(
    nutritionPlanContext({ goal: 'future_goal', plan_weeks: 999 }),
    { trainingGoal: 'rebuild', planWeeks: 12 },
  )
  assert.deepEqual(
    nutritionPlanContext({ goal: 'constructor', plan_weeks: 12 }),
    { trainingGoal: 'rebuild', planWeeks: 12 },
  )
})

test('preset lookup is total for every canonical goal and fails safely for corrupt values', () => {
  const goals: TrainingGoal[] = ['rebuild', 'muscle', 'fat_loss', 'strength', 'endurance']
  for (const trainingGoal of goals) {
    const presets = goalPresetsForPlan({ trainingGoal, planWeeks: 12 })
    assert.deepEqual(presets.map(({ goal }) => goal), ['recomp', 'maintain', 'bulk'])
    assert.ok(presets.every(({ factor }) => Number.isFinite(factor) && factor > 0))
  }

  assert.equal(
    goalPresetsForPlan({ trainingGoal: 'corrupt' as TrainingGoal, planWeeks: 7 as never })[1].goal,
    'maintain',
  )
  assert.equal(goalPresetForPlan('corrupt' as Goal, undefined).goal, 'maintain')
})

test('prototype property names are rejected as persisted nutrition enum values', () => {
  for (const candidate of [
    profile({ goal: 'constructor' as Goal }),
    profile({ activity_level: 'toString' as Profile['activity_level'] }),
  ]) {
    const result = computeTargets(candidate, undefined, { asOf })

    assert.equal(result.reviewState, 'blocked')
    assert.equal(result.isPublishable, false)
    assert.deepEqual([result.kcal, result.protein_g, result.fat_g, result.carbs_g], [0, 0, 0, 0])
    assert.ok([result.bmrMifflin, result.tdee, result.activeBmr].every(Number.isFinite))
  }
})

test('activity labels fall back safely for unsupported and prototype property names', () => {
  const labelFor = (nutritionPolicy as unknown as {
    activityLevelLabel?: (value: unknown, fallback?: string) => string
  }).activityLevelLabel
  assert.equal(typeof labelFor, 'function')
  if (!labelFor) return

  assert.equal(labelFor('moderate'), 'Moderately active')
  assert.equal(labelFor('future_activity'), 'Adaptive')
  assert.equal(labelFor('constructor'), 'Adaptive')
  assert.equal(labelFor('__proto__', 'Target unavailable'), 'Target unavailable')
})

test('nutrition screens consume activity labels through the safe runtime boundary', () => {
  for (const source of [nutritionPageSource, simpleHomeSource]) {
    assert.doesNotMatch(source, /ACTIVITY_MULTIPLIERS\[profile\.activity_level\]/)
    assert.match(source, /activityLevelLabel\(profile\.activity_level/)
  }
})

test('activity selection keeps only rows owned by the active profile on the selected date', () => {
  const selectOwned = (activityPolicy as unknown as {
    activityLogsForOwnerDate?: <T extends { user_id: string; date: string }>(
      logs: readonly T[],
      ownerId: string,
      date: string,
    ) => T[]
  }).activityLogsForOwnerDate
  assert.equal(typeof selectOwned, 'function')
  if (!selectOwned) return

  const rows = [
    { user_id: 'active', date: '2026-09-03', kcal: 300 },
    { user_id: 'foreign', date: '2026-09-03', kcal: 900 },
    { user_id: 'active', date: '2026-09-02', kcal: 500 },
  ]
  assert.deepEqual(selectOwned(rows, 'active', '2026-09-03'), [rows[0]])
})

test('nutrition screens select activity rows through the owner-and-date boundary', () => {
  assert.match(
    nutritionPageSource,
    /activityLogsForOwnerDate\(data\.activity_logs, profile\?\.user_id, selectedLogDate\)/,
  )
  assert.match(
    simpleHomeSource,
    /activityLogsForOwnerDate\(data\.activity_logs, profile\?\.user_id, selectedDate\)/,
  )
})

test('non-finite runtime nutrition factors cannot produce a publishable target', () => {
  const originalActivityFactor = ACTIVITY_MULTIPLIERS.moderate.factor
  const originalGoalFactor = GOALS.maintain.factor
  try {
    for (const corrupt of [
      () => { ACTIVITY_MULTIPLIERS.moderate.factor = Number.NaN },
      () => { GOALS.maintain.factor = Number.POSITIVE_INFINITY },
    ]) {
      corrupt()
      const result = computeTargets(profile(), undefined, { asOf })

      assert.equal(result.reviewState, 'blocked')
      assert.equal(result.isPublishable, false)
      assert.ok([result.kcal, result.protein_g, result.fat_g, result.carbs_g, result.tdee].every(Number.isFinite))
      ACTIVITY_MULTIPLIERS.moderate.factor = originalActivityFactor
      GOALS.maintain.factor = originalGoalFactor
    }
  } finally {
    ACTIVITY_MULTIPLIERS.moderate.factor = originalActivityFactor
    GOALS.maintain.factor = originalGoalFactor
  }
})

test('generic Lean Recomp, Maintain and Lean Bulk use 90%, 100% and 105% of TDEE', () => {
  const base = profile({ custom_bmr: 1558, activity_level: 'sedentary' })
  const recomp = computeTargets({ ...base, goal: 'recomp' }, undefined, { asOf })
  const maintain = computeTargets({ ...base, goal: 'maintain' }, undefined, { asOf })
  const bulk = computeTargets({ ...base, goal: 'bulk' }, undefined, { asOf })

  assert.deepEqual([recomp.tdee, maintain.tdee, bulk.tdee], [1870, 1870, 1870])
  assert.deepEqual([recomp.kcal, maintain.kcal, bulk.kcal], [1683, 1870, 1964])
})

test('standard demographic matrix remains finite, formula-exact and macro-feasible', () => {
  const cases: Array<{
    label: string
    subject: Profile
    expected: [number, number, number, number, number]
  }> = [
    {
      label: 'male moderate activity',
      subject: profile({ sex: 'male', birthdate: '1996-01-01', weight_kg: 80, height_cm: 180 }),
      expected: [1780, 2759, 152, 84, 348],
    },
    {
      label: 'older female low activity',
      subject: profile({ sex: 'female', birthdate: '1956-01-01', weight_kg: 60, height_cm: 160, activity_level: 'sedentary' }),
      expected: [1089, 1307, 96, 48, 122],
    },
    {
      label: 'high-BMI female low activity',
      subject: profile({ sex: 'female', birthdate: '1981-01-01', weight_kg: 160, height_cm: 165, activity_level: 'sedentary' }),
      expected: [2245, 2694, 256, 128, 129],
    },
    {
      label: 'measured resting energy',
      subject: profile({
        weight_kg: 70, custom_bmr: 1683, custom_bmr_source: 'indirect_calorimetry',
      }),
      expected: [1683, 2609, 133, 80, 339],
    },
  ]

  for (const { label, subject, expected } of cases) {
    const result = computeTargets(subject, undefined, { asOf })
    assert.deepEqual(
      [result.activeBmr, result.kcal, result.protein_g, result.fat_g, result.carbs_g],
      expected,
      label,
    )
    const macroKcal = result.protein_g * 4 + result.fat_g * 9 + result.carbs_g * 4
    assert.ok(macroKcal <= result.kcal, `${label}: macros must not exceed the target`)
    assert.ok(Number.isFinite(result.tdee), `${label}: TDEE must remain finite`)
    assert.equal(result.isPublishable, true, label)
  }
})

test('standard calculator exposes target provenance and review state', () => {
  const calculated = computeTargets(profile(), undefined, { asOf })
  const measured = computeTargets(profile({
    custom_bmr: 1683,
    custom_bmr_source: 'indirect_calorimetry',
  }), undefined, { asOf })
  const legacy = computeTargets(profile({ custom_bmr: 1683 }), undefined, { asOf })
  const dexaEstimate = computeTargets(profile({
    custom_bmr: 1683,
    custom_bmr_source: 'dexa_report_estimate',
  }), undefined, { asOf })

  assert.deepEqual(
    [calculated.targetProvenance, calculated.reviewState, calculated.isPublishable],
    ['calculated', 'ready', true],
  )
  assert.deepEqual(
    [measured.targetProvenance, measured.reviewState, measured.activeBmr],
    ['measured_indirect_calorimetry', 'ready', 1683],
  )
  assert.deepEqual(
    [legacy.targetProvenance, legacy.reviewState, legacy.activeBmr],
    ['legacy_user_entered', 'review_recommended', 1683],
  )
  assert.equal(dexaEstimate.targetProvenance, 'calculated')
  assert.equal(dexaEstimate.reviewState, 'review_recommended')
  assert.notEqual(dexaEstimate.activeBmr, 1683)
  assert.ok(dexaEstimate.reviewReasons.includes('dexa_estimated_bmr_ignored'))
})

test('measured resting-energy submission preserves the last valid value until source and range are valid', () => {
  const validate = (nutritionPolicy as typeof nutritionPolicy & {
    validateMeasuredRestingEnergySubmission?: (input: {
      current: { custom_bmr: number | null; custom_bmr_source: string | null }
      draft: string
      selected_source: string
    }) => unknown
  }).validateMeasuredRestingEnergySubmission
  assert.equal(typeof validate, 'function')
  if (!validate) return

  const current = { custom_bmr: 1720, custom_bmr_source: 'dexa_report_estimate' }
  assert.deepEqual(validate({ current, draft: '799', selected_source: 'indirect_calorimetry' }), {
    status: 'rejected',
    reason: 'out_of_range',
    message: 'Enter a resting-energy value from 800 to 4000 kcal/day.',
    current,
  })
  assert.deepEqual(validate({ current, draft: '1683', selected_source: '' }), {
    status: 'rejected',
    reason: 'source_required',
    message: 'Choose indirect calorimetry only when that test measured this value.',
    current,
  })
  assert.deepEqual(validate({ current, draft: '1683', selected_source: 'dexa_report_estimate' }), {
    status: 'rejected',
    reason: 'source_required',
    message: 'Choose indirect calorimetry only when that test measured this value.',
    current,
  })
  assert.deepEqual(validate({ current, draft: '1683.4', selected_source: 'indirect_calorimetry' }), {
    status: 'accepted',
    next: {
      custom_bmr: 1683,
      custom_bmr_source: 'indirect_calorimetry',
    },
  })
})

test('native measured resting-energy editing rejects invalid drafts without clearing the saved value', () => {
  assert.match(nativeSettingsSource, /private func saveMeasuredBMR\(\)/)
  assert.match(
    nativeSettingsSource,
    /guard let value = Double\(measuredBMRDraft\),\s*RestingEnergyPolicy\.validRange\.contains\(value\) else \{[\s\S]*measuredBMRStatus = "Enter a resting-energy value from 800 to 4000 kcal\/day\."[\s\S]*return/,
  )
  assert.match(nativeSettingsSource, /private func clearMeasuredBMR\(\)/)
})

test('under-19 and malformed demographic inputs fail closed without NaN', () => {
  for (const candidate of [
    profile({ birthdate: '2010-01-01' }),
    profile({ birthdate: 'not-a-date' }),
    profile({ birthdate: '1990-02-31' }),
    profile({ birthdate: '2030-01-01' }),
    profile({ height_cm: Number.NaN }),
  ]) {
    const result = computeTargets(candidate, undefined, { asOf })
    assert.equal(result.reviewState, 'blocked')
    assert.equal(result.isPublishable, false)
    assert.deepEqual([result.kcal, result.protein_g, result.fat_g, result.carbs_g], [0, 0, 0, 0])
    assert.ok([result.bmrMifflin, result.tdee, result.activeBmr].every(Number.isFinite))
  }
  const future = computeTargets(profile({ birthdate: '2030-01-01' }), undefined, { asOf })
  assert.ok(future.reviewReasons.includes('invalid_birthdate'))
})

test('invalid standard inputs cannot reappear through the observed-activity path', () => {
  const result = estimateActivityDay(
    profile({ custom_bmr: 799, activity_level: 'moderate' }),
    [activityBlock('watch-kcal', { watchKcal: 900 })],
  )

  assert.deepEqual([result.bmr, result.tdee, result.targetKcal], [0, 0, 0])
  assert.equal(result.hasMeaningfulActivity, false)
  assert.ok([result.pal, result.proteinG, result.fatG, result.carbsG].every(Number.isFinite))
})

test('activity estimates fail closed when resting energy is outside 800 to 4000 kcal', () => {
  const result = estimateActivityDay(profile({
    sex: 'female',
    weight_kg: 30,
    height_cm: 120,
    birthdate: '1930-01-01',
    body_fat_pct: null,
    custom_bmr: null,
  }), [activityBlock('watch-kcal', { watchKcal: 900 })])

  assert.deepEqual([result.bmr, result.tdee, result.targetKcal], [0, 0, 0])
  assert.equal(result.hasMeaningfulActivity, false)
})

test('non-finite activity blocks and calibration cannot create an active estimate', () => {
  const subject = profile({ custom_bmr: 1683, activity_level: 'moderate' })
  const results = [
    estimateActivityDay(subject, [activityBlock('watch-kcal', { watchKcal: Number.POSITIVE_INFINITY })]),
    estimateActivityDay({ ...subject, calibration_k: Number.NaN }, [activityBlock('watch-kcal', { watchKcal: 900 })]),
  ]

  for (const result of results) {
    assert.equal(result.hasMeaningfulActivity, false)
    assert.deepEqual([result.bmr, result.rawBlockKcal, result.tdee, result.targetKcal], [0, 0, 0, 0])
    assert.ok([result.pal, result.proteinG, result.fatG, result.carbsG].every(Number.isFinite))
  }
})

test('prototype property names cannot bypass activity enum validation', () => {
  const results = [
    estimateActivityDay(profile({ goal: 'constructor' as Goal }), [activityBlock('watch-kcal', { watchKcal: 900 })]),
    estimateActivityDay(
      profile({ activity_level: 'toString' as Profile['activity_level'] }),
      [activityBlock('watch-kcal', { watchKcal: 900 })],
    ),
  ]

  for (const result of results) {
    assert.equal(result.hasMeaningfulActivity, false)
    assert.deepEqual([result.bmr, result.tdee, result.targetKcal], [0, 0, 0])
  }
})

test('observed activity cannot replace a blocked quick target', () => {
  const resolve = (activityPolicy as typeof activityPolicy & {
    resolveActivityAdjustedTargets?: (
      quickTargets: Targets | null,
      activityEstimate: ActivityEstimate | null,
      usesWholeDayProtocol: boolean,
    ) => Targets | null
  }).resolveActivityAdjustedTargets
  assert.equal(typeof resolve, 'function')
  if (!resolve) return

  const blocked = computeTargets(profile({ birthdate: 'not-a-date' }), undefined, { asOf })
  const activity = estimateActivityDay(
    profile({ custom_bmr: 1683, goal: 'maintain' }),
    [activityBlock('watch-kcal', { watchKcal: 900 })],
  )
  assert.equal(activity.hasMeaningfulActivity, true)

  assert.strictEqual(resolve(blocked, activity, false), blocked)
})

test('implausible resting energy and infeasible macro floors block publication', () => {
  const implausible = computeTargets(profile({ custom_bmr: 799 }), undefined, { asOf })
  assert.equal(implausible.reviewState, 'blocked')
  assert.ok(implausible.reviewReasons.includes('implausible_bmr'))

  const infeasible = computeTargets(profile({
    sex: 'female', weight_kg: 160, height_cm: 165, birthdate: '1981-01-01',
    custom_bmr: 800, activity_level: 'sedentary', goal: 'maintain',
  }), undefined, { asOf })
  assert.equal(infeasible.kcal, 960)
  assert.equal(infeasible.reviewState, 'blocked')
  assert.equal(infeasible.isPublishable, false)
  assert.ok(infeasible.reviewReasons.includes('macro_infeasible'))
  assert.deepEqual([infeasible.protein_g, infeasible.fat_g, infeasible.carbs_g], [0, 0, 0])
})

test('protected bespoke prescriptions remain authored and finite while malformed references require review', () => {
  const result = computeTargets(profile({
    user_id: '9a0fffbc-bb02-40ac-834a-d4e339b32574', persona: 'constantine', profile_kind: 'bespoke',
    bespoke_protocol_id: 'constantine-v8.5', birthdate: 'malformed', goal: 'recomp',
    activity_level: 'moderate', weight_kg: Number.NaN, body_fat_pct: 22.5, body_fat_source: 'dexa',
  }), undefined, { asOf })

  assert.deepEqual([result.kcal, result.protein_g, result.fat_g, result.carbs_g], [2450, 150, 75, 293])
  assert.equal(result.bmrKatch, null)
  assert.ok([result.bmrMifflin, result.tdee, result.activeBmr].every(Number.isFinite))
  assert.deepEqual(
    [result.targetProvenance, result.reviewState, result.isPublishable],
    ['bespoke_authored', 'review_recommended', true],
  )
  assert.ok(result.reviewReasons.includes('invalid_birthdate'))
  assert.ok(result.reviewReasons.includes('implausible_demographics'))
})

test('malformed bespoke cache keys fail closed and unsafe resting-energy references cannot claim ready', () => {
  const authorized = profile({
    user_id: '9a0fffbc-bb02-40ac-834a-d4e339b32574', persona: 'constantine', profile_kind: 'bespoke',
    bespoke_protocol_id: 'constantine-v8.5', goal: 'recomp', activity_level: 'moderate',
  })

  assert.equal(personalTargetFor({ ...authorized, goal: '__proto__' as Goal }), null)
  assert.equal(personalTargetFor({ ...authorized, activity_level: 'constructor' as ActivityLevel }), null)

  for (const candidate of [
    { ...authorized, custom_bmr: Number.NaN, custom_bmr_source: 'dexa_report_estimate' as const },
    { ...authorized, weight_kg: 30, height_cm: 120, birthdate: '1950-01-01' },
  ]) {
    const result = computeTargets(candidate, undefined, { asOf })
    assert.deepEqual([result.kcal, result.protein_g, result.fat_g, result.carbs_g], [2450, 150, 75, 293])
    assert.ok([result.bmrMifflin, result.tdee, result.activeBmr].every(Number.isFinite))
    assert.equal(result.reviewState, 'review_recommended')
    assert.ok(result.reviewReasons.includes('implausible_bmr'))
    assert.equal(result.isPublishable, true)
  }
})

test('observed exercise changes observed TDEE but not the default prescription', () => {
  const subject = profile({ custom_bmr: 1683, activity_level: 'moderate', goal: 'maintain' })
  const quiet = estimateActivityDay(subject, [], ACTIVITY_BY_ID, 1)
  const active = estimateActivityDay(
    subject,
    [activityBlock('watch-kcal', { watchKcal: 900 })],
    ACTIVITY_BY_ID,
    1,
  )

  assert.notEqual(active.tdee, quiet.tdee)
  assert.notEqual(active.pal, quiet.pal)
  assert.equal(quiet.targetKcal, 2609)
  assert.equal(active.targetKcal, 2609)
  assert.equal(active.prescriptionAdjustmentKcal, 0)
  assert.equal(active.targetPolicy, 'informational')
})

test('zero-energy blocks never activate or alter the prescription', () => {
  const subject = profile({ custom_bmr: 1683, activity_level: 'moderate', goal: 'maintain' })
  const withoutBlock = estimateActivityDay(subject, [], ACTIVITY_BY_ID, 1)
  const zeroBlock = estimateActivityDay(
    subject,
    [activityBlock('watch-kcal', { watchKcal: 0 })],
    ACTIVITY_BY_ID,
    1,
  )

  assert.equal(zeroBlock.targetKcal, withoutBlock.targetKcal)
  assert.equal(zeroBlock.prescriptionAdjustmentKcal, 0)
  assert.equal(zeroBlock.hasMeaningfulActivity, false)
})

test('explicit conservative compensation applies 25% of excess and caps at 250 kcal', () => {
  const subject = profile({ custom_bmr: 1683, activity_level: 'moderate', goal: 'maintain' })
  const modest = estimateActivityDay(
    subject,
    [],
    ACTIVITY_BY_ID,
    1,
    900,
    { kind: 'conservative_compensation' },
  )
  const extreme = estimateActivityDay(
    subject,
    [],
    ACTIVITY_BY_ID,
    1,
    3000,
    { kind: 'conservative_compensation' },
  )

  assert.equal(modest.prescriptionAdjustmentKcal, 78)
  assert.equal(modest.targetKcal, 2687)
  assert.equal(extreme.prescriptionAdjustmentKcal, 250)
  assert.equal(extreme.targetKcal, 2859)
  assert.equal(extreme.targetPolicy, 'conservative_compensation')
})
