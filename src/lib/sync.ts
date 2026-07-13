const UPSERT_CONFLICT_TARGETS: Readonly<Record<string, string>> = {
  rpg_snapshots: 'user_id,date',
}

export function upsertConflictTarget(table: string): string | undefined {
  return UPSERT_CONFLICT_TARGETS[table]
}
