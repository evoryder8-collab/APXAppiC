import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { COMMON_FOODS } from '../data/foodSeeds'
import {
  aggregateLoggedMeals,
  mealTotals,
  snapshotEntry,
  type ComposerFoodItem,
  type FoodPreference,
  type FoodRecord,
  type LoggedFoodEntry,
  type LoggedMeal,
  type MealPreset,
  type MealPresetItem,
  type MealSlot,
} from '../lib/food'
import {
  cacheVisibleFoods,
  deleteMealLocally,
  deletePresetLocally,
  loadVisibleFoods,
  privateDelete,
  privateGetAllForUser,
  privatePut,
  privatePutMany,
  saveMealAtomically,
  savePresetAtomically,
  type PrivateOutboxOp,
} from '../lib/privateDb'
import { isLocalMode, supabase } from '../lib/supabase'
import { todayIso } from '../lib/plan'
import { dailyLogId } from '../lib/ids'
import { useStore } from './AppStore'

interface LogMealInput {
  date?: string
  slot: MealSlot
  name: string
  items: ComposerFoodItem[]
  sourcePresetId?: string | null
  sourcePlannedMealId?: string | null
  replaceMealId?: string | null
  loggedAs?: LoggedMeal['logged_as']
  idempotencyKey?: string
}

interface SavePresetInput {
  id?: string
  name: string
  slot: MealSlot
  items: ComposerFoodItem[]
  sourcePlannedMealId?: string | null
  expectedVersion?: number
}

interface FoodLookupResult {
  state: 'found' | 'not_found' | 'incomplete' | 'invalid' | 'provider_error'
  food?: FoodRecord
  message?: string
}

interface FoodSearchResult {
  state: 'results' | 'provider_error' | 'invalid'
  results: FoodRecord[]
  message?: string
}

interface FoodStoreValue {
  ready: boolean
  syncing: boolean
  queued: boolean
  foods: FoodRecord[]
  preferences: FoodPreference[]
  presets: MealPreset[]
  presetItems: MealPresetItem[]
  meals: LoggedMeal[]
  entries: LoggedFoodEntry[]
  lookupBarcode: (barcode: string) => Promise<FoodLookupResult>
  widerSearch: (query: string) => Promise<FoodSearchResult>
  savePrivateFood: (food: Omit<FoodRecord, 'id' | 'owner_user_id' | 'source' | 'created_at' | 'updated_at'>) => Promise<FoodRecord>
  setPreference: (foodId: string, patch: Partial<FoodPreference>) => Promise<void>
  logMeal: (input: LogMealInput) => Promise<LoggedMeal>
  deleteMeal: (mealId: string) => Promise<void>
  savePreset: (input: SavePresetInput) => Promise<MealPreset>
  deletePreset: (presetId: string) => Promise<void>
  mealsForDate: (date: string) => LoggedMeal[]
  itemsForPreset: (presetId: string) => ComposerFoodItem[]
}

const Ctx = createContext<FoodStoreValue | null>(null)

function outbox(userId: string, operation: string, entityId: string, payload: unknown): PrivateOutboxOp {
  return {
    id: crypto.randomUUID(),
    user_id: userId,
    domain: 'food',
    operation,
    entity_id: entityId,
    payload,
    created_at: new Date().toISOString(),
    attempts: 0,
  }
}

function normalizeRemoteFood(row: Record<string, unknown>): FoodRecord {
  return {
    ...(row as unknown as FoodRecord),
    names_i18n: (row.names_i18n ?? {}) as FoodRecord['names_i18n'],
  }
}

export function FoodStoreProvider({ children }: { children: ReactNode }) {
  const { data, upsert } = useStore()
  const userId = data.profile?.user_id ?? null
  const [ready, setReady] = useState(false)
  const [syncing, setSyncing] = useState(false)
  const [queued, setQueued] = useState(false)
  const [foods, setFoods] = useState<FoodRecord[]>(COMMON_FOODS)
  const [preferences, setPreferences] = useState<FoodPreference[]>([])
  const [presets, setPresets] = useState<MealPreset[]>([])
  const [presetItems, setPresetItems] = useState<MealPresetItem[]>([])
  const [meals, setMeals] = useState<LoggedMeal[]>([])
  const [entries, setEntries] = useState<LoggedFoodEntry[]>([])
  const flushing = useRef(false)

  const hydrate = useCallback(async () => {
    if (!userId) return
    setReady(false)
    try {
      const [localFoods, localPreferences, localPresets, localPresetItems, localMeals, localEntries] = await Promise.all([
        loadVisibleFoods(userId),
        privateGetAllForUser<FoodPreference>('food_preferences', userId),
        privateGetAllForUser<MealPreset>('meal_presets', userId),
        privateGetAllForUser<MealPresetItem>('meal_preset_items', userId),
        privateGetAllForUser<LoggedMeal>('logged_meals', userId),
        privateGetAllForUser<LoggedFoodEntry>('logged_food_entries', userId),
      ])
      const initialFoods = new Map(COMMON_FOODS.map((food) => [food.id, food]))
      for (const food of localFoods) initialFoods.set(food.id, food)
      setFoods([...initialFoods.values()])
      setPreferences(localPreferences)
      setPresets(localPresets)
      setPresetItems(localPresetItems)
      setMeals(localMeals)
      setEntries(localEntries)
      const pending = await privateGetAllForUser<PrivateOutboxOp>('private_outbox', userId)
      setQueued(pending.some((operation) => operation.domain === 'food'))

      if (supabase) {
        setSyncing(true)
        const [foodRes, preferenceRes, presetRes, presetItemRes, mealRes, entryRes] = await Promise.all([
          supabase.from('foods').select('*').or(`owner_user_id.is.null,owner_user_id.eq.${userId}`),
          supabase.from('food_preferences').select('*').eq('user_id', userId),
          supabase.from('meal_presets').select('*').eq('user_id', userId),
          supabase.from('meal_preset_items').select('*').eq('user_id', userId),
          supabase.from('logged_meals').select('*').eq('user_id', userId).order('logged_at', { ascending: false }).limit(500),
          supabase.from('logged_food_entries').select('*').eq('user_id', userId).limit(2000),
        ])
        const firstError = [foodRes, preferenceRes, presetRes, presetItemRes, mealRes, entryRes].find((result) => result.error)?.error
        if (firstError) throw firstError
        const remoteFoods = (foodRes.data ?? []).map((row) => normalizeRemoteFood(row as Record<string, unknown>))
        setFoods(remoteFoods)
        setPreferences((preferenceRes.data ?? []) as FoodPreference[])
        setPresets((presetRes.data ?? []) as MealPreset[])
        setPresetItems((presetItemRes.data ?? []) as MealPresetItem[])
        setMeals((mealRes.data ?? []) as LoggedMeal[])
        setEntries((entryRes.data ?? []) as LoggedFoodEntry[])
        await Promise.all([
          cacheVisibleFoods(userId, remoteFoods),
          privatePutMany('food_preferences', (preferenceRes.data ?? []) as FoodPreference[]),
          privatePutMany('meal_presets', (presetRes.data ?? []) as MealPreset[]),
          privatePutMany('meal_preset_items', (presetItemRes.data ?? []) as MealPresetItem[]),
          privatePutMany('logged_meals', (mealRes.data ?? []) as LoggedMeal[]),
          privatePutMany('logged_food_entries', (entryRes.data ?? []) as LoggedFoodEntry[]),
        ])
      }
    } catch (error) {
      console.warn('Food history refresh failed; using private offline cache', error)
    } finally {
      setSyncing(false)
      setReady(true)
    }
  }, [userId])

  useEffect(() => { void hydrate() }, [hydrate])

  const applyDayAggregate = useCallback((date: string, nextMeals: LoggedMeal[]) => {
    if (!userId) return
    const totals = aggregateLoggedMeals(nextMeals.filter((meal) => meal.local_date === date))
    const existing = data.daily_logs.find((log) => log.date === date)
    const hasStructured = nextMeals.some((meal) => meal.local_date === date)
    const wasManual = existing?.nutrition_source !== 'structured'
    upsert('daily_logs', {
      id: existing?.id ?? dailyLogId(date, userId),
      user_id: userId,
      date,
      water_l: existing?.water_l ?? 0,
      estimated_tdee: existing?.estimated_tdee ?? null,
      computed_pal: existing?.computed_pal ?? null,
      activity_mode: existing?.activity_mode ?? 'quick',
      weight_kg: existing?.weight_kg ?? null,
      ...existing,
      manual_kcal: wasManual ? existing?.kcal ?? existing?.manual_kcal ?? null : existing?.manual_kcal ?? null,
      manual_protein_g: wasManual ? existing?.protein_g ?? existing?.manual_protein_g ?? null : existing?.manual_protein_g ?? null,
      manual_carbs_g: wasManual ? existing?.carbs_g ?? existing?.manual_carbs_g ?? null : existing?.manual_carbs_g ?? null,
      manual_fat_g: wasManual ? existing?.fat_g ?? existing?.manual_fat_g ?? null : existing?.manual_fat_g ?? null,
      kcal: hasStructured ? totals.kcal : existing?.manual_kcal ?? null,
      protein_g: hasStructured ? totals.protein_g : existing?.manual_protein_g ?? null,
      carbs_g: hasStructured ? totals.carbs_g : existing?.manual_carbs_g ?? null,
      fat_g: hasStructured ? totals.fat_g : existing?.manual_fat_g ?? null,
      nutrition_source: hasStructured ? 'structured' : 'manual',
    })
  }, [data.daily_logs, upsert, userId])

  const sendOutbox = useCallback(async (op: PrivateOutboxOp): Promise<boolean> => {
    if (!supabase || isLocalMode) return true
    if (op.operation === 'log_meal') {
      const payload = op.payload as { meal: LoggedMeal & { replace_meal_id?: string | null }; entries: LoggedFoodEntry[] }
      const { error } = await supabase.rpc('log_structured_meal', { p_meal: payload.meal, p_entries: payload.entries })
      if (error) throw error
      return true
    }
    if (op.operation === 'save_food') {
      const { error } = await supabase.from('foods').upsert(op.payload as FoodRecord, { onConflict: 'id' })
      if (error) throw error
      return true
    }
    if (op.operation === 'save_preference') {
      const { error } = await supabase.from('food_preferences').upsert(op.payload as FoodPreference, { onConflict: 'user_id,food_id' })
      if (error) throw error
      return true
    }
    if (op.operation === 'delete_meal') {
      const { error } = await supabase.rpc('delete_structured_meal', { p_meal_id: op.entity_id })
      if (error) throw error
      return true
    }
    if (op.operation === 'save_preset') {
      const payload = op.payload as { preset: MealPreset; items: MealPresetItem[]; expectedVersion: number }
      const { error } = await supabase.rpc('save_meal_preset', {
        p_preset: payload.preset,
        p_items: payload.items,
        p_expected_version: payload.expectedVersion,
      })
      if (error) throw error
      return true
    }
    if (op.operation === 'delete_preset') {
      const { error } = await supabase.rpc('delete_meal_preset', { p_preset_id: op.entity_id })
      if (error) throw error
      return true
    }
    return true
  }, [])

  const flush = useCallback(async () => {
    if (!userId || !supabase || !navigator.onLine || flushing.current) return
    flushing.current = true
    try {
      const operations = (await privateGetAllForUser<PrivateOutboxOp>('private_outbox', userId))
        .filter((operation) => operation.domain === 'food')
        .sort((a, b) => {
          const byTime = a.created_at.localeCompare(b.created_at)
          if (byTime) return byTime
          const priority: Record<string, number> = { save_food: 0, save_preference: 1, save_preset: 2, log_meal: 3, delete_meal: 4, delete_preset: 4 }
          return (priority[a.operation] ?? 9) - (priority[b.operation] ?? 9)
        })
      for (const operation of operations) {
        try {
          await sendOutbox(operation)
          await privateDelete('private_outbox', operation.id)
        } catch (error) {
          await privatePut('private_outbox', { ...operation, attempts: operation.attempts + 1 })
          console.warn('Food sync remains queued', error)
          break
        }
      }
      const remaining = await privateGetAllForUser<PrivateOutboxOp>('private_outbox', userId)
      setQueued(remaining.some((operation) => operation.domain === 'food'))
    } finally {
      flushing.current = false
    }
  }, [sendOutbox, userId])

  useEffect(() => {
    const onOnline = () => void flush()
    window.addEventListener('online', onOnline)
    void flush()
    return () => window.removeEventListener('online', onOnline)
  }, [flush])

  const lookupBarcode = useCallback(async (barcode: string): Promise<FoodLookupResult> => {
    const cached = foods.find((food) => food.barcode === barcode)
    if (cached) return { state: 'found', food: cached }
    if (!supabase) return { state: 'provider_error', message: 'Barcode lookup needs an internet connection.' }
    const { data: result, error } = await supabase.functions.invoke('food-lookup', { body: { barcode } })
    if (error && !result) return { state: 'provider_error', message: error.message }
    const value = result as FoodLookupResult
    if (value.food) {
      const food = normalizeRemoteFood(value.food as unknown as Record<string, unknown>)
      setFoods((current) => current.some((item) => item.id === food.id) ? current : [food, ...current])
      await privatePut('foods', food)
      return { ...value, food }
    }
    return value
  }, [foods])

  const widerSearch = useCallback(async (query: string): Promise<FoodSearchResult> => {
    if (!supabase) return { state: 'provider_error', results: [], message: 'Wider search needs an internet connection.' }
    const { data: result, error } = await supabase.functions.invoke('food-lookup', { body: { query } })
    if (error && !result) return { state: 'provider_error', results: [], message: error.message }
    const value = result as FoodSearchResult
    return { ...value, results: (value.results ?? []).map((food) => normalizeRemoteFood(food as unknown as Record<string, unknown>)) }
  }, [])

  const savePrivateFood = useCallback(async (
    input: Omit<FoodRecord, 'id' | 'owner_user_id' | 'source' | 'created_at' | 'updated_at'>,
  ): Promise<FoodRecord> => {
    if (!userId) throw new Error('Sign in before creating a food')
    const now = new Date().toISOString()
    const food: FoodRecord = { ...input, id: crypto.randomUUID(), owner_user_id: userId, source: 'private', created_at: now, updated_at: now }
    setFoods((current) => [food, ...current])
    await privatePut('foods', food)
    if (!isLocalMode) await privatePut('private_outbox', outbox(userId, 'save_food', food.id, food))
    if (!isLocalMode) setQueued(true)
    if (!isLocalMode && navigator.onLine) await flush()
    return food
  }, [flush, userId])

  const setPreference = useCallback(async (foodId: string, patch: Partial<FoodPreference>) => {
    if (!userId) return
    const current = preferences.find((preference) => preference.food_id === foodId)
    const next: FoodPreference = {
      id: current?.id ?? crypto.randomUUID(),
      user_id: userId,
      food_id: foodId,
      personal_name: null,
      aliases: [],
      favourite: false,
      usual_amount: null,
      usual_unit: null,
      usage_count: 0,
      last_used_at: null,
      hidden: false,
      slot_usage: {},
      version: 1,
      updated_at: new Date().toISOString(),
      ...current,
      ...patch,
    }
    setPreferences((values) => [...values.filter((value) => value.food_id !== foodId), next])
    await privatePut('food_preferences', next)
    if (!isLocalMode) await privatePut('private_outbox', outbox(userId, 'save_preference', next.id, next))
    if (!isLocalMode) setQueued(true)
    if (!isLocalMode && navigator.onLine) await flush()
  }, [flush, preferences, userId])

  const logMeal = useCallback(async (input: LogMealInput): Promise<LoggedMeal> => {
    if (!userId) throw new Error('Sign in before logging food')
    const date = input.date ?? todayIso()
    const now = new Date().toISOString()
    const id = crypto.randomUUID()
    const totals = mealTotals(input.items)
    const meal: LoggedMeal = {
      id,
      user_id: userId,
      local_date: date,
      meal_slot: input.slot,
      display_name: input.name,
      source_preset_id: input.sourcePresetId ?? null,
      source_planned_meal_id: input.sourcePlannedMealId ?? null,
      logged_at: now,
      client_idempotency_key: input.idempotencyKey ?? crypto.randomUUID(),
      logged_as: input.loggedAs ?? 'custom',
      total_kcal: totals.kcal,
      total_protein_g: totals.protein_g,
      total_carbs_g: totals.carbs_g,
      total_fat_g: totals.fat_g,
      created_at: now,
      updated_at: now,
    }
    const snapshots = input.items.flatMap((item) => snapshotEntry(item, userId, id, now) ?? [])
    if (snapshots.length !== input.items.length) throw new Error('Every item needs complete nutrition and a reliable portion unit')
    const preferenceUpdates = input.items.map((item) => {
      const current = preferences.find((preference) => preference.food_id === item.food.id)
      return {
        id: current?.id ?? crypto.randomUUID(),
        user_id: userId,
        food_id: item.food.id,
        personal_name: current?.personal_name ?? null,
        aliases: current?.aliases ?? [],
        favourite: current?.favourite ?? false,
        usual_amount: current?.usual_amount ?? item.quantity,
        usual_unit: current?.usual_unit ?? item.unit,
        usage_count: (current?.usage_count ?? 0) + 1,
        last_used_at: now,
        hidden: current?.hidden ?? false,
        slot_usage: { ...(current?.slot_usage ?? {}), [input.slot]: (current?.slot_usage?.[input.slot] ?? 0) + 1 },
        version: (current?.version ?? 0) + 1,
        updated_at: now,
      } satisfies FoodPreference
    })
    const payloadMeal = { ...meal, replace_meal_id: input.replaceMealId ?? null }
    const operation = outbox(userId, 'log_meal', id, { meal: payloadMeal, entries: snapshots })
    await saveMealAtomically(meal, snapshots, preferenceUpdates, isLocalMode ? null : operation)
    if (!isLocalMode) setQueued(true)
    const nextMeals = [meal, ...meals.filter((value) => value.id !== input.replaceMealId)]
    setMeals(nextMeals)
    applyDayAggregate(date, nextMeals)
    setEntries((current) => [...snapshots, ...current.filter((value) => value.meal_id !== input.replaceMealId)])
    setPreferences((current) => [...current.filter((value) => !preferenceUpdates.some((next) => next.food_id === value.food_id)), ...preferenceUpdates])
    if (!isLocalMode && navigator.onLine) await flush()
    return meal
  }, [applyDayAggregate, flush, meals, preferences, userId])

  const deleteMeal = useCallback(async (mealId: string) => {
    if (!userId) return
    const removed = meals.find((meal) => meal.id === mealId)
    if (!removed) return
    await deleteMealLocally(mealId)
    const operation = outbox(userId, 'delete_meal', mealId, null)
    if (!isLocalMode) await privatePut('private_outbox', operation)
    if (!isLocalMode) setQueued(true)
    const nextMeals = meals.filter((meal) => meal.id !== mealId)
    setMeals(nextMeals)
    applyDayAggregate(removed.local_date, nextMeals)
    setEntries((current) => current.filter((entry) => entry.meal_id !== mealId))
    if (!isLocalMode && navigator.onLine) await flush()
  }, [applyDayAggregate, flush, meals, userId])

  const savePreset = useCallback(async (input: SavePresetInput): Promise<MealPreset> => {
    if (!userId) throw new Error('Sign in before saving a preset')
    const existing = input.id ? presets.find((preset) => preset.id === input.id) : undefined
    const now = new Date().toISOString()
    const preset: MealPreset = {
      id: input.id ?? crypto.randomUUID(), user_id: userId, name: input.name, meal_slot: input.slot,
      source_planned_meal_id: input.sourcePlannedMealId ?? null, archived: false,
      version: (existing?.version ?? 0) + 1, created_at: existing?.created_at ?? now, updated_at: now,
    }
    const items: MealPresetItem[] = input.items.map((item, index) => ({
      id: item.id && item.id.length === 36 ? item.id : crypto.randomUUID(), preset_id: preset.id, user_id: userId,
      food_id: item.food.id, sort_order: index, quantity: item.quantity, unit: item.unit,
      optional: item.optional, locked: item.locked, adjustable: item.adjustable,
      minimum_amount: item.minimum_amount, maximum_amount: item.maximum_amount,
      step_amount: item.step_amount, adjustment_role: item.adjustment_role,
    }))
    const operation = outbox(userId, 'save_preset', preset.id, { preset, items, expectedVersion: input.expectedVersion ?? existing?.version ?? 0 })
    await savePresetAtomically(preset, items, isLocalMode ? null : operation)
    if (!isLocalMode) setQueued(true)
    setPresets((current) => [preset, ...current.filter((value) => value.id !== preset.id)])
    setPresetItems((current) => [...items, ...current.filter((value) => value.preset_id !== preset.id)])
    if (!isLocalMode && navigator.onLine) await flush()
    return preset
  }, [flush, presets, userId])

  const deletePreset = useCallback(async (presetId: string) => {
    if (!userId) return
    const operation = outbox(userId, 'delete_preset', presetId, null)
    if (!isLocalMode) await privatePut('private_outbox', operation)
    if (!isLocalMode) setQueued(true)
    await deletePresetLocally(presetId)
    setPresets((current) => current.filter((preset) => preset.id !== presetId))
    setPresetItems((current) => current.filter((item) => item.preset_id !== presetId))
    if (!isLocalMode && navigator.onLine) await flush()
  }, [flush, userId])

  const mealsForDate = useCallback((date: string) => meals.filter((meal) => meal.local_date === date), [meals])
  const itemsForPreset = useCallback((presetId: string): ComposerFoodItem[] => presetItems
    .filter((item) => item.preset_id === presetId)
    .sort((a, b) => a.sort_order - b.sort_order)
    .flatMap((item) => {
      const food = foods.find((value) => value.id === item.food_id)
      return food ? [{ ...item, food }] : []
    }), [foods, presetItems])

  const value = useMemo<FoodStoreValue>(() => ({
    ready, syncing, queued, foods, preferences, presets, presetItems, meals, entries,
    lookupBarcode, widerSearch, savePrivateFood, setPreference, logMeal, deleteMeal,
    savePreset, deletePreset, mealsForDate, itemsForPreset,
  }), [deleteMeal, deletePreset, entries, foods, itemsForPreset, logMeal, lookupBarcode, meals, mealsForDate, preferences, presetItems, presets, queued, ready, savePreset, savePrivateFood, setPreference, syncing, widerSearch])

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useFoodStore(): FoodStoreValue {
  const value = useContext(Ctx)
  if (!value) throw new Error('useFoodStore outside FoodStoreProvider')
  return value
}
