import { importedActivityId } from './ids.ts'

const UPSERT_CONFLICT_TARGETS: Readonly<Record<string, string>> = {
  rpg_snapshots: 'user_id,date',
  supplement_logs: 'user_id,date,supplement_id',
}

const DAILY_LOG_INTEGER_FIELDS = [
  'kcal',
  'protein_g',
  'fat_g',
  'carbs_g',
  'estimated_tdee',
  'manual_kcal',
  'manual_protein_g',
  'manual_fat_g',
  'manual_carbs_g',
] as const

export interface PendingSyncOperation {
  table: string
  type: 'upsert' | 'delete'
  payload: Record<string, unknown> | Array<Record<string, unknown>>
  /** Local-only transaction identity. It is never sent as a database field. */
  sync_group?: string
}

export interface DurableSyncOperation extends PendingSyncOperation {
  id: string
  ts: number
}

function databaseInteger(value: unknown): unknown {
  if (value == null) return value
  const numeric = typeof value === 'number'
    ? value
    : typeof value === 'string' && value.trim() !== ''
      ? Number(value)
      : Number.NaN
  return Number.isFinite(numeric) ? Math.round(numeric) : value
}

/**
 * Meal snapshots retain decimal macro precision, while daily_logs is the
 * compact integer summary consumed by reports and Avatar. Keep that database
 * contract at the shared write boundary so online writes and offline replay
 * cannot send values such as 195.6 to an integer column.
 */
export function normalizeDailyLogIntegers<T extends object>(row: T): T {
  const next = { ...row } as Record<string, unknown>
  for (const field of DAILY_LOG_INTEGER_FIELDS) {
    if (field in next) next[field] = databaseInteger(next[field])
  }
  return next as T
}

export function normalizeSyncRecord<T extends object>(table: string, row: T): T {
  if (table === 'daily_logs') return normalizeDailyLogIntegers(row)
  if (table === 'imported_activities') {
    const next = { ...row } as Record<string, unknown>
    const id = typeof next.id === 'string' ? next.id : ''
    const userId = typeof next.user_id === 'string' ? next.user_id : ''
    const date = typeof next.date === 'string' ? next.date : ''
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)
      && userId && date) {
      const activity = typeof next.activity === 'string' ? next.activity : 'unknown'
      const source = typeof next.source === 'string' ? next.source : 'unknown'
      next.id = importedActivityId(date, userId, `${source}:${activity}:${id}`)
    }
    return next as T
  }
  if (table === 'profile') {
    /* Measured BMR is persisted in settings.addons, an existing JSONB field.
       Keep the derived runtime property off profile writes so this release is
       compatible with databases that have not added a profile column. */
    const { custom_bmr: _customBmr, ...databaseRow } = row as Record<string, unknown>
    return databaseRow as T
  }
  return row
}

export function normalizeSyncPayload(
  table: string,
  payload: Record<string, unknown> | Array<Record<string, unknown>>,
): Record<string, unknown> | Array<Record<string, unknown>> {
  return Array.isArray(payload)
    ? payload.map((row) => normalizeSyncRecord(table, row))
    : normalizeSyncRecord(table, payload)
}

export function upsertConflictTarget(table: string): string | undefined {
  return UPSERT_CONFLICT_TARGETS[table]
}

/** Supabase rejects a batch that contains a duplicate conflict key. Retain
 * the final local intent for each key before optimistic and network writes. */
export function dedupeUpsertRows<T extends Record<string, unknown>>(table: string, rows: readonly T[]): T[] {
  const conflictFields = upsertConflictTarget(table)?.split(',').map((field) => field.trim()) ?? []
  const seen = new Set<string>()
  const result: T[] = []
  for (let index = rows.length - 1; index >= 0; index -= 1) {
    const row = rows[index]
    const hasConflictKey = conflictFields.length > 0
      && conflictFields.every((field) => row[field] !== null && row[field] !== undefined)
    const key = hasConflictKey
      ? `conflict:${conflictFields.map((field) => String(row[field])).join('|')}`
      : typeof row.id === 'string' ? `id:${row.id}` : `index:${index}`
    if (seen.has(key)) continue
    seen.add(key)
    result.push(row)
  }
  return result.reverse()
}

function operationRows(operation: PendingSyncOperation): Record<string, unknown>[] {
  return Array.isArray(operation.payload) ? operation.payload : [operation.payload]
}

function singleRowKey(operation: PendingSyncOperation): string | null {
  if (Array.isArray(operation.payload)) return null
  const row = operation.payload
  if (typeof row.id === 'string') return `${operation.table}:id:${row.id}`
  if (typeof row.user_id === 'string') return `${operation.table}:user:${row.user_id}`
  return null
}

/**
 * Adds a durable write without ever mutating the operation currently being
 * sent to Supabase. Updating an in-flight operation in place and then deleting
 * its id after the older request succeeds loses the newer edit. Only the most
 * recent, not-in-flight upsert for the same row is safe to coalesce only when
 * it is the queue tail. Writes to other tables between two versions are an
 * ordering barrier (for example pending settings, generated rows, then the
 * final settings marker) and must remain between them during offline replay.
 */
export function enqueuePendingSyncOperation(
  queue: readonly DurableSyncOperation[],
  operation: PendingSyncOperation,
  options: { id: string; ts: number; inFlightId?: string | null },
): DurableSyncOperation[] {
  const next = [...queue]
  const key = operation.type === 'upsert' ? singleRowKey(operation) : null
  if (key) {
    let latestMatchingIndex = -1
    for (let index = next.length - 1; index >= 0; index -= 1) {
      if (singleRowKey(next[index]) === key) {
        latestMatchingIndex = index
        break
      }
    }
    const latest = latestMatchingIndex >= 0 ? next[latestMatchingIndex] : null
    if (
      latestMatchingIndex === next.length - 1 &&
      latest?.type === 'upsert' &&
      latest.id !== options.inFlightId &&
      !latest.sync_group &&
      !operation.sync_group
    ) {
      next[latestMatchingIndex] = {
        ...latest,
        ...operation,
        sync_group: operation.sync_group,
        ts: options.ts,
      }
      return next
    }
  }
  next.push({ ...operation, id: options.id, ts: options.ts })
  return next
}

/** Preserve queue order while joining snapshots taken on either side of an
 * async server read. This closes the acknowledgement race where a write was
 * pending when SELECT began but had left the queue before SELECT returned. */
export function mergePendingSyncOperations<T extends { id: string }>(
  ...groups: readonly (readonly T[])[]
): T[] {
  const merged = new Map<string, T>()
  for (const group of groups) for (const operation of group) merged.set(operation.id, operation)
  return [...merged.values()]
}

export function syncOperationKeys(operation: PendingSyncOperation): string[] {
  const keys = operationRows(operation).flatMap((row) => {
    if (typeof row.id === 'string') return [`${operation.table}:id:${row.id}`]
    if (typeof row.user_id === 'string') return [`${operation.table}:user:${row.user_id}`]
    return []
  })
  return keys.length > 0 ? [...new Set(keys)] : [`${operation.table}:*`]
}

/** A failed batch is an ordered transaction boundary. Later deletes from the
 * same table must wait, even when their ids were not present in the batch. */
export function syncFailureBlockKeys(operation: PendingSyncOperation): string[] {
  return Array.isArray(operation.payload) ? [`${operation.table}:*`] : syncOperationKeys(operation)
}

/** A grouped plan install is committed by a settings marker. If any earlier
 * grouped write fails, ordinary optimistic settings writes must not leak that
 * marker past the transaction boundary. Keep the barrier account-scoped when
 * the failed rows identify their owner; fall back to the current scope. */
export function syncGroupFailureBlockKeys(operation: PendingSyncOperation): string[] {
  if (!operation.sync_group) return []
  const userIDs = operationRows(operation)
    .map((row) => row.user_id)
    .filter((userID): userID is string => typeof userID === 'string')
  return userIDs.length > 0
    ? [...new Set(userIDs)].map((userID) => `settings:user:${userID}`)
    : ['settings:*']
}

export function syncOperationConflicts(
  operation: PendingSyncOperation,
  blockedKeys: ReadonlySet<string>,
  blockedGroups?: ReadonlySet<string>,
): boolean {
  if (operation.sync_group && blockedGroups?.has(operation.sync_group)) return true
  const wildcard = `${operation.table}:*`
  return blockedKeys.has(wildcard) || syncOperationKeys(operation).some((key) => blockedKeys.has(key))
}

function syncOperationsShareLogicalRecord(
  left: PendingSyncOperation,
  right: PendingSyncOperation,
): boolean {
  const leftKeys = syncOperationKeys(left)
  const rightKeys = syncOperationKeys(right)
  return leftKeys.some((leftKey) => rightKeys.some((rightKey) => {
    const leftTable = leftKey.slice(0, leftKey.indexOf(':'))
    const rightTable = rightKey.slice(0, rightKey.indexOf(':'))
    if (leftTable !== rightTable) return false
    return leftKey === rightKey || leftKey === `${leftTable}:*` || rightKey === `${rightTable}:*`
  }))
}

export function nextPendingSyncOperation<T extends DurableSyncOperation>(
  queue: readonly T[],
  attemptedIds: ReadonlySet<string>,
  blockedKeys: ReadonlySet<string>,
  blockedGroups: ReadonlySet<string>,
): T | undefined {
  return queue.find((candidate, index) => {
    if (attemptedIds.has(candidate.id) || syncOperationConflicts(candidate, blockedKeys, blockedGroups)) {
      return false
    }
    /* A blocked transaction may have a later settings snapshot already in the
     * optimistic queue. Never let that snapshot overtake an earlier write to
     * the same account record, because it can expose the final plan marker
     * before the plan rows exist remotely. Unrelated records can still flush. */
    if (queue.slice(0, index).some((earlier) =>
      !attemptedIds.has(earlier.id) && syncOperationsShareLogicalRecord(earlier, candidate))) {
      return false
    }
    /* A group is an ordered transaction, not just a shared failure label. If
     * its pending marker is blocked behind an older plan, its rows must wait
     * too instead of appearing remotely as unmarked authored work. */
    if (candidate.sync_group && queue.slice(0, index).some((earlier) =>
      earlier.sync_group === candidate.sync_group && !attemptedIds.has(earlier.id))) {
      return false
    }
    return true
  })
}

/**
 * Replays the durable offline queue over a fresh server response. Fetching
 * and flushing are intentionally independent, so a reconnecting fetch must
 * not make an optimistic edit disappear while its queued write is still in
 * flight. Operations are applied in queue order, making the latest local
 * intent authoritative until Supabase acknowledges it.
 */
export function replayPendingList<T extends { id: string }>(
  table: string,
  serverRows: T[],
  operations: readonly PendingSyncOperation[],
): T[] {
  const rows = new Map(serverRows.map((row) => [row.id, row]))
  for (const operation of operations) {
    if (operation.table !== table) continue
    for (const raw of operationRows(operation)) {
      const id = typeof raw.id === 'string' ? raw.id : null
      if (!id) continue
      if (operation.type === 'delete') rows.delete(id)
      else rows.set(id, normalizeSyncRecord(table, raw) as T)
    }
  }
  return [...rows.values()]
}

export function replayPendingSingleton<T extends object>(
  table: string,
  serverRow: T | null,
  operations: readonly PendingSyncOperation[],
): T | null {
  let row = serverRow
  for (const operation of operations) {
    if (operation.table !== table) continue
    const latest = operationRows(operation).at(-1)
    if (!latest) continue
    row = operation.type === 'delete' ? null : normalizeSyncRecord(table, latest) as unknown as T
  }
  return row
}

/** Prevent a delayed realtime echo from replacing a newer local intent. */
export function hasPendingSyncForRecord(
  operations: readonly PendingSyncOperation[],
  table: string,
  id: string,
): boolean {
  return operations.some((operation) =>
    operation.table === table && operationRows(operation).some((row) => row.id === id || row.user_id === id),
  )
}
