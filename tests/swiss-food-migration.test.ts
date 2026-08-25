import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(
  new URL('../supabase/migrations/028_swiss_kebab_reference.sql', import.meta.url),
  'utf8',
)

test('Swiss kebab migration is traceable, idempotent and keeps water provenance', () => {
  assert.match(migration, /apex-curated:swiss-fsvo-v7\.1:1572/)
  assert.match(migration, /121, 7\.6, 14\.6, 3\.4/)
  assert.match(migration, /73\.6/)
  assert.match(migration, /'reference'/)
  assert.match(migration, /'swiss-fsvo-v7\.1:1572'/)
  assert.match(migration, /on conflict \(id\) do update/i)
  assert.match(migration, /water_source_id = excluded\.water_source_id/i)
})
