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
export type NutritionFactSectionKind = 'facts' | 'vitamins' | 'minerals'
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
export interface NutritionFactDisplayRow {
  observation: NutrientEvidenceObservation
  label: string
  depth: 0 | 1
}
export interface NutritionFactDisplaySection {
  kind: NutritionFactSectionKind
  rows: NutritionFactDisplayRow[]
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

/**
 * Coverage means an immutable food snapshot carries at least one valid fact
 * beyond calories and the three core macros. Fibre, sugars, fatty-acid
 * detail, salt, water, vitamins, minerals and other secondary nutrients all
 * qualify. Trace and below-detection observations qualify as evidence, but
 * are never converted into numeric intake or zero.
 */
const coreNutritionCodes = new Set(['ENERC_KCAL', 'PROT', 'CHOAVL', 'FAT'])

const categoryOrder: NutrientCategory[] = ['vitamins', 'minerals', 'fats', 'carbohydrates', 'other']

/**
 * Nutrient units cross several historical/provider boundaries, so spelling and
 * embedded per-100 basis text cannot be trusted as an aggregation identity.
 * Only dimensionally unambiguous units are accepted. Vitamin-equivalent
 * semantics remain part of the canonical unit because RE, RAE, alpha-TE and
 * mass alone are not interchangeable values.
 */
export function canonicalNutrientUnit(rawUnit: string): string | null {
  const unit = rawUnit
    .normalize('NFKC')
    .replace(/[μµ]/g, 'µ')
    .trim()
    .replace(/\s+/g, ' ')
    .toLocaleLowerCase()
  if (!unit) return null

  const basis = String.raw`(?:\s*(?:\/|per)\s*100\s*(?:g|ml))?`
  if (new RegExp(String.raw`^(?:kcal|kilocalories?)${basis}$`, 'i').test(unit)) return 'kcal'
  if (new RegExp(String.raw`^(?:g|grams?)${basis}$`, 'i').test(unit)) return 'g'
  if (new RegExp(String.raw`^(?:mg|milligrams?)${basis}$`, 'i').test(unit)) return 'mg'
  if (new RegExp(String.raw`^(?:µg|ug|mcg|micrograms?)${basis}$`, 'i').test(unit)) return 'µg'
  if (new RegExp(String.raw`^(?:ml|millilit(?:er|re)s?)${basis}$`, 'i').test(unit)) return 'ml'
  if (new RegExp(String.raw`^i\.?\s*u\.?${basis}$`, 'i').test(unit)) return 'IU'

  const micro = String.raw`(?:µg|ug|mcg|micrograms?)`
  const equivalentAfterMass = new RegExp(String.raw`^${micro}\s+(re|rae)${basis}$`, 'i').exec(unit)
  if (equivalentAfterMass) return `µg ${equivalentAfterMass[1].toLocaleUpperCase()}`
  const equivalentBeforeMass = new RegExp(
    String.raw`^(re|rae)\s*\(\s*${micro}${basis}\s*\)$`,
    'i',
  ).exec(unit)
  if (equivalentBeforeMass) return `µg ${equivalentBeforeMass[1].toLocaleUpperCase()}`

  const alphaTE = String.raw`(?:α|alpha|alfa)[\s-]*te`
  if (new RegExp(String.raw`^(?:mg|milligrams?)\s*${alphaTE}${basis}$`, 'i').test(unit)) {
    return 'mg α-TE'
  }
  if (new RegExp(String.raw`^${alphaTE}${basis}$`, 'i').test(unit)) return 'mg α-TE'
  return null
}

function canonicalObservation(
  observation: NutrientEvidenceObservation,
): NutrientEvidenceObservation | null {
  const unit = canonicalNutrientUnit(observation.unit)
  return unit ? { ...observation, unit } : null
}

/** Stable interface keys for nutrient identifiers from every supported source. */
export const NUTRIENT_DISPLAY_KEYS: Readonly<Record<string, string>> = Object.freeze({
  BIOT: 'Biotin (B7)',
  CA: 'Calcium',
  CARTB: 'Beta-carotene',
  CHOAVL: 'Total carbs',
  CHOLE: 'Cholesterol',
  CU: 'Copper',
  ENERC_KCAL: 'Calories',
  FAMS: 'Monounsaturated fat',
  FAPU: 'Polyunsaturated fat',
  FASAT: 'Saturated fat',
  FAT: 'Total fat',
  FATRN: 'Trans fat',
  FE: 'Iron',
  FIBT: 'Dietary fibre',
  FOL: 'Folate (B9)',
  I: 'Iodine',
  K: 'Potassium',
  MG: 'Magnesium',
  MN: 'Manganese',
  NA: 'Sodium',
  NACL: 'Salt',
  NIA: 'Niacin (B3)',
  OMEGA3: 'Omega-3 fat',
  OMEGA3_ALA: 'Alpha-linolenic acid (ALA)',
  OMEGA3_DHA: 'Docosahexaenoic acid (DHA)',
  OMEGA3_DPA: 'Docosapentaenoic acid (DPA)',
  OMEGA3_EPA: 'Eicosapentaenoic acid (EPA)',
  OMEGA6: 'Omega-6 fat',
  OMEGA6_AA: 'Arachidonic acid (AA)',
  OMEGA6_GLA: 'Gamma-linolenic acid (GLA)',
  OMEGA6_LA: 'Linoleic acid (LA)',
  P: 'Phosphorus',
  PANTAC: 'Pantothenic acid (B5)',
  PROT: 'Protein',
  RIBF: 'Riboflavin (B2)',
  SALT: 'Salt',
  SE: 'Selenium',
  STARCH: 'Starch',
  SUGAR: 'Total sugars',
  SUGAR_ADDED: 'Added sugars',
  THIA: 'Thiamin (B1)',
  VITA: 'Vitamin A',
  VITB1: 'Thiamin (B1)',
  VITB12: 'Vitamin B12',
  VITB2: 'Riboflavin (B2)',
  VITB3: 'Niacin (B3)',
  VITB5: 'Pantothenic acid (B5)',
  VITB6: 'Vitamin B6',
  VITB6A: 'Vitamin B6',
  VITB7: 'Biotin (B7)',
  VITB9: 'Folate (B9)',
  VITC: 'Vitamin C',
  VITD: 'Vitamin D',
  VITE: 'Vitamin E',
  VITK: 'Vitamin K',
  WATER: 'Water',
  ZN: 'Zinc',
})

export function nutrientDisplayKey(nutrientCode: string): string {
  return NUTRIENT_DISPLAY_KEYS[nutrientCode.trim().toLocaleUpperCase()] ?? 'Other nutrient'
}

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

function nutritionFactLabel(observation: NutrientEvidenceObservation): string {
  return nutrientDisplayKey(observation.nutrient_code)
}

function nutritionFactDepth(observation: NutrientEvidenceObservation): 0 | 1 {
  const code = observation.nutrient_code.toLocaleUpperCase()
  return /^(?:FASAT|FATRN|FAMS|FAPU|OMEGA)/.test(code)
    || /^(?:FIBT|SUGAR|SUGAR_ADDED|STARCH)/.test(code) ? 1 : 0
}

function nutritionFactPriority(observation: NutrientEvidenceObservation): number {
  const code = observation.nutrient_code.toLocaleUpperCase()
  if (code === 'ENERC_KCAL') return 0
  if (code === 'FAT') return 10
  if (code === 'FASAT') return 11
  if (code === 'FATRN') return 12
  if (code === 'FAMS') return 13
  if (code === 'FAPU') return 14
  if (code.startsWith('OMEGA')) return 15
  if (code === 'CHOLE') return 20
  if (code === 'NA') return 30
  if (code === 'NACL') return 31
  if (code === 'CHOAVL') return 40
  if (code === 'FIBT') return 41
  if (code === 'SUGAR') return 42
  if (code === 'SUGAR_ADDED') return 43
  if (code === 'STARCH') return 44
  if (code === 'PROT') return 50
  if (code === 'WATER') return 60
  return 100
}

export function nutritionFactSections(observations: NutrientEvidenceObservation[]): NutritionFactDisplaySection[] {
  const canonical = observations.flatMap((observation) => {
    const row = canonicalObservation(observation)
    return row ? [row] : []
  })
  const grouped: Array<[NutritionFactSectionKind, NutrientEvidenceObservation[]]> = [
    ['facts', canonical.filter((row) => !['vitamins', 'minerals'].includes(nutrientCategory(row)))],
    ['vitamins', canonical.filter((row) => nutrientCategory(row) === 'vitamins')],
    ['minerals', canonical.filter((row) => nutrientCategory(row) === 'minerals')],
  ]
  return grouped.flatMap(([kind, rows]) => {
    if (!rows.length) return []
    const sorted = [...rows].sort((left, right) => {
      if (kind === 'facts') {
        const priority = nutritionFactPriority(left) - nutritionFactPriority(right)
        if (priority) return priority
      }
      return nutritionFactLabel(left).localeCompare(nutritionFactLabel(right)) || left.unit.localeCompare(right.unit)
    })
    return [{
      kind,
      rows: sorted.map((observation) => ({
        observation,
        label: nutritionFactLabel(observation),
        depth: kind === 'facts' ? nutritionFactDepth(observation) : 0,
      })),
    }]
  })
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
  /* The amount card and immutable log use the canonical Food totals. When an
     exact evidence donor differs slightly, its vitamins and detail facts stay
     useful, but it must not display a second calorie or macro truth. */
  const canonicalCodes = new Set(coarse.map((row) => row.nutrient_code.toLocaleUpperCase()))
  const rows = [
    ...(food.nutrient_evidence ?? []).filter(
      (row) => !canonicalCodes.has(row.nutrient_code.toLocaleUpperCase()),
    ),
    ...coarse,
  ].flatMap((observation) => {
    const row = canonicalObservation(observation)
    return row ? [row] : []
  })
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

function isDetailedEvidence(row: NutrientEvidenceObservation): boolean {
  if (canonicalNutrientUnit(row.unit) == null) return false
  if (coreNutritionCodes.has(row.nutrient_code.trim().toLocaleUpperCase())) return false
  if (usableStatuses.has(row.observation_status)) return finiteObservedValue(row) != null
  return (row.observation_status === 'trace' || row.observation_status === 'below_detection')
    && row.value_per_100 == null
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
  const observedDatesByNutrient = new Map<string, Set<string>>()
  for (const entry of eligibleEntries) {
    const localDate = eligibleMeals.get(entry.meal_id)!
    const usable = (entry.snapshot_nutrient_evidence ?? []).flatMap((row) => {
      const canonical = canonicalObservation(row)
      const value = canonical ? finiteObservedValue(canonical) : null
      return canonical == null || value == null
        ? []
        : [{ row: canonical, amount: value * Math.max(0, entry.equivalent_amount) / 100 }]
    })
    if ((entry.snapshot_nutrient_evidence ?? []).some(isDetailedEvidence)) evidenceFoodEntries += 1
    const countedKeys = new Set<string>()
    for (const { row, amount } of usable) {
      const key = `${row.nutrient_code.toLocaleUpperCase()}|${row.unit}`
      const observedDates = observedDatesByNutrient.get(key) ?? new Set<string>()
      observedDates.add(localDate)
      observedDatesByNutrient.set(key, observedDates)
      const previous = groups.get(key)
      groups.set(key, {
        nutrient_code: row.nutrient_code,
        name: previous?.name ?? nutrientDisplayKey(row.nutrient_code),
        unit: row.unit,
        category: nutrientCategory(row),
        total: rounded((previous?.total ?? 0) + amount),
        averagePerObservedDay: 0,
        observedFoodEntries: (previous?.observedFoodEntries ?? 0) + (countedKeys.has(key) ? 0 : 1),
      })
      countedKeys.add(key)
    }
  }
  const rows = [...groups.values()]
    .map((row) => {
      const key = `${row.nutrient_code.toLocaleUpperCase()}|${row.unit}`
      const divisor = Math.max(1, observedDatesByNutrient.get(key)?.size ?? 0)
      return { ...row, averagePerObservedDay: rounded(row.total / divisor) }
    })
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
