import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const migration = readFileSync(
  new URL('../supabase/migrations/020_restrict_rls_auto_enable.sql', import.meta.url),
  'utf8',
)

test('rls auto-enable helper is revoked from API roles without granting execution', () => {
  for (const role of ['public', 'anon', 'authenticated']) {
    assert.match(migration, new RegExp(`revoke\\s+all\\s+on\\s+function\\s+public\\.rls_auto_enable\\(\\)\\s+from\\s+${role}`, 'i'))
  }
  assert.doesNotMatch(migration, /grant\\s+(?:all|execute).*rls_auto_enable/i)
})
