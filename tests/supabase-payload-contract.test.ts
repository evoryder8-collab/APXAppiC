import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { SUPABASE_ENUMS } from '../src/lib/supabaseEnums.ts'
import {
  canonicalMealPresetRPCPayload,
  canonicalStructuredMealRPCPayload,
} from '../src/lib/foodSync.ts'

const fixture = JSON.parse(readFileSync(new URL(
  '../ios/APEXNative/APEXTests/Fixtures/supabase-payload-contract.json',
  import.meta.url,
), 'utf8'))

test('TypeScript uses the shared canonical Supabase enum strings', () => {
  assert.deepEqual(SUPABASE_ENUMS, fixture.enums)
})

test('recovery meals and presets use the supported slot while retaining their dayline identity', () => {
  const legacy = {
    ...fixture.structured_meal,
    p_meal: { ...fixture.structured_meal.p_meal, meal_slot: 'post_workout' },
  }
  const result = canonicalStructuredMealRPCPayload(legacy)
  assert.equal(result.p_meal.meal_slot, 'snack')
  assert.equal(result.p_meal.client_idempotency_key,
    `${legacy.p_meal.client_idempotency_key}|apex-meal-block=post_workout`)
  assert.deepEqual(canonicalStructuredMealRPCPayload(result), result, 'Retries must not change identity.')
  assert.deepEqual(result.p_entries, legacy.p_entries, 'Food facts must be preserved.')
  assert.equal(canonicalStructuredMealRPCPayload({
    ...legacy, p_meal: { ...legacy.p_meal, client_idempotency_key: '' },
  }).p_meal.client_idempotency_key, '', 'Invalid missing identity must still be rejected by the server.')
  const preset = canonicalMealPresetRPCPayload({
    ...fixture.meal_preset,
    p_preset: { ...fixture.meal_preset.p_preset, meal_slot: 'post_workout' },
  })
  assert.equal(preset.p_preset.meal_slot, 'snack')
})

test('web meal writes encode the same minimal RPC payload as Swift', () => {
  const expected = fixture.structured_meal
  assert.deepEqual(canonicalStructuredMealRPCPayload(expected), expected)
  const legacyWebPayload = {
    meal: {
      ...expected.p_meal,
      user_id: '99999999-9999-4999-8999-999999999999',
      total_kcal: 228,
      total_protein_g: 4.7,
      total_carbs_g: 49.4,
      total_fat_g: 0.5,
      created_at: '2026-08-28T12:34:56Z',
      updated_at: '2026-08-28T12:34:56Z',
    },
    entries: expected.p_entries.map((entry: Record<string, unknown>) => ({
      ...entry,
      meal_id: expected.p_meal.id,
      user_id: '99999999-9999-4999-8999-999999999999',
      kcal: 228,
      protein_g: 4.7,
      carbs_g: 49.4,
      fat_g: 0.5,
      fibre_g: 0.7,
      sugar_g: 0.2,
      saturated_fat_g: 0.2,
      salt_g: 0.02,
      water_ml: 119.7,
      created_at: '2026-08-28T12:34:56Z',
    })),
  }

  assert.deepEqual(canonicalStructuredMealRPCPayload(legacyWebPayload), expected)
  assert.equal(
    canonicalStructuredMealRPCPayload({
      ...legacyWebPayload,
      meal: { ...legacyWebPayload.meal, logged_as: 'actual' },
    }).p_meal.logged_as,
    'custom',
  )
})

test('web preset writes encode the same minimal RPC payload as Swift', () => {
  const expected = fixture.meal_preset
  assert.deepEqual(canonicalMealPresetRPCPayload(expected), expected)
  const legacyWebPayload = {
    preset: {
      ...expected.p_preset,
      user_id: '99999999-9999-4999-8999-999999999999',
      version: 8,
      created_at: '2026-08-28T12:34:56Z',
      updated_at: '2026-08-28T12:34:56Z',
    },
    items: expected.p_items.map((item: Record<string, unknown>) => ({
      ...item,
      preset_id: expected.p_preset.id,
      user_id: '99999999-9999-4999-8999-999999999999',
    })),
    expectedVersion: expected.p_expected_version,
  }

  assert.deepEqual(canonicalMealPresetRPCPayload(legacyWebPayload), expected)
})
