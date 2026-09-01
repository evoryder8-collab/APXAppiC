import type { FoodRecord, LoggedFoodEntry, LoggedMeal } from './food.ts'

export type NutrientObservationStatus =
  | 'measured'
  | 'calculated'
  | 'estimated'
  | 'reported'
  | 'trace'
  | 'below_detection'
  | 'not_measured'
  | 'missing'

export type NutrientCategory = 'vitamins' | 'minerals' | 'fats' | 'carbohydrates' | 'other'
export type NutrientPatternPeriod = 'day' | 'week' | 'month'

export interface NutrientEvidenceObservation {
  nutrient_code: string
  name: string
  value_per_100: number | null
  unit: string
  observation_status: NutrientObservationStatus
  original_value_text: string
  derivation_method: string | null
  source_key: string | null
  source_reference: string | null
}
export interface NutrientPatternWindow {
  start: string
  end: string
  calendarDays: number
}

export interface NutrientPatternRow {
  nutrient_code: string
  name: string
  unit: string
  category: NutrientCategory
  total: number
  averagePerObservedDay: number
  observedFoodEntries: number
}

export interface NutrientPatternSummary {
  window: NutrientPatternWindow
  calendarDays: number
  observedDays: number
  totalFoodEntries: number
  evidenceFoodEntries: number
  coverage: number
  rows: NutrientPatternRow[]
}

const usableStatuses = new Set<NutrientObservationStatus>([
  'measured', 'calculated', 'estimated', 'reported',
])

const categoryOrder: NutrientCategory[] = ['vitamins', 'minerals', 'fats', 'carbohydrates', 'other']

function utcDate(localDate: string): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(localDate)) return null
  const [year, month, day] = localDate.split('-').map(Number)
  const value = new Date(Date.UTC(year, month - 1, day))
  if (
    value.getUTCFullYear() !== year
    || value.getUTCMonth() !== month - 1
    || value.getUTCDate() !== day
  ) return null
  return value
}

function localDateString(date: Date): string {
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}-${String(date.getUTCDate()).padStart(2, '0')}`
}

function shifted(localDate: string, days: number): string {
  const date = utcDate(localDate)
  if (!date) return localDate
  date.setUTCDate(date.getUTCDate() + days)
  return localDateString(date)
}

export function nutrientWindow(anchorDate: string, period: NutrientPatternPeriod): NutrientPatternWindow {
  const parsed = utcDate(anchorDate)
  if (!parsed) return { start: anchorDate, end: anchorDate, calendarDays: 1 }
  if (period === 'day') return { start: anchorDate, end: anchorDate, calendarDays: 1 }
  if (period === 'week') return { start: shifted(anchorDate, -6), end: anchorDate, calendarDays: 7 }
  const start = `${parsed.getUTCFullYear()}-${String(parsed.getUTCMonth() + 1).padStart(2, '0')}-01`
  return { start, end: anchorDate, calendarDays: parsed.getUTCDate() }
}

export function nutrientCategory(observation: Pick<NutrientEvidenceObservation, 'nutrient_code' | 'name'>): NutrientCategory {
  const code = observation.nutrient_code.toLocaleUpperCase()
  const name = observation.name.toLocaleLowerCase()
  if (
    code.startsWith('VIT')
    || /vitamin|retinol|carotene|thiam|riboflav|niacin|folate|folic|cobalamin|tocopher|biotin|pantothen/.test(name)
  ) return 'vitamins'
  if (
    /^(?:CA|FE|MG|P|K|NA|ZN|CU|MN|SE|I|CL|F)$/.test(code)
    || /calcium|iron|magnesium|phosph|potassium|sodium|zinc|copper|manganese|selenium|iodine|chloride|fluoride|mineral/.test(name)
  ) return 'minerals'
  if (
    /^(?:FASAT|FAMS|FAPU|FATRN|CHOLE|OMEGA)/.test(code)
    || /saturat|monounsaturat|polyunsaturat|trans fat|cholesterol|omega-|fatty acid/.test(name)
  ) return 'fats'
  if (
    /^(?:SUGAR|SUGAR_ADDED|FIBT|STARCH)/.test(code)
    || /sugar|fibre|fiber|starch/.test(name)
  ) return 'carbohydrates'
  return 'other'
}

function fallback(
  nutrient_code: string,
  name: string,
  value_per_100: number | null | undefined,
  unit: string,
  food: FoodRecord,
): NutrientEvidenceObservation | null {
  if (value_per_100 == null || !Number.isFinite(value_per_100) || value_per_100 < 0) return null
  const providerReported = food.source === 'open_food_facts' || food.confidence === 'provider_verified'
  return {
    nutrient_code,
    name,
    value_per_100,
    unit,
    observation_status: providerReported ? 'reported' : 'estimated',
    original_value_text: String(value_per_100),
    derivation_method: null,
    source_key: food.source,
    source_reference: food.provider_product_id,
  }
}

export function foodNutrientEvidence(food: FoodRecord): NutrientEvidenceObservation[] {
  const rows = [...(food.nutrient_evidence ?? [])]
  const existing = new Set(rows.map((row) => row.nutrient_code.toLocaleUpperCase()))
  const coarse = [
    fallback('ENERC_KCAL', 'Energy', food.kcal_100, 'kcal', food),
    fallback('PROT', 'Protein', food.protein_100, 'g', food),
    fallback('CHOAVL', 'Carbohydrate', food.carbs_100, 'g', food),
    fallback('FAT', 'Fat', food.fat_100, 'g', food),
    fallback('FIBT', 'Dietary fibre', food.fibre_100, 'g', food),
    fallback('SUGAR', 'Total sugars', food.sugar_100, 'g', food),
    fallback('FASAT', 'Saturated fat', food.saturated_fat_100, 'g', food),
    fallback('NACL', 'Salt', food.salt_100, 'g', food),
    fallback('WATER', 'Water', food.water_ml_100, 'ml', food),
  ].filter((row): row is NutrientEvidenceObservation => row !== null)
  for (const row of coarse) {
    if (!existing.has(row.nutrient_code)) rows.push(row)
  }
  return rows.sort((left, right) => {
    const category = categoryOrder.indexOf(nutrientCategory(left)) - categoryOrder.indexOf(nutrientCategory(right))
    return category || left.name.localeCompare(right.name) || left.unit.localeCompare(right.unit)
  })
}

function finiteObservedValue(row: NutrientEvidenceObservation): number | null {
  if (!usableStatuses.has(row.observation_status)) return null
  const value = row.value_per_100
  return value != null && Number.isFinite(value) && value >= 0 ? value : null
}

function rounded(value: number): number {
  return Math.round(value * 1_000_000) / 1_000_000
}

export function summarizeNutrientIntake(input: {
  meals: LoggedMeal[]
  entries: LoggedFoodEntry[]
  userId: string
  anchorDate: string
  period: NutrientPatternPeriod
}): NutrientPatternSummary {
  const window = nutrientWindow(input.anchorDate, input.period)
  const eligibleMeals = new Map(
    input.meals
      .filter((meal) => meal.user_id === input.userId && meal.local_date >= window.start && meal.local_date <= window.end)
      .map((meal) => [meal.id, meal.local_date]),
  )
  const eligibleEntries = input.entries.filter((entry) => (
    entry.user_id === input.userId && eligibleMeals.has(entry.meal_id)
  ))
  const observedDays = new Set(eligibleEntries.map((entry) => eligibleMeals.get(entry.meal_id)!)).size
  let evidenceFoodEntries = 0
  const groups = new Map<string, NutrientPatternRow>()
  for (const entry of eligibleEntries) {
    const usable = (entry.snapshot_nutrient_evidence ?? []).flatMap((row) => {
      const value = finiteObservedValue(row)
      return value == null ? [] : [{ row, amount: value * Math.max(0, entry.equivalent_amount) / 100 }]
    })
    if (usable.length > 0) evidenceFoodEntries += 1
    const countedKeys = new Set<string>()
    for (const { row, amount } of usable) {
      const key = `${row.nutrient_code.toLocaleUpperCase()}|${row.unit}`
      const previous = groups.get(key)
      groups.set(key, {
        nutrient_code: row.nutrient_code,
        name: previous?.name ?? row.name,
        unit: row.unit,
        category: nutrientCategory(row),
        total: rounded((previous?.total ?? 0) + amount),
        averagePerObservedDay: 0,
        observedFoodEntries: (previous?.observedFoodEntries ?? 0) + (countedKeys.has(key) ? 0 : 1),
      })
      countedKeys.add(key)
    }
  }
  const divisor = Math.max(1, observedDays)
  const rows = [...groups.values()]
    .map((row) => ({ ...row, averagePerObservedDay: rounded(row.total / divisor) }))
    .sort((left, right) => {
      const category = categoryOrder.indexOf(left.category) - categoryOrder.indexOf(right.category)
      return category || right.averagePerObservedDay - left.averagePerObservedDay || left.name.localeCompare(right.name)
    })
  return {
    window,
    calendarDays: window.calendarDays,
    observedDays,
    totalFoodEntries: eligibleEntries.length,
    evidenceFoodEntries,
    coverage: eligibleEntries.length === 0 ? 0 : evidenceFoodEntries / eligibleEntries.length,
    rows,
  }
}
