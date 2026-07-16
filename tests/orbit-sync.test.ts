import test from 'node:test'
import assert from 'node:assert/strict'
import { hasPendingOrbitEntity, mergeOrbitEntityRows } from '../src/orbit/domain/sync.ts'

type Row = { id: string; value: string; sync_state: 'local' | 'queued' | 'synced' | 'failed' }

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
