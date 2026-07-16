import type { IntroLanguage } from './introLanguage'

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
  names_i18n: Partial<Record<'en' | 'de' | 'fr' | 'it' | 'ro' | 'th', string>>
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

export function foodPreferenceUsageUpdates(
  current: FoodPreference[],
  items: ComposerFoodItem[],
  userId: string,
  slot: MealSlot,
  now: string,
  createId: () => string = () => crypto.randomUUID(),
): FoodPreference[] {
  const working = new Map(current.map((preference) => [preference.food_id, preference]))
  const touched = new Set<string>()
  for (const item of items) {
    const previous = working.get(item.food.id)
    working.set(item.food.id, {
      id: previous?.id ?? createId(),
      user_id: userId,
      food_id: item.food.id,
      personal_name: previous?.personal_name ?? null,
      aliases: previous?.aliases ?? [],
      favourite: previous?.favourite ?? false,
      usual_amount: previous?.usual_amount ?? item.quantity,
      usual_unit: previous?.usual_unit ?? item.unit,
      usage_count: (previous?.usage_count ?? 0) + 1,
      last_used_at: now,
      hidden: previous?.hidden ?? false,
      slot_usage: { ...(previous?.slot_usage ?? {}), [slot]: (previous?.slot_usage?.[slot] ?? 0) + 1 },
      version: (previous?.version ?? 0) + 1,
      updated_at: now,
    })
    touched.add(item.food.id)
  }
  return [...touched].map((foodId) => working.get(foodId)!)
}

/**
 * A search result is intentionally kept separate from the meal until the user
 * confirms its amount. This prevents a tap on a result from silently logging a
 * 100 g portion and gives the composer one canonical quantity calculation path.
 */
export interface FoodSelectionDraft {
  food: FoodRecord
  quantity: number
  unit: FoodUnit
}

export function availableFoodUnits(food: FoodRecord): FoodUnit[] {
  const basisUnit: FoodUnit = food.nutrition_basis === 'per_100ml' ? 'ml' : 'g'
  return [
    basisUnit,
    ...(food.serving_grams_or_ml != null && food.serving_grams_or_ml > 0 ? ['serving' as const] : []),
    ...(food.piece_grams_or_ml != null && food.piece_grams_or_ml > 0 ? ['piece' as const] : []),
  ]
}

export function beginFoodSelection(food: FoodRecord, preference?: FoodPreference): FoodSelectionDraft {
  const units = availableFoodUnits(food)
  if (
    preference?.usual_amount != null
    && preference.usual_amount > 0
    && preference.usual_unit != null
    && units.includes(preference.usual_unit)
  ) {
    return { food, quantity: preference.usual_amount, unit: preference.usual_unit }
  }
  if (food.piece_grams_or_ml != null && food.piece_grams_or_ml > 0) return { food, quantity: 1, unit: 'piece' }
  if (food.serving_grams_or_ml != null && food.serving_grams_or_ml > 0) return { food, quantity: 1, unit: 'serving' }
  return { food, quantity: 100, unit: units[0] }
}

export function composerItemFromSelection(
  selection: FoodSelectionDraft,
  index: number,
  id: string = crypto.randomUUID(),
): ComposerFoodItem {
  const { food, quantity, unit } = selection
  return {
    id,
    food,
    quantity,
    unit,
    sort_order: index,
    optional: false,
    locked: true,
    adjustable: false,
    minimum_amount: null,
    maximum_amount: null,
    step_amount: unit === 'piece' || unit === 'serving' ? 1 : 5,
    adjustment_role: food.carbs_100 != null && food.protein_100 != null && food.carbs_100 > food.protein_100
      ? 'carb'
      : 'protein',
  }
}

export function commitFoodSelection(
  items: ComposerFoodItem[],
  selection: FoodSelectionDraft,
  id?: string,
): ComposerFoodItem[] {
  return [...items, composerItemFromSelection(selection, items.length, id)]
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

/* Always derive the next history from the latest committed collection. This is
   intentionally tiny, but centralising the rule prevents rapid multi-meal
   operations from replacing one another with a stale render snapshot. */
export function addLoggedMealToHistory(
  current: LoggedMeal[],
  meal: LoggedMeal,
  replaceMealId: string | null = null,
): LoggedMeal[] {
  return [meal, ...current.filter((value) => value.id !== replaceMealId && value.id !== meal.id)]
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

export interface PlannedNutritionMeal extends MealTotals {
  id: string
  name: string
}

export interface ConsumedMeal extends MealTotals {
  id: string
  name: string
  planned_meal_id: string | null
  source: 'logged' | 'checked_plan'
  logged_meal: LoggedMeal | null
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
    .toLocaleLowerCase()
    .replace(/[^\p{L}\p{N}\p{M}]+/gu, ' ')
    .replace(/\b(?:airfryer|airfried)\b/g, 'air fryer')
    .trim()
}

const FOOD_SEARCH_PHRASES: Record<'ro' | 'th', Record<string, string>> = {
  ro: {
    'piept de pui': 'chicken breast',
    'piept de pui crud': 'chicken breast raw',
    'piept de pui fiert': 'chicken breast boiled',
    'piept de pui gatit': 'chicken breast cooked',
    'piept de pui la air fryer': 'chicken breast air fryer',
    'cartof': 'potato',
    'cartofi': 'potato',
    'cartof dulce la microunde': 'sweet potato microwaved',
    'cartof dulce copt': 'sweet potato baked',
    'proteina din zer': 'whey protein',
    'izolat proteic din zer': 'whey protein isolate',
    'izolat proteic din cazeina': 'casein protein isolate',
    'orez alb fiert': 'white rice cooked',
    'ou intreg': 'whole egg',
    'ovaz': 'oats',
    'ovaz integral': 'whole grain oats',
    'ovaz integral organic': 'organic whole grain oats',
    'som tam': 'som tam thai green papaya salad',
    'salata de papaya verde': 'green papaya salad',
    'sos de peste': 'fish sauce',
    'avocado crud': 'avocado raw',
    'ou crud': 'egg raw',
    'oua crude': 'eggs raw',
    'ou fiert': 'egg boiled',
    'oua fierte': 'eggs boiled',
    'afine': 'blueberries',
    'afine proaspete': 'fresh blueberries',
    'afine congelate': 'frozen blueberries',
    'zmeura': 'raspberries',
    'zmeura proaspata': 'fresh raspberries',
    'zmeura congelata': 'frozen raspberries',
    'fructe de padure': 'mixed berries',
    'fructe de padure congelate': 'frozen mixed berries',
    'spanac proaspat': 'fresh spinach',
    'spanac congelat': 'frozen spinach',
    'mazare congelata': 'frozen green peas',
    'ton in suc propriu': 'tuna in own juice',
  },
  th: {
    'อกไก่': 'chicken breast',
    'อกไก่ดิบ': 'chicken breast raw',
    'อกไก่สุก': 'chicken breast cooked',
    'อกไก่ต้ม': 'chicken breast boiled',
    'มันฝรั่ง': 'potato',
    'มันหวานไมโครเวฟ': 'sweet potato microwaved',
    'มันหวานอบ': 'sweet potato baked',
    'เวย์โปรตีน': 'whey protein',
    'เวย์โปรตีนไอโซเลต': 'whey protein isolate',
    'เคซีนโปรตีนไอโซเลต': 'casein protein isolate',
    'ข้าวขาวสุก': 'white rice cooked',
    'ไข่ทั้งฟอง': 'whole egg',
    'ข้าวโอ๊ตออร์แกนิก': 'organic oats',
    'ข้าวโอ๊ตโฮลเกรนออร์แกนิก': 'organic whole grain oats',
    'ส้มตำ': 'som tam thai green papaya salad',
    'ส้มตำไทย': 'som tam thai green papaya salad',
    'น้ำปลา': 'fish sauce',
    'อะโวคาโด': 'avocado',
    'ไข่ดิบ': 'egg raw',
    'ไข่ต้ม': 'egg boiled',
    'บลูเบอร์รี': 'blueberries',
    'บลูเบอร์รี่': 'blueberries',
    'บลูเบอร์รีสด': 'fresh blueberries',
    'บลูเบอร์รี่สด': 'fresh blueberries',
    'บลูเบอร์รีแช่แข็ง': 'frozen blueberries',
    'บลูเบอร์รี่แช่แข็ง': 'frozen blueberries',
    'ราสป์เบอร์รี': 'raspberries',
    'ราสเบอร์รี': 'raspberries',
    'เบอร์รีรวมแช่แข็ง': 'frozen mixed berries',
    'ผักโขมสด': 'fresh spinach',
    'ผักโขมแช่แข็ง': 'frozen spinach',
    'ถั่วลันเตาแช่แข็ง': 'frozen green peas',
    'ทูน่าในน้ำแร่': 'tuna in own juice',
  },
}

const FOOD_SEARCH_TOKENS: Record<'ro' | 'th', Record<string, string>> = {
  ro: {
    piept: 'breast', pui: 'chicken', curcan: 'turkey', vita: 'beef', porc: 'pork', peste: 'fish',
    somon: 'salmon', ton: 'tuna', ou: 'egg', oua: 'eggs', cartof: 'potato', dulce: 'sweet',
    orez: 'rice', ovaz: 'oats', iaurt: 'yogurt', branza: 'cheese', lapte: 'milk', mar: 'apple',
    banana: 'banana', broccoli: 'broccoli', crud: 'raw', cruda: 'raw', crude: 'raw', gatit: 'cooked',
    gatita: 'cooked', fiert: 'boiled', fiarta: 'boiled', copt: 'baked', coapta: 'baked',
    microunde: 'microwaved', gratar: 'grilled', prajit: 'fried', prajita: 'fried', abur: 'steamed',
    proteina: 'protein', proteic: 'protein', zer: 'whey', cazeina: 'casein', izolat: 'isolate',
    integral: 'whole grain', organic: 'organic', sos: 'sauce', avocado: 'avocado',
    afine: 'blueberries', zmeura: 'raspberries', fructe: 'fruit', padure: 'berries',
    spanac: 'spinach', mazare: 'peas', proaspat: 'fresh', proaspata: 'fresh', proaspete: 'fresh',
    congelat: 'frozen', congelata: 'frozen', congelate: 'frozen', suc: 'juice', propriu: 'own',
    de: '', din: '', la: '',
  },
  th: {
    อกไก่: 'chicken breast', ไก่: 'chicken', ไก่งวง: 'turkey', เนื้อวัว: 'beef', หมู: 'pork', ปลา: 'fish',
    แซลมอน: 'salmon', ทูน่า: 'tuna', ไข่: 'egg', มันหวาน: 'sweet potato', มันฝรั่ง: 'potato',
    ข้าว: 'rice', ข้าวโอ๊ต: 'oats', โยเกิร์ต: 'yogurt', ชีส: 'cheese', นม: 'milk',
    ดิบ: 'raw', สุก: 'cooked', ต้ม: 'boiled', อบ: 'baked', ไมโครเวฟ: 'microwaved',
    ย่าง: 'grilled', ทอด: 'fried', นึ่ง: 'steamed',
    เวย์: 'whey', โปรตีน: 'protein', เคซีน: 'casein', ไอโซเลต: 'isolate',
    ส้มตำ: 'som tam', น้ำปลา: 'fish sauce', อะโวคาโด: 'avocado', ไข่ดิบ: 'egg raw', ไข่ต้ม: 'egg boiled',
    บลูเบอร์รี: 'blueberries', บลูเบอร์รี่: 'blueberries', ราสป์เบอร์รี: 'raspberries', ราสเบอร์รี: 'raspberries',
    เบอร์รี: 'berries', ผักโขม: 'spinach', ถั่วลันเตา: 'green peas', สด: 'fresh', แช่แข็ง: 'frozen',
  },
}

export function expandFoodSearchQueries(query: string, language: IntroLanguage): string[] {
  const original = query.trim()
  if (!original) return []
  if (language === 'en') return [original]
  const normalized = normalizeFoodSearch(original)
  const phrase = FOOD_SEARCH_PHRASES[language][normalized]
  const tokenMap = FOOD_SEARCH_TOKENS[language]
  const tokenTranslation = normalized
    .split(' ')
    .map((token) => tokenMap[token] ?? token)
    .filter(Boolean)
    .join(' ')
    .trim()
  return [...new Set([original, phrase, tokenTranslation].filter((value): value is string => Boolean(value)))]
}

export function displayFoodName(food: FoodRecord, language: IntroLanguage): string {
  return food.names_i18n[language] || food.name
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

const FOOD_CATALOG_ALIASES: Record<string, string[]> = {
  'apex-curated:usda-fdc-173904': [
    'oats', 'organic oats', 'whole grain oats', 'organic whole grain oats',
    'ovaz', 'ovăz', 'ovaz integral', 'ovăz integral', 'ovaz integral organic', 'ovăz integral organic',
    'ข้าวโอ๊ต', 'ข้าวโอ๊ตออร์แกนิก', 'ข้าวโอ๊ตโฮลเกรนออร์แกนิก',
  ],
  'apex-curated:som-tam-thai-reference': [
    'som tam', 'som tam thai', 'green papaya salad', 'salata de papaya verde', 'salată de papaya verde', 'ส้มตำ', 'ส้มตำไทย',
  ],
  'apex-curated:usda-fdc-2706457': ['fish sauce', 'sos de peste', 'sos de pește', 'น้ำปลา'],
  'apex-curated:usda-fdc-171705': ['avocado', 'avocado raw', 'avocado crud', 'อะโวคาโด', 'อะโวคาโดดิบ'],
  'apex-curated:usda-fdc-171287': ['raw egg', 'whole egg raw', 'egg raw', 'ou crud', 'oua crude', 'ouă crude', 'ไข่ดิบ', 'ไข่ไก่ดิบ'],
  'apex-curated:usda-fdc-173424': ['boiled egg', 'hard boiled egg', 'whole egg boiled', 'ou fiert', 'oua fierte', 'ouă fierte', 'ไข่ต้ม', 'ไข่ต้มสุก'],
  'apex-curated:lidl-nixe-tuna-own-juice-label': [
    'nixe tuna', 'nixe thunfischfilets', 'tuna in own juice', 'ton in suc propriu', 'ton nixe',
    'ทูน่าในน้ำแร่', 'ทูน่า nixe', 'lidl tuna', 'lidl ton',
  ],
  'apex-curated:swiss-retail-blueberries-fresh-reference': [
    'blueberries', 'fresh blueberries', 'afine', 'afine proaspete', 'afine proaspătă',
    'บลูเบอร์รี', 'บลูเบอร์รี่', 'บลูเบอร์รีสด', 'aldi blueberries', 'lidl blueberries',
  ],
  'apex-curated:swiss-retail-blueberries-frozen-reference': [
    'blueberries', 'frozen blueberries', 'afine', 'afine congelate',
    'บลูเบอร์รีแช่แข็ง', 'บลูเบอร์รี่แช่แข็ง', 'aldi frozen fruit', 'lidl frozen fruit',
  ],
  'apex-curated:swiss-retail-raspberries-fresh-reference': [
    'raspberries', 'fresh raspberries', 'zmeura', 'zmeură', 'zmeura proaspata',
    'ราสป์เบอร์รี', 'ราสเบอร์รี', 'aldi raspberries', 'lidl raspberries',
  ],
  'apex-curated:swiss-retail-raspberries-frozen-reference': [
    'raspberries', 'frozen raspberries', 'zmeura congelata', 'zmeură congelată',
    'ราสป์เบอร์รีแช่แข็ง', 'ราสเบอร์รีแช่แข็ง', 'aldi frozen fruit', 'lidl frozen fruit',
  ],
  'apex-curated:swiss-retail-mixed-berries-frozen-reference': [
    'mixed berries', 'frozen mixed berries', 'fructe de padure', 'fructe de pădure congelate',
    'เบอร์รีรวมแช่แข็ง', 'aldi frozen berries', 'lidl frozen berries',
  ],
  'apex-curated:swiss-retail-spinach-fresh-reference': [
    'spinach', 'fresh spinach', 'spanac', 'spanac proaspat', 'spanac proaspăt', 'ผักโขมสด',
    'aldi spinach', 'lidl spinach',
  ],
  'apex-curated:swiss-retail-spinach-frozen-reference': [
    'spinach', 'frozen spinach', 'spanac congelat', 'ผักโขมแช่แข็ง', 'aldi frozen spinach', 'lidl frozen spinach',
  ],
  'apex-curated:swiss-retail-green-peas-frozen-reference': [
    'green peas', 'frozen peas', 'mazare congelata', 'mazăre congelată', 'ถั่วลันเตาแช่แข็ง',
    'aldi frozen peas', 'lidl frozen peas',
  ],
}

function catalogAliases(food: FoodRecord): string[] {
  return food.provider_product_id ? FOOD_CATALOG_ALIASES[food.provider_product_id] ?? [] : []
}

function foodSearchText(food: FoodRecord): string {
  return [food.name, food.brand ?? '', ...Object.values(food.names_i18n), ...catalogAliases(food)]
    .map(normalizeFoodSearch)
    .join(' ')
}

function includesAny(value: string, terms: string[]): boolean {
  return terms.some((term) => value.includes(term))
}

function categorySearchBoost(query: string, food: FoodRecord): number {
  const text = foodSearchText(food)
  const curated = food.provider_product_id?.startsWith('apex-curated:') ? 220 : 0
  const chickenQuery = includesAny(query, ['chicken breast', 'piept de pui', 'อกไก่'])
  if (chickenQuery) {
    if (includesAny(text, [' raw', ' crud', ' ดิบ'])) return curated + 840
    if (includesAny(text, ['boiled', 'fiert', 'bouilli', 'bollito', ' ต้ม'])) return curated + 760
    if (includesAny(text, ['air fryer', 'heissluftfritteuse', 'heißluftfritteuse', 'หม้อทอดไร้น้ำมัน'])) return curated + 680
    if (includesAny(text, ['cooked', 'gatit', 'gegart', 'cuit', 'cotto', ' สุก'])) return curated + 520
  }

  const plainPotatoQuery = includesAny(query, ['potato', 'cartof', 'มันฝรั่ง'])
    && !includesAny(query, ['sweet potato', 'cartof dulce', 'มันหวาน'])
  if (plainPotatoQuery) {
    if (includesAny(text, ['pringles', 'lays', 'chips', 'crisps', 'potato snack', 'cartofi chips'])) return -1200
    if (includesAny(text, ['sweet potato', 'cartof dulce', 'มันหวาน'])) return -500
    if (includesAny(text, [' raw', ' crud', ' crue', ' cruda', ' ดิบ'])) return curated + 840
    if (includesAny(text, ['french fries', 'cartofi prajiti', 'pommes frites', 'frites', 'เฟรนช์ฟรายส์'])) return curated + 520
    if (includesAny(text, ['baked', 'copt', 'gebacken', 'cuite au four', 'al forno', ' อบ'])) return curated + 760
    if (includesAny(text, ['air fryer', 'heissluftfritteuse', 'heißluftfritteuse', 'หม้อทอดไร้น้ำมัน'])) return curated + 680
  }

  const proteinPowderQuery = includesAny(query, ['whey', 'protein', 'proteina', 'zer', 'casein', 'cazeina', 'เวย์', 'โปรตีน', 'เคซีน'])
  if (proteinPowderQuery && includesAny(text, ['whey', 'protein', 'proteina', 'zer', 'casein', 'cazeina', 'เวย์', 'โปรตีน', 'เคซีน'])) {
    return curated + (food.confidence === 'provider_verified' ? 180 : 80)
  }
  return curated
}

function foodIdentity(food: FoodRecord): string {
  if (food.provider_product_id) return `provider:${food.provider_product_id}`
  if (food.barcode) return `barcode:${food.barcode}`
  return `name:${normalizeFoodSearch(`${food.brand ?? ''} ${food.name}`)}`
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
      const curatedAliases = catalogAliases(food).map(normalizeFoodSearch)
      const searchable = [...names, personal, ...aliases, ...curatedAliases].filter(Boolean)
      if (needle && !searchable.some((value) => value.includes(needle))) return { food, score: -Infinity }

      let score = 0
      if (needle) {
        if (personal === needle) score += 1200
        if (aliases.includes(needle)) score += 1120
        if (curatedAliases.includes(needle)) score += 1100
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
      score += categorySearchBoost(needle, food)
      if (food.owner_user_id) score += 70
      if (food.source === 'apex_cache') score += 30
      return { food, score }
    })
    .filter((candidate) => Number.isFinite(candidate.score))
    .sort((a, b) => b.score - a.score || a.food.name.localeCompare(b.food.name))
    .reduce<FoodRecord[]>((results, candidate) => {
      const identity = foodIdentity(candidate.food)
      if (!results.some((food) => foodIdentity(food) === identity)) results.push(candidate.food)
      return results
    }, [])
}

export function mergeExtendedFoodResults(
  query: string,
  localResults: FoodRecord[],
  providerResults: FoodRecord[],
): FoodRecord[] {
  const seen = new Set(localResults.map(foodIdentity))
  const provider = providerResults
    .filter((food) => {
      const identity = foodIdentity(food)
      if (seen.has(identity)) return false
      seen.add(identity)
      return true
    })
    .map((food, index) => ({ food, index, score: categorySearchBoost(normalizeFoodSearch(query), food) }))
    .sort((a, b) => b.score - a.score || a.index - b.index)
    .map(({ food }) => food)
  return [...localResults, ...provider]
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

/* Planned check-offs predate structured food logs. Reconcile both sources into
   one ledger so a checked plan contributes nutrition, while an edited actual
   meal linked to that plan replaces it exactly once. If an old client created
   duplicate linked logs, only the most recently updated snapshot is current. */
export function reconcileConsumedMeals(
  loggedMeals: LoggedMeal[],
  plannedMeals: PlannedNutritionMeal[],
  checkedPlannedMealIds: Iterable<string>,
): ConsumedMeal[] {
  const latestLinked = new Map<string, LoggedMeal>()
  const custom: LoggedMeal[] = []
  for (const meal of loggedMeals) {
    if (!meal.source_planned_meal_id) {
      custom.push(meal)
      continue
    }
    const previous = latestLinked.get(meal.source_planned_meal_id)
    if (!previous || previous.updated_at.localeCompare(meal.updated_at) < 0) {
      latestLinked.set(meal.source_planned_meal_id, meal)
    }
  }

  const fromLogged = [...custom, ...latestLinked.values()].map<ConsumedMeal>((meal) => ({
    id: meal.id,
    name: meal.display_name,
    planned_meal_id: meal.source_planned_meal_id,
    source: 'logged',
    logged_meal: meal,
    kcal: meal.total_kcal,
    protein_g: meal.total_protein_g,
    carbs_g: meal.total_carbs_g,
    fat_g: meal.total_fat_g,
  }))

  const planById = new Map(plannedMeals.map((meal) => [meal.id, meal]))
  const fallback: ConsumedMeal[] = []
  for (const mealId of checkedPlannedMealIds) {
    if (latestLinked.has(mealId)) continue
    const planned = planById.get(mealId)
    if (!planned) continue
    fallback.push({
      id: `checked-plan:${planned.id}`,
      name: planned.name,
      planned_meal_id: planned.id,
      source: 'checked_plan',
      logged_meal: null,
      kcal: planned.kcal,
      protein_g: planned.protein_g,
      carbs_g: planned.carbs_g,
      fat_g: planned.fat_g,
    })
  }
  return [...fromLogged, ...fallback]
}

export function aggregateConsumedMeals(meals: ConsumedMeal[]): MealTotals {
  return meals.reduce<MealTotals>((sum, meal) => ({
    kcal: sum.kcal + meal.kcal,
    protein_g: Math.round((sum.protein_g + meal.protein_g) * 10) / 10,
    carbs_g: Math.round((sum.carbs_g + meal.carbs_g) * 10) / 10,
    fat_g: Math.round((sum.fat_g + meal.fat_g) * 10) / 10,
  }), { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 })
}

export function mergeMealsIdempotently(current: LoggedMeal[], incoming: LoggedMeal[]): LoggedMeal[] {
  const byKey = new Map(current.map((meal) => [`${meal.user_id}:${meal.client_idempotency_key}`, meal]))
  for (const meal of incoming) byKey.set(`${meal.user_id}:${meal.client_idempotency_key}`, meal)
  return [...byKey.values()]
}
