import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const migrationURL = new URL(
  '../supabase/migrations/041_fitness_evidence.sql',
  import.meta.url,
)
const migration = existsSync(migrationURL) ? await readFile(migrationURL, 'utf8') : ''

test('fitness evidence records provenance, timing, lineage and retry identity', () => {
  assert.match(migration, /create table if not exists public\.fitness_evidence/i)
  for (const column of [
    'user_id',
    'metric',
    'value',
    'unit',
    'source',
    'protocol',
    'device',
    'measured_at',
    'imported_at',
    'confidence',
    'metadata',
    'supersedes_id',
    'client_idempotency_key',
  ]) {
    assert.match(migration, new RegExp(`\\b${column}\\b`, 'i'))
  }
  assert.match(migration, /unique\s*\(\s*user_id\s*,\s*client_idempotency_key\s*\)/i)
  assert.match(
    migration,
    /foreign key\s*\(\s*user_id\s*,\s*supersedes_id\s*,\s*metric\s*\)[\s\S]*references public\.fitness_evidence\s*\(\s*user_id\s*,\s*id\s*,\s*metric\s*\)/i,
  )
  assert.match(migration, /jsonb_typeof\s*\(\s*metadata\s*\)\s*=\s*'object'/i)
  assert.match(migration, /create unique index[\s\S]*supersedes_id[\s\S]*where supersedes_id is not null/i)
})
test('database constraints fail closed for unsupported metrics, units, ranges and confidence escalation', () => {
  for (const metric of [
    'body_mass',
    'body_fat_percentage',
    'resting_metabolic_rate',
    'vo2_max',
    'resting_heart_rate',
    'cardio_capacity_score',
    'upper_body_strength_score',
    'lower_body_strength_score',
    'flexibility_score',
    'joint_health_score',
    'balance_score',
  ]) {
    assert.match(migration, new RegExp(`'${metric}'`, 'i'))
  }
  for (const source of [
    'indirect_calorimetry',
    'dexa_measurement',
    'dexa_derived_estimate',
    'clinical_measurement',
    'supported_device',
    'guided_apex_field_test',
    'structured_self_report',
    'user_entered_external_result',
    'legacy_unverified',
  ]) {
    assert.match(migration, new RegExp(`'${source}'`, 'i'))
  }
  assert.match(migration, /fitness_evidence_metric_unit_range/i)
  assert.match(migration, /fitness_evidence_source_confidence/i)
  assert.match(migration, /measured_at\s*<=\s*imported_at\s*\+/i)
})

test('authenticated users can read only their evidence and cannot mutate the table directly', () => {
  assert.match(migration, /enable row level security/i)
  assert.match(migration, /for select[\s\S]*using\s*\(\s*auth\.uid\(\)\s*=\s*user_id\s*\)/i)
  assert.match(migration, /revoke all on table public\.fitness_evidence from anon, authenticated/i)
  assert.match(migration, /grant select on table public\.fitness_evidence to authenticated/i)
  assert.doesNotMatch(migration, /create policy[\s\S]{0,140}for\s+(?:insert|update|delete)/i)
})

test('user recording RPC derives ownership and admits only low-confidence reportable sources', () => {
  assert.match(migration, /create or replace function public\.record_user_fitness_evidence/i)
  assert.match(migration, /security definer/i)
  assert.match(migration, /set search_path = public, pg_temp/i)
  assert.match(migration, /v_user_id\s+uuid\s*:=\s*auth\.uid\(\)/i)
  assert.match(
    migration,
    /p_source\s+not in\s*\(\s*'structured_self_report'\s*,\s*'user_entered_external_result'\s*\)/i,
  )
  assert.match(migration, /confidence[\s\S]{0,120}'low'/i)
  assert.doesNotMatch(migration, /p_confidence/i)
  assert.match(migration, /grant execute on function public\.record_user_fitness_evidence/i)
})

test('legacy facts are copied conservatively and idempotently without rewriting source tables', () => {
  assert.match(migration, /insert into public\.fitness_evidence[\s\S]*from public\.profile/i)
  assert.match(migration, /insert into public\.fitness_evidence[\s\S]*from public\.health_metrics/i)
  assert.match(migration, /custom_bmr/i)
  assert.match(migration, /legacy_unverified/i)
  assert.match(migration, /user_entered_external_result/i)
  assert.match(migration, /supported_device/i)
  assert.match(migration, /on conflict\s*\(\s*user_id\s*,\s*client_idempotency_key\s*\)\s*do nothing/i)
  assert.doesNotMatch(migration, /(?:update|delete)\s+(?:from\s+)?public\.(?:profile|settings|health_metrics)/i)
})
