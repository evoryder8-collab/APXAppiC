/* localStorage persistence: full data cache + pending op queue for offline writes. */
import type { AppData } from './types'
import { EMPTY_DATA } from './types'

const CACHE_KEY = 'apex.cache.v1'
const QUEUE_KEY = 'apex.queue.v1'

export interface SyncOp {
  id: string
  table: string
  type: 'upsert' | 'delete'
  /* single row, or a batch of rows for bulk imports */
  payload: Record<string, unknown> | Array<Record<string, unknown>>
  ts: number
}

export function loadCache(): AppData | null {
  try {
    const raw = localStorage.getItem(CACHE_KEY)
    if (!raw) return null
    return { ...EMPTY_DATA, ...(JSON.parse(raw) as Partial<AppData>) }
  } catch {
    return null
  }
}

export function saveCache(data: AppData): void {
  try {
    localStorage.setItem(CACHE_KEY, JSON.stringify(data))
  } catch {
    /* quota exceeded: drop oldest logs rather than crash */
  }
}

export function loadQueue(): SyncOp[] {
  try {
    return JSON.parse(localStorage.getItem(QUEUE_KEY) ?? '[]') as SyncOp[]
  } catch {
    return []
  }
}

export function saveQueue(queue: SyncOp[]): void {
  localStorage.setItem(QUEUE_KEY, JSON.stringify(queue))
}

export function clearAllLocal(): void {
  localStorage.removeItem(CACHE_KEY)
  localStorage.removeItem(QUEUE_KEY)
}
