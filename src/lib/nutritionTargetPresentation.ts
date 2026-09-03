import type {
  TargetProvenance,
  TargetReviewReason,
  Targets,
} from './nutrition.ts'
import type { MealTotals } from './food.ts'

const TARGET_PROVENANCE_LABELS: Record<TargetProvenance, string> = {
  calculated: 'Profile-calculated target',
  measured_indirect_calorimetry: 'Profile-calculated target',
  legacy_user_entered: 'Profile-calculated target',
  bespoke_authored: 'Bespoke authored target',
}

export const TARGET_REVIEW_REASON_LABELS: Record<TargetReviewReason, string> = {
  invalid_birthdate: 'Add a valid birthdate before APEX calculates an energy target.',
  age_below_19: 'Automatic energy targets are available only for adults aged 19 or older.',
  implausible_demographics: 'Review your age, height, weight, sex and activity details before using this target.',
  implausible_bmr: 'Review the resting-energy value before using this target.',
  dexa_estimated_bmr_ignored: 'A DEXA-estimated BMR is saved as context; APEX used the calculated resting-energy formula instead.',
  legacy_bmr_needs_review: 'Confirm that this earlier resting-energy value came from indirect calorimetry, or clear it to use the calculated formula.',
  macro_infeasible: 'This calorie target cannot fit the protected protein and fat minimums. Review the inputs before using it.',
}

export function targetProvenanceLabel(provenance: TargetProvenance): string {
  return TARGET_PROVENANCE_LABELS[provenance]
}

export function restingEnergyProvenanceLabel(
  targets: Pick<Targets, 'bmrSource' | 'targetProvenance'>,
): string {
  if (targets.targetProvenance === 'measured_indirect_calorimetry') return 'Measured by indirect calorimetry'
  if (targets.targetProvenance === 'legacy_user_entered') return 'Earlier entered resting-energy value'
  if (targets.bmrSource === 'custom' && targets.targetProvenance === 'bespoke_authored') return 'Bespoke resting-energy reference'
  if (targets.bmrSource === 'katch') return 'Katch-McArdle estimate'
  return 'Mifflin-St Jeor estimate'
}

export function publishableNutritionPrescription(
  targets: Pick<Targets, 'isPublishable' | 'kcal' | 'protein_g' | 'carbs_g' | 'fat_g'>,
): MealTotals | null {
  if (!targets.isPublishable) return null
  const prescription = {
    kcal: targets.kcal,
    protein_g: targets.protein_g,
    carbs_g: targets.carbs_g,
    fat_g: targets.fat_g,
  }
  return Object.values(prescription).every((value) => Number.isFinite(value) && value > 0)
    ? prescription
    : null
}
