/*
 * Offline-first data store. All reads come from memory (hydrated from
 * localStorage instantly, then refreshed from Supabase). All writes apply
 * optimistically to memory + cache, then queue for Supabase; the queue
 * flushes when connectivity returns. Realtime changes from other devices
 * merge straight into memory.
 */
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
import type { Session, SupabaseClient } from '@supabase/supabase-js'
import { createSessionBoundSupabase, isLocalMode, supabase } from '../lib/supabase'
import { clearAllLocal, loadCache, loadQueue, saveCache, saveQueue, type SyncOp } from '../lib/local'
import type { AppData, DailyLog, RpgSnapshot, Settings } from '../lib/types'
import { EMPTY_DATA } from '../lib/types'
import { computeEngine, type SynergyEvent } from '../lib/rpg'
import { eventContextFor, todayIso } from '../lib/plan'
import { activityLogId, dailyLogId, rpgSnapshotId } from '../lib/ids'
import {
  getSelectedPersona,
  personaBySlug,
  personaFromUserMetadata,
  setSelectedPersona,
} from '../lib/persona'
import {
  ACTIVITY_CATALOG,
  activityCatalogMap,
  activityLogFromBlock,
  blockFromActivityLog,
  championshipPrefill,
  estimateActivityDay,
  normalizeActivityType,
} from '../lib/activity'
import { computeTargets } from '../lib/nutrition'
import {
  enqueuePendingSyncOperation,
  hasPendingSyncForRecord,
  mergePendingSyncOperations,
  normalizeDailyLogIntegers,
  normalizeSyncPayload,
  normalizeSyncRecord,
  replayPendingList,
  replayPendingSingleton,
  syncFailureBlockKeys,
  syncOperationConflicts,
  upsertConflictTarget,
} from '../lib/sync'
import {
  CURRENT_SEED_VERSION,
  repairSeedDefinitions,
  type SeedDefinitionTable,
} from '../lib/seedRepair'
import { normalizeMealBlockSettings } from '../lib/mealBlocks'

export type SyncStatus = 'synced' | 'queued' | 'local'
export type ListTable =
  | 'meals'
  | 'meal_logs'
  | 'supplements'
  | 'supplement_logs'
  | 'programs'
  | 'program_days'
  | 'exercises'
  | 'workout_sessions'
  | 'workout_logs'
  | 'activity_logs'
  | 'daily_logs'
  | 'events'
  | 'rpg_snapshots'
  | 'deload_marks'
  | 'health_metrics'
  | 'imported_activities'

const LIST_TABLES: readonly ListTable[] = [
  'meals', 'meal_logs', 'supplements', 'supplement_logs', 'programs', 'program_days',
  'exercises', 'workout_sessions', 'workout_logs', 'activity_logs', 'daily_logs', 'events',
  'deload_marks', 'health_metrics', 'imported_activities',
]
const LIST_TABLE_SET = new Set<string>(LIST_TABLES)

function isListTable(value: string): value is ListTable {
  return LIST_TABLE_SET.has(value)
}

interface StoreValue {
  data: AppData
  ready: boolean
  authed: boolean
  syncStatus: SyncStatus
  snapshots: RpgSnapshot[]
  synergies: SynergyEvent[]
  signIn: (email: string, password: string) => Promise<string | null>
  signOut: () => Promise<void>
  upsert: <T extends { id: string }>(table: ListTable, row: T) => void
  bulkUpsert: <T extends { id: string }>(table: ListTable, rows: T[]) => void
  remove: (table: ListTable, id: string) => void
  setProfile: (patch: Partial<AppData['profile']> & object) => void
  setSettings: (patch: Partial<Settings>) => void
  toast: (message: string, kind?: 'error' | 'ok') => void
  toasts: Array<{ id: number; message: string; kind: 'error' | 'ok' }>
}

const Ctx = createContext<StoreValue | null>(null)

const LOCAL_USER = '00000000-0000-4000-8000-000000000001'

function normalizeDailyLog(log: DailyLog): DailyLog {
  return normalizeDailyLogIntegers({
    ...log,
    estimated_tdee: log.estimated_tdee ?? null,
    computed_pal: log.computed_pal ?? null,
    activity_mode: log.activity_mode ?? 'quick',
    weight_kg: log.weight_kg ?? null,
    nutrition_source: log.nutrition_source ?? 'manual',
    manual_kcal: log.manual_kcal ?? null,
    manual_protein_g: log.manual_protein_g ?? null,
    manual_fat_g: log.manual_fat_g ?? null,
    manual_carbs_g: log.manual_carbs_g ?? null,
  })
}

function normalizeAppData(value: AppData): AppData {
  const settings: Settings | null = value.settings
    ? {
        ...value.settings,
        addons: {
          ...value.settings.addons,
          endurance1: value.settings.addons?.endurance1 ?? false,
          endurance2: value.settings.addons?.endurance2 ?? false,
          endurance3: value.settings.addons?.endurance3 ?? false,
          newbie_mode: value.settings.addons?.newbie_mode ?? false,
          training_induction: value.settings.addons?.training_induction ?? null,
          comparison_export_mode: value.settings.addons?.comparison_export_mode === 'minimal' ? 'minimal' : 'detailed',
          weight_unit: value.settings.addons?.weight_unit === 'lb' ? 'lb' : 'kg',
          simple_show_orbit: value.settings.addons?.simple_show_orbit ?? true,
          simple_show_body_index: value.settings.addons?.simple_show_body_index ?? true,
          simple_show_guided_plan: value.settings.addons?.simple_show_guided_plan ?? true,
          simple_show_hydration_reminder: value.settings.addons?.simple_show_hydration_reminder ?? false,
          simple_show_manual_workout: value.settings.addons?.simple_show_manual_workout ?? false,
          adhd_mode: value.settings.addons?.adhd_mode ?? false,
          meal_blocks: normalizeMealBlockSettings(value.settings.addons?.meal_blocks),
        },
      }
    : null
  const settingsHasCustomBmr = Boolean(settings?.addons && Object.prototype.hasOwnProperty.call(settings.addons, 'custom_bmr'))
  const storedCustomBmr = settingsHasCustomBmr ? settings!.addons.custom_bmr : value.profile?.custom_bmr
  const profile = value.profile
    ? {
        ...value.profile,
        custom_bmr: storedCustomBmr == null ? null : Number(storedCustomBmr),
        calibration_k: Number(value.profile.calibration_k ?? 1),
        seed_version: Number(value.profile.seed_version ?? 0),
        calibration_history: Array.isArray(value.profile.calibration_history)
          ? value.profile.calibration_history
          : [],
      }
    : null
  return {
    ...EMPTY_DATA,
    ...value,
    profile,
    settings,
    activity_types: value.activity_types?.length ? value.activity_types : ACTIVITY_CATALOG,
    activity_logs: value.activity_logs ?? [],
    daily_logs: (value.daily_logs ?? []).map(normalizeDailyLog),
  }
}

function isSchemaCacheError(error: { code?: string; message: string }): boolean {
  return (
    error.code === 'PGRST205' ||
    error.message.includes('schema cache') ||
    error.message.includes('Could not find the table')
  )
}

function recordsEqual(a: object, b: object): boolean {
  const left = a as Record<string, unknown>
  const right = b as Record<string, unknown>
  const keys = Object.keys(left)
  if (keys.length !== Object.keys(right).length) return false
  return keys.every((key) => {
    const l = left[key]
    const r = right[key]
    if (l === r) return true
    if (l && r && typeof l === 'object' && typeof r === 'object') {
      return JSON.stringify(l) === JSON.stringify(r)
    }
    return false
  })
}

async function fetchAllOwnedRows(
  client: SupabaseClient,
  table: ListTable,
  userId: string,
): Promise<Array<{ id: string; user_id: string }>> {
  const pageSize = 500
  const rows: Array<{ id: string; user_id: string }> = []
  for (let offset = 0; ; offset += pageSize) {
    const { data: page, error } = await client
      .from(table)
      .select('*')
      .eq('user_id', userId)
      .order('id', { ascending: true })
      .range(offset, offset + pageSize - 1)
    if (error) throw error
    rows.push(...((page ?? []).filter((row) => row.user_id === userId) as Array<{ id: string; user_id: string }>))
    if ((page?.length ?? 0) < pageSize) return rows
  }
}

export function AppStoreProvider({ children }: { children: ReactNode }) {
  const scopeRef = useRef(isLocalMode ? LOCAL_USER : 'pending')
  const [data, setData] = useState<AppData>(() =>
    isLocalMode ? normalizeAppData(loadCache(LOCAL_USER) ?? EMPTY_DATA) : EMPTY_DATA,
  )
  const [ready, setReady] = useState(isLocalMode)
  const [session, setSession] = useState<Session | null>(null)
  const sessionRef = useRef(session)
  sessionRef.current = session
  const [queueLen, setQueueLen] = useState(() =>
    isLocalMode ? loadQueue(LOCAL_USER).length : 0,
  )
  const [online, setOnline] = useState(navigator.onLine)
  const [hydrationRetry, setHydrationRetry] = useState(0)
  const [toasts, setToasts] = useState<Array<{ id: number; message: string; kind: 'error' | 'ok' }>>([])
  const dataRef = useRef(data)
  dataRef.current = data
  const flushing = useRef(false)
  const flushRequested = useRef(false)
  const inFlightOperationId = useRef<string | null>(null)
  const mutationRevision = useRef(0)
  const fetchGeneration = useRef(0)
  const lastSchemaToastAt = useRef(0)
  const lastSyncErrorToastAt = useRef(0)
  const pendingCache = useRef<{ data: AppData; scope: string } | null>(null)
  const cacheSaveTimer = useRef<number | null>(null)

  const flushPendingCache = useCallback(() => {
    if (cacheSaveTimer.current !== null) {
      window.clearTimeout(cacheSaveTimer.current)
      cacheSaveTimer.current = null
    }
    const pending = pendingCache.current
    pendingCache.current = null
    if (pending) saveCache(pending.data, pending.scope)
  }, [])

  const scheduleCacheSave = useCallback((next: AppData) => {
    pendingCache.current = { data: next, scope: scopeRef.current }
    if (cacheSaveTimer.current !== null) return
    /* JSON serialisation and localStorage are synchronous. Coalesce rapid
       steppers/check-offs so a tap never serialises the complete app dataset
       several times in the same interaction. */
    cacheSaveTimer.current = window.setTimeout(flushPendingCache, 180)
  }, [flushPendingCache])

  const toast = useCallback((message: string, kind: 'error' | 'ok' = 'error') => {
    const id = Date.now() + Math.random()
    setToasts((t) => [...t, { id, message, kind }])
    window.setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 4200)
  }, [])

  const persist = useCallback((next: AppData) => {
    /* update the ref synchronously so several writes in one tick compose */
    dataRef.current = next
    setData(next)
    scheduleCacheSave(next)
  }, [scheduleCacheSave])

  useEffect(() => {
    const flushOnPageHide = (): void => flushPendingCache()
    const flushWhenHidden = (): void => {
      if (document.visibilityState === 'hidden') flushPendingCache()
    }
    window.addEventListener('pagehide', flushOnPageHide)
    document.addEventListener('visibilitychange', flushWhenHidden)
    return () => {
      window.removeEventListener('pagehide', flushOnPageHide)
      document.removeEventListener('visibilitychange', flushWhenHidden)
      flushPendingCache()
    }
  }, [flushPendingCache])

  /* ---------- queue flush ---------- */
  const flush = useCallback(async () => {
    if (!supabase || !navigator.onLine) return
    if (flushing.current) {
      flushRequested.current = true
      return
    }
    flushing.current = true
    const scope = scopeRef.current
    try {
      const syncSession = sessionRef.current
      const syncClient = syncSession?.user.id === scope
        ? createSessionBoundSupabase(syncSession.access_token)
        : null
      if (!syncClient) return
      let queue = loadQueue(scope)
      const attemptedIds = new Set<string>()
      const blockedKeys = new Set<string>()
      while (queue.length > 0) {
        if (scopeRef.current !== scope) break
        const op = queue.find((candidate) =>
          !attemptedIds.has(candidate.id) && !syncOperationConflicts(candidate, blockedKeys),
        )
        if (!op) break
        attemptedIds.add(op.id)
        const conflictTarget = upsertConflictTarget(op.table)
        const syncPayload = op.type === 'upsert'
          ? normalizeSyncPayload(op.table, op.payload)
          : op.payload
        let error: { code?: string; message: string } | null = null
        let requestThrew = false
        inFlightOperationId.current = op.id
        try {
          const result = op.type === 'upsert'
            ? conflictTarget
              ? await syncClient.from(op.table).upsert(syncPayload, { onConflict: conflictTarget })
              : await syncClient.from(op.table).upsert(syncPayload)
            : await syncClient
                .from(op.table)
                .delete()
                .eq('id', (op.payload as Record<string, unknown>).id as string)
                .eq('user_id', scope)
          error = result.error
        } catch (requestError) {
          requestThrew = true
          error = {
            message: requestError instanceof Error ? requestError.message : 'The network request failed',
          }
        } finally {
          if (inFlightOperationId.current === op.id) inFlightOperationId.current = null
        }
        if (scopeRef.current !== scope) break
        if (error) {
          /* A PostgREST schema refresh can lag just after a migration. Keep the
             write queued instead of dropping user data as a validation error. */
          if (isSchemaCacheError(error)) {
            if (Date.now() - lastSchemaToastAt.current > 15_000) {
              lastSchemaToastAt.current = Date.now()
              toast('Sync is reconnecting. Your changes are queued safely.')
            }
            blockedKeys.add(`${op.table}:*`)
            continue
          }
          /* Never discard the only durable copy of a user's server-write
             intent. Validation and policy failures can be repaired by an app
             or schema update, so retain the operation for a later replay. */
          if (Date.now() - lastSyncErrorToastAt.current > 15_000) {
            lastSyncErrorToastAt.current = Date.now()
            toast(`Sync paused on ${op.table}. Your change remains queued: ${error.message}`)
          }
          if (requestThrew || error.message.toLowerCase().includes('fetch')) break
          for (const key of syncFailureBlockKeys(op)) blockedKeys.add(key)
          continue
        }
        queue = loadQueue(scope).filter((queued) => queued.id !== op.id)
        saveQueue(queue, scope)
      }
      if (scopeRef.current === scope) setQueueLen(loadQueue(scope).length)
    } finally {
      flushing.current = false
      inFlightOperationId.current = null
      if (flushRequested.current) {
        flushRequested.current = false
        /* The request may have belonged to an account that just signed out.
           Resume against whichever scoped account is active now. */
        if (navigator.onLine) window.setTimeout(() => void flush(), 0)
      }
    }
  }, [toast])

  const enqueue = useCallback(
    (op: { table: string; type: 'upsert' | 'delete'; payload: object }) => {
      if (!supabase) return
      const queue = loadQueue(scopeRef.current)
      const rawPayload = op.payload as Record<string, unknown> | Array<Record<string, unknown>>
      const payload = op.type === 'upsert'
        ? normalizeSyncPayload(op.table, rawPayload)
        : rawPayload
      const nextQueue = enqueuePendingSyncOperation(queue, { ...op, payload }, {
        id: crypto.randomUUID(),
        ts: Date.now(),
        inFlightId: inFlightOperationId.current,
      }) as SyncOp[]
      saveQueue(nextQueue, scopeRef.current)
      setQueueLen(nextQueue.length)
      void flush()
    },
    [flush],
  )

  /* ---------- writes ---------- */
  const upsert = useCallback(
    <T extends { id: string }>(table: ListTable, row: T) => {
      const normalizedRow = normalizeSyncRecord(table, row)
      mutationRevision.current += 1
      const cur = dataRef.current
      const list = cur[table] as unknown as T[]
      const i = list.findIndex((r) => r.id === normalizedRow.id)
      const nextList = i >= 0
        ? list.map((r) => (r.id === normalizedRow.id ? normalizedRow : r))
        : [...list, normalizedRow]
      persist({ ...cur, [table]: nextList })
      enqueue({ table, type: 'upsert', payload: normalizedRow as unknown as Record<string, unknown> })
    },
    [persist, enqueue],
  )

  /* bulk merge for imports: one state update, chunked sync ops */
  const bulkUpsert = useCallback(
    <T extends { id: string }>(table: ListTable, rows: T[]) => {
      if (rows.length === 0) return
      const normalizedRows = rows.map((row) => normalizeSyncRecord(table, row))
      mutationRevision.current += 1
      const cur = dataRef.current
      const list = cur[table] as unknown as T[]
      const map = new Map(list.map((r) => [r.id, r]))
      for (const row of normalizedRows) map.set(row.id, row)
      persist({ ...cur, [table]: [...map.values()] })
      for (let i = 0; i < normalizedRows.length; i += 400) {
        enqueue({
          table,
          type: 'upsert',
          payload: normalizedRows.slice(i, i + 400) as unknown as Array<Record<string, unknown>>,
        })
      }
    },
    [persist, enqueue],
  )

  const remove = useCallback(
    (table: ListTable, id: string) => {
      mutationRevision.current += 1
      const cur = dataRef.current
      const list = cur[table] as Array<{ id: string }>
      persist({ ...cur, [table]: list.filter((r) => r.id !== id) })
      enqueue({ table, type: 'delete', payload: { id } })
    },
    [persist, enqueue],
  )

  const setProfile = useCallback(
    (patch: object) => {
      const cur = dataRef.current
      if (!cur.profile) return
      mutationRevision.current += 1
      const profile = { ...cur.profile, ...patch, updated_at: new Date().toISOString() }
      persist({ ...cur, profile })
      enqueue({ table: 'profile', type: 'upsert', payload: profile })
    },
    [persist, enqueue],
  )

  const setSettings = useCallback(
    (patch: Partial<Settings>) => {
      const cur = dataRef.current
      if (!cur.settings) return
      mutationRevision.current += 1
      const settings = { ...cur.settings, ...patch }
      const hasCustomBmr = Boolean(patch.addons && Object.prototype.hasOwnProperty.call(patch.addons, 'custom_bmr'))
      const profile = hasCustomBmr && cur.profile
        ? { ...cur.profile, custom_bmr: patch.addons?.custom_bmr ?? null, updated_at: new Date().toISOString() }
        : cur.profile
      persist({ ...cur, settings, profile })
      enqueue({ table: 'settings', type: 'upsert', payload: settings })
    },
    [persist, enqueue],
  )

  /* ---------- auth + initial fetch ---------- */
  const adoptSession = useCallback((nextSession: Session | null) => {
    /* Finish the previous account's cache write before changing the scope. */
    flushPendingCache()
    fetchGeneration.current += 1
    if (nextSession) {
      const scope = nextSession.user.id
      let cached = loadCache(scope)
      let queue = loadQueue(scope)
      /* One-time migration from the original single-account cache. Only the
         legacy Constantine account may inherit it; friend accounts always
         start with isolated storage. */
      if (!cached && personaFromUserMetadata(nextSession.user.user_metadata) === 'constantine') {
        const legacyCache = loadCache('local')
        const legacyQueue = loadQueue('local')
        if (legacyCache) {
          cached = legacyCache
          saveCache(legacyCache, scope)
        }
        if (legacyQueue.length > 0) {
          queue = legacyQueue
          saveQueue(legacyQueue, scope)
        }
        if (legacyCache || legacyQueue.length > 0) clearAllLocal('local')
      }
      if (cached?.profile) {
        const cachedProfile = cached.profile
        cached = {
          ...cached,
          profile: {
            ...cachedProfile,
            persona: cachedProfile.persona ?? 'constantine',
            display_name: cachedProfile.display_name ?? 'Constantine',
            target_kcal: cachedProfile.target_kcal ?? null,
            target_protein_g: cachedProfile.target_protein_g ?? null,
            target_fat_g: cachedProfile.target_fat_g ?? null,
            target_carbs_g: cachedProfile.target_carbs_g ?? null,
            custom_bmr: cachedProfile.custom_bmr == null ? null : Number(cachedProfile.custom_bmr),
            profile_note: cachedProfile.profile_note ?? '',
            seed_version: Number(cachedProfile.seed_version ?? 0),
            calibration_k: Number(cachedProfile.calibration_k ?? 1),
            calibration_history: Array.isArray(cachedProfile.calibration_history)
              ? cachedProfile.calibration_history
              : [],
          },
        }
      }
      if (cached) cached = normalizeAppData(cached)
      scopeRef.current = scope
      dataRef.current = cached ?? EMPTY_DATA
      setData(cached ?? EMPTY_DATA)
      setQueueLen(queue.length)
    } else {
      scopeRef.current = 'pending'
      dataRef.current = EMPTY_DATA
      setData(EMPTY_DATA)
      setQueueLen(0)
    }
    setSession(nextSession)
    setReady(true)
  }, [flushPendingCache])

  useEffect(() => {
    if (!supabase) {
      /* Local mode: seed on first ever run */
      if (!dataRef.current.profile) {
        const persona = getSelectedPersona() ?? 'constantine'
        void import('../data/seed').then(({ buildSeedData }) => {
          if (!dataRef.current.profile) persist(buildSeedData(LOCAL_USER, persona))
        })
      } else if (Number(dataRef.current.profile.seed_version ?? 0) < CURRENT_SEED_VERSION) {
        const persona = dataRef.current.profile.persona
        void import('../data/seed').then(({ buildSeedData }) => {
          const current = dataRef.current
          if (!current.profile || Number(current.profile.seed_version ?? 0) >= CURRENT_SEED_VERSION) return
          persist(normalizeAppData(repairSeedDefinitions(current, buildSeedData(LOCAL_USER, persona)).data))
        })
      }
      return
    }
    void supabase.auth.getSession().then(({ data: { session: s } }) => {
      adoptSession(s)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_evt, s) => adoptSession(s))
    return () => sub.subscription.unsubscribe()
  }, [adoptSession, persist])

  const fetchAll = useCallback(async () => {
    if (!session) return
    const sessionUserId = session.user.id
    const sb = createSessionBoundSupabase(session.access_token)
    if (!sb || scopeRef.current !== sessionUserId) return
    const accountPersona = personaFromUserMetadata(session.user.user_metadata)
    const generation = ++fetchGeneration.current
    const revision = mutationRevision.current
    const pendingBefore = loadQueue(sessionUserId)
    try {
      const [profileRes, settingsRes, catalogRes, listRows] = await Promise.all([
        sb.from('profile').select('*').eq('user_id', sessionUserId).maybeSingle(),
        sb.from('settings').select('*').eq('user_id', sessionUserId).maybeSingle(),
        sb.from('activity_types').select('*'),
        Promise.all(LIST_TABLES.map((table) => fetchAllOwnedRows(sb, table, sessionUserId))),
      ])
      if (scopeRef.current !== sessionUserId || fetchGeneration.current !== generation) return
      const failed = [profileRes, settingsRes, catalogRes].find((result) => result.error)?.error
      if (failed) throw failed
      const pending = mergePendingSyncOperations(pendingBefore, loadQueue(sessionUserId))
      /* Never let a SELECT that began before a local edit replace that edit.
         Retry from the durable cache/outbox once this render settles. */
      if (mutationRevision.current !== revision) {
        setHydrationRetry((value) => value + 1)
        return
      }
      const next: AppData = {
        ...EMPTY_DATA,
        profile: replayPendingSingleton(
          'profile',
          (profileRes.data?.user_id === sessionUserId ? profileRes.data : null) as NonNullable<AppData['profile']> | null,
          pending,
        ) as AppData['profile'],
        settings: replayPendingSingleton(
          'settings',
          (settingsRes.data?.user_id === sessionUserId ? settingsRes.data : null) as Settings | null,
          pending,
        ),
        activity_types: catalogRes.data?.length
          ? catalogRes.data.map((row) => normalizeActivityType(row as Parameters<typeof normalizeActivityType>[0]))
          : ACTIVITY_CATALOG,
        rpg_snapshots: dataRef.current.rpg_snapshots,
      }
      LIST_TABLES.forEach((table, index) => {
        const remoteRows = (listRows[index] ?? [])
          .filter((row) => row.user_id === sessionUserId) as Array<{ id: string }>
        ;(next as unknown as Record<string, unknown>)[table] = replayPendingList(table, remoteRows, pending)
      })
      next.daily_logs = next.daily_logs.map(normalizeDailyLog)

      const needsSeedRepair = !next.profile || Number(next.profile.seed_version ?? 0) < CURRENT_SEED_VERSION
      if (needsSeedRepair) {
        const { buildSeedData } = await import('../data/seed')
        if (
          scopeRef.current !== sessionUserId ||
          fetchGeneration.current !== generation ||
          mutationRevision.current !== revision
        ) {
          setHydrationRetry((value) => value + 1)
          return
        }
        const seeded = buildSeedData(sessionUserId, accountPersona)
        const repair = repairSeedDefinitions(next, seeded)
        persist(normalizeAppData(repair.data))

        if (repair.needsRepair) {
          /* Definition rows go first and the profile version marker goes last.
             A second device can therefore resume an interrupted repair safely. */
          if (repair.settingsChanged && repair.data.settings) {
            enqueue({ table: 'settings', type: 'upsert', payload: repair.data.settings })
          }
          const seedTables: SeedDefinitionTable[] = ['meals', 'supplements', 'programs', 'program_days', 'exercises']
          for (const table of seedTables) {
            if (repair.missing[table].length > 0) {
              enqueue({ table, type: 'upsert', payload: repair.missing[table] })
            }
          }
          if (repair.profileChanged && repair.data.profile) {
            enqueue({ table: 'profile', type: 'upsert', payload: repair.data.profile })
          }
        }
      } else {
        persist(normalizeAppData(next))
      }
    } catch {
      toast('Could not reach Supabase, running from local cache')
    }
  }, [session, persist, enqueue, toast])

  useEffect(() => {
    if (session) void fetchAll()
  }, [session, fetchAll, hydrationRetry])

  /* A profile switch can interrupt an in-flight write after Supabase has
     received it but before the local queue is acknowledged. Resume every
     scoped queue as soon as that account is active again, even if the user
     has not made another edit yet. */
  useEffect(() => {
    if (session && online && queueLen > 0) void flush()
  }, [session, online, queueLen, flush])

  /* ---------- activity automation shared by every route ---------- */
  useEffect(() => {
    const profile = data.profile
    if (!profile) return
    const date = todayIso()
    const context = eventContextFor(date, data.events)
    if (!context?.isDuring || context.event.type !== 'filming_championship') return
    const catalog = activityCatalogMap(data.activity_types)
    let index = 0
    const blocks = championshipPrefill(() =>
      activityLogId(date, profile.user_id, `event:${context.event.id}:${index++}`),
    )
    for (const block of blocks) {
      if (!data.activity_logs.some((log) => log.id === block.id)) {
        upsert('activity_logs', activityLogFromBlock(block, profile, date, catalog))
      }
    }
  }, [data.activity_logs, data.activity_types, data.events, data.profile, upsert])

  useEffect(() => {
    const profile = data.profile
    if (!profile) return
    const date = todayIso()
    const catalog = activityCatalogMap(data.activity_types)
    const activityLogs = data.activity_logs.filter((log) => log.date === date)
    const blocks = activityLogs.map((log) => blockFromActivityLog(log, catalog))
    const estimate = estimateActivityDay(profile, blocks, catalog)
    const quickTargets = computeTargets(profile)
    const mode = blocks.length > 0 ? 'precise' : 'quick'
    const estimatedTdee = mode === 'precise' ? estimate.tdee : quickTargets.tdee
    const computedPal = Math.round((estimatedTdee / estimate.bmr) * 100) / 100
    const existing = data.daily_logs.find((log) => log.date === date)
    if (
      existing?.activity_mode === mode &&
      existing.estimated_tdee === estimatedTdee &&
      Number(existing.computed_pal ?? 0) === computedPal
    ) return
    upsert('daily_logs', {
      id: existing?.id ?? dailyLogId(date, profile.user_id),
      user_id: profile.user_id,
      date,
      kcal: existing?.kcal ?? null,
      protein_g: existing?.protein_g ?? null,
      fat_g: existing?.fat_g ?? null,
      carbs_g: existing?.carbs_g ?? null,
      water_l: existing?.water_l ?? 0,
      estimated_tdee: estimatedTdee,
      computed_pal: computedPal,
      activity_mode: mode,
      weight_kg: existing?.weight_kg ?? null,
    })
  }, [data.activity_logs, data.activity_types, data.daily_logs, data.profile, upsert])

  /* ---------- realtime merge from other devices ---------- */
  useEffect(() => {
    const sb = supabase
    if (!sb || !session) return
    const channel = sb
      .channel(`apex-sync-${session.user.id}`)
      .on('postgres_changes', { event: '*', schema: 'public' }, (payload) => {
        if (scopeRef.current !== session.user.id) return
        const table = payload.table
        if (table !== 'profile' && table !== 'settings' && !isListTable(table)) return
        const cur = dataRef.current
        if (table === 'profile') {
          if (payload.new) {
            const incoming = payload.new as NonNullable<AppData['profile']>
            if (incoming.user_id !== session.user.id) return
            if (hasPendingSyncForRecord(loadQueue(session.user.id), table, incoming.id)) return
            const profile = {
              ...incoming,
              custom_bmr: cur.settings?.addons.custom_bmr ?? cur.profile?.custom_bmr ?? null,
            }
            if (cur.profile && recordsEqual(cur.profile, profile)) return
            persistSilent({ ...cur, profile })
          }
          return
        }
        if (table === 'settings') {
          if (payload.new) {
            const settings = payload.new as Settings
            if (settings.user_id !== session.user.id) return
            if (hasPendingSyncForRecord(loadQueue(session.user.id), table, settings.user_id)) return
            if (cur.settings && recordsEqual(cur.settings, settings)) return
            const hasCustomBmr = Object.prototype.hasOwnProperty.call(settings.addons ?? {}, 'custom_bmr')
            const profile = hasCustomBmr && cur.profile
              ? { ...cur.profile, custom_bmr: settings.addons.custom_bmr ?? null }
              : cur.profile
            persistSilent({ ...cur, settings, profile })
          }
          return
        }
        const list = cur[table] as Array<{ id: string }>
        if (payload.eventType === 'DELETE') {
          const old = payload.old as { id?: string; user_id?: string }
          if (old.user_id && old.user_id !== session.user.id) return
          const oldId = old.id
          if (!oldId || hasPendingSyncForRecord(loadQueue(session.user.id), table, oldId)) return
          /* With the default replica identity a delete may contain only the
             primary key. Only remove ids already present in this account. */
          if (list.some((row) => row.id === oldId)) {
            persistSilent({ ...cur, [table]: list.filter((row) => row.id !== oldId) })
          }
        } else {
          const incoming = payload.new as { id: string; user_id?: string }
          if (incoming.user_id !== session.user.id) return
          if (hasPendingSyncForRecord(loadQueue(session.user.id), table, incoming.id)) return
          const row = normalizeSyncRecord(table, incoming)
          const i = list.findIndex((r) => r.id === row.id)
          if (i >= 0 && recordsEqual(list[i], row)) return
          const nextList = i >= 0 ? list.map((r) => (r.id === row.id ? row : r)) : [...list, row]
          persistSilent({ ...cur, [table]: nextList })
        }
      })
      .subscribe()
    const persistSilent = (next: AppData): void => {
      mutationRevision.current += 1
      dataRef.current = next
      setData(next)
      scheduleCacheSave(next)
    }
    return () => {
      void sb.removeChannel(channel)
    }
  }, [session, scheduleCacheSave])

  /* ---------- connectivity ---------- */
  useEffect(() => {
    const on = (): void => {
      setOnline(true)
      void flush()
    }
    const off = (): void => setOnline(false)
    window.addEventListener('online', on)
    window.addEventListener('offline', off)
    const vis = (): void => {
      if (document.visibilityState === 'visible') void flush()
    }
    document.addEventListener('visibilitychange', vis)
    return () => {
      window.removeEventListener('online', on)
      window.removeEventListener('offline', off)
      document.removeEventListener('visibilitychange', vis)
    }
  }, [flush])

  /* ---------- RPG engine: recompute on load + when history changes ---------- */
  const engine = useMemo(
    () => computeEngine(data, todayIso()),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [data.profile, data.workout_sessions, data.workout_logs, data.daily_logs, data.program_days, data.exercises, data.health_metrics, data.imported_activities],
  )
  const snapshots = engine.snapshots
  useEffect(() => {
    if (snapshots.length === 0) return
    const cur = dataRef.current
    const latest = snapshots[snapshots.length - 1]
    const prev = cur.rpg_snapshots[cur.rpg_snapshots.length - 1]
    if (!prev || prev.date !== latest.date || prev.overall !== latest.overall) {
      persist({ ...cur, rpg_snapshots: snapshots })
      /* Persist only the newest snapshot remotely; history replays deterministically.
         Deterministic id per date makes the upsert idempotent. */
      if (supabase && session) {
        enqueue({
          table: 'rpg_snapshots',
          type: 'upsert',
          payload: { ...latest, id: rpgSnapshotId(latest.date, session.user.id) },
        })
      }
    }
  }, [snapshots, persist, enqueue, session])

  const signIn = useCallback(async (email: string, password: string): Promise<string | null> => {
    const selectedPersona = getSelectedPersona() ?? 'constantine'
    if (!supabase) {
      scopeRef.current = LOCAL_USER
      const { buildSeedData } = await import('../data/seed')
      persist(buildSeedData(LOCAL_USER, selectedPersona))
      return null
    }
    const { data: authData, error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) return error.message

    const accountPersona = personaFromUserMetadata(authData.user?.user_metadata)
    if (selectedPersona !== accountPersona) {
      await supabase.auth.signOut()
      return `Those credentials belong to ${personaBySlug(accountPersona).name}. Choose that profile to continue.`
    }
    setSelectedPersona(accountPersona)
    return null
  }, [persist])

  const signOut = useCallback(async () => {
    if (supabase) await supabase.auth.signOut()
    adoptSession(null)
  }, [adoptSession])

  const syncStatus: SyncStatus = isLocalMode ? 'local' : queueLen > 0 || !online ? 'queued' : 'synced'

  const value = useMemo<StoreValue>(() => ({
    data,
    ready,
    authed: isLocalMode || !!session,
    syncStatus,
    snapshots,
    synergies: engine.synergies,
    signIn,
    signOut,
    upsert,
    bulkUpsert,
    remove,
    setProfile,
    setSettings,
    toast,
    toasts,
  }), [
    bulkUpsert,
    data,
    engine.synergies,
    ready,
    remove,
    session,
    setProfile,
    setSettings,
    signIn,
    signOut,
    snapshots,
    syncStatus,
    toast,
    toasts,
    upsert,
  ])
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useStore(): StoreValue {
  const v = useContext(Ctx)
  if (!v) throw new Error('useStore outside provider')
  return v
}
