import type {
  ActivityLevel,
  Goal,
  Meal,
  Profile,
  TrainingGoal,
  TrainingInductionProfile,
  TrainingPlanWeeks,
} from './types'
import { personalTargetFor } from './personalProtocol.ts'
import { bodyFatIsEnergyEligible } from './profilePolicy.ts'
import { SUPABASE_ENUMS } from './supabaseEnums.ts'

const TRAINING_GOAL_ALIASES: Record<string, TrainingGoal> = {
  rebuild: 'rebuild',
  general: 'rebuild',
  muscle: 'muscle',
  hypertrophy: 'muscle',
  fat_loss: 'fat_loss',
  strength: 'strength',
  endurance: 'endurance',
}

const TRAINING_PLAN_WEEKS = new Set<number>([4, 8, 12, 26])

export function canonicalTrainingGoal(value: unknown): TrainingGoal {
  if (typeof value !== 'string') return 'rebuild'
  const normalized = value.trim().toLowerCase()
  return Object.hasOwn(TRAINING_GOAL_ALIASES, normalized)
    ? TRAINING_GOAL_ALIASES[normalized]
    : 'rebuild'
}

export function canonicalTrainingPlanWeeks(value: unknown): TrainingPlanWeeks {
  const numeric = typeof value === 'number' ? value : Number(value)
  return TRAINING_PLAN_WEEKS.has(numeric) ? numeric as TrainingPlanWeeks : 12
}

function parsedBirthdate(value: string): Date | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
  if (!match) return null
  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  const date = new Date(Date.UTC(year, month - 1, day))
  return date.getUTCFullYear() === year
    && date.getUTCMonth() === month - 1
    && date.getUTCDate() === day
    ? date
    : null
}

function validAgeFrom(birthdate: string, at: Date = new Date()): number | null {
  const birth = parsedBirthdate(birthdate)
  if (!birth || !Number.isFinite(at.getTime()) || birth.getTime() > at.getTime()) return null
  let age = at.getUTCFullYear() - birth.getUTCFullYear()
  const month = at.getUTCMonth() - birth.getUTCMonth()
  if (month < 0 || (month === 0 && at.getUTCDate() < birth.getUTCDate())) age -= 1
  return age
}

export function ageFrom(birthdate: string, at: Date = new Date()): number {
  return validAgeFrom(birthdate, at) ?? 0
}

/* Mifflin-St Jeor: weight/height/age based */
export function bmrMifflin(p: Profile, at: Date = new Date()): number {
  const age = validAgeFrom(p.birthdate, at)
  if (age == null || !Number.isFinite(p.weight_kg) || !Number.isFinite(p.height_cm)) return 0
  const base = 10 * p.weight_kg + 6.25 * p.height_cm - 5 * age
  const estimate = base + (p.sex === 'male' ? 5 : -161)
  return Number.isFinite(estimate) ? Math.round(estimate) : 0
}

/* Katch-McArdle: lean-mass based, more accurate when body fat % is known */
export function bmrKatch(p: Profile): number | null {
  if (!bodyFatIsEnergyEligible(p) || !Number.isFinite(p.weight_kg)) return null
  const lean = p.weight_kg * (1 - p.body_fat_pct! / 100)
  const estimate = 370 + 21.6 * lean
  return Number.isFinite(estimate) ? Math.round(estimate) : null
}

export const ACTIVITY_MULTIPLIERS: Record<ActivityLevel, { label: string; factor: number }> = {
  sedentary: { label: 'Sedentary', factor: 1.2 },
  light: { label: 'Lightly active', factor: 1.375 },
  moderate: { label: 'Moderately active', factor: 1.55 },
  very: { label: 'Very active', factor: 1.725 },
  extra: { label: 'Extra active', factor: 1.9 },
}

export const GOALS: Record<Goal, { label: string; factor: number }> = {
  recomp: { label: 'Lean recomp', factor: 0.90 },
  maintain: { label: 'Maintain', factor: 1 },
  bulk: { label: 'Lean bulk', factor: 1.05 },
}

const ACTIVITY_LEVEL_VALUES = new Set<string>(SUPABASE_ENUMS.activity_level)
const GOAL_VALUES = new Set<string>(SUPABASE_ENUMS.goal)

function finitePositive(value: number): boolean {
  return Number.isFinite(value) && value > 0
}

function targetSafeRestingEnergy(value: unknown): value is number {
  return typeof value === 'number'
    && Number.isFinite(value)
    && value >= 800
    && value <= 4_000
}

export function isSupportedActivityLevel(value: unknown): value is ActivityLevel {
  return typeof value === 'string'
    && ACTIVITY_LEVEL_VALUES.has(value)
    && finitePositive(ACTIVITY_MULTIPLIERS[value as ActivityLevel].factor)
}

export function activityLevelLabel(value: unknown, fallback = 'Adaptive'): string {
  return isSupportedActivityLevel(value) ? ACTIVITY_MULTIPLIERS[value].label : fallback
}

export function isSupportedNutritionGoal(value: unknown): value is Goal {
  return typeof value === 'string'
    && GOAL_VALUES.has(value)
    && finitePositive(GOALS[value as Goal].factor)
}

export type MeasuredRestingEnergySubmission =
  | {
      status: 'accepted'
      next: {
        custom_bmr: number
        custom_bmr_source: 'indirect_calorimetry'
      }
    }
  | {
      status: 'rejected'
      reason: 'out_of_range' | 'source_required'
      message: string
      current: {
        custom_bmr: number | null
        custom_bmr_source: string | null
      }
    }

export function validateMeasuredRestingEnergySubmission(input: {
  current: { custom_bmr: number | null; custom_bmr_source: string | null }
  draft: string
  selected_source: string
}): MeasuredRestingEnergySubmission {
  const parsed = Number(input.draft.trim().replace(',', '.'))
  if (!input.draft.trim() || !Number.isFinite(parsed) || parsed < 800 || parsed > 4_000) {
    return {
      status: 'rejected',
      reason: 'out_of_range',
      message: 'Enter a resting-energy value from 800 to 4000 kcal/day.',
      current: input.current,
    }
  }
  if (input.selected_source !== 'indirect_calorimetry') {
    return {
      status: 'rejected',
      reason: 'source_required',
      message: 'Choose indirect calorimetry only when that test measured this value.',
      current: input.current,
    }
  }
  return {
    status: 'accepted',
    next: {
      custom_bmr: Math.round(parsed),
      custom_bmr_source: 'indirect_calorimetry',
    },
  }
}

export interface NutritionPlanContext {
  trainingGoal: TrainingGoal
  planWeeks: TrainingPlanWeeks
}

export interface NutritionGoalPreset {
  goal: Goal
  label: string
  factor: number
  explanation: string
  caution: string
}

export function nutritionPlanContext(
  induction: Pick<TrainingInductionProfile, 'goal' | 'plan_weeks'> | {
    goal?: unknown
    plan_weeks?: unknown
  } | null | undefined,
): NutritionPlanContext | undefined {
  if (!induction) return undefined
  return {
    trainingGoal: canonicalTrainingGoal(induction.goal),
    planWeeks: canonicalTrainingPlanWeeks(induction.plan_weeks),
  }
}

function canonicalPlanContext(context: NutritionPlanContext): NutritionPlanContext {
  return {
    trainingGoal: canonicalTrainingGoal(context.trainingGoal),
    planWeeks: canonicalTrainingPlanWeeks(context.planWeeks),
  }
}

function preset(
  goal: Goal,
  label: string,
  factor: number,
  explanation: string,
  caution: string,
): NutritionGoalPreset {
  return { goal, label, factor, explanation, caution }
}

/**
 * The persisted profile keeps its stable three-value axis. The active training
 * plan gives those positions honest goal-specific meaning at read time, so a
 * fat-loss plan never offers a surplus disguised as "Lean bulk" and changing
 * the resolver needs no data migration.
 */
export function goalPresetsForPlan(context?: NutritionPlanContext): NutritionGoalPreset[] {
  if (!context) {
    return [
      preset('recomp', 'Lean recomp', 0.90, 'A moderate deficit with extra protein support.', 'Review recovery, hunger, and weight trend after two weeks.'),
      preset('maintain', 'Maintain', 1, 'Match estimated daily expenditure without targeting weight change.', 'Wearable estimates are a starting point, not a metabolic measurement.'),
      preset('bulk', 'Lean bulk', 1.05, 'A controlled surplus to support training progression.', 'Reduce the surplus if weight rises faster than intended.'),
    ]
  }

  const canonical = canonicalPlanContext(context)
  switch (canonical.trainingGoal) {
  case 'muscle':
    return [
      preset('recomp', 'Lean recomp', 0.95, 'Build skill and preserve muscle while trimming slowly.', 'Choose Maintain if training performance or recovery declines.'),
      preset('maintain', 'Maintain', 1, 'Hold body weight while progressive training drives recomposition.', 'Progress is slower, so judge the trend over several weeks.'),
      preset('bulk', 'Lean bulk', 1.07, 'Use a small surplus to support muscle gain and harder sessions.', 'Review the two-week weight trend and reduce if gain is too fast.'),
    ]
  case 'fat_loss': {
    const acceleratedFactor: Record<TrainingPlanWeeks, number> = { 4: 0.80, 8: 0.82, 12: 0.84, 26: 0.86 }
    const steadyFactor: Record<TrainingPlanWeeks, number> = { 4: 0.86, 8: 0.87, 12: 0.88, 26: 0.89 }
    return [
      preset('recomp', 'Accelerated cut', acceleratedFactor[canonical.planWeeks], 'The largest bounded deficit for this plan horizon.', 'Not the default. Stop and reassess if recovery, sleep, or performance falls.'),
      preset('maintain', 'Steady cut', steadyFactor[canonical.planWeeks], 'A repeatable deficit balanced against training and lean-mass retention.', 'Best default; use measured trends instead of cutting harder too soon.'),
      preset('bulk', 'Gentle cut', 0.93, 'A smaller deficit with more room for training and appetite control.', 'Loss is intentionally slower and depends on consistent weeks.'),
    ]
  }
  case 'strength':
    return [
      preset('recomp', 'Strength recomp', 0.95, 'A small deficit while strength skill remains the priority.', 'Move to Strength base if load or recovery trends down.'),
      preset('maintain', 'Strength base', 1, 'Maintenance energy for repeatable heavy practice and recovery.', 'The recommended starting point for most strength plans.'),
      preset('bulk', 'Power surplus', 1.05, 'A small surplus for higher volume and progressive loading.', 'Review body-weight trend after two weeks; more is not automatically better.'),
    ]
  case 'endurance':
    return [
      preset('recomp', 'Light fuel', 0.96, 'A slight deficit while protecting useful training fuel.', 'Avoid on high-volume weeks if pace, mood, or recovery deteriorates.'),
      preset('maintain', 'Balanced fuel', 1, 'Match daily expenditure for consistent endurance work.', 'The recommended base before adding fuel for longer sessions.'),
      preset('bulk', 'High-volume fuel', 1.06, 'Extra energy for long or dense training weeks.', 'Use for real workload, then return to Balanced fuel as volume falls.'),
    ]
  case 'rebuild':
    return [
      preset('recomp', 'Light balance', 0.95, 'A small deficit while rebuilding a consistent routine.', 'Choose Balanced fitness if hunger or recovery disrupts consistency.'),
      preset('maintain', 'Balanced fitness', 1, 'Maintenance fuel for broad fitness and repeatable sessions.', 'The recommended start when body-weight change is not the main goal.'),
      preset('bulk', 'Fuel progress', 1.04, 'A small surplus for higher volume and easier recovery.', 'Review body-weight trend after two weeks and adjust deliberately.'),
    ]
  }
}

export function goalPresetForPlan(goal: Goal, context?: NutritionPlanContext): NutritionGoalPreset {
  const presets = goalPresetsForPlan(context)
  return presets.find((candidate) => candidate.goal === goal)
    ?? presets.find((candidate) => candidate.goal === 'maintain')
    ?? goalPresetsForPlan()[1]
}

export function recommendedGoalForTrainingGoal(trainingGoal: TrainingGoal | unknown): Goal {
  return canonicalTrainingGoal(trainingGoal) === 'muscle' ? 'bulk' : 'maintain'
}

export type TargetProvenance =
  | 'calculated'
  | 'measured_indirect_calorimetry'
  | 'legacy_user_entered'
  | 'bespoke_authored'

export type TargetReviewState = 'ready' | 'review_recommended' | 'blocked'
export type TargetReviewReason =
  | 'invalid_birthdate'
  | 'age_below_19'
  | 'implausible_demographics'
  | 'implausible_bmr'
  | 'dexa_estimated_bmr_ignored'
  | 'legacy_bmr_needs_review'
  | 'macro_infeasible'

export interface Targets {
  bmrMifflin: number
  bmrKatch: number | null
  tdee: number
  kcal: number
  protein_g: number
  fat_g: number
  carbs_g: number
  water_l: number
  bmrSource: 'custom' | 'katch' | 'mifflin'
  activeBmr: number
  targetProvenance: TargetProvenance
  reviewState: TargetReviewState
  reviewReasons: TargetReviewReason[]
  isPublishable: boolean
}

export interface TargetMeal extends Meal {
  /* True when the displayed foods were rebuilt from the active calorie target. */
  portioned: boolean
  portionNote: string
}

const PROTEIN_G_PER_KG: Record<ActivityLevel, number> = {
  sedentary: 1.6,
  light: 1.75,
  moderate: 1.9,
  very: 2,
  extra: 2.1,
}

const GOAL_PROTEIN_ADJUSTMENT: Record<Goal, number> = {
  recomp: 0.2,
  maintain: 0,
  bulk: -0.1,
}

const FAT_ENERGY_SHARE: Record<Goal, number> = {
  recomp: 0.25,
  maintain: 0.275,
  bulk: 0.28,
}

const FAT_FLOOR_G_PER_KG: Record<Goal, number> = {
  recomp: 0.7,
  maintain: 0.8,
  bulk: 0.8,
}

export interface MacroTargets {
  protein_g: number
  fat_g: number
  carbs_g: number
  protein_g_per_kg: number
  fat_energy_share: number
}

/* APEX protects protein inside the athlete-supported range, keeps fat near the
   middle of the adult AMDR with a body-weight floor, then assigns the remaining
   energy to carbohydrate. Activity and goal therefore update all three targets
   instead of leaving protein and fat frozen while only carbohydrate moves. */
export function computeMacroTargets(
  weightKg: number,
  activityLevel: ActivityLevel,
  goal: Goal,
  targetKcal: number,
): MacroTargets {
  const proteinGPerKg = Math.min(2.4, Math.max(1.6, PROTEIN_G_PER_KG[activityLevel] + GOAL_PROTEIN_ADJUSTMENT[goal]))
  const proteinG = Math.round(weightKg * proteinGPerKg)
  const fatEnergyShare = FAT_ENERGY_SHARE[goal]
  const fatFromEnergy = targetKcal * fatEnergyShare / 9
  const fatFloor = weightKg * FAT_FLOOR_G_PER_KG[goal]
  const fatG = Math.round(Math.max(fatFloor, fatFromEnergy))
  /* Whole-gram carbohydrate is rounded down so displayed macros never claim
     more energy than the prescription they accompany. */
  const carbsG = Math.max(0, Math.floor((targetKcal - proteinG * 4 - fatG * 9) / 4))
  return {
    protein_g: proteinG,
    fat_g: fatG,
    carbs_g: carbsG,
    protein_g_per_kg: Math.round(proteinGPerKg * 100) / 100,
    fat_energy_share: fatEnergyShare,
  }
}

/* TDEE builds on Katch-McArdle when a credible body-fat value is available. */
export interface TargetComputationOptions {
  asOf?: Date
}

function finiteOrZero(value: number): number {
  return Number.isFinite(value) ? value : 0
}

function blockedTargets(
  bmrMifflinValue: number,
  bmrKatchValue: number | null,
  reasons: TargetReviewReason[],
  kcal = 0,
  tdee = 0,
  activeBmr = 0,
  bmrSource: Targets['bmrSource'] = 'mifflin',
  provenance: TargetProvenance = 'calculated',
): Targets {
  return {
    bmrMifflin: finiteOrZero(bmrMifflinValue),
    bmrKatch: bmrKatchValue != null && Number.isFinite(bmrKatchValue) ? bmrKatchValue : null,
    tdee: finiteOrZero(tdee),
    kcal: finiteOrZero(kcal),
    protein_g: 0,
    fat_g: 0,
    carbs_g: 0,
    water_l: 2.75,
    bmrSource,
    activeBmr: finiteOrZero(activeBmr),
    targetProvenance: provenance,
    reviewState: 'blocked',
    reviewReasons: reasons,
    isPublishable: false,
  }
}

function standardInputReasons(p: Profile, at: Date): TargetReviewReason[] {
  const age = validAgeFrom(p.birthdate, at)
  if (age == null) return ['invalid_birthdate']
  if (age < 19) return ['age_below_19']
  if (
    age > 100
    || !Number.isFinite(p.weight_kg) || p.weight_kg < 30 || p.weight_kg > 300
    || !Number.isFinite(p.height_cm) || p.height_cm < 120 || p.height_cm > 230
    || (p.sex !== 'male' && p.sex !== 'female')
    || !isSupportedActivityLevel(p.activity_level)
    || !isSupportedNutritionGoal(p.goal)
  ) return ['implausible_demographics']
  return []
}

/* TDEE builds on Katch-McArdle when a credible body-fat value is available. */
export function computeTargets(
  p: Profile,
  planContext?: NutritionPlanContext,
  options: TargetComputationOptions = {},
): Targets {
  const at = options.asOf ?? new Date()
  const katch = bmrKatch(p)
  const mifflin = bmrMifflin(p, at)
  const hasBodyFat = bodyFatIsEnergyEligible(p)
  const personal = isSupportedNutritionGoal(p.goal) && isSupportedActivityLevel(p.activity_level)
    ? personalTargetFor(p)
    : null
  if (personal) {
    const personalHasCustomBmrInput = p.custom_bmr != null
    const personalCustomBmrIsTargetSafe = targetSafeRestingEnergy(p.custom_bmr)
    const personalDexaEstimate = personalCustomBmrIsTargetSafe
      && p.custom_bmr_source === 'dexa_report_estimate'
    const personalCustomBmr = personalCustomBmrIsTargetSafe && !personalDexaEstimate
    const personalHasKatchCandidate = hasBodyFat && katch != null
    const personalHasKatchReference = personalHasKatchCandidate && targetSafeRestingEnergy(katch)
    const personalHasMifflinReference = targetSafeRestingEnergy(mifflin)
    const personalActiveBmr = personalCustomBmr
      ? Math.round(p.custom_bmr!)
      : personalHasKatchReference
        ? katch
        : personalHasMifflinReference ? mifflin : 0
    const reviewReasons = standardInputReasons(p, at)
    const addReviewReason = (reason: TargetReviewReason) => {
      if (!reviewReasons.includes(reason)) reviewReasons.push(reason)
    }
    if (
      !Number.isFinite(p.weight_kg) || p.weight_kg < 30 || p.weight_kg > 300
      || !Number.isFinite(p.height_cm) || p.height_cm < 120 || p.height_cm > 230
      || (p.sex !== 'male' && p.sex !== 'female')
    ) {
      addReviewReason('implausible_demographics')
    }
    if (personalHasCustomBmrInput && !personalCustomBmrIsTargetSafe) {
      addReviewReason('implausible_bmr')
    } else if (personalDexaEstimate) {
      addReviewReason('dexa_estimated_bmr_ignored')
    } else if (personalCustomBmr && p.custom_bmr_source !== 'indirect_calorimetry') {
      addReviewReason('legacy_bmr_needs_review')
    }
    if (
      (personalHasKatchCandidate && !personalHasKatchReference)
      || (!personalCustomBmr && !personalHasKatchReference && !personalHasMifflinReference)
    ) {
      addReviewReason('implausible_bmr')
    }
    const authoredTargetIsPublishable = [
      personal.tdee,
      personal.kcal,
      personal.proteinG,
      personal.fatG,
      personal.carbsG,
    ].every(Number.isFinite)
      && personal.tdee > 0
      && personal.kcal > 0
      && personal.proteinG > 0
      && personal.fatG > 0
      && personal.carbsG >= 0
      && personal.proteinG * 4 + personal.fatG * 9 + personal.carbsG * 4 <= personal.kcal
    return {
      bmrMifflin: mifflin,
      bmrKatch: katch,
      tdee: personal.tdee,
      kcal: personal.kcal,
      protein_g: personal.proteinG,
      fat_g: personal.fatG,
      carbs_g: personal.carbsG,
      water_l: p.persona === 'june' ? 2.2 : 2.75,
      bmrSource: personalCustomBmr ? 'custom' : personalHasKatchReference ? 'katch' : 'mifflin',
      activeBmr: personalActiveBmr,
      targetProvenance: 'bespoke_authored',
      reviewState: authoredTargetIsPublishable
        ? reviewReasons.length > 0 ? 'review_recommended' : 'ready'
        : 'blocked',
      reviewReasons,
      isPublishable: authoredTargetIsPublishable,
    }
  }

  const inputReasons = standardInputReasons(p, at)
  if (inputReasons.length > 0) return blockedTargets(mifflin, katch, inputReasons)

  const hasCustomInput = p.custom_bmr != null
  const customBmrIsPlausible = hasCustomInput
    && Number.isFinite(p.custom_bmr)
    && p.custom_bmr! >= 800
    && p.custom_bmr! <= 4000
  if (hasCustomInput && !customBmrIsPlausible) {
    return blockedTargets(mifflin, katch, ['implausible_bmr'])
  }

  const ignoresDexaEstimate = customBmrIsPlausible && p.custom_bmr_source === 'dexa_report_estimate'
  const usesCustomBmr = customBmrIsPlausible && !ignoresDexaEstimate
  const activeBmr = usesCustomBmr
    ? Math.round(p.custom_bmr!)
    : hasBodyFat && katch != null
      ? katch
      : mifflin
  if (!Number.isFinite(activeBmr) || activeBmr < 800 || activeBmr > 4000) {
    return blockedTargets(mifflin, katch, ['implausible_bmr'])
  }

  const bmrSource: Targets['bmrSource'] = usesCustomBmr ? 'custom' : hasBodyFat ? 'katch' : 'mifflin'
  const targetProvenance: TargetProvenance = usesCustomBmr
    ? p.custom_bmr_source === 'indirect_calorimetry'
      ? 'measured_indirect_calorimetry'
      : 'legacy_user_entered'
    : 'calculated'
  const reviewReasons: TargetReviewReason[] = ignoresDexaEstimate
    ? ['dexa_estimated_bmr_ignored']
    : usesCustomBmr && p.custom_bmr_source !== 'indirect_calorimetry'
      ? ['legacy_bmr_needs_review']
      : []

  const tdee = Math.round(activeBmr * ACTIVITY_MULTIPLIERS[p.activity_level].factor)
  const selectedFactor = goalPresetForPlan(p.goal, planContext).factor
  const formulaTarget = tdee * selectedFactor
  const kcal = Math.round(formulaTarget)
  const macros = computeMacroTargets(p.weight_kg, p.activity_level, p.goal, kcal)
  const macroKcal = macros.protein_g * 4 + macros.fat_g * 9 + macros.carbs_g * 4
  const isPublishable = finitePositive(tdee)
    && finitePositive(selectedFactor)
    && finitePositive(kcal)
    && finitePositive(macros.protein_g)
    && finitePositive(macros.fat_g)
    && Number.isFinite(macros.carbs_g)
    && macros.carbs_g >= 0
    && Number.isFinite(macroKcal)
    && macroKcal <= kcal
  if (!isPublishable) {
    return blockedTargets(
      mifflin,
      katch,
      [...reviewReasons, 'macro_infeasible'],
      kcal,
      tdee,
      activeBmr,
      bmrSource,
      targetProvenance,
    )
  }
  return {
    bmrMifflin: mifflin,
    bmrKatch: katch,
    tdee,
    kcal,
    protein_g: macros.protein_g,
    fat_g: macros.fat_g,
    carbs_g: macros.carbs_g,
    water_l: 2.75,
    bmrSource,
    activeBmr,
    targetProvenance,
    reviewState: reviewReasons.length > 0 ? 'review_recommended' : 'ready',
    reviewReasons,
    isPublishable,
  }
}

/* The original food brief totals 2,670 kcal. It remains the recipe reference,
   while the rendered portions and meal-level macro budget follow the live
   target. Keeping this derived avoids rewriting the user's Supabase meal rows
   every time an activity button is pressed. */
function stepped(base: number, scale: number, step: number, minimum = step): number {
  return Math.max(minimum, Math.round((base * scale) / step) * step)
}

function allocate(total: number, weights: number[]): number[] {
  const weightTotal = weights.reduce((sum, value) => sum + Math.max(0, value), 0)
  if (weights.length === 0) return []
  if (weightTotal === 0) {
    const even = Math.floor(total / weights.length)
    return weights.map((_, index) => even + (index < total - even * weights.length ? 1 : 0))
  }

  const exact = weights.map((weight) => (total * Math.max(0, weight)) / weightTotal)
  const result = exact.map(Math.floor)
  let left = total - result.reduce((sum, value) => sum + value, 0)
  const byRemainder = exact
    .map((value, index) => ({ index, remainder: value - Math.floor(value) }))
    .sort((a, b) => b.remainder - a.remainder)
  for (let i = 0; i < left; i += 1) result[byRemainder[i % byRemainder.length].index] += 1
  return result
}

function scaleQuantities(text: string, scale: number): string {
  return text.replace(/(\d+(?:\.\d+)?)\s*(g|ml|eggs?)/gi, (_match, amount: string, unit: string) => {
    const value = Number(amount)
    if (/egg/i.test(unit)) return `${Math.max(1, Math.round(value * scale))} eggs`
    const scaled = stepped(value, scale, 5)
    return `${scaled} ${unit.toLowerCase()}`
  })
}

interface PortionScales {
  energy: number
  protein: number
  fat: number
  carbs: number
}

function portionedFoods(meal: Meal, scales: PortionScales): string {
  const key = meal.name.trim().toLowerCase()
  if (key === 'breakfast' && /nut mix/i.test(meal.foods)) {
    return `${Math.max(2, Math.round(4 * scales.protein))} eggs + ${stepped(35, scales.fat, 5, 15)} g nut mix. Zero-starch, protein-first morning.`
  }
  if (key === 'oat jar') {
    return [
      `${stepped(80, scales.carbs, 5, 35)} g oats`,
      `${stepped(200, scales.carbs, 25, 100)} ml milk`,
      `${stepped(100, scales.carbs, 10, 50)} g berries`,
      `${stepped(100, scales.carbs, 10, 50)} g banana`,
      `${stepped(75, scales.carbs, 10, 40)} g kiwi`,
      `${stepped(200, scales.protein, 25, 100)} g magerquark or chicken hearts`,
      `${stepped(15, scales.fat, 5, 5)} g seed mix`,
      `${stepped(5, scales.fat, 5, 5)} g EVOO`,
    ].join(' + ')
  }
  if (key === 'bulgur snack') {
    return `${stepped(70, scales.carbs, 5, 35)} g dry bulgur + ${stepped(200, scales.protein, 25, 100)} g cottage cheese + ${stepped(200, scales.carbs, 25, 100)} g vegetables. Full days only.`
  }
  if (key === 'dinner') {
    return `${stepped(300, scales.carbs, 25, 150)} g sweet potato + ${stepped(200, scales.protein, 25, 100)} g pollock or chicken + ${stepped(100, scales.fat, 10, 40)} g avocado + ${stepped(200, scales.carbs, 25, 100)} g vegetables.`
  }
  if (key === 'casein shake') {
    return `Casein isolate ${stepped(45, scales.protein, 5, 25)} g in water.`
  }
  return scaleQuantities(meal.foods, scales.energy)
}

function portionNote(meal: Meal, scales: PortionScales, dayLabel: string): string {
  const key = meal.name.trim().toLowerCase()
  if (key === 'oat jar') return `${dayLabel} day: oats ${stepped(80, scales.carbs, 5, 35)} g instead of 80 g.`
  if (key === 'bulgur snack') return `${dayLabel} day: dry bulgur ${stepped(70, scales.carbs, 5, 35)} g instead of 70 g.`
  if (key === 'dinner') return `${dayLabel} day: sweet potato ${stepped(300, scales.carbs, 25, 150)} g instead of 300 g.`
  if (key === 'breakfast' && /nut mix/i.test(meal.foods)) return `${dayLabel} day: protein stays pinned; nut mix adjusts to ${stepped(35, scales.fat, 5, 15)} g.`
  if (key === 'casein shake') return `${dayLabel} day: casein remains protein-led at ${stepped(45, scales.protein, 5, 25)} g.`
  return `${dayLabel} day: carbohydrate portions move first; protein moves last.`
}

/* Builds a complete target-aligned timeline. Integer allocation uses largest
   remainders, so every meal card adds back up to the exact targets shown at
   the top even after rounding. */
export function buildTargetMealPlan(meals: Meal[], targets: Targets, dayLabel = 'Adaptive'): TargetMeal[] {
  if (meals.length === 0 || !targets.isPublishable) return []
  const referenceKcal = meals.reduce((sum, meal) => sum + meal.kcal, 0) || targets.kcal
  const referenceProtein = meals.reduce((sum, meal) => sum + meal.protein_g, 0) || targets.protein_g
  const referenceFat = meals.reduce((sum, meal) => sum + meal.fat_g, 0) || targets.fat_g
  const referenceCarbs = meals.reduce((sum, meal) => sum + meal.carbs_g, 0) || targets.carbs_g
  const scales: PortionScales = {
    energy: Math.min(1.35, Math.max(0.5, targets.kcal / referenceKcal)),
    protein: Math.min(1.25, Math.max(0.65, targets.protein_g / referenceProtein)),
    fat: Math.min(1.4, Math.max(0.45, targets.fat_g / referenceFat)),
    carbs: Math.min(1.6, Math.max(0.4, targets.carbs_g / referenceCarbs)),
  }
  const kcal = allocate(targets.kcal, meals.map((meal) => meal.kcal))
  const protein = allocate(targets.protein_g, meals.map((meal) => meal.protein_g))
  const fat = allocate(targets.fat_g, meals.map((meal) => meal.fat_g))
  const carbs = allocate(targets.carbs_g, meals.map((meal) => meal.carbs_g))

  return meals.map((meal, index) => ({
    ...meal,
    foods: portionedFoods(meal, scales),
    kcal: kcal[index],
    protein_g: protein[index],
    fat_g: fat[index],
    carbs_g: carbs[index],
    portioned: true,
    portionNote: portionNote(meal, scales, dayLabel),
  }))
}
