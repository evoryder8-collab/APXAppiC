import type {
  ActiveRun,
  CampaignSession,
  MarathonCampaign,
  MarathonInduction,
  OrbitRoute,
  OrbitRun,
  PersonalSegment,
  RoutePoster,
  RunningShoe,
} from '../domain/types.ts'

const DB_NAME = 'apex-orbit-v1'
const DB_VERSION = 1

export type OrbitStoreName = 'runs' | 'routes' | 'segments' | 'shoes' | 'posters' | 'inductions' | 'campaigns' | 'sessions' | 'active_runs' | 'outbox'

export type OrbitRecord = OrbitRun | OrbitRoute | PersonalSegment | RunningShoe | RoutePoster | MarathonInduction | MarathonCampaign | CampaignSession

export interface OrbitOutboxOp {
  id: string
  user_id: string
  store: Exclude<OrbitStoreName, 'active_runs' | 'outbox'>
  table: string
  operation: 'upsert' | 'delete'
  entity_id: string
  payload: Record<string, unknown>
  attempts: number
  created_at: string
}

let dbPromise: Promise<IDBDatabase> | null = null

function result<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error ?? new Error('Orbit storage request failed'))
  })
}

function complete(transaction: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve()
    transaction.onerror = () => reject(transaction.error ?? new Error('Orbit storage transaction failed'))
    transaction.onabort = () => reject(transaction.error ?? new Error('Orbit storage transaction was cancelled'))
  })
}

export function openOrbitDb(): Promise<IDBDatabase> {
  if (!('indexedDB' in globalThis)) return Promise.reject(new Error('IndexedDB is unavailable'))
  if (dbPromise) return dbPromise
  dbPromise = new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION)
    request.onupgradeneeded = () => {
      const database = request.result
      const stores: OrbitStoreName[] = ['runs', 'routes', 'segments', 'shoes', 'posters', 'inductions', 'campaigns', 'sessions', 'active_runs', 'outbox']
      for (const name of stores) {
        const store = database.objectStoreNames.contains(name)
          ? request.transaction!.objectStore(name)
          : database.createObjectStore(name, { keyPath: 'id' })
        if (!store.indexNames.contains('user_id')) store.createIndex('user_id', 'user_id', { unique: false })
        if (name === 'sessions' && !store.indexNames.contains('campaign_id')) store.createIndex('campaign_id', 'campaign_id', { unique: false })
        if (name === 'runs' && !store.indexNames.contains('local_date')) store.createIndex('local_date', ['user_id', 'local_date'], { unique: false })
      }
    }
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error ?? new Error('Could not open Orbit private storage'))
  })
  return dbPromise
}

export async function orbitPut<T>(storeName: OrbitStoreName, value: T): Promise<void> {
  const database = await openOrbitDb()
  const transaction = database.transaction(storeName, 'readwrite')
  transaction.objectStore(storeName).put(value)
  await complete(transaction)
}

export async function orbitPutMany<T>(storeName: OrbitStoreName, values: T[]): Promise<void> {
  if (values.length === 0) return
  const database = await openOrbitDb()
  const transaction = database.transaction(storeName, 'readwrite')
  const store = transaction.objectStore(storeName)
  for (const value of values) store.put(value)
  await complete(transaction)
}

export async function orbitGet<T>(storeName: OrbitStoreName, id: string): Promise<T | null> {
  const database = await openOrbitDb()
  const transaction = database.transaction(storeName, 'readonly')
  return (await result(transaction.objectStore(storeName).get(id)) as T | undefined) ?? null
}

export async function orbitForUser<T extends { user_id: string }>(storeName: OrbitStoreName, userId: string): Promise<T[]> {
  const database = await openOrbitDb()
  const transaction = database.transaction(storeName, 'readonly')
  return result(transaction.objectStore(storeName).index('user_id').getAll(userId)) as Promise<T[]>
}

export async function orbitDelete(storeName: OrbitStoreName, id: string): Promise<void> {
  const database = await openOrbitDb()
  const transaction = database.transaction(storeName, 'readwrite')
  transaction.objectStore(storeName).delete(id)
  await complete(transaction)
}

export async function orbitDeleteForUser(storeName: OrbitStoreName, userId: string): Promise<void> {
  const database = await openOrbitDb()
  const transaction = database.transaction(storeName, 'readwrite')
  const store = transaction.objectStore(storeName)
  const cursor = store.index('user_id').openKeyCursor(IDBKeyRange.only(userId))
  cursor.onsuccess = () => {
    const row = cursor.result
    if (!row) return
    store.delete(row.primaryKey)
    row.continue()
  }
  await complete(transaction)
}

export async function saveActiveRun(active: ActiveRun | null, userId: string): Promise<void> {
  if (active) await orbitPut('active_runs', { ...active, id: userId, user_id: userId })
  else await orbitDelete('active_runs', userId)
}

export async function loadActiveRun(userId: string): Promise<ActiveRun | null> {
  return orbitGet<ActiveRun>('active_runs', userId)
}

export async function queueOrbitOp(op: OrbitOutboxOp): Promise<void> {
  await orbitPut('outbox', op)
}

export async function orbitOutbox(userId: string): Promise<OrbitOutboxOp[]> {
  return (await orbitForUser<OrbitOutboxOp>('outbox', userId)).sort((a, b) => a.created_at.localeCompare(b.created_at))
}

export async function saveRunAtomically(run: OrbitRun, outbox: OrbitOutboxOp): Promise<void> {
  const database = await openOrbitDb()
  const transaction = database.transaction(['runs', 'active_runs', 'outbox'], 'readwrite')
  transaction.objectStore('runs').put(run)
  transaction.objectStore('active_runs').delete(run.user_id)
  transaction.objectStore('outbox').put(outbox)
  await complete(transaction)
}
