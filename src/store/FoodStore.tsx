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
import type { SupabaseClient } from '@supabase/supabase-js'
import { COMMON_FOODS } from '../data/foodSeeds'
import {
  addLoggedMealToHistory,
  aggregateLoggedMeals,
  expandFoodSearchQueries,
  foodPreferenceUsageUpdates,
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
import type { IntroLanguage } from '../lib/introLanguage'
import {
  foodMutationBelongsToActiveUser,
  foodOperationBelongsToUser,
  replayFoodOutbox,
  foodSessionBelongsToExpectedUser,
} from '../lib/foodSync'
import { mergePendingSyncOperations } from '../lib/sync'
import {
  cacheVisibleFoods,
  deleteMealLocally,
  deletePresetLocally,
  loadVisibleFoods,
  privateDeleteForUser,
  privateGetAllForUser,
  privatePut,
  replaceFoodUserCacheAtomically,
  saveMealAtomically,
  savePresetAtomically,
  type PrivateOutboxOp,
} from '../lib/privateDb'
import { createSessionBoundSupabase, isLocalMode, supabase } from '../lib/supabase'
import { todayIso } from '../lib/plan'
import { dailyLogId } from '../lib/ids'
import { useStore } from './AppStore'
import {
  OPEN_FOOD_FACTS_FIELDS,
  normalizeBarcode,
  normalizeOpenFoodFactsProduct,
} from '../../shared/openFoodFacts'

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
  widerSearch: (query: string, language?: IntroLanguage) => Promise<FoodSearchResult>
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
let lastFoodOutboxMs = 0

function outbox(userId: string, operation: string, entityId: string, payload: unknown): PrivateOutboxOp {
  lastFoodOutboxMs = Math.max(Date.now(), lastFoodOutboxMs + 1)
  return {
    id: crypto.randomUUID(),
    user_id: userId,
    domain: 'food',
    operation,
    entity_id: entityId,
    payload,
    created_at: new Date(lastFoodOutboxMs).toISOString(),
    attempts: 0,
  }
}

function normalizeRemoteFood(row: Record<string, unknown>): FoodRecord {
  return {
    ...(row as unknown as FoodRecord),
    names_i18n: (row.names_i18n ?? {}) as FoodRecord['names_i18n'],
  }
}

async function searchPublicFoodCatalog(query: string): Promise<FoodRecord[]> {
  const searchUrl = new URL('https://world.openfoodfacts.org/cgi/search.pl')
  searchUrl.searchParams.set('search_terms', query)
  searchUrl.searchParams.set('search_simple', '1')
  searchUrl.searchParams.set('action', 'process')
  searchUrl.searchParams.set('json', '1')
  searchUrl.searchParams.set('page_size', '15')
  searchUrl.searchParams.set('fields', OPEN_FOOD_FACTS_FIELDS)
  const controller = new AbortController()
  const timeout = window.setTimeout(() => controller.abort(), 8_000)
  try {
    const response = await fetch(searchUrl, { headers: { Accept: 'application/json' }, signal: controller.signal })
    if (!response.ok) return []
    const payload = await response.json() as { products?: Array<Record<string, unknown>> }
    const now = new Date().toISOString()
    return (payload.products ?? []).flatMap((product) => {
      const code = normalizeBarcode(String(product.code ?? ''))
      if (!code) return []
      const normalized = normalizeOpenFoodFactsProduct({ status: 1, product }, code)
      return normalized ? [{
        id: `off:${code}`,
        owner_user_id: null,
        ...normalized,
        piece_grams_or_ml: null,
        created_at: now,
        updated_at: now,
      }] : []
    })
  } catch {
    return []
  } finally {
    window.clearTimeout(timeout)
  }
}

function mergeFoodCatalog(incoming: FoodRecord[]): FoodRecord[] {
  const merged = new Map(COMMON_FOODS.map((food) => [food.id, food]))
  for (const food of incoming) {
    const fallback = merged.get(food.id)
    merged.set(food.id, {
      ...fallback,
      ...food,
      names_i18n: { ...(fallback?.names_i18n ?? {}), ...(food.names_i18n ?? {}) },
    })
  }
  return [...merged.values()]
}

async function fetchAllOwnedFoodRows(
  client: SupabaseClient,
  table: string,
  userId: string,
): Promise<Record<string, unknown>[]> {
  const pageSize = 500
  const rows: Record<string, unknown>[] = []
  for (let offset = 0; ; offset += pageSize) {
    const { data: page, error } = await client
      .from(table)
      .select('*')
      .eq('user_id', userId)
      .order('id', { ascending: true })
      .range(offset, offset + pageSize - 1)
    if (error) throw error
    const owned = (page ?? []).filter((row) => row.user_id === userId) as Record<string, unknown>[]
    rows.push(...owned)
    if ((page?.length ?? 0) < pageSize) return rows
  }
}

export function FoodStoreProvider({ children }: { children: ReactNode }) {
  const { data, upsert } = useStore()
  const userId = data.profile?.user_id ?? null
  const userIdRef = useRef(userId)
  userIdRef.current = userId
  const [ready, setReady] = useState(false)
  const [hydrationRetry, setHydrationRetry] = useState(0)
  const [syncing, setSyncing] = useState(false)
  const [queued, setQueued] = useState(false)
  const [foods, setFoods] = useState<FoodRecord[]>(COMMON_FOODS)
  const [preferences, setPreferences] = useState<FoodPreference[]>([])
  const preferencesRef = useRef<FoodPreference[]>([])
  const [presets, setPresets] = useState<MealPreset[]>([])
  const [presetItems, setPresetItems] = useState<MealPresetItem[]>([])
  const [meals, setMeals] = useState<LoggedMeal[]>([])
  const mealsRef = useRef<LoggedMeal[]>([])
  const [entries, setEntries] = useState<LoggedFoodEntry[]>([])
  const flushingUsers = useRef(new Set<string>())
  const requestedFlushUsers = useRef(new Set<string>())
  const hydrationGeneration = useRef(0)
  const mutationRevision = useRef(0)

  const hydrate = useCallback(async () => {
    const expectedUserId = userId
    const generation = ++hydrationGeneration.current
    const revision = mutationRevision.current
    const current = (): boolean =>
      hydrationGeneration.current === generation && userIdRef.current === expectedUserId
    if (!expectedUserId) {
      setFoods(COMMON_FOODS)
      preferencesRef.current = []
      setPreferences([])
      setPresets([])
      setPresetItems([])
      mealsRef.current = []
      setMeals([])
      setEntries([])
      setQueued(false)
      setSyncing(false)
      setReady(true)
      return
    }
    setReady(false)
    try {
      const [localFoods, localPreferences, localPresets, localPresetItems, localMeals, localEntries] = await Promise.all([
        loadVisibleFoods(expectedUserId),
        privateGetAllForUser<FoodPreference>('food_preferences', expectedUserId),
        privateGetAllForUser<MealPreset>('meal_presets', expectedUserId),
        privateGetAllForUser<MealPresetItem>('meal_preset_items', expectedUserId),
        privateGetAllForUser<LoggedMeal>('logged_meals', expectedUserId),
        privateGetAllForUser<LoggedFoodEntry>('logged_food_entries', expectedUserId),
      ])
      if (!current()) return
      if (mutationRevision.current !== revision) {
        setHydrationRetry((value) => value + 1)
        return
      }
      setFoods(mergeFoodCatalog(localFoods))
      preferencesRef.current = localPreferences
      setPreferences(localPreferences)
      setPresets(localPresets)
      setPresetItems(localPresetItems)
      mealsRef.current = localMeals
      setMeals(localMeals)
      setEntries(localEntries)
      const pending = await privateGetAllForUser<PrivateOutboxOp>('private_outbox', expectedUserId)
      if (!current()) return
      setQueued(pending.some((operation) => operation.domain === 'food'))

      if (supabase) {
        const { data: { session: hydrationSession }, error: sessionError } = await supabase.auth.getSession()
        if (!current()) return
        if (sessionError) throw sessionError
        if (
          !hydrationSession ||
          !foodSessionBelongsToExpectedUser(hydrationSession.user.id, expectedUserId)
        ) return
        const hydrationClient = createSessionBoundSupabase(hydrationSession.access_token)
        if (!hydrationClient || !current()) return
        setSyncing(true)
        const [foodRes, remotePreferences, remotePresets, remotePresetItems, remoteMeals, remoteEntries] = await Promise.all([
          hydrationClient.from('foods').select('*').or(`owner_user_id.is.null,owner_user_id.eq.${expectedUserId}`),
          fetchAllOwnedFoodRows(hydrationClient, 'food_preferences', expectedUserId),
          fetchAllOwnedFoodRows(hydrationClient, 'meal_presets', expectedUserId),
          fetchAllOwnedFoodRows(hydrationClient, 'meal_preset_items', expectedUserId),
          fetchAllOwnedFoodRows(hydrationClient, 'logged_meals', expectedUserId),
          fetchAllOwnedFoodRows(hydrationClient, 'logged_food_entries', expectedUserId),
        ])
        if (!current()) return
        if (foodRes.error) throw foodRes.error
        const latestPending = (await privateGetAllForUser<PrivateOutboxOp>('private_outbox', expectedUserId))
          .filter((operation) => operation.domain === 'food')
        if (!current()) return
        if (mutationRevision.current !== revision) {
          setHydrationRetry((value) => value + 1)
          return
        }
        const pendingDuringRead = mergePendingSyncOperations(
          pending.filter((operation) => operation.domain === 'food'),
          latestPending,
        )
        const remoteFoods = (foodRes.data ?? [])
          .map((row) => normalizeRemoteFood(row as Record<string, unknown>))
          .filter((food) => food.owner_user_id == null || food.owner_user_id === expectedUserId)
        const replayed = replayFoodOutbox({
          foods: remoteFoods,
          preferences: remotePreferences as unknown as FoodPreference[],
          presets: remotePresets as unknown as MealPreset[],
          presetItems: remotePresetItems as unknown as MealPresetItem[],
          meals: remoteMeals as unknown as LoggedMeal[],
          entries: remoteEntries as unknown as LoggedFoodEntry[],
        }, pendingDuringRead)
        setFoods(mergeFoodCatalog(replayed.foods))
        preferencesRef.current = replayed.preferences
        setPreferences(replayed.preferences)
        setPresets(replayed.presets)
        setPresetItems(replayed.presetItems)
        mealsRef.current = replayed.meals
        setMeals(replayed.meals)
        setEntries(replayed.entries)
        await Promise.all([
          cacheVisibleFoods(expectedUserId, replayed.foods),
          replaceFoodUserCacheAtomically(expectedUserId, replayed),
        ])
        if (!current()) return
        if (mutationRevision.current !== revision) setHydrationRetry((value) => value + 1)
      }
    } catch (error) {
      if (current()) console.warn('Food history refresh failed; using private offline cache', error)
    } finally {
      if (current()) {
        setSyncing(false)
        setReady(true)
      }
    }
  }, [hydrationRetry, userId])

  useEffect(() => { void hydrate() }, [hydrate])

  /* Food history lives in its own transactional store. Re-hydrate it when a
     second device changes a meal or preset, and whenever iOS foregrounds the
     app after potentially suspending its realtime socket. A short debounce
     collapses the meal + entry + total events emitted by one RPC. */
  useEffect(() => {
    if (!supabase || !userId) return
    const sb = supabase
    let timer: number | null = null
    const refresh = (): void => {
      if (timer !== null) window.clearTimeout(timer)
      timer = window.setTimeout(() => setHydrationRetry((value) => value + 1), 240)
    }
    const channel = sb.channel(`apex-food-sync-${userId}`)
    for (const table of ['logged_meals', 'logged_food_entries', 'meal_presets', 'meal_preset_items', 'food_preferences']) {
      channel.on('postgres_changes', { event: '*', schema: 'public', table }, refresh)
    }
    channel.subscribe()
    const onVisibility = (): void => {
      if (document.visibilityState === 'visible') refresh()
    }
    document.addEventListener('visibilitychange', onVisibility)
    return () => {
      if (timer !== null) window.clearTimeout(timer)
      document.removeEventListener('visibilitychange', onVisibility)
      void sb.removeChannel(channel)
    }
  }, [userId])

  const applyDayAggregate = useCallback((date: string, nextMeals: LoggedMeal[]) => {
    if (!userId || !foodMutationBelongsToActiveUser(userId, userIdRef.current)) return
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

  const sendOutbox = useCallback(async (client: SupabaseClient, op: PrivateOutboxOp): Promise<boolean> => {
    if (op.operation === 'log_meal') {
      const payload = op.payload as { meal: LoggedMeal & { replace_meal_id?: string | null }; entries: LoggedFoodEntry[] }
      const { error } = await client.rpc('log_structured_meal', { p_meal: payload.meal, p_entries: payload.entries })
      if (error) throw error
      return true
    }
    if (op.operation === 'save_food') {
      const { error } = await client.from('foods').upsert(op.payload as FoodRecord, { onConflict: 'id' })
      if (error) throw error
      return true
    }
    if (op.operation === 'save_preference') {
      const { error } = await client.from('food_preferences').upsert(op.payload as FoodPreference, { onConflict: 'user_id,food_id' })
      if (error) throw error
      return true
    }
    if (op.operation === 'delete_meal') {
      const { error } = await client.rpc('delete_structured_meal', { p_meal_id: op.entity_id })
      if (error) throw error
      return true
    }
    if (op.operation === 'save_preset') {
      const payload = op.payload as { preset: MealPreset; items: MealPresetItem[]; expectedVersion: number }
      const { error } = await client.rpc('save_meal_preset', {
        p_preset: payload.preset,
        p_items: payload.items,
        p_expected_version: payload.expectedVersion,
      })
      if (error) throw error
      return true
    }
    if (op.operation === 'delete_preset') {
      const { error } = await client.rpc('delete_meal_preset', { p_preset_id: op.entity_id })
      if (error) throw error
      return true
    }
    return true
  }, [])

  const flush = useCallback(async () => {
    if (!userId || !supabase || !navigator.onLine) return
    const syncUserId = userId
    if (flushingUsers.current.has(syncUserId)) {
      requestedFlushUsers.current.add(syncUserId)
      return
    }
    flushingUsers.current.add(syncUserId)
    try {
      const { data: { session: syncSession }, error: sessionError } = await supabase.auth.getSession()
      if (sessionError) throw sessionError
      if (!syncSession || syncSession.user.id !== syncUserId) return
      const syncClient = createSessionBoundSupabase(syncSession.access_token)
      if (!syncClient) return
      const operations = (await privateGetAllForUser<PrivateOutboxOp>('private_outbox', syncUserId))
        .filter((operation) => operation.domain === 'food')
        .sort((a, b) => {
          const byTime = a.created_at.localeCompare(b.created_at)
          if (byTime) return byTime
          const priority: Record<string, number> = { save_food: 0, save_preference: 1, save_preset: 2, log_meal: 3, delete_meal: 4, delete_preset: 4 }
          return (priority[a.operation] ?? 9) - (priority[b.operation] ?? 9)
        })
      for (const operation of operations) {
        if (userIdRef.current !== syncUserId || !foodOperationBelongsToUser(operation, syncUserId)) break
        try {
          await sendOutbox(syncClient, operation)
          if (!foodOperationBelongsToUser(operation, syncUserId)) break
          await privateDeleteForUser('private_outbox', operation.id, syncUserId)
        } catch (error) {
          await privatePut('private_outbox', {
            ...operation,
            attempts: operation.attempts + 1,
            last_attempt_at: new Date().toISOString(),
            last_error: error instanceof Error ? error.message : 'Food sync request failed',
          })
          console.warn('Food sync remains queued', error)
          break
        }
      }
      const remaining = await privateGetAllForUser<PrivateOutboxOp>('private_outbox', syncUserId)
      if (userIdRef.current === syncUserId) setQueued(remaining.some((operation) => operation.domain === 'food'))
    } catch (error) {
      console.warn('Food sync will retry from its private queue', error)
    } finally {
      flushingUsers.current.delete(syncUserId)
      if (requestedFlushUsers.current.delete(syncUserId) && navigator.onLine) void flush()
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
    try {
      const { data: result, error } = await supabase.functions.invoke('food-lookup', { body: { barcode } })
      if (error || !result) return { state: 'provider_error', message: 'The barcode provider is temporarily unavailable. Search by name or add a private food.' }
      const value = result as FoodLookupResult
      if (value.food) {
        const food = normalizeRemoteFood(value.food as unknown as Record<string, unknown>)
        setFoods((current) => current.some((item) => item.id === food.id) ? current : [food, ...current])
        await privatePut('foods', food)
        return { ...value, food }
      }
      return value
    } catch {
      return { state: 'provider_error', message: 'The barcode provider is temporarily unavailable. Search by name or add a private food.' }
    }
  }, [foods])

  const widerSearch = useCallback(async (query: string, language: IntroLanguage = 'en'): Promise<FoodSearchResult> => {
    const queries = expandFoodSearchQueries(query, language).slice(0, 3)
    const responses = await Promise.allSettled(queries.map(async (candidate) => {
      if (supabase) {
        try {
          const { data: result, error } = await supabase.functions.invoke('food-lookup', { body: { query: candidate } })
          const value = result as FoodSearchResult | null
          if (!error && value?.results?.length) return value.results.map((row) => normalizeRemoteFood(row as unknown as Record<string, unknown>))
        } catch {
          // The public fallback below keeps search useful when the edge function is unavailable.
        }
      }
      return searchPublicFoodCatalog(candidate)
    }))
    const merged = new Map<string, FoodRecord>()
    for (const response of responses) {
      if (response.status !== 'fulfilled') continue
      for (const food of response.value) merged.set(food.provider_product_id ?? food.id, food)
    }
    return {
      state: 'results',
      results: [...merged.values()],
      message: merged.size ? undefined : 'No additional matches. Your essential foods are still available above.',
    }
  }, [])

  const savePrivateFood = useCallback(async (
    input: Omit<FoodRecord, 'id' | 'owner_user_id' | 'source' | 'created_at' | 'updated_at'>,
  ): Promise<FoodRecord> => {
    if (!userId || !foodMutationBelongsToActiveUser(userId, userIdRef.current)) {
      throw new Error('The active account changed. Please retry creating this food.')
    }
    mutationRevision.current += 1
    const now = new Date().toISOString()
    const food: FoodRecord = { ...input, id: crypto.randomUUID(), owner_user_id: userId, source: 'private', created_at: now, updated_at: now }
    setFoods((current) => [food, ...current])
    await privatePut('foods', food)
    if (!isLocalMode) await privatePut('private_outbox', outbox(userId, 'save_food', food.id, food))
    if (!foodMutationBelongsToActiveUser(userId, userIdRef.current)) return food
    if (!isLocalMode) setQueued(true)
    if (!isLocalMode && navigator.onLine) await flush()
    return food
  }, [flush, userId])

  const setPreference = useCallback(async (foodId: string, patch: Partial<FoodPreference>) => {
    if (!userId || !foodMutationBelongsToActiveUser(userId, userIdRef.current)) return
    mutationRevision.current += 1
    const current = preferencesRef.current.find((preference) => preference.food_id === foodId)
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
    const nextPreferences = [...preferencesRef.current.filter((value) => value.food_id !== foodId), next]
    preferencesRef.current = nextPreferences
    setPreferences(nextPreferences)
    await privatePut('food_preferences', next)
    if (!isLocalMode) await privatePut('private_outbox', outbox(userId, 'save_preference', next.id, next))
    if (!foodMutationBelongsToActiveUser(userId, userIdRef.current)) return
    if (!isLocalMode) setQueued(true)
    if (!isLocalMode && navigator.onLine) await flush()
  }, [flush, userId])

  const logMeal = useCallback(async (input: LogMealInput): Promise<LoggedMeal> => {
    if (!userId || !foodMutationBelongsToActiveUser(userId, userIdRef.current)) {
      throw new Error('The active account changed. Please retry logging this meal.')
    }
    if (input.idempotencyKey) {
      const existing = mealsRef.current.find((meal) => (
        meal.user_id === userId && meal.client_idempotency_key === input.idempotencyKey
      ))
      if (existing) return existing
    }
    mutationRevision.current += 1
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
    const preferenceUpdates = foodPreferenceUsageUpdates(preferencesRef.current, input.items, userId, input.slot, now)
    const payloadMeal = { ...meal, replace_meal_id: input.replaceMealId ?? null }
    const operation = outbox(userId, 'log_meal', id, { meal: payloadMeal, entries: snapshots })
    await saveMealAtomically(
      meal,
      snapshots,
      preferenceUpdates,
      isLocalMode ? null : operation,
      input.replaceMealId ?? null,
    )
    /* The account may have changed while IndexedDB was committing. The A
       intent remains durable, but it must never be merged into B's refs or
       forwarded into B's AppStore daily-log queue. */
    if (!foodMutationBelongsToActiveUser(userId, userIdRef.current)) return meal
    if (!isLocalMode) setQueued(true)
    const nextMeals = addLoggedMealToHistory(mealsRef.current, meal, input.replaceMealId ?? null)
    mealsRef.current = nextMeals
    setMeals(nextMeals)
    applyDayAggregate(date, nextMeals)
    setEntries((current) => [...snapshots, ...current.filter((value) => value.meal_id !== input.replaceMealId)])
    const updatedFoodIds = new Set(preferenceUpdates.map((preference) => preference.food_id))
    const nextPreferences = [...preferencesRef.current.filter((value) => !updatedFoodIds.has(value.food_id)), ...preferenceUpdates]
    preferencesRef.current = nextPreferences
    setPreferences(nextPreferences)
    if (!isLocalMode && navigator.onLine) await flush()
    return meal
  }, [applyDayAggregate, flush, userId])

  const deleteMeal = useCallback(async (mealId: string) => {
    if (!userId || !foodMutationBelongsToActiveUser(userId, userIdRef.current)) return
    const removed = mealsRef.current.find((meal) => meal.id === mealId)
    if (!removed) return
    mutationRevision.current += 1
    const operation = outbox(userId, 'delete_meal', mealId, null)
    await deleteMealLocally(mealId, isLocalMode ? null : operation)
    if (!foodMutationBelongsToActiveUser(userId, userIdRef.current)) return
    if (!isLocalMode) setQueued(true)
    const nextMeals = mealsRef.current.filter((meal) => meal.id !== mealId)
    mealsRef.current = nextMeals
    setMeals(nextMeals)
    applyDayAggregate(removed.local_date, nextMeals)
    setEntries((current) => current.filter((entry) => entry.meal_id !== mealId))
    if (!isLocalMode && navigator.onLine) await flush()
  }, [applyDayAggregate, flush, userId])

  const savePreset = useCallback(async (input: SavePresetInput): Promise<MealPreset> => {
    if (!userId || !foodMutationBelongsToActiveUser(userId, userIdRef.current)) {
      throw new Error('The active account changed. Please retry saving this preset.')
    }
    mutationRevision.current += 1
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
    if (!foodMutationBelongsToActiveUser(userId, userIdRef.current)) return preset
    if (!isLocalMode) setQueued(true)
    setPresets((current) => [preset, ...current.filter((value) => value.id !== preset.id)])
    setPresetItems((current) => [...items, ...current.filter((value) => value.preset_id !== preset.id)])
    if (!isLocalMode && navigator.onLine) await flush()
    return preset
  }, [flush, presets, userId])

  const deletePreset = useCallback(async (presetId: string) => {
    if (!userId || !foodMutationBelongsToActiveUser(userId, userIdRef.current)) return
    mutationRevision.current += 1
    const operation = outbox(userId, 'delete_preset', presetId, null)
    await deletePresetLocally(presetId, isLocalMode ? null : operation)
    if (!foodMutationBelongsToActiveUser(userId, userIdRef.current)) return
    if (!isLocalMode) setQueued(true)
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
