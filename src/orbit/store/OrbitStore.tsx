import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { supabase } from '../../lib/supabase.ts'
import { useStore } from '../../store/AppStore.tsx'
import { EMPTY_ORBIT_STATE, type ActiveRun, type CampaignSession, type MarathonCampaign, type MarathonInduction, type OrbitRoute, type OrbitRun, type OrbitState, type PersonalSegment, type RoutePoster, type RunningShoe } from '../domain/types.ts'
import {
  loadActiveRun,
  orbitDelete,
  orbitDeleteForUser,
  orbitForUser,
  orbitOutbox,
  orbitPut,
  orbitPutMany,
  queueOrbitOp,
  saveActiveRun,
  saveRunAtomically,
  type OrbitOutboxOp,
  type OrbitStoreName,
} from '../data/orbitDb.ts'

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
  const [state, setState] = useState<OrbitState>(EMPTY_ORBIT_STATE)
  const stateRef = useRef(state)
  stateRef.current = state
  const [ready, setReady] = useState(false)
  const [queueLength, setQueueLength] = useState(0)
  const syncing = useRef(false)

  const refreshQueueLength = useCallback(async () => {
    if (!userId) return setQueueLength(0)
    setQueueLength((await orbitOutbox(userId)).length)
  }, [userId])

  const syncNow = useCallback(async () => {
    if (!supabase || !userId || !navigator.onLine || syncing.current) return
    syncing.current = true
    try {
      const queue = await orbitOutbox(userId)
      for (const op of queue) {
        const request = op.operation === 'upsert'
          ? supabase.from(op.table).upsert(op.payload)
          : supabase.from(op.table).delete().eq('id', op.entity_id).eq('user_id', userId)
        const { error } = await request
        if (error) {
          const retryable = error.message.includes('fetch') || error.message.includes('schema cache') || error.code === 'PGRST205'
          if (!retryable) {
            await orbitDelete('outbox', op.id)
            toast(`Orbit sync error: ${error.message}`)
          }
          break
        }
        await orbitDelete('outbox', op.id)
      }
      await refreshQueueLength()
    } finally {
      syncing.current = false
    }
  }, [refreshQueueLength, toast, userId])

  useEffect(() => {
    if (!userId) {
      setState(EMPTY_ORBIT_STATE)
      setReady(true)
      return
    }
    let cancelled = false
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
          const pendingOps = await orbitOutbox(userId)
          const remoteResults = await Promise.allSettled(Object.entries(TABLES).map(async ([store, table]) => {
            // RLS is the authoritative boundary. The explicit owner filter is a
            // second, visible guard and prevents a misconfigured policy from
            // ever being merged into another profile's offline cache.
            const { data: rows, error } = await supabase!.from(table).select('*').eq('user_id', userId)
            if (error) throw error
            return [store as EntityStore, (rows ?? []).filter((row) => row.user_id === userId)] as const
          }))
          if (cancelled) return
          let merged = { ...stateRef.current }
          for (const result of remoteResults) {
            if (result.status !== 'fulfilled') continue
            const [store, rows] = result.value
            const key = stateKey(store)
            const localRows = merged[key] as OrbitEntity[]
            const storeOps = pendingOps.filter((operation) => operation.store === store)
            const deletedIds = new Set(storeOps.filter((operation) => operation.operation === 'delete').map((operation) => operation.entity_id))
            const pendingUpsertIds = new Set(storeOps.filter((operation) => operation.operation === 'upsert').map((operation) => operation.entity_id))
            const byId = new Map<string, OrbitEntity>()
            for (const remote of rows as OrbitEntity[]) {
              if (!deletedIds.has(remote.id)) byId.set(remote.id, { ...remote, sync_state: 'synced' } as OrbitEntity)
            }
            for (const local of localRows) {
              if (pendingUpsertIds.has(local.id) || local.sync_state !== 'synced') byId.set(local.id, local)
            }
            const values = [...byId.values()]
            merged = { ...merged, [key]: values }
            await orbitPutMany(store, values)
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
  }, [refreshQueueLength, syncNow, toast, userId])

  useEffect(() => {
    const online = () => void syncNow()
    window.addEventListener('online', online)
    return () => window.removeEventListener('online', online)
  }, [syncNow])

  const saveEntity = useCallback(async (store: EntityStore, entity: OrbitEntity) => {
    if (!userId || entity.user_id !== userId) throw new Error('Orbit refused a cross-account write.')
    const stamped = { ...entity, sync_state: supabase ? 'queued' : 'local' } as OrbitEntity
    const key = stateKey(store)
    const current = stateRef.current[key] as OrbitEntity[]
    const nextRows = current.some((row) => row.id === stamped.id)
      ? current.map((row) => row.id === stamped.id ? stamped : row)
      : [...current, stamped]
    const nextState = { ...stateRef.current, [key]: nextRows }
    stateRef.current = nextState
    setState(nextState)
    await orbitPut(store, stamped)
    if (supabase) {
      const outbox: OrbitOutboxOp = {
        id: crypto.randomUUID(), user_id: userId, store, table: TABLES[store], operation: 'upsert', entity_id: stamped.id,
        payload: withoutSyncState(stamped), attempts: 0, created_at: new Date().toISOString(),
      }
      await queueOrbitOp(outbox)
      await refreshQueueLength()
      void syncNow()
    }
  }, [refreshQueueLength, syncNow, userId])

  const saveRun = useCallback(async (run: OrbitRun) => {
    if (!userId || run.user_id !== userId) throw new Error('Orbit refused a cross-account run.')
    const stamped = { ...run, sync_state: supabase ? 'queued' as const : 'local' as const }
    const rows = stateRef.current.runs.some((item) => item.id === run.id)
      ? stateRef.current.runs.map((item) => item.id === run.id ? stamped : item)
      : [...stateRef.current.runs, stamped]
    const nextState = { ...stateRef.current, runs: rows, active_run: null }
    stateRef.current = nextState
    setState(nextState)
    const outbox: OrbitOutboxOp = {
      id: crypto.randomUUID(), user_id: userId, store: 'runs', table: TABLES.runs, operation: 'upsert', entity_id: stamped.id,
      payload: withoutSyncState(stamped), attempts: 0, created_at: new Date().toISOString(),
    }
    if (supabase) await saveRunAtomically(stamped, outbox)
    else {
      await orbitPut('runs', stamped)
      await saveActiveRun(null, userId)
    }
    await refreshQueueLength()
    void syncNow()
  }, [refreshQueueLength, syncNow, userId])

  const setActiveRun = useCallback(async (run: ActiveRun | null) => {
    if (!userId) return
    if (run && run.user_id !== userId) throw new Error('Orbit refused a cross-account active run.')
    const next = { ...stateRef.current, active_run: run }
    stateRef.current = next
    setState(next)
    await saveActiveRun(run, userId)
  }, [userId])

  const removeEntity = useCallback(async (store: EntityStore, id: string) => {
    if (!userId) return
    const key = stateKey(store)
    const rows = (stateRef.current[key] as OrbitEntity[]).filter((row) => row.id !== id)
    const next = { ...stateRef.current, [key]: rows }
    stateRef.current = next
    setState(next)
    await orbitDelete(store, id)
    if (supabase) {
      await queueOrbitOp({
        id: crypto.randomUUID(), user_id: userId, store, table: TABLES[store], operation: 'delete', entity_id: id,
        payload: { id, user_id: userId }, attempts: 0, created_at: new Date().toISOString(),
      })
      await refreshQueueLength()
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
    const stores = Object.keys(TABLES) as EntityStore[]
    if (supabase) {
      for (const table of Object.values(TABLES)) {
        const { error } = await supabase.from(table).delete().eq('user_id', userId)
        if (error) throw new Error(`Orbit could not permanently delete ${table}: ${error.message}`)
      }
    }
    await Promise.all([...stores, 'active_runs', 'outbox'].map((store) => orbitDeleteForUser(store as OrbitStoreName, userId)))
    stateRef.current = EMPTY_ORBIT_STATE
    setState(EMPTY_ORBIT_STATE)
    setQueueLength(0)
  }, [userId])

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
