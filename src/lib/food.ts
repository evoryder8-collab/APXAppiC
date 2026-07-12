export type MealSlot = 'breakfast' | 'lunch' | 'dinner' | 'snack'
export type FoodUnit = 'g' | 'ml' | 'serving' | 'piece'
export type NutritionBasis = 'per_100g' | 'per_100ml'
export type PreparationState = 'dry' | 'cooked' | 'prepared' | 'drained' | 'as_sold' | 'unknown'
export type FoodSource = 'open_food_facts' | 'private' | 'apex_cache'
export type NutritionConfidence = 'complete' | 'partial' | 'user_entered' | 'provider_verified'

export interface FoodRecord {
  id: string
  owner_user_id: string | null
  name: string
  names_i18n: Partial<Record<'en' | 'de' | 'fr' | 'it', string>>
  brand: string | null
  barcode: string | null
  source: FoodSource
  provider_product_id: string | null
  external_image_url: string | null
  package_quantity: string | null
  nutrition_basis: NutritionBasis
  preparation_state: PreparationState
  kcal_100: number | null
  protein_100: number | null
  carbs_100: number | null
  fat_100: number | null
  fibre_100: number | null
  sugar_100: number | null
  saturated_fat_100: number | null
  salt_100: number | null
  serving_amount: number | null
  serving_unit: FoodUnit | null
  serving_grams_or_ml: number | null
  piece_grams_or_ml: number | null
  provider_updated_at: string | null
  confidence: NutritionConfidence
  created_at: string
  updated_at: string
}

export interface FoodPreference {
  id: string
  user_id: string
  food_id: string
  personal_name: string | null
  aliases: string[]
  favourite: boolean
  usual_amount: number | null
  usual_unit: FoodUnit | null
  usage_count: number
  last_used_at: string | null
  hidden: boolean
  slot_usage: Partial<Record<MealSlot, number>>
  version: number
  updated_at: string
}

export interface PortionNutrition {
  equivalent_amount: number
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fibre_g: number | null
  sugar_g: number | null
  saturated_fat_g: number | null
  salt_g: number | null
}

export interface ComposerFoodItem {
  id: string
  food: FoodRecord
  quantity: number
  unit: FoodUnit
  sort_order: number
  optional: boolean
  locked: boolean
  adjustable: boolean
  minimum_amount: number | null
  maximum_amount: number | null
  step_amount: number | null
  adjustment_role: 'carb' | 'protein' | 'energy' | 'none'
}

export interface LoggedMeal {
  id: string
  user_id: string
  local_date: string
  meal_slot: MealSlot
  display_name: string
  source_preset_id: string | null
  source_planned_meal_id: string | null
  logged_at: string
  client_idempotency_key: string
  logged_as: 'planned' | 'changed' | 'custom'
  total_kcal: number
  total_protein_g: number
  total_carbs_g: number
  total_fat_g: number
  created_at: string
  updated_at: string
}

/* Every nutrition field below is a snapshot. It intentionally duplicates the
   food record so provider refreshes and preset edits cannot rewrite history. */
export interface LoggedFoodEntry {
  id: string
  meal_id: string
  user_id: string
  food_id: string | null
  sort_order: number
  snapshot_name: string
  snapshot_brand: string | null
  snapshot_preparation_state: PreparationState
  snapshot_nutrition_basis: NutritionBasis
  snapshot_kcal_100: number
  snapshot_protein_100: number
  snapshot_carbs_100: number
  snapshot_fat_100: number
  snapshot_fibre_100: number | null
  snapshot_sugar_100: number | null
  snapshot_saturated_fat_100: number | null
  snapshot_salt_100: number | null
  quantity: number
  unit: FoodUnit
  equivalent_amount: number
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fibre_g: number | null
  sugar_g: number | null
  saturated_fat_g: number | null
  salt_g: number | null
  created_at: string
}

export interface MealPreset {
  id: string
  user_id: string
  name: string
  meal_slot: MealSlot
  source_planned_meal_id: string | null
  archived: boolean
  version: number
  created_at: string
  updated_at: string
}

export interface MealPresetItem {
  id: string
  preset_id: string
  user_id: string
  food_id: string
  sort_order: number
  quantity: number
  unit: FoodUnit
  optional: boolean
  locked: boolean
  adjustable: boolean
  minimum_amount: number | null
  maximum_amount: number | null
  step_amount: number | null
  adjustment_role: 'carb' | 'protein' | 'energy' | 'none'
}

export interface MealTotals {
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
}

export interface AdaptiveContext {
  target: MealTotals
  consumed: MealTotals
  activityLabel: string
  trainingToday: boolean
}

export interface AdaptiveSuggestion {
  item_id: string
  food_name: string
  original_quantity: number
  proposed_quantity: number
  unit: FoodUnit
  delta: MealTotals
  explanation: string
}

export function normalizeFoodSearch(value: string): string {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('en')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

export function parseDecimalInput(value: string | number): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null
  let normalized = value.trim().replace(/[\s']/g, '')
  if (!normalized) return null
  if (normalized.includes(',') && normalized.includes('.')) {
    normalized = normalized.lastIndexOf(',') > normalized.lastIndexOf('.')
      ? normalized.replace(/\./g, '').replace(',', '.')
      : normalized.replace(/,/g, '')
  } else {
    normalized = normalized.replace(',', '.')
  }
  const parsed = Number(normalized)
  return Number.isFinite(parsed) ? parsed : null
}

export function isFoodNutritionComplete(food: FoodRecord): boolean {
  return [food.kcal_100, food.protein_100, food.carbs_100, food.fat_100]
    .every((value) => value != null && Number.isFinite(value) && value >= 0)
}

export function equivalentAmount(food: FoodRecord, quantity: number, unit: FoodUnit): number | null {
  if (!Number.isFinite(quantity) || quantity <= 0) return null
  if (unit === 'g') return food.nutrition_basis === 'per_100g' ? quantity : null
  if (unit === 'ml') return food.nutrition_basis === 'per_100ml' ? quantity : null
  if (unit === 'serving') {
    return food.serving_grams_or_ml == null ? null : quantity * food.serving_grams_or_ml
  }
  return food.piece_grams_or_ml == null ? null : quantity * food.piece_grams_or_ml
}

function scaled(value: number | null, factor: number): number | null {
  return value == null ? null : Math.round(value * factor * 100) / 100
}

export function calculatePortion(food: FoodRecord, quantity: number, unit: FoodUnit): PortionNutrition | null {
  if (!isFoodNutritionComplete(food)) return null
  const equivalent = equivalentAmount(food, quantity, unit)
  if (equivalent == null) return null
  const factor = equivalent / 100
  return {
    equivalent_amount: Math.round(equivalent * 100) / 100,
    kcal: Math.round((food.kcal_100 ?? 0) * factor),
    protein_g: Math.round((food.protein_100 ?? 0) * factor * 10) / 10,
    carbs_g: Math.round((food.carbs_100 ?? 0) * factor * 10) / 10,
    fat_g: Math.round((food.fat_100 ?? 0) * factor * 10) / 10,
    fibre_g: scaled(food.fibre_100, factor),
    sugar_g: scaled(food.sugar_100, factor),
    saturated_fat_g: scaled(food.saturated_fat_100, factor),
    salt_g: scaled(food.salt_100, factor),
  }
}

export function mealTotals(items: ComposerFoodItem[]): MealTotals {
  return items.reduce<MealTotals>((total, item) => {
    const portion = calculatePortion(item.food, item.quantity, item.unit)
    if (!portion) return total
    return {
      kcal: total.kcal + portion.kcal,
      protein_g: Math.round((total.protein_g + portion.protein_g) * 10) / 10,
      carbs_g: Math.round((total.carbs_g + portion.carbs_g) * 10) / 10,
      fat_g: Math.round((total.fat_g + portion.fat_g) * 10) / 10,
    }
  }, { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 })
}

export function snapshotEntry(
  item: ComposerFoodItem,
  userId: string,
  mealId: string,
  now = new Date().toISOString(),
): LoggedFoodEntry | null {
  const portion = calculatePortion(item.food, item.quantity, item.unit)
  if (!portion || !isFoodNutritionComplete(item.food)) return null
  return {
    id: crypto.randomUUID(),
    meal_id: mealId,
    user_id: userId,
    food_id: item.food.id,
    sort_order: item.sort_order,
    snapshot_name: item.food.name,
    snapshot_brand: item.food.brand,
    snapshot_preparation_state: item.food.preparation_state,
    snapshot_nutrition_basis: item.food.nutrition_basis,
    snapshot_kcal_100: item.food.kcal_100 ?? 0,
    snapshot_protein_100: item.food.protein_100 ?? 0,
    snapshot_carbs_100: item.food.carbs_100 ?? 0,
    snapshot_fat_100: item.food.fat_100 ?? 0,
    snapshot_fibre_100: item.food.fibre_100,
    snapshot_sugar_100: item.food.sugar_100,
    snapshot_saturated_fat_100: item.food.saturated_fat_100,
    snapshot_salt_100: item.food.salt_100,
    quantity: item.quantity,
    unit: item.unit,
    ...portion,
    created_at: now,
  }
}

function preferenceFor(foodId: string, preferences: FoodPreference[]): FoodPreference | undefined {
  return preferences.find((preference) => preference.food_id === foodId)
}

export function rankFoods(
  query: string,
  foods: FoodRecord[],
  preferences: FoodPreference[],
  slot: MealSlot,
  now = Date.now(),
): FoodRecord[] {
  const needle = normalizeFoodSearch(query)
  return foods
    .map((food) => {
      const preference = preferenceFor(food.id, preferences)
      if (preference?.hidden) return { food, score: -Infinity }
      const names = [
        food.name,
        food.brand ?? '',
        ...Object.values(food.names_i18n),
      ].map(normalizeFoodSearch)
      const personal = normalizeFoodSearch(preference?.personal_name ?? '')
      const aliases = (preference?.aliases ?? []).map(normalizeFoodSearch)
      const searchable = [...names, personal, ...aliases].filter(Boolean)
      if (needle && !searchable.some((value) => value.includes(needle))) return { food, score: -Infinity }

      let score = 0
      if (needle) {
        if (personal === needle) score += 1200
        if (aliases.includes(needle)) score += 1120
        if (names[0] === needle) score += 1040
        if (`${names[1]} ${names[0]}`.trim() === needle) score += 1000
        if (searchable.some((value) => value.startsWith(needle))) score += 500
        if (searchable.some((value) => value.includes(needle))) score += 220
      }
      if (preference?.favourite) score += 360
      score += Math.min(240, (preference?.usage_count ?? 0) * 12)
      score += Math.min(180, (preference?.slot_usage[slot] ?? 0) * 18)
      if (preference?.last_used_at) {
        const ageDays = Math.max(0, (now - new Date(preference.last_used_at).getTime()) / 86_400_000)
        score += Math.max(0, 160 - ageDays * 4)
      }
      if (food.owner_user_id) score += 70
      if (food.source === 'apex_cache') score += 30
      return { food, score }
    })
    .filter((candidate) => Number.isFinite(candidate.score))
    .sort((a, b) => b.score - a.score || a.food.name.localeCompare(b.food.name))
    .map((candidate) => candidate.food)
}

function clampStepped(value: number, min: number, max: number, step: number): number {
  const stepped = Math.round(value / step) * step
  return Math.max(min, Math.min(max, Math.round(stepped * 100) / 100))
}

export function suggestPresetAdaptation(
  items: ComposerFoodItem[],
  context: AdaptiveContext,
): AdaptiveSuggestion[] {
  const current = mealTotals(items)
  const remaining = {
    kcal: Math.max(0, context.target.kcal - context.consumed.kcal),
    protein_g: Math.max(0, context.target.protein_g - context.consumed.protein_g),
    carbs_g: Math.max(0, context.target.carbs_g - context.consumed.carbs_g),
    fat_g: Math.max(0, context.target.fat_g - context.consumed.fat_g),
  }
  const proteinGap = remaining.protein_g - current.protein_g
  const calorieGap = remaining.kcal - current.kcal
  const preferredRole = proteinGap >= 15 ? 'protein' : 'carb'
  const candidate = items
    .filter((item) => item.adjustable && !item.locked && item.adjustment_role !== 'none')
    .sort((a, b) => {
      const ap = a.adjustment_role === preferredRole ? 2 : a.adjustment_role === 'energy' ? 1 : 0
      const bp = b.adjustment_role === preferredRole ? 2 : b.adjustment_role === 'energy' ? 1 : 0
      return bp - ap || a.sort_order - b.sort_order
    })[0]
  if (!candidate || Math.abs(calorieGap) < 40) return []
  const currentPortion = calculatePortion(candidate.food, candidate.quantity, candidate.unit)
  if (!currentPortion || currentPortion.kcal <= 0) return []
  const kcalPerUnit = currentPortion.kcal / candidate.quantity
  const min = candidate.minimum_amount ?? Math.max(0, candidate.quantity * 0.5)
  const max = candidate.maximum_amount ?? candidate.quantity * 1.75
  const step = candidate.step_amount ?? (candidate.unit === 'piece' ? 1 : 5)
  const proposed = clampStepped(candidate.quantity + calorieGap / kcalPerUnit, min, max, step)
  if (proposed === candidate.quantity) return []
  const proposedPortion = calculatePortion(candidate.food, proposed, candidate.unit)
  if (!proposedPortion) return []
  const delta = {
    kcal: proposedPortion.kcal - currentPortion.kcal,
    protein_g: Math.round((proposedPortion.protein_g - currentPortion.protein_g) * 10) / 10,
    carbs_g: Math.round((proposedPortion.carbs_g - currentPortion.carbs_g) * 10) / 10,
    fat_g: Math.round((proposedPortion.fat_g - currentPortion.fat_g) * 10) / 10,
  }
  const direction = proposed > candidate.quantity ? 'increase' : 'reduce'
  const rationale = preferredRole === 'protein'
    ? 'Protein is meaningfully below today’s protected target.'
    : `${context.activityLabel}${context.trainingToday ? ' training' : ''} leaves ${calorieGap > 0 ? 'more' : 'less'} flexible energy for this meal.`
  return [{
    item_id: candidate.id,
    food_name: candidate.food.name,
    original_quantity: candidate.quantity,
    proposed_quantity: proposed,
    unit: candidate.unit,
    delta,
    explanation: `APEX suggests you ${direction} this adjustable item. ${rationale}`,
  }]
}

export function aggregateLoggedMeals(meals: LoggedMeal[]): MealTotals {
  return meals.reduce<MealTotals>((sum, meal) => ({
    kcal: sum.kcal + meal.total_kcal,
    protein_g: Math.round((sum.protein_g + meal.total_protein_g) * 10) / 10,
    carbs_g: Math.round((sum.carbs_g + meal.total_carbs_g) * 10) / 10,
    fat_g: Math.round((sum.fat_g + meal.total_fat_g) * 10) / 10,
  }), { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 })
}

export function mergeMealsIdempotently(current: LoggedMeal[], incoming: LoggedMeal[]): LoggedMeal[] {
  const byKey = new Map(current.map((meal) => [`${meal.user_id}:${meal.client_idempotency_key}`, meal]))
  for (const meal of incoming) byKey.set(`${meal.user_id}:${meal.client_idempotency_key}`, meal)
  return [...byKey.values()]
}
