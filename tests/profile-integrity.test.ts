import assert from 'node:assert/strict'
import test from 'node:test'
import { buildSeedData } from '../src/data/seed.ts'
import { activityBmr } from '../src/lib/activity.ts'
import { computeTargets } from '../src/lib/nutrition.ts'
import { personalTargetFor } from '../src/lib/personalProtocol.ts'
import { bodyFatBaselineClause } from '../src/lib/profilePolicy.ts'
import { repairSeedDefinitions } from '../src/lib/seedRepair.ts'
import type { Profile } from '../src/lib/types.ts'

type PolicyFields = {
  profile_kind?: 'standard' | 'bespoke' | null
  bespoke_protocol_id?: 'constantine-v8.5' | 'june-v8.4' | null
  body_fat_source?:
    | 'dexa'
    | 'bia_scale'
    | 'calipers'
    | 'professional_estimate'
    | 'self_estimate'
    | 'legacy_unverified'
    | null
  body_fat_measured_at?: string | null
}

function profile(
  overrides: Partial<Profile & PolicyFields> = {},
): Profile & PolicyFields {
  return {
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    user_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    persona: 'constantine',
    display_name: 'APEX Athlete',
    sex: 'male',
    weight_kg: 80,
    body_fat_pct: 23,
    body_fat_source: 'legacy_unverified',
    body_fat_measured_at: null,
    custom_bmr: null,
    height_cm: 180,
    birthdate: '1990-01-01',
    activity_level: 'moderate',
    goal: 'recomp',
    profile_kind: 'standard',
    bespoke_protocol_id: null,
    target_kcal: null,
    target_protein_g: null,
    target_fat_g: null,
    target_carbs_g: null,
    training_time: '19:00',
    baseline_date: '2026-01-01',
    profile_note: '',
    seed_version: 8,
    calibration_k: 1,
    calibration_history: [],
    updated_at: '2026-08-30T00:00:00Z',
    ...overrides,
  }
}

test('a Constantine presentation persona cannot authorize bespoke nutrition for a standard account', () => {
  const standard = profile()

  assert.equal(personalTargetFor(standard), null)
  assert.notEqual(computeTargets(standard).kcal, 2_450)
})

test('only an exact matching bespoke policy resolves an authored protocol', () => {
  assert.equal(
    personalTargetFor(profile({
      profile_kind: 'bespoke',
      bespoke_protocol_id: 'constantine-v8.5',
    })),
    null,
  )

  assert.deepEqual(
    personalTargetFor(profile({
      id: '9a0fffbc-bb02-40ac-834a-d4e339b32574',
      user_id: '9a0fffbc-bb02-40ac-834a-d4e339b32574',
      profile_kind: 'bespoke',
      bespoke_protocol_id: 'constantine-v8.5',
    })),
    { kcal: 2_450, tdee: 2_550, proteinG: 150, fatG: 75, carbsG: 293 },
  )

  assert.equal(
    personalTargetFor(profile({
      id: '9a0fffbc-bb02-40ac-834a-d4e339b32574',
      user_id: '9a0fffbc-bb02-40ac-834a-d4e339b32574',
      persona: 'june',
      profile_kind: 'bespoke',
      bespoke_protocol_id: 'constantine-v8.5',
      goal: 'bulk',
    })),
    null,
  )
})

test('different standard bodies receive anthropometric targets instead of one Constantine target', () => {
  const smaller = computeTargets(profile({
    sex: 'female',
    weight_kg: 45,
    height_cm: 153,
    birthdate: '1983-06-19',
  }))
  const larger = computeTargets(profile({
    sex: 'male',
    weight_kg: 120,
    height_cm: 195,
    birthdate: '1990-01-01',
  }))

  assert.notEqual(smaller.kcal, 2_450)
  assert.notEqual(larger.kcal, 2_450)
  assert.ok(smaller.kcal < larger.kcal)
})

test('unverified or self-estimated body fat cannot select a lean-mass energy equation', () => {
  const legacy = profile({ persona: 'iulian', body_fat_source: 'legacy_unverified' })
  const selfEstimated = profile({ persona: 'iulian', body_fat_source: 'self_estimate' })

  assert.equal(computeTargets(legacy).bmrSource, 'mifflin')
  assert.equal(computeTargets(selfEstimated).bmrSource, 'mifflin')
  assert.equal(activityBmr(legacy), activityBmr(selfEstimated))
})

test('eligible measured body-fat sources may select the lean-mass equation', () => {
  for (const body_fat_source of [
    'dexa',
    'bia_scale',
    'calipers',
    'professional_estimate',
  ] as const) {
    const measured = profile({ persona: 'iulian', body_fat_source })
    assert.equal(computeTargets(measured).bmrSource, 'katch')
    assert.ok(Math.abs(activityBmr(measured) - (370 + 21.6 * 80 * 0.77)) < 0.000_001)
  }
})

test('standard profiles cannot install or upgrade bespoke seed definitions', () => {
  const seeded = buildSeedData('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'constantine')
  const current = {
    ...seeded,
    profile: {
      ...seeded.profile!,
      profile_kind: 'standard' as const,
      bespoke_protocol_id: null,
      seed_version: 0,
    },
    programs: [],
    program_days: [],
    exercises: [],
  }

  const repaired = repairSeedDefinitions(current, seeded)
  assert.equal(repaired.needsRepair, false)
  assert.deepEqual(repaired.data.programs, [])
  assert.deepEqual(repaired.data.program_days, [])
  assert.deepEqual(repaired.data.exercises, [])
})

test('an unknown body-fat baseline is omitted instead of rendering null percent', () => {
  assert.equal(bodyFatBaselineClause(profile({ body_fat_pct: null, body_fat_source: null })), '')
  assert.equal(bodyFatBaselineClause(profile({ body_fat_pct: 23.5, body_fat_source: 'dexa' })), ', 23.5% body fat')
})
