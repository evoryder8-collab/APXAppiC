import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import test from 'node:test'
import {
  DEFAULT_HYDRATION_PRESETS,
  mergeHydrationEvents,
  resolveHydrationDay,
  type HydrationEvent,
} from '../src/lib/hydrationLedger.ts'

const owner = '11111111-2222-3333-4444-555555555555'
const otherOwner = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
const date = '2026-08-25'

function event(overrides: Partial<HydrationEvent> = {}): HydrationEvent {
  return {
    id: 'event-1',
    user_id: owner,
    client_idempotency_key: 'iphone:event-1',
    local_date: date,
    occurred_at: '2026-08-25T08:00:00.000Z',
    amount_ml: 250,
    kind: 'water',
    palette_token: 'aqua',
    icon_token: 'drop.fill',
    source: 'iphone',
    healthkit_sample_id: null,
    created_at: '2026-08-25T08:00:00.000Z',
    updated_at: '2026-08-25T08:00:00.000Z',
    ...overrides,
  }
}

test('hydration migration is additive, account-scoped and idempotent', () => {
  const path = 'supabase/migrations/026_hydration_ledger.sql'
  assert.equal(existsSync(path), true, 'migration 026 is missing')
  if (!existsSync(path)) return
  const migration = readFileSync(path, 'utf8')

  for (const table of ['hydration_events', 'hydration_presets', 'hydration_preferences']) {
    assert.match(migration, new RegExp(`create table if not exists public\\.${table}`, 'i'))
    assert.match(migration, new RegExp(`alter table public\\.${table} enable row level security`, 'i'))
    assert.match(
      migration,
      new RegExp(`create policy "owner_all" on public\\.${table}[\\s\\S]*?user_id = \\(select auth\\.uid\\(\\)\\)[\\s\\S]*?with check \\(user_id = \\(select auth\\.uid\\(\\)\\)\\)`, 'i'),
    )
    assert.match(migration, new RegExp(`revoke all on table public\\.${table} from public, anon`, 'i'))
    assert.match(migration, new RegExp(`grant select, insert, update, delete on table public\\.${table} to authenticated`, 'i'))
  }

  assert.match(migration, /unique \(user_id, client_idempotency_key\)/i)
  assert.match(migration, /unique index[\s\S]*healthkit_sample_id[\s\S]*where healthkit_sample_id is not null/i)
  assert.match(migration, /primary key \(user_id\)/i)
  assert.doesNotMatch(migration, /drop table|truncate table|delete from/i)
})

test('one account can never resolve another account hydration', () => {
  const result = resolveHydrationDay({
    ownerID: owner,
    date,
    events: [
      event(),
      event({ id: 'foreign', user_id: otherOwner, client_idempotency_key: 'watch:foreign', amount_ml: 900 }),
      event({ id: 'tomorrow', client_idempotency_key: 'iphone:tomorrow', local_date: '2026-08-26', amount_ml: 700 }),
    ],
    legacyDrinkLiters: 4,
  })

  assert.equal(result.drinkML, 250)
  assert.equal(result.totalML, 250)
  assert.deepEqual(result.composition.map((band) => [band.kind, band.milliliters]), [['water', 250]])
})

test('event facts replace aggregate legacy water without creating fake events', () => {
  const withFacts = resolveHydrationDay({
    ownerID: owner,
    date,
    events: [event({ amount_ml: 190, kind: 'coffee', palette_token: 'espresso', icon_token: 'cup.and.saucer.fill' })],
    legacyDrinkLiters: 2.5,
  })
  assert.equal(withFacts.drinkML, 190)
  assert.equal(withFacts.usesLegacyAggregate, false)

  const legacyOnly = resolveHydrationDay({ ownerID: owner, date, events: [], legacyDrinkLiters: 2.5 })
  assert.equal(legacyOnly.drinkML, 2_500)
  assert.equal(legacyOnly.usesLegacyAggregate, true)
  assert.equal(legacyOnly.composition[0]?.kind, 'legacy')
})

test('drink, food and external water remain attributable in one total', () => {
  const result = resolveHydrationDay({
    ownerID: owner,
    date,
    events: [
      event({ amount_ml: 250 }),
      event({ id: 'coffee', client_idempotency_key: 'watch:coffee', amount_ml: 190, kind: 'coffee', palette_token: 'espresso' }),
      event({ id: 'food', client_idempotency_key: 'food:2026-08-25', amount_ml: 420, kind: 'food', source: 'food', palette_token: 'food' }),
      event({ id: 'external', client_idempotency_key: 'healthkit:sample-1', amount_ml: 180, kind: 'external', source: 'healthkit_external', palette_token: 'external' }),
    ],
    legacyDrinkLiters: 0,
  })

  assert.equal(result.drinkML, 620)
  assert.equal(result.foodML, 420)
  assert.equal(result.totalML, 1_040)
  assert.deepEqual(result.composition.map((band) => band.kind), ['water', 'coffee', 'external', 'food'])
})

test('idempotency is scoped by account and newer revisions win', () => {
  const first = event({ updated_at: '2026-08-25T08:00:00.000Z' })
  const revised = event({ id: 'server-copy', amount_ml: 300, updated_at: '2026-08-25T08:01:00.000Z' })
  const foreign = event({ id: 'foreign-copy', user_id: otherOwner, amount_ml: 600, updated_at: '2026-08-25T08:02:00.000Z' })
  const merged = mergeHydrationEvents([first], [revised, foreign])

  assert.equal(merged.length, 2)
  assert.equal(merged.find((row) => row.user_id === owner)?.amount_ml, 300)
  assert.equal(merged.find((row) => row.user_id === otherOwner)?.amount_ml, 600)
})

test('default presets cover useful beverage kinds with stable ordering', () => {
  assert.deepEqual(DEFAULT_HYDRATION_PRESETS.map((preset) => preset.kind), [
    'water', 'water', 'coffee', 'tea', 'juice', 'shake',
  ])
  assert.deepEqual(DEFAULT_HYDRATION_PRESETS.map((preset) => preset.sort_order), [0, 1, 2, 3, 4, 5])
  assert.equal(new Set(DEFAULT_HYDRATION_PRESETS.map((preset) => preset.id)).size, DEFAULT_HYDRATION_PRESETS.length)
})
