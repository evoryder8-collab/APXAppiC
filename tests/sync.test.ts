import test from 'node:test'
import assert from 'node:assert/strict'
import {
  normalizeDailyLogIntegers,
  normalizeSyncPayload,
  normalizeSyncRecord,
  upsertConflictTarget,
} from '../src/lib/sync.ts'

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
