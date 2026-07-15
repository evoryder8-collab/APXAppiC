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
