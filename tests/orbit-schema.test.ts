import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const migration = readFileSync(new URL('../supabase/migrations/006_apex_orbit.sql', import.meta.url), 'utf8')
const edge = readFileSync(new URL('../supabase/functions/orbit-geo/index.ts', import.meta.url), 'utf8')
const offline = readFileSync(new URL('../src/orbit/data/orbitDb.ts', import.meta.url), 'utf8')
const store = readFileSync(new URL('../src/orbit/store/OrbitStore.tsx', import.meta.url), 'utf8')
const providers = readFileSync(new URL('../src/orbit/platform/providers.ts', import.meta.url), 'utf8')
const localization = readFileSync(new URL('../src/orbit/ui/i18n.ts', import.meta.url), 'utf8')

const tables = ['orbit_routes', 'orbit_runs', 'orbit_segments', 'orbit_shoes', 'orbit_posters', 'orbit_inductions', 'orbit_campaigns', 'orbit_campaign_sessions']

test('Orbit migration is additive, idempotent and includes every private domain table', () => {
  for (const table of tables) {
    assert.match(migration, new RegExp(`create table if not exists ${table}`))
    assert.match(migration, new RegExp(`alter table ${table} enable row level security`))
  }
  assert.match(migration, /add value if not exists 'orbit'/)
  assert.match(migration, /add column if not exists rating/)
  assert.match(migration, /rating between 1 and 5/)
  assert.match(migration, /add column if not exists prescribed_date/)
  assert.doesNotMatch(migration, /drop table|truncate table/i)
})

test('all new rows are owner scoped and anonymous access is explicitly revoked', () => {
  assert.match(migration, /for all to authenticated using \(user_id = auth\.uid\(\)\) with check \(user_id = auth\.uid\(\)\)/)
  assert.match(migration, /revoke all on table %I from anon/)
  assert.match(migration, /foreign key \(route_id, user_id\)/)
  assert.match(migration, /foreign key \(campaign_id, user_id\)/)
  assert.match(migration, /foreign key \(run_id, user_id\)/)
  assert.match(migration, /unique \(user_id, client_idempotency_key\)/)
  assert.match(store, /select\('\*'\)\s*\.eq\('user_id', userId\)\s*\.order\('id', \{ ascending: true \}\)\s*\.range\(from, to\)/)
  assert.match(store, /filter\(\(row\) => row\.user_id === userId\)/)
  assert.match(store, /createSessionBoundSupabase\(session\.access_token\)/)
  assert.match(store, /mutationRevision\.current !== revision/)
})

test('geographic proxy validates the caller and keeps provider requests server-side', () => {
  assert.match(edge, /auth\.getUser\(\)/)
  assert.match(edge, /Authentication required/)
  assert.match(edge, /User-Agent.*APEX-Orbit/)
  assert.match(edge, /profile: 'trekking'/)
  assert.match(providers, /const result = supabase\s+\? await edgeRequest/)
  assert.match(providers, /if \(supabase\) \{\s+const data = await edgeRequest\('geocode'/)
  assert.doesNotMatch(providers, /catch \{\s+result = await directBrouter/)
})

test('active run finish is atomic and the offline outbox is user indexed', () => {
  assert.match(offline, /transaction\(\['runs', 'active_runs', 'outbox'\], 'readwrite'\)/)
  assert.match(offline, /createIndex\('user_id'/)
  assert.match(offline, /transaction\.objectStore\('active_runs'\)\.delete\(run\.user_id\)/)
  assert.match(offline, /scheduleLatestOutbox\(transaction, outbox\)/)
  assert.match(offline, /recordOrbitOutboxFailure/)
  assert.match(offline, /orbitReplaceForUser/)
})

test('critical Orbit actions and induction copy ship in Romanian and Thai', () => {
  for (const key of ['Run Intelligence', 'Route planner', 'Live run', 'Performance Debrief', 'Marathon Campaign', 'Fitness-readiness check', 'Duration', 'Running shoes']) {
    const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    assert.match(localization, new RegExp(`'${escaped}': \\{ ro: '[^']+', th: '[^']+' \\}`), `missing Orbit localization for ${key}`)
  }
})
