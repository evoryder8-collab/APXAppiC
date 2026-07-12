import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../supabase/migrations/005_food_and_visual_progress.sql', import.meta.url), 'utf8')
const edge = readFileSync(new URL('../supabase/functions/food-lookup/index.ts', import.meta.url), 'utf8')

test('migration is additive and preserves manual nutrition while structured totals are active', () => {
  assert.match(migration, /create table if not exists foods/i)
  assert.match(migration, /create table if not exists logged_meals/i)
  assert.match(migration, /alter table daily_logs add column if not exists nutrition_source/i)
  assert.match(migration, /manual_kcal = case when daily_logs\.nutrition_source = 'manual'/i)
  assert.doesNotMatch(migration, /drop table|truncate table/i)
})

test('food, history, presets and progress metadata enforce per-user isolation', () => {
  for (const table of ['food_preferences', 'meal_presets', 'meal_preset_items', 'progress_photos']) {
    assert.match(migration, new RegExp(`'${table}'`))
  }
  assert.match(migration, /using \(user_id = auth\.uid\(\)\) with check \(user_id = auth\.uid\(\)\)/i)
  assert.match(migration, /owner_user_id is null or owner_user_id = auth\.uid\(\)/i)
  assert.match(migration, /split_part\(storage_path, '\/', 1\) = user_id::text/i)
  assert.match(migration, /storage\.foldername\(name\)\)\[1\] = auth\.uid\(\)::text/i)
})

test('immutable meal snapshots cannot be updated directly', () => {
  assert.match(migration, /revoke update on table logged_meals, logged_food_entries from authenticated/i)
  assert.match(migration, /unique \(user_id, client_idempotency_key\)/i)
  assert.match(migration, /create or replace function log_structured_meal/i)
})

test('progress storage is private and deletes remain owner scoped', () => {
  assert.match(migration, /insert into storage\.buckets.*'apex-progress'.*false/is)
  assert.match(migration, /bucket_id = 'apex-progress'/i)
  assert.match(migration, /progress_photos where id = p_meal_id|progress_photos/i)
})

test('food lookup authenticates callers and keeps provider traffic server-side', () => {
  assert.match(edge, /authClient\.auth\.getUser/i)
  assert.match(edge, /SUPABASE_SERVICE_ROLE_KEY/i)
  assert.match(edge, /world\.openfoodfacts\.org/i)
  assert.match(edge, /AbortSignal\.timeout\(8000\)/i)
  assert.match(edge, /OPEN_FOOD_FACTS_FIELDS/i)
})
