import type { ProviderNutrientEvidenceObservation } from './nutrientEvidence.ts'

type NumericEvidence = number | string | null

export interface FoodCorpusSearchResult {
  record_id: string
  source_key: string
  source_record_id: string
  name: string
  names_i18n: Record<string, string>
  aliases: string[]
  brand: string | null
  barcode: string | null
  market: string | null
  basis_kind: string
  basis_amount?: number | null
  basis_unit?: string | null
  source_metadata?: Record<string, unknown> | null
  preparation_state: string | null
  kcal: NumericEvidence
  protein_g: NumericEvidence
  carbs_g: NumericEvidence
  fat_g: NumericEvidence
  fibre_g: NumericEvidence
  sugar_g: NumericEvidence
  saturated_fat_g: NumericEvidence
  salt_g: NumericEvidence
  water_g: NumericEvidence
  nutrient_evidence?: ProviderNutrientEvidenceObservation[] | null
}

const supportedPreparationStates = new Set([
  'dry',
  'cooked',
  'prepared',
  'drained',
  'as_sold',
  'unknown',
])

function publishedServingGrams(result: FoodCorpusSearchResult): number | null {
  if (result.basis_kind !== 'per_serving') return null
  const publishedServing = result.source_metadata?.published_serving
  if (typeof publishedServing !== 'string') return null
  const match = publishedServing.match(/\(([0-9]+(?:[.,][0-9]+)?)\s*g\)/i)
  if (!match) return null
  const grams = Number(match[1].replace(',', '.'))
  return Number.isFinite(grams) && grams > 0 ? grams : null
}

function scaledEvidence(value: NumericEvidence, multiplier: number): number | null {
  if (value === null || (typeof value === 'string' && value.trim() === '')) return null
  const numeric = typeof value === 'number' ? value : Number(value)
  if (!Number.isFinite(numeric)) return null
  return Math.round(numeric * multiplier * 1_000_000) / 1_000_000
}

export function normalizeFoodCorpusSearchResult(result: FoodCorpusSearchResult) {
  const servingGrams = publishedServingGrams(result)
  const isServing = result.basis_kind === 'per_serving'
  if (
    result.basis_kind !== 'per_100g'
    && result.basis_kind !== 'per_100ml'
    && servingGrams === null
  ) return null
  const multiplier = servingGrams === null ? 1 : 100 / servingGrams
  const nutritionBasis = isServing ? 'per_100g' : result.basis_kind
  const preparationState = result.preparation_state?.trim().toLocaleLowerCase() ?? ''
  const waterPer100 = scaledEvidence(result.water_g, multiplier)
  const macroComplete = [result.kcal, result.protein_g, result.carbs_g, result.fat_g]
    .every((value) => scaledEvidence(value, 1) !== null)

  return {
    id: result.record_id,
    owner_user_id: null,
    name: result.name,
    names_i18n: result.names_i18n ?? {},
    brand: result.brand,
    barcode: result.barcode,
    source: 'apex_cache',
    provider_product_id: `corpus:${result.source_key}:${result.source_record_id}`,
    external_image_url: null,
    package_quantity: isServing
      ? String(result.source_metadata?.published_serving ?? '').trim() || null
      : null,
    nutrition_basis: nutritionBasis,
    preparation_state: supportedPreparationStates.has(preparationState)
      ? preparationState
      : 'unknown',
    kcal_100: scaledEvidence(result.kcal, multiplier),
    protein_100: scaledEvidence(result.protein_g, multiplier),
    carbs_100: scaledEvidence(result.carbs_g, multiplier),
    fat_100: scaledEvidence(result.fat_g, multiplier),
    fibre_100: scaledEvidence(result.fibre_g, multiplier),
    sugar_100: scaledEvidence(result.sugar_g, multiplier),
    saturated_fat_100: scaledEvidence(result.saturated_fat_g, multiplier),
    salt_100: scaledEvidence(result.salt_g, multiplier),
    /* Composition tables publish grams of water. Pure water is 1 g/mL, so the
       mass of water in 100 g of food is the same numeric hydration volume. */
    water_ml_100: waterPer100,
    water_basis: waterPer100 === null ? null : 'provider_reported',
    water_source_id: waterPer100 === null
      ? null
      : `corpus:${result.source_key}:${result.source_record_id}:WATER`,
    serving_amount: isServing ? 1 : null,
    serving_unit: isServing ? 'serving' : null,
    serving_grams_or_ml: servingGrams,
    piece_grams_or_ml: null,
    confidence: macroComplete ? 'provider_verified' : 'partial',
    nutrient_evidence: (result.nutrient_evidence ?? []).map((row) => ({ ...row })),
  }
}
