import test from 'node:test'
import assert from 'node:assert/strict'
import {
  enqueuePendingSyncOperation,
  hasPendingSyncForRecord,
  mergePendingSyncOperations,
  normalizeDailyLogIntegers,
  normalizeSyncPayload,
  normalizeSyncRecord,
  replayPendingList,
  replayPendingSingleton,
  syncFailureBlockKeys,
  syncOperationConflicts,
  syncOperationKeys,
  upsertConflictTarget,
} from '../src/lib/sync.ts'

test('a newer edit never replaces the operation currently in flight', () => {
  const queued = [
    { id: 'blocked', ts: 1, table: 'programs', type: 'upsert' as const, payload: { id: 'program' } },
    { id: 'sending', ts: 2, table: 'workout_sessions', type: 'upsert' as const, payload: { id: 'session', notes: 'old' } },
  ]
  const next = enqueuePendingSyncOperation(
    queued,
    { table: 'workout_sessions', type: 'upsert', payload: { id: 'session', notes: 'new' } },
    { id: 'new-intent', ts: 3, inFlightId: 'sending' },
  )

  assert.deepEqual(next.map((operation) => operation.id), ['blocked', 'sending', 'new-intent'])
  assert.deepEqual(next.at(-1)?.payload, { id: 'session', notes: 'new' })
  assert.equal(next.filter((operation) => operation.id !== 'sending').some((operation) => (
    !Array.isArray(operation.payload) && operation.payload.notes === 'new'
  )), true)
})

test('queue compaction respects a later delete instead of reviving stale order', () => {
  const next = enqueuePendingSyncOperation([
    { id: 'upsert', ts: 1, table: 'workout_logs', type: 'upsert', payload: { id: 'set' } },
    { id: 'delete', ts: 2, table: 'workout_logs', type: 'delete', payload: { id: 'set' } },
  ], {
    table: 'workout_logs', type: 'upsert', payload: { id: 'set', reps: 12 },
  }, { id: 'restore', ts: 3 })

  assert.deepEqual(next.map((operation) => operation.id), ['upsert', 'delete', 'restore'])
})

test('a failed workout set batch blocks later deletes until the replacement retries', () => {
  const failedBatch = {
    table: 'workout_logs',
    type: 'upsert' as const,
    payload: [{ id: 'replacement-1' }, { id: 'replacement-2' }],
  }
  const blocked = new Set(syncFailureBlockKeys(failedBatch))
  assert.equal(syncOperationConflicts({
    table: 'workout_logs', type: 'delete', payload: { id: 'old-set' },
  }, blocked), true)
})

test('hydration retains operations acknowledged while a server snapshot was in flight', () => {
  const before = [
    { id: 'meal-write', ts: 1, table: 'workout_sessions', type: 'upsert' as const, payload: { id: 'future-session' } },
  ]
  assert.deepEqual(mergePendingSyncOperations(before, []), before)
})

test('RPG snapshots reconcile legacy ids through their per-user date key', () => {
  assert.equal(upsertConflictTarget('rpg_snapshots'), 'user_id,date')
})

test('ordinary queued writes retain primary-key upsert behavior', () => {
  assert.equal(upsertConflictTarget('profile'), undefined)
  assert.equal(upsertConflictTarget('workout_logs'), undefined)
})

test('daily log writes round structured decimal macros to database integers', () => {
  const row = normalizeDailyLogIntegers({
    kcal: 1674.6,
    protein_g: 102.4,
    carbs_g: 195.6,
    fat_g: 43,
    manual_kcal: null,
    manual_protein_g: '155.5',
  })

  assert.deepEqual(row, {
    kcal: 1675,
    protein_g: 102,
    carbs_g: 196,
    fat_g: 43,
    manual_kcal: null,
    manual_protein_g: 156,
  })
})

test('shared sync normalization protects daily logs without mutating precise meal records', () => {
  const summary = normalizeSyncRecord('daily_logs', { carbs_g: 195.6 })
  const meal = normalizeSyncRecord('logged_meals', { total_carbs_g: 195.6 })

  assert.equal(summary.carbs_g, 196)
  assert.equal(meal.total_carbs_g, 195.6)
})

test('legacy offline batches are repaired before replay', () => {
  const payload = normalizeSyncPayload('daily_logs', [
    { id: 'today', carbs_g: 195.6, protein_g: 102.4 },
    { id: 'yesterday', carbs_g: null, protein_g: 154.8 },
  ])

  assert.deepEqual(payload, [
    { id: 'today', carbs_g: 196, protein_g: 102 },
    { id: 'yesterday', carbs_g: null, protein_g: 155 },
  ])
})

test('measured BMR remains compatible with the existing profile schema', () => {
  const profile = normalizeSyncRecord('profile', {
    id: 'profile-id',
    user_id: 'user-id',
    weight_kg: 78,
    custom_bmr: 1840,
  })

  assert.deepEqual(profile, {
    id: 'profile-id',
    user_id: 'user-id',
    weight_kg: 78,
  })
})

test('fresh server reads replay queued upserts and deletes without hiding offline edits', () => {
  const rows = replayPendingList('daily_logs', [
    { id: 'remote-kept', user_id: 'user', water_l: 1 },
    { id: 'remote-deleted', user_id: 'user', water_l: 2 },
  ], [
    { table: 'daily_logs', type: 'delete', payload: { id: 'remote-deleted' } },
    { table: 'daily_logs', type: 'upsert', payload: { id: 'local-new', user_id: 'user', water_l: 3 } },
    { table: 'daily_logs', type: 'upsert', payload: { id: 'remote-kept', user_id: 'user', water_l: 4 } },
  ])

  assert.deepEqual(rows, [
    { id: 'remote-kept', user_id: 'user', water_l: 4 },
    { id: 'local-new', user_id: 'user', water_l: 3 },
  ])
})

test('queued singleton settings remain authoritative during reconnect hydration', () => {
  const settings = replayPendingSingleton('settings', { id: 'settings', user_id: 'user', language: 'en' }, [
    { table: 'settings', type: 'upsert', payload: { id: 'settings', user_id: 'user', language: 'ro' } },
  ])
  assert.deepEqual(settings, { id: 'settings', user_id: 'user', language: 'ro' })
})

test('realtime conflict guard detects records inside ordinary and bulk queue payloads', () => {
  const operations = [
    { table: 'meals', type: 'upsert' as const, payload: [{ id: 'meal-1' }, { id: 'meal-2' }] },
  ]
  assert.equal(hasPendingSyncForRecord(operations, 'meals', 'meal-2'), true)
  assert.equal(hasPendingSyncForRecord(operations, 'meals', 'meal-3'), false)
  assert.equal(hasPendingSyncForRecord(operations, 'supplements', 'meal-2'), false)
})

test('a failed record blocks only later writes for the same queued entity', () => {
  const failed = { table: 'meals', type: 'upsert' as const, payload: { id: 'meal-1' } }
  const blocked = new Set(syncOperationKeys(failed))
  assert.equal(syncOperationConflicts({ table: 'meals', type: 'delete', payload: { id: 'meal-1' } }, blocked), true)
  assert.equal(syncOperationConflicts({ table: 'meals', type: 'upsert', payload: { id: 'meal-2' } }, blocked), false)
  assert.equal(syncOperationConflicts({ table: 'daily_logs', type: 'upsert', payload: { id: 'meal-1' } }, blocked), false)
})
