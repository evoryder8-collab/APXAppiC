import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const migrationURL = new URL(
  '../supabase/migrations/050_testflight_account_entitlements.sql',
  import.meta.url,
)
const migration = existsSync(migrationURL) ? await readFile(migrationURL, 'utf8') : ''

test('TestFlight access is an account row with an explicit shared expiry', () => {
  assert.match(migration, /create table if not exists public\.account_entitlements/i)
  assert.match(migration, /user_id\s+uuid\s+primary key\s+references auth\.users\s*\(\s*id\s*\)/i)
  assert.match(migration, /state\s+text\s+not null/i)
  assert.match(migration, /expires_at\s+timestamptz/i)
  assert.match(migration, /2027-12-31T23:59:59Z/i)
  assert.doesNotMatch(migration, /now\(\)\s*\+\s*interval/i)
})

test('backfill and new-account provisioning are idempotent without regranting existing rows', () => {
  assert.match(
    migration,
    /insert into public\.account_entitlements[\s\S]*?from auth\.users[\s\S]*?on conflict\s*\(\s*user_id\s*\)\s*do nothing/i,
  )
  assert.match(migration, /after insert on auth\.users/i)
  assert.match(migration, /security definer/i)
  assert.match(migration, /insert into public\.account_entitlements[\s\S]*?values[\s\S]*?on conflict\s*\(\s*user_id\s*\)\s*do nothing/i)
  assert.doesNotMatch(
    migration,
    /on conflict\s*\(\s*user_id\s*\)\s*do update/i,
    'rerunning the migration or trigger must not overwrite a revoke or changed expiry',
  )
})

test('profile creation time preserves the original authenticated-account time', () => {
  assert.match(migration, /alter table public\.profile[\s\S]*add column if not exists created_at timestamptz/i)
  assert.match(
    migration,
    /update public\.profile[\s\S]*from auth\.users[\s\S]*profile\.created_at is null/i,
  )
  assert.match(migration, /alter column created_at set default now\(\)/i)
  assert.match(migration, /alter column created_at set not null/i)
})

test('entitlements and release policy have no direct client table access', () => {
  assert.match(migration, /create table if not exists public\.client_release_policy/i)
  assert.match(migration, /minimum_build\s+integer\s+not null/i)
  assert.match(migration, /web_beta_codes_enabled\s+boolean\s+not null\s+default false/i)
  assert.match(migration, /alter table public\.account_entitlements enable row level security/i)
  assert.match(migration, /alter table public\.client_release_policy enable row level security/i)
  for (const table of ['account_entitlements', 'client_release_policy']) {
    assert.match(
      migration,
      new RegExp(`revoke all on table public\\.${table} from public, anon, authenticated`, 'i'),
    )
  }
  assert.doesNotMatch(migration, /create policy[\s\S]{0,200}for\s+(?:insert|update|delete)/i)
})

test('the access RPC is profileless, owner-derived, expiry-aware and supports only active seats', () => {
  const rpc = migration.match(
    /create or replace function public\.get_my_app_access[\s\S]*?\n\$\$;/i,
  )?.[0] ?? ''
  assert.match(rpc, /security definer/i)
  assert.match(rpc, /set search_path = public, pg_temp/i)
  assert.match(rpc, /auth\.uid\(\)/i)
  assert.doesNotMatch(rpc, /public\.profile|from\s+profile/i)
  assert.match(rpc, /relationship\.client_user_id\s*=\s*v_user_id/i)
  assert.match(rpc, /relationship\.status\s*=\s*'active'/i)
  assert.match(rpc, /relationship\.seat_state\s*=\s*'active'/i)
  assert.match(rpc, /expires_at\s*>\s*v_server_now/i)
  assert.match(rpc, /p_build\s*<\s*v_minimum_build/i)
  assert.match(migration, /revoke all on function public\.get_my_app_access\(text, integer\) from public, anon/i)
  assert.match(migration, /grant execute on function public\.get_my_app_access\(text, integer\) to authenticated/i)
})
