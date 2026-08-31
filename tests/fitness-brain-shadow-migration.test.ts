import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const migrationURL = new URL(
  '../supabase/migrations/042_fitness_brain_shadow_validation.sql',
  import.meta.url,
)
const migration = existsSync(migrationURL) ? await readFile(migrationURL, 'utf8') : ''

test('shadow observations persist only privacy-safe buckets and counts', () => {
  assert.match(migration, /create table if not exists public\.fitness_brain_shadow_observations/i)
  const table = migration.match(
    /create table if not exists public\.fitness_brain_shadow_observations\s*\(([\s\S]*?)\n\);/i,
  )?.[1] ?? ''

  for (const column of [
    'observed_on',
    'platform',
    'profile_kind',
    'age_band',
    'sex_group',
    'presentation_model_version',
    'shadow_model_version',
    'legacy_overall_band',
    'shadow_overall_band',
    'absolute_disagreement_band',
    'overall_coverage_band',
    'overall_confidence',
    'source_distribution',
    'issue_codes',
    'invariant_codes',
  ]) {
    assert.match(table, new RegExp(`\\b${column}\\b`, 'i'))
  }

  for (const forbidden of [
    'legacy_overall',
    'shadow_overall',
    'heart_rate',
    'vo2',
    'body_fat',
    'resting_metabolic_rate',
    'evidence_id',
    'receipt_id',
    'workout_name',
    'birthdate',
  ]) {
    assert.doesNotMatch(table, new RegExp(`\\b${forbidden}\\b`, 'i'))
  }

  assert.match(migration, /fitness_brain_shadow_source_distribution_is_safe/i)
  assert.match(migration, /fitness_brain_shadow_issue_codes_are_safe/i)
  assert.match(migration, /invariant_codes\s*<@\s*array\s*\[/i)
  assert.match(
    migration,
    /unique\s*\(\s*user_id\s*,\s*observed_on\s*,\s*platform\s*,\s*shadow_model_version\s*\)/i,
  )
})

test('clients can read only their observations and cannot mutate the table directly', () => {
  assert.match(migration, /enable row level security/i)
  assert.match(migration, /for select[\s\S]*auth\.uid\(\)\s*=\s*user_id/i)
  assert.match(
    migration,
    /revoke all on table public\.fitness_brain_shadow_observations from public, anon, authenticated/i,
  )
  assert.match(
    migration,
    /grant select on table public\.fitness_brain_shadow_observations to authenticated/i,
  )
  assert.doesNotMatch(migration, /create policy[\s\S]{0,160}for\s+(?:insert|update|delete)/i)
})

test('constrained RPC derives ownership and writes only validated observation fields', () => {
  assert.match(migration, /create or replace function public\.record_fitness_brain_shadow_observation/i)
  assert.match(migration, /security definer/i)
  assert.match(migration, /set search_path = public, pg_temp/i)
  assert.match(migration, /v_user_id\s+uuid\s*:=\s*auth\.uid\(\)/i)
  assert.doesNotMatch(migration, /p_user_id/i)
  assert.match(migration, /on conflict\s*\(\s*user_id\s*,\s*observed_on\s*,\s*platform\s*,\s*shadow_model_version\s*\)/i)
  assert.match(
    migration,
    /revoke all on function public\.record_fitness_brain_shadow_observation[\s\S]*from public, anon/i,
  )
  assert.match(
    migration,
    /grant execute on function public\.record_fitness_brain_shadow_observation[\s\S]*to authenticated/i,
  )
})

test('review telemetry is available only as service-role aggregates without account identifiers', () => {
  assert.match(migration, /create or replace view public\.fitness_brain_shadow_review/i)
  const view = migration.match(
    /create or replace view public\.fitness_brain_shadow_review[\s\S]*?as\s*([\s\S]*?);/i,
  )?.[1] ?? ''
  assert.match(view, /count\(\*\)::bigint\s+as observation_count/i)
  assert.match(view, /sufficient_coverage_count/i)
  assert.match(view, /disagreement_outlier_count/i)
  assert.match(view, /invariant_violation_count/i)
  assert.doesNotMatch(view, /\buser_id\b/i)
  assert.match(
    migration,
    /revoke all on (?:table )?public\.fitness_brain_shadow_review from public, anon, authenticated/i,
  )
  assert.match(
    migration,
    /grant select on (?:table )?public\.fitness_brain_shadow_review to service_role/i,
  )
})
