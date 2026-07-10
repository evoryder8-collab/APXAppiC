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
import type { Session } from '@supabase/supabase-js'
import { isLocalMode, supabase } from '../lib/supabase'
import { loadCache, loadQueue, saveCache, saveQueue, type SyncOp } from '../lib/local'
import type { AppData, RpgSnapshot, Settings } from '../lib/types'
import { EMPTY_DATA } from '../lib/types'
import { buildSeedData } from '../data/seed'
import { computeEngine, type SynergyEvent } from '../lib/rpg'
import { todayIso } from '../lib/plan'

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
  | 'daily_logs'
  | 'events'
  | 'deload_marks'
  | 'health_metrics'
  | 'imported_activities'

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

function isSchemaCacheError(error: { code?: string; message: string }): boolean {
  return (
    error.code === 'PGRST205' ||
    error.message.includes('schema cache') ||
    error.message.includes('Could not find the table')
  )
}

export function AppStoreProvider({ children }: { children: ReactNode }) {
  const [data, setData] = useState<AppData>(() => loadCache() ?? EMPTY_DATA)
  const [ready, setReady] = useState(isLocalMode)
  const [session, setSession] = useState<Session | null>(null)
  const [queueLen, setQueueLen] = useState(() => loadQueue().length)
  const [online, setOnline] = useState(navigator.onLine)
  const [toasts, setToasts] = useState<Array<{ id: number; message: string; kind: 'error' | 'ok' }>>([])
  const dataRef = useRef(data)
  dataRef.current = data
  const flushing = useRef(false)
  const lastSchemaToastAt = useRef(0)

  const toast = useCallback((message: string, kind: 'error' | 'ok' = 'error') => {
    const id = Date.now() + Math.random()
    setToasts((t) => [...t, { id, message, kind }])
    window.setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 4200)
  }, [])

  const persist = useCallback((next: AppData) => {
    /* update the ref synchronously so several writes in one tick compose */
    dataRef.current = next
    setData(next)
    saveCache(next)
  }, [])

  /* ---------- queue flush ---------- */
  const flush = useCallback(async () => {
    if (!supabase || flushing.current || !navigator.onLine) return
    flushing.current = true
    try {
      let queue = loadQueue()
      while (queue.length > 0) {
        const op = queue[0]
        const { error } = op.type === 'upsert'
          ? await supabase.from(op.table).upsert(op.payload)
          : await supabase
              .from(op.table)
              .delete()
              .eq('id', (op.payload as Record<string, unknown>).id as string)
        if (error) {
          /* A PostgREST schema refresh can lag just after a migration. Keep the
             write queued instead of dropping user data as a validation error. */
          if (isSchemaCacheError(error)) {
            if (Date.now() - lastSchemaToastAt.current > 15_000) {
              lastSchemaToastAt.current = Date.now()
              toast('Sync is reconnecting. Your changes are queued safely.')
            }
            break
          }
          /* RLS/validation errors would loop forever: drop op and surface it */
          if (error.code && error.code !== 'PGRST301' && !error.message.includes('fetch')) {
            queue = queue.slice(1)
            saveQueue(queue)
            toast(`Sync error on ${op.table}: ${error.message}`)
            continue
          }
          break // network-ish: retry later
        }
        queue = queue.slice(1)
        saveQueue(queue)
      }
      setQueueLen(queue.length)
    } finally {
      flushing.current = false
    }
  }, [toast])

  const enqueue = useCallback(
    (op: { table: string; type: 'upsert' | 'delete'; payload: object }) => {
      if (!supabase) return
      const queue = loadQueue()
      queue.push({
        ...op,
        payload: op.payload as Record<string, unknown>,
        id: crypto.randomUUID(),
        ts: Date.now(),
      } satisfies SyncOp)
      saveQueue(queue)
      setQueueLen(queue.length)
      void flush()
    },
    [flush],
  )

  /* ---------- writes ---------- */
  const upsert = useCallback(
    <T extends { id: string }>(table: ListTable, row: T) => {
      const cur = dataRef.current
      const list = cur[table] as unknown as T[]
      const i = list.findIndex((r) => r.id === row.id)
      const nextList = i >= 0 ? list.map((r) => (r.id === row.id ? row : r)) : [...list, row]
      persist({ ...cur, [table]: nextList })
      enqueue({ table, type: 'upsert', payload: row as unknown as Record<string, unknown> })
    },
    [persist, enqueue],
  )

  /* bulk merge for imports: one state update, chunked sync ops */
  const bulkUpsert = useCallback(
    <T extends { id: string }>(table: ListTable, rows: T[]) => {
      if (rows.length === 0) return
      const cur = dataRef.current
      const list = cur[table] as unknown as T[]
      const map = new Map(list.map((r) => [r.id, r]))
      for (const row of rows) map.set(row.id, row)
      persist({ ...cur, [table]: [...map.values()] })
      for (let i = 0; i < rows.length; i += 400) {
        enqueue({
          table,
          type: 'upsert',
          payload: rows.slice(i, i + 400) as unknown as Array<Record<string, unknown>>,
        })
      }
    },
    [persist, enqueue],
  )

  const remove = useCallback(
    (table: ListTable, id: string) => {
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
      const settings = { ...cur.settings, ...patch }
      persist({ ...cur, settings })
      enqueue({ table: 'settings', type: 'upsert', payload: settings })
    },
    [persist, enqueue],
  )

  /* ---------- auth + initial fetch ---------- */
  useEffect(() => {
    if (!supabase) {
      /* Local mode: seed on first ever run */
      if (!dataRef.current.profile) persist(buildSeedData(LOCAL_USER))
      return
    }
    void supabase.auth.getSession().then(({ data: { session: s } }) => {
      setSession(s)
      setReady(true)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_evt, s) => setSession(s))
    return () => sub.subscription.unsubscribe()
  }, [persist])

  const fetchAll = useCallback(async () => {
    const sb = supabase
    if (!sb || !session) return
    const tables: ListTable[] = [
      'meals', 'meal_logs', 'supplements', 'supplement_logs', 'programs', 'program_days',
      'exercises', 'workout_sessions', 'workout_logs', 'daily_logs', 'events', 'deload_marks',
      'health_metrics', 'imported_activities',
    ]
    try {
      const results = await Promise.all([
        sb.from('profile').select('*').maybeSingle(),
        sb.from('settings').select('*').maybeSingle(),
        ...tables.map((t) => sb.from(t).select('*')),
      ])
      const [profileRes, settingsRes, ...listRes] = results
      const next: AppData = {
        ...EMPTY_DATA,
        profile: (profileRes.data as AppData['profile']) ?? null,
        settings: (settingsRes.data as Settings | null) ?? null,
        rpg_snapshots: dataRef.current.rpg_snapshots,
      }
      tables.forEach((t, i) => {
        ;(next as unknown as Record<string, unknown>)[t] = listRes[i].data ?? []
      })

      /* First sign-in: seed everything */
      if (!next.profile || next.programs.length === 0) {
        const seeded = buildSeedData(session.user.id)
        const merged: AppData = {
          ...next,
          profile: next.profile ?? seeded.profile,
          settings: next.settings ?? seeded.settings,
          meals: next.meals.length ? next.meals : seeded.meals,
          supplements: next.supplements.length ? next.supplements : seeded.supplements,
          programs: next.programs.length ? next.programs : seeded.programs,
          program_days: next.program_days.length ? next.program_days : seeded.program_days,
          exercises: next.exercises.length ? next.exercises : seeded.exercises,
        }
        persist(merged)
        /* Push seeds through the queue so they land server-side too */
        if (!next.profile && merged.profile) enqueue({ table: 'profile', type: 'upsert', payload: merged.profile })
        if (!next.settings && merged.settings) enqueue({ table: 'settings', type: 'upsert', payload: merged.settings })
        if (!next.meals.length) merged.meals.forEach((r) => enqueue({ table: 'meals', type: 'upsert', payload: r }))
        if (!next.supplements.length) merged.supplements.forEach((r) => enqueue({ table: 'supplements', type: 'upsert', payload: r }))
        if (!next.programs.length) {
          merged.programs.forEach((r) => enqueue({ table: 'programs', type: 'upsert', payload: r }))
          merged.program_days.forEach((r) => enqueue({ table: 'program_days', type: 'upsert', payload: r }))
          merged.exercises.forEach((r) => enqueue({ table: 'exercises', type: 'upsert', payload: r }))
        }
      } else {
        persist(next)
      }
    } catch {
      toast('Could not reach Supabase, running from local cache')
    }
  }, [session, persist, enqueue, toast])

  useEffect(() => {
    if (session) void fetchAll()
  }, [session, fetchAll])

  /* ---------- realtime merge from other devices ---------- */
  useEffect(() => {
    const sb = supabase
    if (!sb || !session) return
    const channel = sb
      .channel('apex-sync')
      .on('postgres_changes', { event: '*', schema: 'public' }, (payload) => {
        const table = payload.table as ListTable | 'profile' | 'settings'
        const cur = dataRef.current
        if (table === 'profile') {
          if (payload.new) persistSilent({ ...cur, profile: payload.new as AppData['profile'] })
          return
        }
        if (table === 'settings') {
          if (payload.new) persistSilent({ ...cur, settings: payload.new as Settings })
          return
        }
        const list = cur[table] as Array<{ id: string }>
        if (payload.eventType === 'DELETE') {
          const oldId = (payload.old as { id?: string }).id
          if (oldId) persistSilent({ ...cur, [table]: list.filter((r) => r.id !== oldId) })
        } else {
          const row = payload.new as { id: string }
          const i = list.findIndex((r) => r.id === row.id)
          const nextList = i >= 0 ? list.map((r) => (r.id === row.id ? row : r)) : [...list, row]
          persistSilent({ ...cur, [table]: nextList })
        }
      })
      .subscribe()
    const persistSilent = (next: AppData): void => {
      dataRef.current = next
      setData(next)
      saveCache(next)
    }
    return () => {
      void sb.removeChannel(channel)
    }
  }, [session])

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
        const dateDigits = latest.date.replaceAll('-', '').padStart(12, '0')
        enqueue({
          table: 'rpg_snapshots' as ListTable,
          type: 'upsert',
          payload: { ...latest, id: `22222222-0000-4000-8000-${dateDigits}` },
        })
      }
    }
  }, [snapshots, persist, enqueue, session])

  const signIn = useCallback(async (email: string, password: string): Promise<string | null> => {
    if (!supabase) return 'Local mode, no sign-in needed'
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    return error ? error.message : null
  }, [])

  const signOut = useCallback(async () => {
    if (supabase) await supabase.auth.signOut()
    setSession(null)
  }, [])

  const syncStatus: SyncStatus = isLocalMode ? 'local' : queueLen > 0 || !online ? 'queued' : 'synced'

  const value: StoreValue = {
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
  }
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useStore(): StoreValue {
  const v = useContext(Ctx)
  if (!v) throw new Error('useStore outside provider')
  return v
}
