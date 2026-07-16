export interface PendingOrbitOperation {
  store: string
  operation: 'upsert' | 'delete'
  entity_id: string
}

export function hasPendingOrbitEntity(
  operations: readonly PendingOrbitOperation[],
  store: string,
  entityId: string,
): boolean {
  return operations.some((operation) => operation.store === store && operation.entity_id === entityId)
}

/**
 * Reconciles a complete owner-scoped server snapshot with private storage.
 * Server deletions remove previously-synced rows, while the durable outbox
 * keeps unsent local upserts and deletions authoritative until acknowledged.
 */
export function mergeOrbitEntityRows<T extends { id: string; sync_state: string }>(
  remoteRows: readonly T[],
  localRows: readonly T[],
  operations: readonly PendingOrbitOperation[],
  store: string,
): T[] {
  const storeOperations = operations.filter((operation) => operation.store === store)
  const deletedIds = new Set(
    storeOperations.filter((operation) => operation.operation === 'delete').map((operation) => operation.entity_id),
  )
  const pendingUpsertIds = new Set(
    storeOperations.filter((operation) => operation.operation === 'upsert').map((operation) => operation.entity_id),
  )
  const byId = new Map<string, T>()
  for (const remote of remoteRows) {
    if (!deletedIds.has(remote.id)) byId.set(remote.id, { ...remote, sync_state: 'synced' })
  }
  for (const local of localRows) {
    if (pendingUpsertIds.has(local.id) || local.sync_state !== 'synced') byId.set(local.id, local)
  }
  return [...byId.values()]
}
