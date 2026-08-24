import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { MOVEMENTS } from '../src/data/movements.ts'

const migrationPath = 'supabase/migrations/024_movement_catalog_enrichment.sql'

test('the enrichment migration is an exact generated deployment of 209 reviewed rows and 8 mace rows', () => {
  const migration = readFileSync(migrationPath, 'utf8')
  const generated = execFileSync(
    'python3',
    ['tools/movement-library.py', '--enrichment-sql'],
    { encoding: 'utf8' },
  )
  assert.equal(migration, generated)

  const imported = MOVEMENTS.filter((movement) => movement.importSourceName)
  const mace = MOVEMENTS.filter((movement) => movement.id.startsWith('steel_mace_'))
  assert.equal(imported.length, 209)
  assert.equal(mace.length, 8)
  assert.equal(new Set(imported.map((movement) => movement.importSourceName)).size, 209)
})

test('the migration preserves queue RLS while approving every formerly pending source row', () => {
  const migration = readFileSync(migrationPath, 'utf8')
  assert.match(migration, /add column if not exists evidence_source_ids text\[\]/i)
  assert.match(migration, /add column if not exists import_source_name text/i)
  assert.match(migration, /set match_status = 'canonical_exact'/i)
  assert.match(migration, /review_status = 'approved'/i)
  assert.match(migration, /queue\.match_status = 'pending_review'/i)
  assert.match(migration, /209 approved owner rows plus 8 researched steel-mace movements/i)
  assert.doesNotMatch(migration, /create policy/i)
  assert.doesNotMatch(migration, /grant .*movement_import_review_queue.*authenticated/i)
})
