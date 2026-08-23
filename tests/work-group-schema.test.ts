import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import test from 'node:test'

test('work groups use one generic additive exercise membership contract', () => {
  const path = 'supabase/migrations/022_exercise_work_groups.sql'
  assert.equal(existsSync(path), true, 'migration 022 is missing')
  if (!existsSync(path)) return

  const migration = readFileSync(path, 'utf8')
  assert.match(migration, /alter table public\.exercises/i)
  assert.match(migration, /add column if not exists work_group_id uuid/i)
  assert.match(migration, /add column if not exists work_group_position integer/i)
  assert.match(migration, /work_group_id is null and work_group_position is null/i)
  assert.match(migration, /work_group_id is not null and work_group_position > 0/i)
  assert.match(
    migration,
    /create unique index[\s\S]*\(user_id, program_day_id, is_lite, work_group_id, work_group_position\)/i,
    'member positions must be unique inside each account/day/variant group',
  )
  assert.doesNotMatch(migration, /drop table|truncate table|superset_group|circuit_group/i)

  const workflow = readFileSync('.github/workflows/deploy.yml', 'utf8')
  assert.match(workflow, /exercises\?select=work_group_id,work_group_position&limit=0/)
})
