import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const migrationURL = new URL(
  '../supabase/migrations/040_profile_integrity_policy.sql',
  import.meta.url,
)
const migration = existsSync(migrationURL) ? await readFile(migrationURL, 'utf8') : ''

test('new and recovered profiles default to standard while body fat defaults to unknown', () => {
  assert.match(
    migration,
    /add column if not exists profile_kind text not null default 'standard'/i,
  )
  assert.match(migration, /add column if not exists bespoke_protocol_id text/i)
  assert.match(migration, /alter column body_fat_pct drop default/i)
  assert.match(migration, /alter column body_fat_pct drop not null/i)
})

test('only immutable protected owners receive exact bespoke protocol authorization', () => {
  assert.match(
    migration,
    /9a0fffbc-bb02-40ac-834a-d4e339b32574[\s\S]*constantine-v8\.5/i,
  )
  assert.match(
    migration,
    /f1cc8158-0480-47c9-a2f1-bd03890182f9[\s\S]*june-v8\.4/i,
  )
  assert.match(migration, /raise exception[\s\S]*persona/i)
  assert.doesNotMatch(migration, /where\s+persona\s+in\s*\(/i)
})

test('legacy body-fat values gain explicit unverified provenance without profile deletion', () => {
  assert.match(migration, /body_fat_source[\s\S]*legacy_unverified/i)
  assert.doesNotMatch(migration, /delete\s+from\s+(?:public\.)?profile/i)
  assert.doesNotMatch(migration, /drop\s+table/i)
})

test('policy, protocol, source, and body-fat ranges are constrained at the database boundary', () => {
  assert.match(migration, /profile_kind\s+in\s*\(\s*'standard'\s*,\s*'bespoke'\s*\)/i)
  assert.match(
    migration,
    /profile_kind\s*=\s*'standard'[\s\S]*bespoke_protocol_id\s+is\s+null/i,
  )
  assert.match(
    migration,
    /profile_kind\s*=\s*'bespoke'[\s\S]*bespoke_protocol_id\s+is\s+not\s+null/i,
  )
  for (const source of [
    'dexa',
    'bia_scale',
    'calipers',
    'professional_estimate',
    'self_estimate',
    'legacy_unverified',
  ]) {
    assert.match(migration, new RegExp(`'${source}'`, 'i'))
  }
  assert.match(migration, /body_fat_pct\s+between\s+2\s+and\s+70/i)
})
