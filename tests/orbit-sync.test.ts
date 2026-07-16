import test from 'node:test'
import assert from 'node:assert/strict'
import {
  fetchAllOrbitPages,
  hasPendingOrbitEntity,
  mergeOrbitEntityRows,
  mergeOrbitPendingOperations,
  orbitAcknowledgementDisposition,
} from '../src/orbit/domain/sync.ts'

type Row = { id: string; value: string; sync_state: 'local' | 'queued' | 'synced' | 'failed' }

test('Orbit authoritative hydration reads every ordered page beyond the server row cap', async () => {
  const source = Array.from({ length: 1_207 }, (_, index) => ({ id: `row-${String(index).padStart(4, '0')}` }))
  const ranges: Array<[number, number]> = []

  const rows = await fetchAllOrbitPages(async (from, to) => {
    ranges.push([from, to])
    return source.slice(from, to + 1)
  }, 500)

  assert.deepEqual(ranges, [[0, 499], [500, 999], [1000, 1499]])
  assert.deepEqual(rows, source)
})

test('Orbit pagination confirms completion after an exact full final page', async () => {
  const source = Array.from({ length: 1_000 }, (_, index) => ({ id: `row-${index}` }))
  const starts: number[] = []

  const rows = await fetchAllOrbitPages(async (from, to) => {
    starts.push(from)
    return source.slice(from, to + 1)
  }, 500)

  assert.deepEqual(starts, [0, 500, 1000])
  assert.equal(rows.length, source.length)
})

test('Orbit reconciliation removes server-deleted synced rows without losing queued edits', () => {
  const remote: Row[] = [
    { id: 'remote', value: 'server', sync_state: 'synced' },
    { id: 'deleted-locally', value: 'server copy', sync_state: 'synced' },
  ]
  const local: Row[] = [
    { id: 'stale-server-delete', value: 'old cache', sync_state: 'synced' },
    { id: 'remote', value: 'new local value', sync_state: 'queued' },
    { id: 'local-new', value: 'offline', sync_state: 'queued' },
  ]
  const operations = [
    { store: 'routes', operation: 'upsert' as const, entity_id: 'remote' },
    { store: 'routes', operation: 'upsert' as const, entity_id: 'local-new' },
    { store: 'routes', operation: 'delete' as const, entity_id: 'deleted-locally' },
  ]

  assert.deepEqual(mergeOrbitEntityRows(remote, local, operations, 'routes'), [
    { id: 'remote', value: 'new local value', sync_state: 'queued' },
    { id: 'local-new', value: 'offline', sync_state: 'queued' },
  ])
})

test('Orbit pending checks are isolated by entity and store', () => {
  const operations = [{ store: 'runs', operation: 'upsert' as const, entity_id: 'same-id' }]
  assert.equal(hasPendingOrbitEntity(operations, 'runs', 'same-id'), true)
  assert.equal(hasPendingOrbitEntity(operations, 'routes', 'same-id'), false)
  assert.equal(hasPendingOrbitEntity(operations, 'runs', 'other-id'), false)
})

test('Orbit hydration includes deletes queued while the server snapshot was loading', () => {
  const before = [{ id: 'before', store: 'routes', operation: 'upsert' as const, entity_id: 'kept-local' }]
  const after = [{ id: 'after', store: 'routes', operation: 'delete' as const, entity_id: 'deleted-mid-fetch' }]
  const pending = mergeOrbitPendingOperations(before, after)
  const remote: Row[] = [{ id: 'deleted-mid-fetch', value: 'stale server row', sync_state: 'synced' }]

  assert.deepEqual(mergeOrbitEntityRows(remote, [], pending, 'routes'), [])
  assert.deepEqual(pending.map((operation) => operation.id), ['before', 'after'])
})

test('Orbit delete acknowledgement removes stale cache rows unless a newer edit exists', () => {
  assert.equal(orbitAcknowledgementDisposition({ operation: 'delete' }, false), 'delete')
  assert.equal(orbitAcknowledgementDisposition({ operation: 'delete' }, true), 'retain')
  assert.equal(orbitAcknowledgementDisposition({ operation: 'upsert' }, false), 'sync')
})
