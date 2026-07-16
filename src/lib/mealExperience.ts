import type {
  FoodRecord,
  LoggedFoodEntry,
  LoggedMeal,
  MealPreset,
  MealSlot,
} from './food'
import { mealMomentIdFromIdempotencyKey, type MealBlockIdentity, type MealBlockKind } from './mealBlocks.ts'

export interface GesturePoint {
  x: number
  y: number
}

export const MEAL_ROW_REVEAL_PX = 104
const MEAL_ROW_REVEALED_OFFSET = -104 as const

/** Settle a row-owned gesture without ever returning a day-navigation offset. */
export function mealRowSwipeOffset(
  start: GesturePoint,
  end: GesturePoint,
  wasOpen = false,
): 0 | -104 {
  const dx = end.x - start.x
  const dy = end.y - start.y
  if (Math.abs(dx) < Math.abs(dy) * 1.2) return wasOpen ? MEAL_ROW_REVEALED_OFFSET : 0
  if (dx <= -42) return MEAL_ROW_REVEALED_OFFSET
  if (dx >= 30) return 0
  return wasOpen ? MEAL_ROW_REVEALED_OFFSET : 0
}

export interface LoggedMealEditorState {
  slot: MealSlot
  blockId: MealBlockKind | null
  mealIdentity: MealBlockIdentity | null
  title: string
  plannedMealId: string | null
  replaceMealId: string
  targetTime: string | null
}

export function loggedMealEditorState(
  meal: LoggedMeal,
  blockId: MealBlockKind | null = null,
  targetTime: string | null = null,
  mealIdentity: MealBlockIdentity | null = mealMomentIdFromIdempotencyKey(meal.client_idempotency_key),
): LoggedMealEditorState {
  return {
    slot: meal.meal_slot,
    blockId,
    mealIdentity: mealIdentity ?? blockId,
    title: meal.display_name,
    plannedMealId: meal.source_planned_meal_id,
    replaceMealId: meal.id,
    targetTime,
  }
}

export interface MealRecommendationContext {
  date: string
  slot: MealSlot
  blockId?: MealBlockIdentity | null
  targetTime?: string | null
  sequenceIndex?: number | null
  excludeMealId?: string | null
}

export interface MealHistoryRecommendations {
  meals: LoggedMeal[]
  foods: FoodRecord[]
  presets: MealPreset[]
}

function dateMs(value: string): number {
  const parsed = Date.parse(`${value}T12:00:00Z`)
  return Number.isFinite(parsed) ? parsed : 0
}

function weekday(value: string): number {
  return new Date(`${value}T12:00:00Z`).getUTCDay()
}

function clockMinutes(value: string | null | undefined): number | null {
  if (!value || !/^\d{2}:\d{2}/.test(value)) return null
  const hours = Number(value.slice(0, 2))
  const minutes = Number(value.slice(3, 5))
  return Number.isFinite(hours + minutes) ? hours * 60 + minutes : null
}

function mealClock(meal: LoggedMeal): string | null {
  const match = meal.logged_at.match(/T(\d{2}:\d{2})/)
  return match?.[1] ?? null
}

function markedBlock(meal: LoggedMeal): string | null {
  const marker = meal.client_idempotency_key.lastIndexOf('apex-meal-block=')
  if (marker < 0) return null
  return meal.client_idempotency_key.slice(marker + 'apex-meal-block='.length).split('|')[0] || null
}

function sequenceIndexes(meals: LoggedMeal[]): Map<string, number> {
  const byDate = new Map<string, LoggedMeal[]>()
  for (const meal of meals) byDate.set(meal.local_date, [...(byDate.get(meal.local_date) ?? []), meal])
  const result = new Map<string, number>()
  for (const dayMeals of byDate.values()) {
    dayMeals
      .slice()
      .sort((left, right) => left.logged_at.localeCompare(right.logged_at) || left.id.localeCompare(right.id))
      .forEach((meal, index) => result.set(meal.id, index))
  }
  return result
}

/** Rank repeatable starts from immutable history. No source record is mutated
 * or reconstructed, and foods are returned only when their current catalogue
 * identity still exists. */
export function rankMealHistoryRecommendations(input: {
  context: MealRecommendationContext
  meals: LoggedMeal[]
  entries: LoggedFoodEntry[]
  foods: FoodRecord[]
  presets: MealPreset[]
  mealLimit?: number
  foodLimit?: number
  presetLimit?: number
}): MealHistoryRecommendations {
  const { context } = input
  const targetMs = dateMs(context.date)
  const targetWeekday = weekday(context.date)
  const targetMinutes = clockMinutes(context.targetTime)
  const indexes = sequenceIndexes(input.meals)
  const scoreByMeal = new Map<string, number>()

  for (const meal of input.meals) {
    if (meal.id === context.excludeMealId || meal.local_date > context.date) continue
    const ageDays = Math.max(0, Math.round((targetMs - dateMs(meal.local_date)) / 86_400_000))
    let score = Math.max(0, 260 - ageDays * 3)
    score += meal.meal_slot === context.slot ? 260 : -180
    if (context.blockId && markedBlock(meal) === context.blockId) score += 320
    if (weekday(meal.local_date) === targetWeekday) score += 90
    if (context.sequenceIndex != null && indexes.get(meal.id) === context.sequenceIndex) score += 120
    const loggedMinutes = clockMinutes(mealClock(meal))
    if (targetMinutes != null && loggedMinutes != null) {
      const rawDelta = Math.abs(loggedMinutes - targetMinutes)
      const delta = Math.min(rawDelta, 1440 - rawDelta)
      score += Math.max(0, 130 - delta / 2)
    }
    if (meal.source_preset_id) score += 35
    scoreByMeal.set(meal.id, score)
  }

  const rankedMeals = input.meals
    .filter((meal) => scoreByMeal.has(meal.id))
    .slice()
    .sort((left, right) => (scoreByMeal.get(right.id) ?? 0) - (scoreByMeal.get(left.id) ?? 0)
      || right.local_date.localeCompare(left.local_date)
      || right.logged_at.localeCompare(left.logged_at))

  const foodById = new Map(input.foods.map((food) => [food.id, food]))
  const entriesByMeal = new Map<string, LoggedFoodEntry[]>()
  for (const entry of input.entries) entriesByMeal.set(entry.meal_id, [...(entriesByMeal.get(entry.meal_id) ?? []), entry])
  const foodScores = new Map<string, number>()
  const presetScores = new Map<string, number>()
  /* Eighty high-signal meals cover months of repetition without turning a
     blank-search render into a quadratic scan of an account's full history. */
  for (const meal of rankedMeals.slice(0, 80)) {
    const mealScore = scoreByMeal.get(meal.id) ?? 0
    if (meal.source_preset_id) presetScores.set(meal.source_preset_id, (presetScores.get(meal.source_preset_id) ?? 0) + mealScore)
    for (const entry of entriesByMeal.get(meal.id) ?? []) {
      if (!entry.food_id || !foodById.has(entry.food_id)) continue
      foodScores.set(entry.food_id, (foodScores.get(entry.food_id) ?? 0) + mealScore + 45)
    }
  }

  const uniqueMeals: LoggedMeal[] = []
  const seenMealStarts = new Set<string>()
  for (const meal of rankedMeals) {
    const identity = meal.source_preset_id
      ? `preset:${meal.source_preset_id}`
      : `meal:${meal.meal_slot}:${meal.display_name.trim().toLocaleLowerCase()}`
    if (seenMealStarts.has(identity)) continue
    seenMealStarts.add(identity)
    uniqueMeals.push(meal)
  }

  return {
    meals: uniqueMeals.slice(0, input.mealLimit ?? 5),
    foods: [...foodScores.entries()]
      .sort((left, right) => right[1] - left[1])
      .flatMap(([foodId]) => foodById.get(foodId) ?? [])
      .slice(0, input.foodLimit ?? 10),
    presets: input.presets
      .filter((preset) => !preset.archived && (preset.meal_slot === context.slot || presetScores.has(preset.id)))
      .slice()
      .sort((left, right) => (presetScores.get(right.id) ?? 0) - (presetScores.get(left.id) ?? 0)
        || right.updated_at.localeCompare(left.updated_at))
      .slice(0, input.presetLimit ?? 5),
  }
}
