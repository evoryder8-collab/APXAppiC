import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { createSessionBoundSupabase, supabase } from '../../lib/supabase.ts'
import { useStore } from '../../store/AppStore.tsx'
import { EMPTY_ORBIT_STATE, type ActiveRun, type CampaignSession, type MarathonCampaign, type MarathonInduction, type OrbitRoute, type OrbitRun, type OrbitState, type PersonalSegment, type RoutePoster, type RunningShoe } from '../domain/types.ts'
import {
  acknowledgeOrbitOutbox,
  deleteEntityAtomically,
  loadActiveRun,
  orbitDelete,
  orbitDeleteForUser,
  orbitForUser,
  orbitOutbox,
  orbitPut,
  orbitReplaceForUser,
  recordOrbitOutboxFailure,
  saveActiveRun,
  saveEntityAtomically,
  saveRunAtomically,
  type OrbitOutboxOp,
  type OrbitStoreName,
} from '../data/orbitDb.ts'
import { fetchAllOrbitPages, hasPendingOrbitEntity, mergeOrbitEntityRows, mergeOrbitPendingOperations } from '../domain/sync.ts'

type EntityStore = Exclude<OrbitStoreName, 'active_runs' | 'outbox'>
type OrbitEntity = OrbitRun | OrbitRoute | PersonalSegment | RunningShoe | RoutePoster | MarathonInduction | MarathonCampaign | CampaignSession

const TABLES: Record<EntityStore, string> = {
  runs: 'orbit_runs', routes: 'orbit_routes', segments: 'orbit_segments', shoes: 'orbit_shoes', posters: 'orbit_posters',
  inductions: 'orbit_inductions', campaigns: 'orbit_campaigns', sessions: 'orbit_campaign_sessions',
}

interface OrbitStoreValue {
  state: OrbitState
  ready: boolean
  syncState: 'local' | 'queued' | 'synced'
  saveRoute: (route: OrbitRoute) => Promise<void>
  saveRun: (run: OrbitRun) => Promise<void>
  saveSegment: (segment: PersonalSegment) => Promise<void>
  saveShoe: (shoe: RunningShoe) => Promise<void>
  savePoster: (poster: RoutePoster) => Promise<void>
  saveInduction: (induction: MarathonInduction) => Promise<void>
  saveCampaign: (campaign: MarathonCampaign, sessions: CampaignSession[]) => Promise<void>
  cancelCampaign: (campaignId: string) => Promise<void>
  saveSession: (session: CampaignSession) => Promise<void>
  setActiveRun: (run: ActiveRun | null) => Promise<void>
  removeEntity: (store: EntityStore, id: string) => Promise<void>
  syncNow: () => Promise<void>
  exportPrivateData: () => void
  deleteAllPrivateData: () => Promise<void>
}

const OrbitContext = createContext<OrbitStoreValue | null>(null)

function withoutSyncState(entity: OrbitEntity): Record<string, unknown> {
  const { sync_state: _syncState, ...row } = entity
  return row as unknown as Record<string, unknown>
}

function stateKey(store: EntityStore): keyof Omit<OrbitState, 'active_run'> {
  return store
}

export function OrbitStoreProvider({ children }: { children: ReactNode }) {
  const { data, toast } = useStore()
  const userId = data.profile?.user_id ?? null
  const userIdRef = useRef(userId)
  userIdRef.current = userId
  const [state, setState] = useState<OrbitState>(EMPTY_ORBIT_STATE)
  const stateRef = useRef(state)
  stateRef.current = state
  const [ready, setReady] = useState(false)
  const [queueLength, setQueueLength] = useState(0)
  const [hydrationRetry, setHydrationRetry] = useState(0)
  const syncingUsers = useRef(new Set<string>())
  const requestedSyncUsers = useRef(new Set<string>())
  const latestSyncNow = useRef<() => Promise<void>>(async () => undefined)
  const mutationRevision = useRef(0)
  const lastSyncToastAt = useRef(0)

  const sessionClientForUser = useCallback(async (expectedUserId: string) => {
    if (!supabase) return null
    const { data: { session }, error } = await supabase.auth.getSession()
    if (error || !session || session.user.id !== expectedUserId) return null
    return createSessionBoundSupabase(session.access_token)
  }, [])

  const refreshQueueLength = useCallback(async (expectedUserId = userId) => {
    if (!expectedUserId) {
      if (!userIdRef.current) setQueueLength(0)
      return
    }
    const length = (await orbitOutbox(expectedUserId)).length
    if (userIdRef.current === expectedUserId) setQueueLength(length)
  }, [userId])

  const markEntitySyncState = useCallback(async (
    expectedUserId: string,
    store: EntityStore,
    entityId: string,
    syncState: 'synced' | 'failed',
  ) => {
    if (userIdRef.current !== expectedUserId) return
    const key = stateKey(store)
    const current = stateRef.current[key] as OrbitEntity[]
    const entity = current.find((row) => row.id === entityId)
    if (!entity || entity.user_id !== expectedUserId || entity.sync_state === syncState) return
    const stamped = { ...entity, sync_state: syncState } as OrbitEntity
    const nextState = {
      ...stateRef.current,
      [key]: current.map((row) => row.id === entityId ? stamped : row),
    }
    stateRef.current = nextState
    setState(nextState)
    await orbitPut(store, stamped)
  }, [])

  const removeAcknowledgedDeleteFromState = useCallback((
    expectedUserId: string,
    store: EntityStore,
    entityId: string,
  ): void => {
    if (userIdRef.current !== expectedUserId) return
    const key = stateKey(store)
    const current = stateRef.current[key] as OrbitEntity[]
    const rows = current.filter((row) => row.id !== entityId)
    if (rows.length === current.length) return
    const nextState = { ...stateRef.current, [key]: rows }
    stateRef.current = nextState
    setState(nextState)
  }, [])

  const syncNow = useCallback(async () => {
    if (!supabase || !userId || !navigator.onLine) return
    if (syncingUsers.current.has(userId)) {
      requestedSyncUsers.current.add(userId)
      return
    }
    const syncUserId = userId
    syncingUsers.current.add(syncUserId)
    try {
      const syncClient = await sessionClientForUser(syncUserId)
      if (!syncClient) return
      const queue = await orbitOutbox(syncUserId)
      for (const op of queue) {
        let error: { message: string } | null = null
        try {
          const request = op.operation === 'upsert'
            ? syncClient.from(op.table).upsert(op.payload)
            : syncClient.from(op.table).delete().eq('id', op.entity_id).eq('user_id', syncUserId)
          const result = await request
          error = result.error
        } catch (requestError) {
          error = { message: requestError instanceof Error ? requestError.message : 'The network request failed' }
        }
        if (error) {
          const retained = await recordOrbitOutboxFailure(op, error.message)
          if (retained) await markEntitySyncState(syncUserId, op.store, op.entity_id, 'failed')
          if (Date.now() - lastSyncToastAt.current > 15_000) {
            lastSyncToastAt.current = Date.now()
            toast(`Orbit sync paused. Your change remains safely queued: ${error.message}`)
          }
          continue
        }
        await acknowledgeOrbitOutbox(op)
        const pending = await orbitOutbox(syncUserId)
        if (!hasPendingOrbitEntity(pending, op.store, op.entity_id)) {
          if (op.operation === 'delete') {
            removeAcknowledgedDeleteFromState(syncUserId, op.store, op.entity_id)
          } else {
            await markEntitySyncState(syncUserId, op.store, op.entity_id, 'synced')
          }
        }
      }
    } catch (syncError) {
      if (Date.now() - lastSyncToastAt.current > 15_000) {
        lastSyncToastAt.current = Date.now()
        toast(`Orbit sync will retry automatically: ${syncError instanceof Error ? syncError.message : 'private storage is unavailable'}`)
      }
    } finally {
      syncingUsers.current.delete(syncUserId)
      try {
        await refreshQueueLength(syncUserId)
      } catch {
        /* The next focus/online event retries private storage as well. */
      }
      if (requestedSyncUsers.current.delete(syncUserId) && navigator.onLine) {
        queueMicrotask(() => { void latestSyncNow.current() })
      }
    }
  }, [markEntitySyncState, refreshQueueLength, removeAcknowledgedDeleteFromState, sessionClientForUser, toast, userId])
  latestSyncNow.current = syncNow

  useEffect(() => {
    if (!userId) {
      setState(EMPTY_ORBIT_STATE)
      setReady(true)
      return
    }
    let cancelled = false
    const revision = mutationRevision.current
    void (async () => {
      try {
        const [runs, routes, segments, shoes, posters, inductions, campaigns, sessions, activeRun] = await Promise.all([
          orbitForUser<OrbitRun>('runs', userId), orbitForUser<OrbitRoute>('routes', userId),
          orbitForUser<PersonalSegment>('segments', userId), orbitForUser<RunningShoe>('shoes', userId),
          orbitForUser<RoutePoster>('posters', userId), orbitForUser<MarathonInduction>('inductions', userId),
          orbitForUser<MarathonCampaign>('campaigns', userId), orbitForUser<CampaignSession>('sessions', userId), loadActiveRun(userId),
        ])
        if (cancelled) return
        const local: OrbitState = { runs, routes, segments, shoes, posters, inductions, campaigns, sessions, active_run: activeRun }
        setState(local)
        stateRef.current = local
        setReady(true)
        await refreshQueueLength()
        if (supabase && navigator.onLine) {
          const remoteClient = await sessionClientForUser(userId)
          if (!remoteClient || cancelled || userIdRef.current !== userId) return
          const pendingBefore = await orbitOutbox(userId)
          const remoteResults = await Promise.allSettled(Object.entries(TABLES).map(async ([store, table]) => {
            // RLS is the authoritative boundary. The explicit owner filter is a
            // second, visible guard and prevents a misconfigured policy from
            // ever being merged into another profile's offline cache.
            const rows = await fetchAllOrbitPages(async (from, to) => {
              const { data: page, error } = await remoteClient
                .from(table)
                .select('*')
                .eq('user_id', userId)
                .order('id', { ascending: true })
                .range(from, to)
              if (error) throw error
              return (page ?? []).filter((row) => row.user_id === userId)
            })
            return [store as EntityStore, rows] as const
          }))
          const pendingAfter = await orbitOutbox(userId)
          if (cancelled || userIdRef.current !== userId) return
          if (mutationRevision.current !== revision) {
            setHydrationRetry((value) => value + 1)
            return
          }
          const pendingOps = mergeOrbitPendingOperations(pendingBefore, pendingAfter)
          let merged = { ...stateRef.current }
          const replacements: Array<{ store: EntityStore; values: OrbitEntity[] }> = []
          for (const result of remoteResults) {
            if (result.status !== 'fulfilled') continue
            const [store, rows] = result.value
            const key = stateKey(store)
            const localRows = merged[key] as OrbitEntity[]
            const values = mergeOrbitEntityRows(rows as OrbitEntity[], localRows, pendingOps, store)
            merged = { ...merged, [key]: values }
            replacements.push({ store, values })
          }
          for (const replacement of replacements) {
            if (cancelled || userIdRef.current !== userId) return
            if (mutationRevision.current !== revision) {
              setHydrationRetry((value) => value + 1)
              return
            }
            /* Replace the owner-scoped snapshot, rather than only putting the
               merged rows. Otherwise a server-side deletion disappears from
               React state but remains in IndexedDB and resurrects offline on
               the next launch. Pending local rows are already in values. */
            await orbitReplaceForUser(replacement.store, userId, replacement.values)
          }
          if (cancelled || userIdRef.current !== userId) return
          if (mutationRevision.current !== revision) {
            setHydrationRetry((value) => value + 1)
            return
          }
          setState(merged)
          stateRef.current = merged
          await syncNow()
        }
      } catch {
        if (!cancelled) {
          setReady(true)
          toast('Orbit is running from private offline storage.')
        }
      }
    })()
    return () => { cancelled = true }
  }, [hydrationRetry, refreshQueueLength, sessionClientForUser, syncNow, toast, userId])

  useEffect(() => {
    const retry = (): void => { if (navigator.onLine) void syncNow() }
    const visible = (): void => { if (document.visibilityState === 'visible') retry() }
    window.addEventListener('online', retry)
    window.addEventListener('pageshow', retry)
    document.addEventListener('visibilitychange', visible)
    return () => {
      window.removeEventListener('online', retry)
      window.removeEventListener('pageshow', retry)
      document.removeEventListener('visibilitychange', visible)
    }
  }, [syncNow])

  /* A write queued while another request is in flight must get its own drain
     pass. Without this dependency it could remain stranded until the browser
     happened to emit a later online event. */
  useEffect(() => {
    if (userId && queueLength > 0 && navigator.onLine) void syncNow()
  }, [queueLength, syncNow, userId])

  const saveEntity = useCallback(async (store: EntityStore, entity: OrbitEntity) => {
    if (!userId || entity.user_id !== userId) throw new Error('Orbit refused a cross-account write.')
    mutationRevision.current += 1
    const stamped = { ...entity, sync_state: supabase ? 'queued' : 'local' } as OrbitEntity
    if (supabase) {
      const outbox: OrbitOutboxOp = {
        id: crypto.randomUUID(), user_id: userId, store, table: TABLES[store], operation: 'upsert', entity_id: stamped.id,
        payload: withoutSyncState(stamped), attempts: 0, created_at: new Date().toISOString(),
      }
      await saveEntityAtomically(store, stamped, outbox)
    } else {
      await orbitPut(store, stamped)
    }
    const key = stateKey(store)
    const current = stateRef.current[key] as OrbitEntity[]
    const nextRows = current.some((row) => row.id === stamped.id)
      ? current.map((row) => row.id === stamped.id ? stamped : row)
      : [...current, stamped]
    const nextState = { ...stateRef.current, [key]: nextRows }
    stateRef.current = nextState
    setState(nextState)
    if (supabase) {
      await refreshQueueLength(userId)
      void syncNow()
    }
  }, [refreshQueueLength, syncNow, userId])

  const saveRun = useCallback(async (run: OrbitRun) => {
    if (!userId || run.user_id !== userId) throw new Error('Orbit refused a cross-account run.')
    mutationRevision.current += 1
    const stamped = { ...run, sync_state: supabase ? 'queued' as const : 'local' as const }
    const outbox: OrbitOutboxOp = {
      id: crypto.randomUUID(), user_id: userId, store: 'runs', table: TABLES.runs, operation: 'upsert', entity_id: stamped.id,
      payload: withoutSyncState(stamped), attempts: 0, created_at: new Date().toISOString(),
    }
    if (supabase) await saveRunAtomically(stamped, outbox)
    else {
      await orbitPut('runs', stamped)
      await saveActiveRun(null, userId)
    }
    const rows = stateRef.current.runs.some((item) => item.id === run.id)
      ? stateRef.current.runs.map((item) => item.id === run.id ? stamped : item)
      : [...stateRef.current.runs, stamped]
    const nextState = { ...stateRef.current, runs: rows, active_run: null }
    stateRef.current = nextState
    setState(nextState)
    await refreshQueueLength(userId)
    void syncNow()
  }, [refreshQueueLength, syncNow, userId])

  const setActiveRun = useCallback(async (run: ActiveRun | null) => {
    if (!userId) return
    if (run && run.user_id !== userId) throw new Error('Orbit refused a cross-account active run.')
    await saveActiveRun(run, userId)
    const next = { ...stateRef.current, active_run: run }
    stateRef.current = next
    setState(next)
  }, [userId])

  const removeEntity = useCallback(async (store: EntityStore, id: string) => {
    if (!userId) return
    const key = stateKey(store)
    const existing = (stateRef.current[key] as OrbitEntity[]).find((row) => row.id === id)
    if (!existing || existing.user_id !== userId) throw new Error('Orbit refused a cross-account delete.')
    mutationRevision.current += 1
    if (supabase) {
      await deleteEntityAtomically(store, id, {
        id: crypto.randomUUID(), user_id: userId, store, table: TABLES[store], operation: 'delete', entity_id: id,
        payload: { id, user_id: userId }, attempts: 0, created_at: new Date().toISOString(),
      })
    } else {
      await orbitDelete(store, id)
    }
    const rows = (stateRef.current[key] as OrbitEntity[]).filter((row) => row.id !== id)
    const next = { ...stateRef.current, [key]: rows }
    stateRef.current = next
    setState(next)
    if (supabase) {
      await refreshQueueLength(userId)
      void syncNow()
    }
  }, [refreshQueueLength, syncNow, userId])

  const saveCampaign = useCallback(async (campaign: MarathonCampaign, sessions: CampaignSession[]) => {
    await saveEntity('campaigns', campaign)
    for (const session of sessions) await saveEntity('sessions', session)
  }, [saveEntity])

  const cancelCampaign = useCallback(async (campaignId: string) => {
    const campaignSessions = stateRef.current.sessions.filter((session) => session.campaign_id === campaignId)
    const sessionIds = new Set(campaignSessions.map((session) => session.id))
    if (stateRef.current.active_run?.campaign_session_id && sessionIds.has(stateRef.current.active_run.campaign_session_id)) {
      await setActiveRun(null)
    }
    for (const session of campaignSessions) await removeEntity('sessions', session.id)
    await removeEntity('campaigns', campaignId)
  }, [removeEntity, setActiveRun])

  const exportPrivateData = useCallback(() => {
    if (!userId) return
    const blob = new Blob([JSON.stringify({ exported_at: new Date().toISOString(), user_id: userId, ...stateRef.current }, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = `apex-orbit-${new Date().toISOString().slice(0, 10)}.json`
    anchor.click()
    URL.revokeObjectURL(url)
  }, [userId])

  const deleteAllPrivateData = useCallback(async () => {
    if (!userId) return
    mutationRevision.current += 1
    const stores = Object.keys(TABLES) as EntityStore[]
    if (supabase) {
      const deleteClient = await sessionClientForUser(userId)
      if (!deleteClient) throw new Error('Orbit could not verify the active account. Sign in again and retry.')
      for (const table of Object.values(TABLES)) {
        const { error } = await deleteClient.from(table).delete().eq('user_id', userId)
        if (error) throw new Error(`Orbit could not permanently delete ${table}: ${error.message}`)
      }
    }
    await Promise.all([...stores, 'active_runs', 'outbox'].map((store) => orbitDeleteForUser(store as OrbitStoreName, userId)))
    if (userIdRef.current === userId) {
      stateRef.current = EMPTY_ORBIT_STATE
      setState(EMPTY_ORBIT_STATE)
      setQueueLength(0)
    }
  }, [sessionClientForUser, userId])

  const value = useMemo<OrbitStoreValue>(() => ({
    state, ready, syncState: supabase ? queueLength > 0 ? 'queued' : 'synced' : 'local',
    saveRoute: (route) => saveEntity('routes', route), saveRun,
    saveSegment: (segment) => saveEntity('segments', segment), saveShoe: (shoe) => saveEntity('shoes', shoe),
    savePoster: (poster) => saveEntity('posters', poster), saveInduction: (induction) => saveEntity('inductions', induction),
    saveCampaign, cancelCampaign, saveSession: (session) => saveEntity('sessions', session), setActiveRun, removeEntity, syncNow,
    exportPrivateData, deleteAllPrivateData,
  }), [cancelCampaign, deleteAllPrivateData, exportPrivateData, queueLength, ready, removeEntity, saveCampaign, saveEntity, saveRun, setActiveRun, state, syncNow])

  return <OrbitContext.Provider value={value}>{children}</OrbitContext.Provider>
}

export function useOrbitStore(): OrbitStoreValue {
  const value = useContext(OrbitContext)
  if (!value) throw new Error('useOrbitStore must be used inside OrbitStoreProvider')
  return value
}
