/* localStorage persistence: full data cache + pending op queue for offline writes. */
import type { AppData } from './types.ts'
import { EMPTY_DATA } from './types.ts'

const LEGACY_CACHE_KEY = 'apex.cache.v1'
const LEGACY_QUEUE_KEY = 'apex.queue.v1'
const CACHE_KEY = 'apex.cache.v2'
const QUEUE_KEY = 'apex.queue.v2'
const ATOMIC_MUTATION_KEY = 'apex.atomic-mutation.v1'

/* localStorage can be unavailable even while the page is usable (private
   browsing, a full quota, or an embedded browser policy). Keep the latest
   queue in memory in that case so the current session can still flush it
   instead of throwing from an interaction and silently abandoning the
   server write. A reload may still require storage to be available. */
const volatileQueues = new Map<string, SyncOp[]>()

function scopedKey(base: string, scope: string): string {
  return `${base}.${scope}`
}

export interface LocalPersistenceStorage {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
  removeItem(key: string): void
}

interface InterruptedAtomicMutation {
  version: 1
  scope: string
  previousCache: string | null
  previousQueue: string | null
}

function restoreRawValue(storage: LocalPersistenceStorage, key: string, value: string | null): void {
  if (value === null) storage.removeItem(key)
  else storage.setItem(key, value)
}

/**
 * A transaction journal represents an operation that never reached its commit
 * point. Restore both old keys before either cache or queue is observed.
 */
function recoverInterruptedAtomicMutation(
  scope: string,
  storage: LocalPersistenceStorage = localStorage,
): InterruptedAtomicMutation | null {
  const journalKey = scopedKey(ATOMIC_MUTATION_KEY, scope)
  let raw: string | null
  try {
    raw = storage.getItem(journalKey)
  } catch {
    return null
  }
  if (!raw) return null
  let interrupted: InterruptedAtomicMutation | null = null
  try {
    const journal = JSON.parse(raw) as Partial<InterruptedAtomicMutation>
    if (
      journal.version !== 1
      || journal.scope !== scope
      || (journal.previousCache !== null && typeof journal.previousCache !== 'string')
      || (journal.previousQueue !== null && typeof journal.previousQueue !== 'string')
    ) {
      storage.removeItem(journalKey)
      return null
    }
    interrupted = journal as InterruptedAtomicMutation
    restoreRawValue(storage, scopedKey(CACHE_KEY, scope), journal.previousCache ?? null)
    restoreRawValue(storage, scopedKey(QUEUE_KEY, scope), journal.previousQueue ?? null)
    storage.removeItem(journalKey)
    return null
  } catch {
    /* Keep the journal so the next read can finish the rollback. */
    return interrupted
  }
}

export interface SyncOp {
  id: string
  table: string
  type: 'upsert' | 'delete' | 'rpc'
  rpc_function?: string
  /* single row, or a batch of rows for bulk imports */
  payload: Record<string, unknown> | Array<Record<string, unknown>>
  ts: number
  sync_group?: string
  dedupe_key?: string
}

export function loadCache(scope = 'local'): AppData | null {
  const interrupted = recoverInterruptedAtomicMutation(scope)
  try {
    const raw = interrupted ? interrupted.previousCache : (
      localStorage.getItem(scopedKey(CACHE_KEY, scope)) ??
      (scope === 'local' ? localStorage.getItem(LEGACY_CACHE_KEY) : null))
    if (!raw) return null
    return { ...EMPTY_DATA, ...(JSON.parse(raw) as Partial<AppData>) }
  } catch {
    return null
  }
}

export function saveCache(data: AppData, scope = 'local'): boolean {
  if (recoverInterruptedAtomicMutation(scope)) return false
  try {
    localStorage.setItem(scopedKey(CACHE_KEY, scope), JSON.stringify(data))
    return true
  } catch {
    /* Let the caller with user-visible success semantics report the failure. */
    return false
  }
}

export function loadQueue(scope = 'local'): SyncOp[] {
  const interrupted = recoverInterruptedAtomicMutation(scope)
  const volatile = volatileQueues.get(scope)
  if (volatile) return [...volatile]
  try {
    const raw = interrupted ? interrupted.previousQueue : (
      localStorage.getItem(scopedKey(QUEUE_KEY, scope)) ??
      (scope === 'local' ? localStorage.getItem(LEGACY_QUEUE_KEY) : null))
    return JSON.parse(raw ?? '[]') as SyncOp[]
  } catch {
    return []
  }
}

export function saveQueue(queue: SyncOp[], scope = 'local'): boolean {
  if (recoverInterruptedAtomicMutation(scope)) {
    volatileQueues.set(scope, [...queue])
    return false
  }
  const serialized = JSON.stringify(queue)
  try {
    localStorage.setItem(scopedKey(QUEUE_KEY, scope), serialized)
    volatileQueues.delete(scope)
    return true
  } catch {
    /* The outbox is the only copy that can reconstruct an offline edit after
       reload. If the full cache consumed the localStorage quota, sacrifice
       that reproducible cache and retry the much smaller write-intent queue. */
    try {
      localStorage.removeItem(scopedKey(CACHE_KEY, scope))
      localStorage.setItem(scopedKey(QUEUE_KEY, scope), serialized)
      volatileQueues.delete(scope)
      return true
    } catch {
      volatileQueues.set(scope, [...queue])
      return false
    }
  }
}

/**
 * Commit the complete owner cache and ordered outbox as one crash-consistent
 * unit. The journal contains the previous pair: until it is removed, startup
 * rolls both keys back. Publication therefore happens only after the commit
 * point, and a failed cache or queue write cannot leave half a mutation.
 */
export function saveCacheAndQueueAtomically(
  data: AppData,
  queue: SyncOp[],
  scope = 'local',
  storage: LocalPersistenceStorage = localStorage,
): boolean {
  if (recoverInterruptedAtomicMutation(scope, storage)) return false
  const cacheKey = scopedKey(CACHE_KEY, scope)
  const queueKey = scopedKey(QUEUE_KEY, scope)
  const journalKey = scopedKey(ATOMIC_MUTATION_KEY, scope)
  const previousVolatileQueue = volatileQueues.get(scope)
  let journalWritten = false
  try {
    const journal: InterruptedAtomicMutation = {
      version: 1,
      scope,
      previousCache: storage.getItem(cacheKey),
      previousQueue: storage.getItem(queueKey),
    }
    const serializedCache = JSON.stringify(data)
    const serializedQueue = JSON.stringify(queue)
    storage.setItem(journalKey, JSON.stringify(journal))
    journalWritten = true
    storage.setItem(queueKey, serializedQueue)
    storage.setItem(cacheKey, serializedCache)
    storage.removeItem(journalKey)
    volatileQueues.delete(scope)
    return true
  } catch {
    if (journalWritten) recoverInterruptedAtomicMutation(scope, storage)
    if (previousVolatileQueue) volatileQueues.set(scope, [...previousVolatileQueue])
    else volatileQueues.delete(scope)
    return false
  }
}

export function clearAllLocal(scope = 'local'): void {
  recoverInterruptedAtomicMutation(scope)
  volatileQueues.delete(scope)
  try {
    localStorage.removeItem(scopedKey(CACHE_KEY, scope))
    localStorage.removeItem(scopedKey(QUEUE_KEY, scope))
    localStorage.removeItem(scopedKey(ATOMIC_MUTATION_KEY, scope))
    if (scope === 'local') {
      localStorage.removeItem(LEGACY_CACHE_KEY)
      localStorage.removeItem(LEGACY_QUEUE_KEY)
    }
  } catch {
    /* The volatile account scope was still cleared above. */
  }
}
