import test from 'node:test'
import assert from 'node:assert/strict'
import {
  dedupeUpsertRows,
  enqueuePendingSyncOperation,
  hasPendingSyncForRecord,
  mergePendingSyncOperations,
  nextPendingSyncOperation,
  normalizeDailyLogIntegers,
  normalizeSyncPayload,
  normalizeSyncRecord,
  replayPendingList,
  replayPendingSingleton,
  syncGroupFailureBlockKeys,
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

test('daily shadow telemetry coalesces offline retries without replacing an in-flight payload', () => {
  const key = 'fitness-brain-shadow:2026-08-31:web:2'
  const first = enqueuePendingSyncOperation([], {
    table: 'fitness_brain_shadow_observations',
    type: 'rpc',
    rpc_function: 'record_fitness_brain_shadow_observation',
    dedupe_key: key,
    payload: { p_shadow_overall_band: 'capable' },
  }, { id: 'first', ts: 1 })
  const coalesced = enqueuePendingSyncOperation(first, {
    table: 'fitness_brain_shadow_observations',
    type: 'rpc',
    rpc_function: 'record_fitness_brain_shadow_observation',
    dedupe_key: key,
    payload: { p_shadow_overall_band: 'strong' },
  }, { id: 'second', ts: 2 })

  assert.equal(coalesced.length, 1)
  assert.equal(coalesced[0].id, 'second')
  assert.deepEqual(coalesced[0].payload, { p_shadow_overall_band: 'strong' })

  const whileSending = enqueuePendingSyncOperation(coalesced, {
    table: 'fitness_brain_shadow_observations',
    type: 'rpc',
    rpc_function: 'record_fitness_brain_shadow_observation',
    dedupe_key: key,
    payload: { p_shadow_overall_band: 'exceptional' },
  }, { id: 'third', ts: 3, inFlightId: 'second' })
  assert.deepEqual(whileSending.map((operation) => operation.id), ['second', 'third'])
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

test('tail coalescing never erases a training transaction boundary', () => {
  const ordinary = [{
    id: 'settings', ts: 1, table: 'settings', type: 'upsert' as const,
    payload: { user_id: 'user', addons: { weight_unit: 'kg' } },
  }]
  const pending = enqueuePendingSyncOperation(ordinary, {
    table: 'settings', type: 'upsert', sync_group: 'training:user:2',
    payload: { user_id: 'user', addons: { training_induction_pending_day_ids: ['day'] } },
  }, { id: 'pending', ts: 2 })
  assert.deepEqual(pending.map((operation) => operation.id), ['settings', 'pending'])
  assert.equal(pending[0].sync_group, undefined)
  assert.equal(pending[1].sync_group, 'training:user:2')

  const laterOrdinary = enqueuePendingSyncOperation(pending, {
    table: 'settings', type: 'upsert',
    payload: { user_id: 'user', addons: { weight_unit: 'lb' } },
  }, { id: 'ordinary', ts: 3 })
  assert.deepEqual(laterOrdinary.map((operation) => operation.id), ['settings', 'pending', 'ordinary'])
  assert.equal(laterOrdinary[1].sync_group, 'training:user:2')
  assert.equal(laterOrdinary[2].sync_group, undefined)
})

test('training rebuild keeps the pending settings barrier ahead of rows and the final marker behind them', () => {
  let queue = enqueuePendingSyncOperation([], {
    table: 'settings', type: 'upsert', payload: { user_id: 'user', addons: { training_induction_pending_day_ids: ['day-v2'] } },
  }, { id: 'pending-settings', ts: 1 })
  queue = enqueuePendingSyncOperation(queue, {
    table: 'programs', type: 'upsert', payload: [{ id: 'program' }],
  }, { id: 'programs', ts: 2 })
  queue = enqueuePendingSyncOperation(queue, {
    table: 'program_days', type: 'upsert', payload: [{ id: 'day-v2' }],
  }, { id: 'days', ts: 3 })
  queue = enqueuePendingSyncOperation(queue, {
    table: 'exercises', type: 'upsert', payload: [{ id: 'exercise-v2' }],
  }, { id: 'exercises', ts: 4 })
  queue = enqueuePendingSyncOperation(queue, {
    table: 'settings', type: 'upsert', payload: { user_id: 'user', addons: { training_induction: { generation_revision: 2 } } },
  }, { id: 'final-settings', ts: 5 })

  assert.deepEqual(queue.map((operation) => operation.id), [
    'pending-settings', 'programs', 'days', 'exercises', 'final-settings',
  ])
})

test('a failed training-plan group blocks its final marker without blocking unrelated records', () => {
  const group = 'training-plan:user:2'
  const queue = [
    { id: 'pending', ts: 1, sync_group: group, table: 'settings', type: 'upsert' as const, payload: { user_id: 'user' } },
    { id: 'days', ts: 2, sync_group: group, table: 'program_days', type: 'upsert' as const, payload: [{ id: 'day', user_id: 'user' }] },
    { id: 'final', ts: 3, sync_group: group, table: 'settings', type: 'upsert' as const, payload: { user_id: 'user' } },
    {
      id: 'ordinary-settings', ts: 4, table: 'settings', type: 'upsert' as const,
      payload: { user_id: 'user', addons: { training_induction: { generation_revision: 2 } } },
    },
    { id: 'meal', ts: 5, table: 'meals', type: 'upsert' as const, payload: { id: 'meal' } },
  ]
  const attempted = new Set(['pending', 'days'])
  const failedGroups = new Set([group])
  const blockedKeys = new Set(syncGroupFailureBlockKeys(queue[1]))

  assert.equal(
    nextPendingSyncOperation(queue, attempted, blockedKeys, failedGroups)?.id,
    'meal',
  )
  attempted.add('meal')
  assert.equal(nextPendingSyncOperation(queue, attempted, blockedKeys, failedGroups), undefined)
})

test('a later plan group cannot upload rows ahead of its blocked pending marker', () => {
  const failedGroup = 'training-plan:user:1'
  const laterGroup = 'training-plan:user:2'
  const queue = [
    { id: 'a-pending', ts: 1, sync_group: failedGroup, table: 'settings', type: 'upsert' as const, payload: { user_id: 'user' } },
    { id: 'a-days', ts: 2, sync_group: failedGroup, table: 'program_days', type: 'upsert' as const, payload: [{ id: 'day-a', user_id: 'user' }] },
    { id: 'b-pending', ts: 3, sync_group: laterGroup, table: 'settings', type: 'upsert' as const, payload: { user_id: 'user' } },
    { id: 'b-programs', ts: 4, sync_group: laterGroup, table: 'programs', type: 'upsert' as const, payload: [{ id: 'program-b', user_id: 'user' }] },
    { id: 'b-days', ts: 5, sync_group: laterGroup, table: 'program_days', type: 'upsert' as const, payload: [{ id: 'day-b', user_id: 'user' }] },
    { id: 'b-final', ts: 6, sync_group: laterGroup, table: 'settings', type: 'upsert' as const, payload: { user_id: 'user' } },
    { id: 'meal', ts: 7, table: 'meals', type: 'upsert' as const, payload: { id: 'meal', user_id: 'user' } },
  ]
  const attempted = new Set(['a-pending', 'a-days'])
  const blockedKeys = new Set(syncGroupFailureBlockKeys(queue[1]))
  const blockedGroups = new Set([failedGroup])

  assert.equal(
    nextPendingSyncOperation(queue, attempted, blockedKeys, blockedGroups)?.id,
    'meal',
  )
  attempted.add('meal')
  assert.equal(nextPendingSyncOperation(queue, attempted, blockedKeys, blockedGroups), undefined)
})

test('an external table failure cannot let a later settings snapshot cross a plan barrier', () => {
  const group = 'training-plan:user:2'
  const queue = [
    { id: 'old-programs', ts: 1, table: 'programs', type: 'upsert' as const, payload: [{ id: 'old-program', user_id: 'user' }] },
    { id: 'pending', ts: 2, sync_group: group, table: 'settings', type: 'upsert' as const, payload: { user_id: 'user' } },
    { id: 'programs', ts: 3, sync_group: group, table: 'programs', type: 'upsert' as const, payload: [{ id: 'program', user_id: 'user' }] },
    { id: 'days', ts: 4, sync_group: group, table: 'program_days', type: 'upsert' as const, payload: [{ id: 'day', user_id: 'user' }] },
    { id: 'final', ts: 5, sync_group: group, table: 'settings', type: 'upsert' as const, payload: { user_id: 'user' } },
    {
      id: 'later-settings', ts: 6, table: 'settings', type: 'upsert' as const,
      payload: { user_id: 'user', addons: { training_induction: { generation_revision: 2 } } },
    },
    { id: 'meal', ts: 7, table: 'meals', type: 'upsert' as const, payload: { id: 'meal', user_id: 'user' } },
  ]
  const attempted = new Set(['old-programs', 'pending'])
  const blockedKeys = new Set(syncFailureBlockKeys(queue[0]))

  assert.equal(
    nextPendingSyncOperation(queue, attempted, blockedKeys, new Set())?.id,
    'meal',
  )
  attempted.add('meal')
  assert.equal(nextPendingSyncOperation(queue, attempted, blockedKeys, new Set()), undefined)
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

test('supplement logs use the production composite conflict key', () => {
  assert.equal(upsertConflictTarget('supplement_logs'), 'user_id,date,supplement_id')
})

test('supplement import batches deduplicate composite keys before network replay', () => {
  const rows = dedupeUpsertRows('supplement_logs', [
    { id: 'first-id', user_id: 'user', date: '2026-08-21', supplement_id: 'taurine', taken: false },
    { id: 'second-id', user_id: 'user', date: '2026-08-21', supplement_id: 'taurine', taken: true },
    { id: 'third-id', user_id: 'user', date: '2026-08-21', supplement_id: 'zinc', taken: true },
  ])

  assert.deepEqual(rows, [
    { id: 'second-id', user_id: 'user', date: '2026-08-21', supplement_id: 'taurine', taken: true },
    { id: 'third-id', user_id: 'user', date: '2026-08-21', supplement_id: 'zinc', taken: true },
  ])
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

test('legacy Orbit imported activity ids are repaired before Supabase replay', () => {
  const repaired = normalizeSyncRecord('imported_activities', {
    id: 'orbit-d4c3a069-9bb5-42c7-83f8-6b6f880d50b9',
    user_id: '00000000-0000-4000-8000-000000000001',
    date: '2026-08-17',
    source: 'APEX Orbit',
    activity: 'APEX Orbit: easy',
  })

  assert.match(repaired.id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
})

test('measured BMR remains compatible with the existing profile schema', () => {
  const profile = normalizeSyncRecord('profile', {
    id: 'profile-id',
    user_id: 'user-id',
    weight_kg: 78,
    custom_bmr: 1840,
    custom_bmr_source: 'indirect_calorimetry',
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
