import test from 'node:test'
import assert from 'node:assert/strict'
import { upsertConflictTarget } from '../src/lib/sync.ts'

test('RPG snapshots reconcile legacy ids through their per-user date key', () => {
  assert.equal(upsertConflictTarget('rpg_snapshots'), 'user_id,date')
})

test('ordinary queued writes retain primary-key upsert behavior', () => {
  assert.equal(upsertConflictTarget('profile'), undefined)
  assert.equal(upsertConflictTarget('workout_logs'), undefined)
})
