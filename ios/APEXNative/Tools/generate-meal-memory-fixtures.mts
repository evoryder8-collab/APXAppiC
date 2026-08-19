/*
 * Golden parity fixtures for the native MealMemory ranking.
 *
 * Runs the REAL web engine (src/lib/mealExperience.ts) over deterministic
 * histories and freezes inputs + outputs as JSON. The Swift XCTest suite
 * decodes the same inputs, runs the Swift port, and must reproduce the same
 * food order and the same remembered amounts. Regenerate after any web
 * change:
 *
 *   node --experimental-strip-types ios/APEXNative/Tools/generate-meal-memory-fixtures.mts
 */
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { rankMealHistoryRecommendations, type MealRecommendationContext } from '../../../src/lib/mealExperience.ts'
import type { FoodRecord, LoggedFoodEntry, LoggedMeal, MealSlot } from '../../../src/lib/food.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
const OUT = join(HERE, '..', 'APEXTests', 'Fixtures', 'meal-memory-parity.json')

const USER = '99999999-0000-4000-8000-000000000001'
const TS = '2026-06-01T12:00:00.000Z'

let idSeq = 0
function fid(): string {
  idSeq += 1
  return `77777777-0000-4000-8000-${String(idSeq).padStart(12, '0')}`
}

function food(name: string, kcal: number, piece?: number): FoodRecord {
  return {
    id: fid(),
    owner_user_id: USER,
    name,
    names_i18n: {},
    brand: 'APEX',
    barcode: null,
    source: 'private',
    provider_product_id: null,
    external_image_url: null,
    package_quantity: null,
    nutrition_basis: 'per_100g',
    preparation_state: 'as_sold',
    kcal_100: kcal,
    protein_100: 10,
    carbs_100: 40,
    fat_100: 5,
    fibre_100: null,
    sugar_100: null,
    saturated_fat_100: null,
    salt_100: null,
    serving_amount: null,
    serving_unit: null,
    serving_grams_or_ml: null,
    piece_grams_or_ml: piece ?? null,
    provider_updated_at: null,
    confidence: 'complete',
    created_at: TS,
    updated_at: TS,
  }
}

const oats = food('Rolled oats', 370)
const whey = food('Whey isolate', 360)
const banana = food('Banana', 89, 118)
const rice = food('Jasmine rice', 355)
const foods = [oats, whey, banana, rice]

const meals: LoggedMeal[] = []
const entries: LoggedFoodEntry[] = []

function logMeal(input: {
  date: string
  slot: MealSlot
  name: string
  time: string
  block?: string
  items: Array<{ food: FoodRecord; quantity: number; unit: LoggedFoodEntry['unit'] }>
}): void {
  const id = fid()
  const key = input.block ? `apex-meal-block=${input.block}|${id}` : id
  let kcal = 0
  input.items.forEach((item, index) => {
    const grams = item.unit === 'piece' ? item.quantity * (item.food.piece_grams_or_ml ?? 100) : item.quantity
    const energy = (item.food.kcal_100 ?? 0) * grams / 100
    kcal += energy
    entries.push({
      id: fid(),
      meal_id: id,
      user_id: USER,
      food_id: item.food.id,
      sort_order: index,
      snapshot_name: item.food.name,
      snapshot_brand: item.food.brand,
      snapshot_preparation_state: item.food.preparation_state,
      snapshot_nutrition_basis: item.food.nutrition_basis,
      snapshot_kcal_100: item.food.kcal_100 ?? 0,
      snapshot_protein_100: item.food.protein_100 ?? 0,
      snapshot_carbs_100: item.food.carbs_100 ?? 0,
      snapshot_fat_100: item.food.fat_100 ?? 0,
      snapshot_fibre_100: null,
      snapshot_sugar_100: null,
      snapshot_saturated_fat_100: null,
      snapshot_salt_100: null,
      quantity: item.quantity,
      unit: item.unit,
      equivalent_amount: grams,
      kcal: energy,
      protein_g: 0,
      carbs_g: 0,
      fat_g: 0,
      fibre_g: null,
      sugar_g: null,
      saturated_fat_g: null,
      salt_g: null,
      created_at: `${input.date}T${input.time}:00.000Z`,
      updated_at: `${input.date}T${input.time}:00.000Z`,
    } as LoggedFoodEntry)
  })
  meals.push({
    id,
    user_id: USER,
    local_date: input.date,
    meal_slot: input.slot,
    display_name: input.name,
    source_preset_id: null,
    source_planned_meal_id: null,
    logged_at: `${input.date}T${input.time}:00.000Z`,
    client_idempotency_key: key,
    logged_as: 'actual',
    total_kcal: kcal,
    total_protein_g: 0,
    total_carbs_g: 0,
    total_fat_g: 0,
    created_at: `${input.date}T${input.time}:00.000Z`,
    updated_at: `${input.date}T${input.time}:00.000Z`,
  } as LoggedMeal)
}

/* Weekday breakfasts settle on 80 g oats; the Sunday one is 120 g with a
   banana, which is exactly what weekly memory should surface on a Sunday. */
logMeal({ date: '2026-05-18', slot: 'breakfast', name: 'Oats', time: '07:05', block: 'breakfast', items: [{ food: oats, quantity: 80, unit: 'g' }, { food: whey, quantity: 30, unit: 'g' }] })
logMeal({ date: '2026-05-19', slot: 'breakfast', name: 'Oats', time: '07:12', block: 'breakfast', items: [{ food: oats, quantity: 80, unit: 'g' }, { food: whey, quantity: 30, unit: 'g' }] })
logMeal({ date: '2026-05-24', slot: 'breakfast', name: 'Sunday oats', time: '09:30', block: 'breakfast', items: [{ food: oats, quantity: 120, unit: 'g' }, { food: banana, quantity: 1, unit: 'piece' }] })
logMeal({ date: '2026-05-26', slot: 'breakfast', name: 'Oats', time: '07:02', block: 'breakfast', items: [{ food: oats, quantity: 95, unit: 'g' }, { food: whey, quantity: 35, unit: 'g' }] })
logMeal({ date: '2026-05-31', slot: 'breakfast', name: 'Sunday oats', time: '09:40', block: 'breakfast', items: [{ food: oats, quantity: 120, unit: 'g' }, { food: banana, quantity: 2, unit: 'piece' }] })
logMeal({ date: '2026-05-27', slot: 'dinner', name: 'Rice bowl', time: '19:20', block: 'dinner', items: [{ food: rice, quantity: 250, unit: 'g' }] })

const scenarios: Array<{ name: string; context: MealRecommendationContext }> = [
  { name: 'daily-breakfast', context: { date: '2026-06-01', slot: 'breakfast', memoryMode: 'daily', blockId: 'breakfast', targetTime: '07:00' } },
  { name: 'weekly-sunday-breakfast', context: { date: '2026-06-07', slot: 'breakfast', memoryMode: 'weekly', blockId: 'breakfast', targetTime: '09:30' } },
  { name: 'weekly-monday-breakfast', context: { date: '2026-06-01', slot: 'breakfast', memoryMode: 'weekly', blockId: 'breakfast', targetTime: '07:00' } },
  { name: 'daily-dinner', context: { date: '2026-06-01', slot: 'dinner', memoryMode: 'daily', blockId: 'dinner', targetTime: '19:00' } },
  { name: 'empty-lunch', context: { date: '2026-06-01', slot: 'lunch', memoryMode: 'daily', blockId: 'lunch', targetTime: '13:00' } },
]

const cases = scenarios.map((scenario) => {
  const result = rankMealHistoryRecommendations({ context: scenario.context, meals, entries, foods, presets: [], foodLimit: 12 })
  return {
    name: scenario.name,
    context: scenario.context,
    expected: {
      meals: result.meals.map((meal) => meal.id),
      foods: result.foods.map((value) => value.id),
      selections: result.selections,
    },
  }
})

mkdirSync(dirname(OUT), { recursive: true })
writeFileSync(OUT, `${JSON.stringify({ foods, meals, entries, cases }, null, 2)}\n`)
console.log(`wrote ${OUT} (${cases.length} cases)`)
