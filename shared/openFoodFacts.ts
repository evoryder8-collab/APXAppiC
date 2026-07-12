export const OPEN_FOOD_FACTS_FIELDS = [
  'code',
  'product_name',
  'product_name_en',
  'product_name_de',
  'product_name_fr',
  'product_name_it',
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
  names_i18n: Partial<Record<'en' | 'de' | 'fr' | 'it', string>>
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
  sugar_100: number | null
  saturated_fat_100: number | null
  salt_100: number | null
  serving_amount: number | null
  serving_unit: 'g' | 'ml' | null
  serving_grams_or_ml: number | null
  provider_updated_at: string | null
  confidence: 'complete' | 'partial' | 'provider_verified'
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
  }
  const name = text(product, 'product_name') ?? localized.en ?? localized.de ?? localized.fr ?? localized.it
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
    serving_amount: servingQuantity,
    serving_unit: servingQuantity == null ? null : basis === 'per_100ml' ? 'ml' : 'g',
    serving_grams_or_ml: servingQuantity,
    provider_updated_at: providerTimestamp == null ? null : new Date(providerTimestamp * 1000).toISOString(),
    confidence: required.every((value) => value != null) ? 'provider_verified' : 'partial',
  }
}

export function openFoodFactsUrl(barcode: string): string | null {
  const normalized = normalizeBarcode(barcode)
  if (!normalized) return null
  return `https://world.openfoodfacts.org/api/v2/product/${normalized}.json?fields=${encodeURIComponent(OPEN_FOOD_FACTS_FIELDS)}`
}
