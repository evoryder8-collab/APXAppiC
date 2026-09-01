import type {
  FoodPreference,
  FoodRecord,
  LoggedFoodEntry,
  LoggedMeal,
  MealPreset,
  MealPresetItem,
} from './food'
import { SUPABASE_ENUMS } from './supabaseEnums.ts'
import type { NutrientEvidenceObservation } from './nutrientEvidence.ts'

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

export type LoggedMealKind = (typeof SUPABASE_ENUMS.logged_as)[number]

export interface StructuredMealRequest {
  id: string
  local_date: string
  meal_slot: string
  display_name: string
  source_preset_id?: string
  source_planned_meal_id?: string
  logged_at: string
  client_idempotency_key: string
  logged_as: LoggedMealKind
  replace_meal_id?: string
}

export interface StructuredFoodEntryRequest {
  id: string
  food_id?: string
  sort_order: number
  snapshot_name: string
  snapshot_brand?: string
  snapshot_preparation_state: string
  snapshot_nutrition_basis: string
  snapshot_kcal_100: number
  snapshot_protein_100: number
  snapshot_carbs_100: number
  snapshot_fat_100: number
  snapshot_fibre_100?: number
  snapshot_sugar_100?: number
  snapshot_saturated_fat_100?: number
  snapshot_salt_100?: number
  snapshot_water_ml_100?: number
  snapshot_water_basis?: string
  snapshot_water_source_id?: string
  snapshot_nutrient_evidence?: NutrientEvidenceObservation[]
  quantity: number
  unit: string
  equivalent_amount: number
}

export interface LoggedMealSyncPayload {
  p_meal: StructuredMealRequest
  p_entries: StructuredFoodEntryRequest[]
}

export interface MealPresetRequest {
  id: string
  name: string
  meal_slot: string
  source_planned_meal_id?: string
  archived: boolean
}

export interface MealPresetItemRequest {
  id: string
  food_id: string
  sort_order: number
  quantity: number
  unit: string
  optional: boolean
  locked: boolean
  adjustable: boolean
  minimum_amount?: number
  maximum_amount?: number
  step_amount?: number
  adjustment_role: string
}

export interface MealPresetRPCPayload {
  p_preset: MealPresetRequest
  p_items: MealPresetItemRequest[]
  p_expected_version: number
}

interface LegacyLoggedMealSyncPayload {
  meal: LoggedMeal & { replace_meal_id?: string | null }
  entries: LoggedFoodEntry[]
}

interface LegacyMealPresetSyncPayload {
  preset: MealPreset
  items: MealPresetItem[]
  expectedVersion: number
}

function present<T>(value: T | null | undefined): value is T {
  return value !== null && value !== undefined
}

export function canonicalMealLogKind(value: unknown): LoggedMealKind {
  return SUPABASE_ENUMS.logged_as.includes(value as LoggedMealKind)
    ? value as LoggedMealKind
    : 'custom'
}

/** Strip local/server-owned row fields before the JSON reaches the shared RPC. */
export function canonicalStructuredMealRPCPayload(
  payload: LoggedMealSyncPayload | LegacyLoggedMealSyncPayload,
): LoggedMealSyncPayload {
  const sourceMeal = 'p_meal' in payload ? payload.p_meal : payload.meal
  const sourceEntries = 'p_entries' in payload ? payload.p_entries : payload.entries
  const meal: StructuredMealRequest = {
    id: sourceMeal.id,
    local_date: sourceMeal.local_date,
    meal_slot: sourceMeal.meal_slot,
    display_name: sourceMeal.display_name,
    ...(present(sourceMeal.source_preset_id) ? { source_preset_id: sourceMeal.source_preset_id } : {}),
    ...(present(sourceMeal.source_planned_meal_id) ? { source_planned_meal_id: sourceMeal.source_planned_meal_id } : {}),
    logged_at: sourceMeal.logged_at,
    client_idempotency_key: sourceMeal.client_idempotency_key,
    logged_as: canonicalMealLogKind(sourceMeal.logged_as),
    ...(present(sourceMeal.replace_meal_id) ? { replace_meal_id: sourceMeal.replace_meal_id } : {}),
  }
  const entries = sourceEntries.map((source): StructuredFoodEntryRequest => ({
    id: source.id,
    ...(present(source.food_id) ? { food_id: source.food_id } : {}),
    sort_order: source.sort_order,
    snapshot_name: source.snapshot_name,
    ...(present(source.snapshot_brand) ? { snapshot_brand: source.snapshot_brand } : {}),
    snapshot_preparation_state: source.snapshot_preparation_state,
    snapshot_nutrition_basis: source.snapshot_nutrition_basis,
    snapshot_kcal_100: source.snapshot_kcal_100,
    snapshot_protein_100: source.snapshot_protein_100,
    snapshot_carbs_100: source.snapshot_carbs_100,
    snapshot_fat_100: source.snapshot_fat_100,
    ...(present(source.snapshot_fibre_100) ? { snapshot_fibre_100: source.snapshot_fibre_100 } : {}),
    ...(present(source.snapshot_sugar_100) ? { snapshot_sugar_100: source.snapshot_sugar_100 } : {}),
    ...(present(source.snapshot_saturated_fat_100) ? { snapshot_saturated_fat_100: source.snapshot_saturated_fat_100 } : {}),
    ...(present(source.snapshot_salt_100) ? { snapshot_salt_100: source.snapshot_salt_100 } : {}),
    ...(present(source.snapshot_water_ml_100) ? { snapshot_water_ml_100: source.snapshot_water_ml_100 } : {}),
    ...(present(source.snapshot_water_basis) ? { snapshot_water_basis: source.snapshot_water_basis } : {}),
    ...(present(source.snapshot_water_source_id) ? { snapshot_water_source_id: source.snapshot_water_source_id } : {}),
    ...(present(source.snapshot_nutrient_evidence)
      ? { snapshot_nutrient_evidence: source.snapshot_nutrient_evidence.map((row) => ({ ...row })) }
      : {}),
    quantity: source.quantity,
    unit: source.unit,
    equivalent_amount: source.equivalent_amount,
  }))
  return { p_meal: meal, p_entries: entries }
}

export function canonicalMealPresetRPCPayload(
  payload: MealPresetRPCPayload | LegacyMealPresetSyncPayload,
): MealPresetRPCPayload {
  const sourcePreset = 'p_preset' in payload ? payload.p_preset : payload.preset
  const sourceItems = 'p_items' in payload ? payload.p_items : payload.items
  const expectedVersion = 'p_expected_version' in payload
    ? payload.p_expected_version
    : payload.expectedVersion
  return {
    p_preset: {
      id: sourcePreset.id,
      name: sourcePreset.name,
      meal_slot: sourcePreset.meal_slot,
      ...(present(sourcePreset.source_planned_meal_id)
        ? { source_planned_meal_id: sourcePreset.source_planned_meal_id }
        : {}),
      archived: sourcePreset.archived,
    },
    p_items: sourceItems.map((source): MealPresetItemRequest => ({
      id: source.id,
      food_id: source.food_id,
      sort_order: source.sort_order,
      quantity: source.quantity,
      unit: source.unit,
      optional: source.optional,
      locked: source.locked,
      adjustable: source.adjustable,
      ...(present(source.minimum_amount) ? { minimum_amount: source.minimum_amount } : {}),
      ...(present(source.maximum_amount) ? { maximum_amount: source.maximum_amount } : {}),
      ...(present(source.step_amount) ? { step_amount: source.step_amount } : {}),
      adjustment_role: source.adjustment_role,
    })),
    p_expected_version: expectedVersion,
  }
}

/**
 * A logged meal is already an immutable nutrition snapshot. Optional links to
 * a food, preset or planned meal improve navigation, but they must never make
 * the meal itself impossible to persist when an older database has not yet
 * received a newer client catalogue row.
 */
export function detachedLoggedMealPayload(
  payload: LoggedMealSyncPayload | LegacyLoggedMealSyncPayload,
): LoggedMealSyncPayload {
  const canonical = canonicalStructuredMealRPCPayload(payload)
  return canonicalStructuredMealRPCPayload({
    p_meal: {
      ...canonical.p_meal,
      source_preset_id: undefined,
      source_planned_meal_id: undefined,
    },
    p_entries: canonical.p_entries.map((entry) => ({ ...entry, food_id: undefined })),
  })
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

/** A preference may be discarded only when the server proves its food_id is
 * stale. All unrelated validation, authorization, FK and transport failures
 * must remain visible and retryable. */
export function isStaleFoodPreferenceReferenceError(error: unknown, foodId: string): boolean {
  const candidate = error as { code?: unknown; status?: unknown; message?: unknown; details?: unknown; hint?: unknown }
  const code = String(candidate?.code ?? '')
  const status = Number(candidate?.status)
  const message = `${String(candidate?.message ?? '')} ${String(candidate?.details ?? '')} ${String(candidate?.hint ?? '')}`
    .toLocaleLowerCase()
  const normalizedFoodId = foodId.trim().toLocaleLowerCase()
  const identifiesFoodForeignKey = message.includes('food_preferences_food_id_fkey')
    || (message.includes('key (food_id)') && message.includes('table "foods"'))
  if ((code === '23503' || status === 409) && identifiesFoodForeignKey) return true
  return code === '22P02'
    && message.includes('invalid input syntax for type uuid')
    && normalizedFoodId.length > 0
    && message.includes(normalizedFoodId)
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
    // A missing catalogue row in an incomplete cache/snapshot is not proof
    // that the server rejected this preference. Only the classified outbound
    // foreign-key failure may remove it.
    preferences: values(preferences),
    presets: values(presets),
    presetItems: values(presetItems),
    meals: values(meals),
    entries: values(entries),
  }
}
