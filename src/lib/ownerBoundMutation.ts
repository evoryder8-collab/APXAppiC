import type { SyncOp } from './local.ts'
import { enqueuePendingSyncOperation } from './sync.ts'

export interface OwnerBoundMutationWrite {
  /** Local-only account boundary. It is validated before staging and is not sent remotely. */
  ownerID: string
  table: string
  type: 'upsert' | 'delete' | 'rpc'
  payload: Record<string, unknown> | Array<Record<string, unknown>>
  rpc_function?: string
  dedupe_key?: string
}

export interface OwnerBoundMutationStage<TState, TResult> {
  state: TState
  result: TResult
}

export class OwnerBoundMutationBusyError extends Error {
  constructor() {
    super('Another account-owned change is still being saved.')
    this.name = 'OwnerBoundMutationBusyError'
  }
}

export class OwnerBoundMutationAccountError extends Error {
  constructor() {
    super('The active account changed before this edit could be saved.')
    this.name = 'OwnerBoundMutationAccountError'
  }
}

export class OwnerBoundMutationPersistenceError extends Error {
  constructor() {
    super('This edit could not be saved on this device. Please free storage and try again.')
    this.name = 'OwnerBoundMutationPersistenceError'
  }
}

function writeRows(write: OwnerBoundMutationWrite): Record<string, unknown>[] {
  return Array.isArray(write.payload) ? write.payload : [write.payload]
}

/** Reject a staged row that could escape the account owning the durable queue. */
export function validateOwnerBoundMutationWrites(
  expectedOwnerID: string,
  writes: readonly OwnerBoundMutationWrite[],
): void {
  for (const write of writes) {
    if (write.ownerID !== expectedOwnerID) throw new OwnerBoundMutationAccountError()
    if (write.type === 'rpc') continue
    for (const row of writeRows(write)) {
      if (row.user_id !== expectedOwnerID) throw new OwnerBoundMutationAccountError()
    }
  }
}

/**
 * One synchronous lease protects the shared workout authoring boundary. The
 * initial microtask checkpoint makes two calls started in the same UI turn
 * overlap deterministically, while the opaque token prevents an older task
 * from releasing a newer account's mutation.
 */
export class OwnerBoundMutationCoordinator {
  private active: { ownerID: string; token: string } | null = null

  get isActive(): boolean {
    return this.active !== null
  }

  async run<T>(
    expectedOwnerID: string,
    currentOwnerID: () => string | null,
    operation: () => T | Promise<T>,
  ): Promise<T> {
    if (currentOwnerID() !== expectedOwnerID) throw new OwnerBoundMutationAccountError()
    if (this.active) throw new OwnerBoundMutationBusyError()
    const token = crypto.randomUUID()
    this.active = { ownerID: expectedOwnerID, token }
    try {
      await Promise.resolve()
      if (
        this.active?.token !== token
        || this.active.ownerID !== expectedOwnerID
        || currentOwnerID() !== expectedOwnerID
      ) {
        throw new OwnerBoundMutationAccountError()
      }
      const result = await operation()
      if (currentOwnerID() !== expectedOwnerID) throw new OwnerBoundMutationAccountError()
      return result
    } finally {
      if (this.active?.token === token) this.active = null
    }
  }

  reset(): void {
    this.active = null
  }
}

/** Build one durable, account-scoped transaction group without starting I/O. */
export function orderedOwnerMutationQueue(
  existing: readonly SyncOp[],
  writes: readonly OwnerBoundMutationWrite[],
  syncGroup: string,
  makeID: () => string = () => crypto.randomUUID(),
  now: () => number = () => Date.now(),
  inFlightID: string | null = null,
): SyncOp[] {
  let queue = [...existing]
  for (const write of writes) {
    const { ownerID: _ownerID, ...operation } = write
    queue = enqueuePendingSyncOperation(queue, {
      ...operation,
      sync_group: syncGroup,
    }, {
      id: makeID(),
      ts: now(),
      inFlightId: inFlightID,
    }) as SyncOp[]
  }
  return queue
}

/**
 * Stage, durably checkpoint, then publish. `persist` is deliberately
 * synchronous: no same-account state can slip between the durable commit and
 * publication on the browser's single JavaScript thread.
 */
export async function commitOwnerBoundMutationAtomically<TState, TResult>(input: {
  coordinator: OwnerBoundMutationCoordinator
  expectedOwnerID: string
  currentOwnerID: () => string | null
  stage: () => OwnerBoundMutationStage<TState, TResult>
  persist: (stage: OwnerBoundMutationStage<TState, TResult>) => boolean
  publish: (state: TState) => void
}): Promise<TResult> {
  return input.coordinator.run(
    input.expectedOwnerID,
    input.currentOwnerID,
    () => {
      const staged = input.stage()
      let persisted = false
      try {
        persisted = input.persist(staged)
      } catch {
        throw new OwnerBoundMutationPersistenceError()
      }
      if (!persisted) throw new OwnerBoundMutationPersistenceError()
      if (input.currentOwnerID() !== input.expectedOwnerID) {
        throw new OwnerBoundMutationAccountError()
      }
      input.publish(staged.state)
      return staged.result
    },
  )
}
