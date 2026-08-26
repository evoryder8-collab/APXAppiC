import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(
  new URL('../supabase/migrations/030_sportyfeel_clear_whey.sql', import.meta.url),
  'utf8',
)

test('Sportyfeel Clear Whey migration is exact, barcode-ready and idempotent', () => {
  assert.match(migration, /4335619267756/)
  assert.match(migration, /apex-curated:sportyfeel-clear-whey-peach-iced-tea-label/)
  assert.match(migration, /347, 84, 2\.4, 0\.1/)
  assert.match(migration, /10, 'difference', null/)
  assert.match(migration, /25, 'g', 25/)
  assert.match(migration, /'provider_verified'/)
  assert.match(migration, /on conflict \(id\) do update/i)
  assert.match(migration, /barcode = excluded\.barcode/i)
  assert.doesNotMatch(migration, /drop table|truncate table|delete from/i)
})
