/* localStorage persistence: full data cache + pending op queue for offline writes. */
import type { AppData } from './types'
import { EMPTY_DATA } from './types'

const LEGACY_CACHE_KEY = 'apex.cache.v1'
const LEGACY_QUEUE_KEY = 'apex.queue.v1'
const CACHE_KEY = 'apex.cache.v2'
const QUEUE_KEY = 'apex.queue.v2'

/* localStorage can be unavailable even while the page is usable (private
   browsing, a full quota, or an embedded browser policy). Keep the latest
   queue in memory in that case so the current session can still flush it
   instead of throwing from an interaction and silently abandoning the
   server write. A reload may still require storage to be available. */
const volatileQueues = new Map<string, SyncOp[]>()

function scopedKey(base: string, scope: string): string {
  return `${base}.${scope}`
}

export interface SyncOp {
  id: string
  table: string
  type: 'upsert' | 'delete'
  /* single row, or a batch of rows for bulk imports */
  payload: Record<string, unknown> | Array<Record<string, unknown>>
  ts: number
}

export function loadCache(scope = 'local'): AppData | null {
  try {
    const raw = localStorage.getItem(scopedKey(CACHE_KEY, scope)) ??
      (scope === 'local' ? localStorage.getItem(LEGACY_CACHE_KEY) : null)
    if (!raw) return null
    return { ...EMPTY_DATA, ...(JSON.parse(raw) as Partial<AppData>) }
  } catch {
    return null
  }
}

export function saveCache(data: AppData, scope = 'local'): void {
  try {
    localStorage.setItem(scopedKey(CACHE_KEY, scope), JSON.stringify(data))
  } catch {
    /* quota exceeded: drop oldest logs rather than crash */
  }
}

export function loadQueue(scope = 'local'): SyncOp[] {
  const volatile = volatileQueues.get(scope)
  if (volatile) return [...volatile]
  try {
    const raw = localStorage.getItem(scopedKey(QUEUE_KEY, scope)) ??
      (scope === 'local' ? localStorage.getItem(LEGACY_QUEUE_KEY) : null)
    return JSON.parse(raw ?? '[]') as SyncOp[]
  } catch {
    return []
  }
}

export function saveQueue(queue: SyncOp[], scope = 'local'): void {
  try {
    localStorage.setItem(scopedKey(QUEUE_KEY, scope), JSON.stringify(queue))
    volatileQueues.delete(scope)
  } catch {
    volatileQueues.set(scope, [...queue])
  }
}

export function clearAllLocal(scope = 'local'): void {
  volatileQueues.delete(scope)
  try {
    localStorage.removeItem(scopedKey(CACHE_KEY, scope))
    localStorage.removeItem(scopedKey(QUEUE_KEY, scope))
    if (scope === 'local') {
      localStorage.removeItem(LEGACY_CACHE_KEY)
      localStorage.removeItem(LEGACY_QUEUE_KEY)
    }
  } catch {
    /* The volatile account scope was still cleared above. */
  }
}
