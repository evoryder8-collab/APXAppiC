const UPSERT_CONFLICT_TARGETS: Readonly<Record<string, string>> = {
  rpg_snapshots: 'user_id,date',
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

function operationRows(operation: PendingSyncOperation): Record<string, unknown>[] {
  return Array.isArray(operation.payload) ? operation.payload : [operation.payload]
}

export function syncOperationKeys(operation: PendingSyncOperation): string[] {
  const keys = operationRows(operation).flatMap((row) => {
    if (typeof row.id === 'string') return [`${operation.table}:id:${row.id}`]
    if (typeof row.user_id === 'string') return [`${operation.table}:user:${row.user_id}`]
    return []
  })
  return keys.length > 0 ? [...new Set(keys)] : [`${operation.table}:*`]
}

export function syncOperationConflicts(operation: PendingSyncOperation, blockedKeys: ReadonlySet<string>): boolean {
  const wildcard = `${operation.table}:*`
  return blockedKeys.has(wildcard) || syncOperationKeys(operation).some((key) => blockedKeys.has(key))
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
