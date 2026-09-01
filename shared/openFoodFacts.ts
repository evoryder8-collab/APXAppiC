import type { ProviderNutrientEvidenceObservation } from './nutrientEvidence.ts'

export const OPEN_FOOD_FACTS_FIELDS = [
  'code',
  'product_name',
  'product_name_en',
  'product_name_de',
  'product_name_fr',
  'product_name_it',
  'product_name_ro',
  'product_name_th',
  'brands',
  'quantity',
  'product_quantity',
  'product_quantity_unit',
  'serving_size',
  'serving_quantity',
  'image_front_small_url',
  'nutriments',
  'last_modified_t',
].join(',')

export interface OpenFoodFactsResponse {
  status?: number
  status_verbose?: string
  code?: string
  product?: Record<string, unknown>
}

export interface NormalizedProviderFood {
  name: string
  names_i18n: Partial<Record<'en' | 'de' | 'fr' | 'it' | 'ro' | 'th', string>>
  brand: string | null
  barcode: string
  source: 'open_food_facts'
  provider_product_id: string
  external_image_url: string | null
  package_quantity: string | null
  nutrition_basis: 'per_100g' | 'per_100ml'
  preparation_state: 'as_sold'
  kcal_100: number | null
  protein_100: number | null
  carbs_100: number | null
  fat_100: number | null
  fibre_100: number | null
  water_ml_100: number | null
  water_basis: 'provider_reported' | 'unknown'
  water_source_id: string | null
  sugar_100: number | null
  saturated_fat_100: number | null
  salt_100: number | null
  serving_amount: number | null
  serving_unit: 'g' | 'ml' | null
  serving_grams_or_ml: number | null
  provider_updated_at: string | null
  confidence: 'complete' | 'partial' | 'provider_verified'
  nutrient_evidence: ProviderNutrientEvidenceObservation[]
}

function digits(value: string): string {
  return value.replace(/\D/g, '')
}

function hasValidCheckDigit(value: string): boolean {
  const numbers = [...value].map(Number)
  const check = numbers.pop()
  if (check == null) return false
  const sum = numbers
    .reverse()
    .reduce((total, number, index) => total + number * (index % 2 === 0 ? 3 : 1), 0)
  return (10 - (sum % 10)) % 10 === check
}

export function normalizeBarcode(value: string): string | null {
  const normalized = digits(value)
  if (![8, 12, 13].includes(normalized.length)) return null
  return hasValidCheckDigit(normalized) ? normalized : null
}

function finiteNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value.replace(',', '.'))
    return Number.isFinite(parsed) ? parsed : null
  }
  return null
}

function safeNutrient(value: unknown, maximum = 100): number | null {
  const parsed = finiteNumber(value)
  if (parsed == null || parsed < 0 || parsed > maximum) return null
  return Math.round(parsed * 100) / 100
}

interface DetailedNutrientDefinition {
  source: string
  code: string
  name: string
  unit: 'g' | 'mg' | 'µg'
  multiplier: number
}

/* Open Food Facts guarantees that weight-based `<nutrient>_100g` fields use
 * normalized grams. We convert only to reader-friendly units, retain the
 * original grams, and omit absent keys rather than manufacturing zeroes. */
const detailedNutrients: DetailedNutrientDefinition[] = [
  { source: 'monounsaturated-fat', code: 'FAMS', name: 'Monounsaturated fat', unit: 'g', multiplier: 1 },
  { source: 'polyunsaturated-fat', code: 'FAPU', name: 'Polyunsaturated fat', unit: 'g', multiplier: 1 },
  { source: 'trans-fat', code: 'FATRN', name: 'Trans fat', unit: 'g', multiplier: 1 },
  { source: 'cholesterol', code: 'CHOLE', name: 'Cholesterol', unit: 'mg', multiplier: 1_000 },
  { source: 'omega-3-fat', code: 'OMEGA3', name: 'Omega-3 fat', unit: 'g', multiplier: 1 },
  { source: 'omega-6-fat', code: 'OMEGA6', name: 'Omega-6 fat', unit: 'g', multiplier: 1 },
  { source: 'added-sugars', code: 'SUGAR_ADDED', name: 'Added sugars', unit: 'g', multiplier: 1 },
  { source: 'starch', code: 'STARCH', name: 'Starch', unit: 'g', multiplier: 1 },
  { source: 'sodium', code: 'NA', name: 'Sodium', unit: 'mg', multiplier: 1_000 },
  { source: 'vitamin-a', code: 'VITA', name: 'Vitamin A', unit: 'µg', multiplier: 1_000_000 },
  { source: 'beta-carotene', code: 'CARTB', name: 'Beta-carotene', unit: 'µg', multiplier: 1_000_000 },
  { source: 'vitamin-d', code: 'VITD', name: 'Vitamin D', unit: 'µg', multiplier: 1_000_000 },
  { source: 'vitamin-e', code: 'VITE', name: 'Vitamin E', unit: 'mg', multiplier: 1_000 },
  { source: 'vitamin-k', code: 'VITK', name: 'Vitamin K', unit: 'µg', multiplier: 1_000_000 },
  { source: 'vitamin-c', code: 'VITC', name: 'Vitamin C', unit: 'mg', multiplier: 1_000 },
  { source: 'vitamin-b1', code: 'THIA', name: 'Thiamin (B1)', unit: 'mg', multiplier: 1_000 },
  { source: 'vitamin-b2', code: 'RIBF', name: 'Riboflavin (B2)', unit: 'mg', multiplier: 1_000 },
  { source: 'vitamin-pp', code: 'NIA', name: 'Niacin (B3)', unit: 'mg', multiplier: 1_000 },
  { source: 'pantothenic-acid', code: 'PANTAC', name: 'Pantothenic acid (B5)', unit: 'mg', multiplier: 1_000 },
  { source: 'vitamin-b6', code: 'VITB6A', name: 'Vitamin B6', unit: 'mg', multiplier: 1_000 },
  { source: 'biotin', code: 'BIOT', name: 'Biotin (B7)', unit: 'µg', multiplier: 1_000_000 },
  { source: 'folates', code: 'FOL', name: 'Folate (B9)', unit: 'µg', multiplier: 1_000_000 },
  { source: 'vitamin-b12', code: 'VITB12', name: 'Vitamin B12', unit: 'µg', multiplier: 1_000_000 },
  { source: 'calcium', code: 'CA', name: 'Calcium', unit: 'mg', multiplier: 1_000 },
  { source: 'iron', code: 'FE', name: 'Iron', unit: 'mg', multiplier: 1_000 },
  { source: 'magnesium', code: 'MG', name: 'Magnesium', unit: 'mg', multiplier: 1_000 },
  { source: 'phosphorus', code: 'P', name: 'Phosphorus', unit: 'mg', multiplier: 1_000 },
  { source: 'potassium', code: 'K', name: 'Potassium', unit: 'mg', multiplier: 1_000 },
  { source: 'zinc', code: 'ZN', name: 'Zinc', unit: 'mg', multiplier: 1_000 },
  { source: 'copper', code: 'CU', name: 'Copper', unit: 'mg', multiplier: 1_000 },
  { source: 'manganese', code: 'MN', name: 'Manganese', unit: 'mg', multiplier: 1_000 },
  { source: 'selenium', code: 'SE', name: 'Selenium', unit: 'µg', multiplier: 1_000_000 },
  { source: 'iodine', code: 'I', name: 'Iodine', unit: 'µg', multiplier: 1_000_000 },
]

function detailedNutrientEvidence(
  nutriments: Record<string, unknown>,
  barcode: string,
): ProviderNutrientEvidenceObservation[] {
  return detailedNutrients.flatMap<ProviderNutrientEvidenceObservation>((definition): ProviderNutrientEvidenceObservation[] => {
    const modifierValue = nutriments[`${definition.source}_modifier`]
    const modifier = typeof modifierValue === 'string' ? modifierValue.trim() : ''
    const rawGrams = finiteNumber(nutriments[`${definition.source}_100g`])
    const explicitlyMissing = modifier === '-'
    if ((rawGrams == null || rawGrams < 0 || rawGrams > 100) && !explicitlyMissing) return []
    const sourceValue = nutriments[`${definition.source}_value`]
    const sourceValueText = typeof sourceValue === 'string' || typeof sourceValue === 'number'
      ? String(sourceValue).trim()
      : rawGrams == null ? '' : String(rawGrams)
    const sourceUnitValue = nutriments[`${definition.source}_unit`]
    const sourceUnit = typeof sourceUnitValue === 'string' && sourceUnitValue.trim()
      ? sourceUnitValue.trim()
      : 'g'
    const originalValueText = sourceValueText
      ? `${modifier}${sourceValueText} ${sourceUnit}`.slice(0, 180)
      : modifier.slice(0, 180)
    const trace = modifier === '~' && rawGrams === 0
    const belowDetection = modifier === '<' || modifier === '≤' || modifier === '<='
    if (trace || belowDetection || explicitlyMissing) {
      return [{
        nutrient_code: definition.code,
        name: definition.name,
        value_per_100: null,
        unit: definition.unit,
        observation_status: trace ? 'trace' as const : belowDetection ? 'below_detection' as const : 'missing' as const,
        original_value_text: originalValueText,
        derivation_method: null,
        source_key: 'open_food_facts',
        source_reference: barcode,
      }]
    }
    if (rawGrams == null) return []
    const grams = Math.round(rawGrams * 1_000_000_000) / 1_000_000_000
    const converted = Math.round(grams * definition.multiplier * 1_000_000) / 1_000_000
    return [{
      nutrient_code: definition.code,
      name: definition.name,
      value_per_100: converted,
      unit: definition.unit,
      observation_status: 'reported' as const,
      original_value_text: originalValueText || `${grams} g/100`,
      derivation_method: definition.multiplier === 1
        ? null
        : 'open_food_facts_standard_grams_conversion',
      source_key: 'open_food_facts',
      source_reference: barcode,
    }]
  })
}

export function kilojoulesToKilocalories(kilojoules: number): number {
  return Math.round((kilojoules / 4.184) * 100) / 100
}

function text(product: Record<string, unknown>, key: string): string | null {
  const value = product[key]
  return typeof value === 'string' && value.trim() ? value.trim() : null
}

export function normalizeOpenFoodFactsProduct(
  payload: OpenFoodFactsResponse,
  requestedBarcode: string,
): NormalizedProviderFood | null {
  const barcode = normalizeBarcode(String(payload.code ?? requestedBarcode))
  if (!barcode || payload.status !== 1 || !payload.product) return null
  const product = payload.product
  const localized = {
    en: text(product, 'product_name_en'),
    de: text(product, 'product_name_de'),
    fr: text(product, 'product_name_fr'),
    it: text(product, 'product_name_it'),
    ro: text(product, 'product_name_ro'),
    th: text(product, 'product_name_th'),
  }
  const name = text(product, 'product_name') ?? localized.en ?? localized.de ?? localized.fr ?? localized.it ?? localized.ro ?? localized.th
  if (!name) return null
  const nutriments = product.nutriments && typeof product.nutriments === 'object'
    ? product.nutriments as Record<string, unknown>
    : {}
  let kcal = safeNutrient(nutriments['energy-kcal_100g'], 1000)
  if (kcal == null) {
    const kj = safeNutrient(nutriments['energy-kj_100g'] ?? nutriments.energy_100g, 5000)
    if (kj != null) kcal = kilojoulesToKilocalories(kj)
  }
  const protein = safeNutrient(nutriments.proteins_100g)
  const carbs = safeNutrient(nutriments.carbohydrates_100g)
  const fat = safeNutrient(nutriments.fat_100g)
  const required = [kcal, protein, carbs, fat]
  if (required.filter((value) => value != null).length < 2) return null
  if ((protein ?? 0) + (carbs ?? 0) + (fat ?? 0) > 110) return null

  const quantityUnit = text(product, 'product_quantity_unit')?.toLocaleLowerCase('en')
  const basis = quantityUnit === 'ml' || quantityUnit === 'l' ? 'per_100ml' : 'per_100g'
  const servingQuantity = safeNutrient(product.serving_quantity, 5000)
  const providerTimestamp = finiteNumber(product.last_modified_t)
  const reportedWater = safeNutrient(nutriments.water_100g, 100)
  const names_i18n = Object.fromEntries(
    Object.entries(localized).filter((entry): entry is [string, string] => Boolean(entry[1])),
  ) as NormalizedProviderFood['names_i18n']
  return {
    name,
    names_i18n,
    brand: text(product, 'brands'),
    barcode,
    source: 'open_food_facts',
    provider_product_id: barcode,
    external_image_url: text(product, 'image_front_small_url'),
    package_quantity: text(product, 'quantity'),
    nutrition_basis: basis,
    preparation_state: 'as_sold',
    kcal_100: kcal,
    protein_100: protein,
    carbs_100: carbs,
    fat_100: fat,
    fibre_100: safeNutrient(nutriments.fiber_100g),
    sugar_100: safeNutrient(nutriments.sugars_100g),
    saturated_fat_100: safeNutrient(nutriments['saturated-fat_100g']),
    salt_100: safeNutrient(nutriments.salt_100g, 50),
    /* Open Food Facts rarely publishes water, so this is usually null and the
       hydration estimator fills it from the composition instead. */
    water_ml_100: reportedWater,
    water_basis: reportedWater == null ? 'unknown' : 'provider_reported',
    water_source_id: reportedWater == null ? null : `open-food-facts:${barcode}`,
    serving_amount: servingQuantity,
    serving_unit: servingQuantity == null ? null : basis === 'per_100ml' ? 'ml' : 'g',
    serving_grams_or_ml: servingQuantity,
    provider_updated_at: providerTimestamp == null ? null : new Date(providerTimestamp * 1000).toISOString(),
    confidence: required.every((value) => value != null) ? 'provider_verified' : 'partial',
    nutrient_evidence: detailedNutrientEvidence(nutriments, barcode),
  }
}

export function openFoodFactsUrl(barcode: string): string | null {
  const normalized = normalizeBarcode(barcode)
  if (!normalized) return null
  return `https://world.openfoodfacts.org/api/v2/product/${normalized}.json?fields=${encodeURIComponent(OPEN_FOOD_FACTS_FIELDS)}`
}
