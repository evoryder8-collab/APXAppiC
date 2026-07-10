import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const migration = await readFile(
  new URL('../supabase/migrations/003_daily_activity_estimator.sql', import.meta.url),
  'utf8',
)
const seedRepairMigration = await readFile(
  new URL('../supabase/migrations/004_seed_repair_version.sql', import.meta.url),
  'utf8',
)

test('activity migration is additive, idempotent, and backfills Quick Mode', () => {
  assert.match(migration, /create table if not exists activity_types/i)
  assert.match(migration, /create table if not exists activity_logs/i)
  assert.match(migration, /add column if not exists activity_mode/i)
  assert.match(migration, /update daily_logs set activity_mode = 'quick' where activity_mode is null/i)
  assert.doesNotMatch(migration, /drop table|truncate table/i)
})

test('global catalog is authenticated read-only while logs are owner-scoped', () => {
  assert.match(migration, /revoke all on table activity_types from anon, authenticated/i)
  assert.match(migration, /grant select on table activity_types to authenticated/i)
  assert.match(migration, /create policy "owner_all" on activity_logs[\s\S]*user_id = auth\.uid\(\)/i)
  assert.doesNotMatch(migration, /grant .*insert.*activity_types/i)
})

test('calibration and daily snapshot fields are per-user table additions', () => {
  assert.match(migration, /profile add column if not exists calibration_k/i)
  assert.match(migration, /profile add column if not exists calibration_history/i)
  assert.match(migration, /daily_logs add column if not exists estimated_tdee/i)
  assert.match(migration, /daily_logs add column if not exists computed_pal/i)
  assert.match(migration, /daily_logs add column if not exists weight_kg/i)
})

test('seed repair marker is additive and defaults existing profiles to pending', () => {
  assert.match(seedRepairMigration, /profile add column if not exists seed_version/i)
  assert.match(seedRepairMigration, /not null default 0/i)
  assert.doesNotMatch(seedRepairMigration, /drop table|truncate table|delete from/i)
})
