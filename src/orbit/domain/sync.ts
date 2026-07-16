export interface PendingOrbitOperation {
  store: string
  operation: 'upsert' | 'delete'
  entity_id: string
}

/**
 * Read a complete authoritative snapshot without relying on PostgREST's
 * server-side row cap. The caller supplies an explicitly ordered range query;
 * a short page (including an empty page after an exact multiple) terminates
 * the snapshot.
 */
export async function fetchAllOrbitPages<T>(
  fetchPage: (from: number, to: number) => Promise<readonly T[]>,
  pageSize = 500,
): Promise<T[]> {
  if (!Number.isSafeInteger(pageSize) || pageSize <= 0) throw new Error('Orbit page size must be a positive integer')
  const rows: T[] = []
  for (let offset = 0; ; offset += pageSize) {
    const page = await fetchPage(offset, offset + pageSize - 1)
    rows.push(...page)
    if (page.length < pageSize) return rows
  }
}

/**
 * Join outbox snapshots captured on both sides of a remote read. An operation
 * that was acknowledged while SELECT was running must still be replayed over
 * that potentially older response, while an edit created during SELECT must
 * be included as well.
 */
export function mergeOrbitPendingOperations<T extends PendingOrbitOperation & { id: string }>(
  ...groups: readonly (readonly T[])[]
): T[] {
  const merged = new Map<string, T>()
  for (const group of groups) for (const operation of group) merged.set(operation.id, operation)
  return [...merged.values()]
}

export type OrbitAcknowledgementDisposition = 'retain' | 'delete' | 'sync'

/** A successful delete must remove any stale cache row that hydration may
 * have observed while the request was in flight. A newer operation for the
 * same entity always remains authoritative. */
export function orbitAcknowledgementDisposition(
  operation: Pick<PendingOrbitOperation, 'operation'>,
  hasNewerPendingOperation: boolean,
): OrbitAcknowledgementDisposition {
  if (hasNewerPendingOperation) return 'retain'
  return operation.operation === 'delete' ? 'delete' : 'sync'
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
