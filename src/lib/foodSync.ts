import type {
  FoodPreference,
  FoodRecord,
  LoggedFoodEntry,
  LoggedMeal,
  MealPreset,
  MealPresetItem,
} from './food'

export interface FoodPendingOperation {
  operation: string
  entity_id: string
  payload: unknown
  created_at?: string
}

export interface FoodSyncSnapshot {
  foods: FoodRecord[]
  preferences: FoodPreference[]
  presets: MealPreset[]
  presetItems: MealPresetItem[]
  meals: LoggedMeal[]
  entries: LoggedFoodEntry[]
}

export interface LoggedMealSyncPayload {
  meal: LoggedMeal & { replace_meal_id?: string | null }
  entries: LoggedFoodEntry[]
}

/**
 * A logged meal is already an immutable nutrition snapshot. Optional links to
 * a food, preset or planned meal improve navigation, but they must never make
 * the meal itself impossible to persist when an older database has not yet
 * received a newer client catalogue row.
 */
export function detachedLoggedMealPayload(payload: LoggedMealSyncPayload): LoggedMealSyncPayload {
  return {
    meal: {
      ...payload.meal,
      source_preset_id: null,
      source_planned_meal_id: null,
    },
    entries: payload.entries.map((entry) => ({ ...entry, food_id: null })),
  }
}

/** Postgres codes used when an optional client-side catalogue reference is
 * absent or is not a server UUID. Both are safe to retry as a detached meal
 * because every calorie and macro remains inside the entry snapshot. */
export function isMealReferenceError(error: unknown): boolean {
  const candidate = error as { code?: unknown; message?: unknown; details?: unknown }
  const code = String(candidate?.code ?? '')
  const message = `${String(candidate?.message ?? '')} ${String(candidate?.details ?? '')}`.toLocaleLowerCase()
  return code === '23503'
    || code === '22P02'
    || message.includes('foreign key')
    || message.includes('invalid input syntax for type uuid')
}

/** Catalogue conveniences may retry independently. Ledger mutations retain
 * strict ordering so a later edit or delete can never overtake its meal. */
export function foodSyncFailureCanYield(operation: string): boolean {
  return operation === 'save_food'
    || operation === 'save_preference'
    || operation === 'save_usage_preference'
    || operation === 'save_preset'
}

/** Keep a queued intent and its acknowledgement inside its captured account. */
export function foodOperationBelongsToUser(
  operation: { user_id: string },
  userId: string,
): boolean {
  return operation.user_id === userId
}

/** Async UI work may finish after the user changes profiles. Only the account
 * that started the mutation may update the currently visible food state. */
export function foodMutationBelongsToActiveUser(
  mutationUserId: string,
  activeUserId: string | null,
): boolean {
  return mutationUserId === activeUserId
}

/** Remote hydration must use credentials owned by the same account whose
 * private cache is about to be reconciled. */
export function foodSessionBelongsToExpectedUser(
  sessionUserId: string | null | undefined,
  expectedUserId: string,
): boolean {
  return sessionUserId === expectedUserId
}

function values<T extends { id: string }>(rows: Map<string, T>): T[] {
  return [...rows.values()]
}

/** Apply durable food intents over a server snapshot before it reaches UI or IndexedDB. */
export function replayFoodOutbox(
  snapshot: FoodSyncSnapshot,
  operations: readonly FoodPendingOperation[],
): FoodSyncSnapshot {
  const foods = new Map(snapshot.foods.map((row) => [row.id, row]))
  const preferences = new Map(snapshot.preferences.map((row) => [row.id, row]))
  const presets = new Map(snapshot.presets.map((row) => [row.id, row]))
  const presetItems = new Map(snapshot.presetItems.map((row) => [row.id, row]))
  const meals = new Map(snapshot.meals.map((row) => [row.id, row]))
  const entries = new Map(snapshot.entries.map((row) => [row.id, row]))

  const orderedOperations = [...operations].sort((left, right) =>
    (left.created_at ?? '').localeCompare(right.created_at ?? ''),
  )
  for (const operation of orderedOperations) {
    if (operation.operation === 'save_food') {
      const food = operation.payload as FoodRecord
      if (food?.id) foods.set(food.id, food)
      continue
    }
    if (operation.operation === 'save_preference' || operation.operation === 'save_usage_preference') {
      const preference = operation.payload as FoodPreference
      if (preference?.id) preferences.set(preference.id, preference)
      continue
    }
    if (operation.operation === 'log_meal') {
      const payload = operation.payload as {
        meal?: LoggedMeal & { replace_meal_id?: string | null }
        entries?: LoggedFoodEntry[]
      }
      if (!payload.meal?.id) continue
      const replacedId = payload.meal.replace_meal_id
      if (replacedId) {
        meals.delete(replacedId)
        for (const [id, entry] of entries) if (entry.meal_id === replacedId) entries.delete(id)
      }
      const { replace_meal_id: _replaceMealId, ...meal } = payload.meal
      meals.set(meal.id, meal)
      for (const entry of payload.entries ?? []) entries.set(entry.id, entry)
      continue
    }
    if (operation.operation === 'delete_meal') {
      meals.delete(operation.entity_id)
      for (const [id, entry] of entries) if (entry.meal_id === operation.entity_id) entries.delete(id)
      continue
    }
    if (operation.operation === 'save_preset') {
      const payload = operation.payload as { preset?: MealPreset; items?: MealPresetItem[] }
      if (!payload.preset?.id) continue
      presets.set(payload.preset.id, payload.preset)
      for (const [id, item] of presetItems) if (item.preset_id === payload.preset.id) presetItems.delete(id)
      for (const item of payload.items ?? []) presetItems.set(item.id, item)
      continue
    }
    if (operation.operation === 'delete_preset') {
      presets.delete(operation.entity_id)
      for (const [id, item] of presetItems) if (item.preset_id === operation.entity_id) presetItems.delete(id)
    }
  }

  return {
    foods: values(foods),
    preferences: values(preferences),
    presets: values(presets),
    presetItems: values(presetItems),
    meals: values(meals),
    entries: values(entries),
  }
}
