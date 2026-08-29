import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const migration = await readFile(
  new URL('../supabase/migrations/032_external_healthkit_workouts.sql', import.meta.url),
  'utf8',
)
const baseMigration = await readFile(
  new URL('../supabase/migrations/001_schema.sql', import.meta.url),
  'utf8',
)

test('external HealthKit workout fields are an additive, repeatable extension', () => {
  const columns = [
    ['healthkit_workout_id', 'uuid'],
    ['started_at', 'timestamptz'],
    ['ended_at', 'timestamptz'],
    ['workout_name_key', 'text'],
    ['distance_km', 'double precision'],
    ['active_energy_kcal', 'double precision'],
    ['source_bundle_id', 'text'],
    ['activity_type_raw', 'bigint'],
    ['apex_workout_session_id', 'uuid'],
    ['hidden_at', 'timestamptz'],
  ] as const

  assert.match(migration, /alter table public\.imported_activities/i)
  for (const [name, type] of columns) {
    assert.match(
      migration,
      new RegExp(`add column if not exists ${name} ${type.replace(' ', '\\s+')}`, 'i'),
      `${name} must remain additive and idempotent`,
    )
  }
  assert.doesNotMatch(
    migration,
    /\b(?:drop\s+(?:table|column)|truncate\s+table|delete\s+from|alter\s+column)\b/i,
  )
})

test('HealthKit UUID deduplication is scoped to the owning account', () => {
  assert.match(
    migration,
    /add constraint imported_activities_owner_healthkit_workout_key\s+unique\s*\(user_id,\s*healthkit_workout_id\)/i,
  )
})

test('external workout metrics and timestamps reject invalid receipts', () => {
  assert.match(
    migration,
    /constraint imported_activities_external_metrics_nonnegative[\s\S]*?distance_km is null or distance_km >= 0[\s\S]*?active_energy_kcal is null or active_energy_kcal >= 0/i,
  )
  assert.match(
    migration,
    /constraint imported_activities_external_time_order[\s\S]*?started_at is null or ended_at is null or ended_at >= started_at/i,
  )
})

test('visible external receipts have an owner-and-start-time partial index', () => {
  assert.match(
    migration,
    /create index if not exists idx_imported_activities_owner_started\s+on public\.imported_activities\s*\(user_id,\s*started_at desc\)\s+where healthkit_workout_id is not null and hidden_at is null/i,
  )
})

test('hiding an external receipt never deletes its Apple Health source', () => {
  assert.match(
    migration,
    /comment on column public\.imported_activities\.hidden_at is\s+'[^']*hides the receipt from APEX without deleting the original workout from Apple Health[^']*'/i,
  )
  assert.match(
    migration,
    /comment on column public\.imported_activities\.healthkit_workout_id is\s+'[^']*HealthKit object remains the source of truth[^']*'/i,
  )
  assert.doesNotMatch(migration, /delete\s+from\s+public\.imported_activities/i)
})

test('the base imported activities table retains owner-scoped row-level security', () => {
  assert.match(
    baseMigration,
    /foreach t in array array\[[\s\S]*?'imported_activities'[\s\S]*?execute format\('alter table %I enable row level security', t\)[\s\S]*?create policy "owner_all" on %I for all to authenticated using \(user_id = auth\.uid\(\)\) with check \(user_id = auth\.uid\(\)\)/i,
  )
  assert.doesNotMatch(
    migration,
    /(?:disable row level security|drop policy[^;]*owner_all|create policy)/i,
    'the additive migration must not weaken or replace the base owner policy',
  )
})
