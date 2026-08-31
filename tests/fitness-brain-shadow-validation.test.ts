import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import type { FitnessEvidenceRecord } from '../src/lib/types.ts'
import {
  buildShadowCapacityInputs,
  buildFitnessBrainShadowRuntimeObservation,
  composeFitnessBrainShadowObservation,
  evaluateFitnessBrainRolloutGate,
  fitnessBrainShadowOutboxKey,
  fitnessBrainShadowRPCPayload,
  type FitnessBrainShadowFixture,
} from '../src/lib/fitnessBrainShadowValidation.ts'

const fixture = JSON.parse(readFileSync(new URL(
  './fixtures/fitness-brain-shadow-validation.json',
  import.meta.url,
), 'utf8')) as FitnessBrainShadowFixture

for (const scenario of fixture.scenarios) {
  test(`Fitness Brain shadow parity: ${scenario.name}`, () => {
    const before = structuredClone(scenario.input)
    const observation = composeFitnessBrainShadowObservation(scenario.input)

    assert.deepEqual(observation, scenario.expected)
    assert.deepEqual(scenario.input, before, 'shadow validation must not mutate inputs')
  })
}

test('shadow observations contain buckets and counts but no private raw evidence', () => {
  const observation = composeFitnessBrainShadowObservation(fixture.scenarios[1].input)
  const serialized = JSON.stringify(observation)

  for (const forbidden of [
    'user_id', 'evidence_id', 'receipt_id', 'birthdate', 'workout_name',
    'heart_rate', 'vo2_max', 'body_fat', 'resting_metabolic_rate',
  ]) {
    assert.doesNotMatch(serialized, new RegExp(forbidden, 'i'))
  }
  assert.equal(typeof observation.source_distribution.supported_device, 'number')
  assert.equal(observation.presentation_model_version, 1)
  assert.equal(observation.shadow_model_version, 2)
})

test('evidence adapter is owner-scoped, ignores superseded rows and never turns generic flexibility into regional mobility', () => {
  const record = (
    id: string,
    metric: FitnessEvidenceRecord['metric'],
    user_id = 'owner-a',
    supersedes_id: string | null = null,
  ): FitnessEvidenceRecord => ({
    id,
    user_id,
    metric,
    value: 62,
    unit: 'score_0_100',
    source: 'structured_self_report',
    protocol: 'apex_baseline_calibration_v1',
    device: null,
    measured_at: '2026-08-30T10:00:00.000Z',
    imported_at: '2026-08-30T10:01:00.000Z',
    confidence: 'low',
    metadata: { lower_bound: 45, upper_bound: 75, answered_count: 3 },
    supersedes_id,
    client_idempotency_key: `shadow-test:${id}`,
  })
  const records = [
    record('old-cardio', 'cardio_capacity_score'),
    record('new-cardio', 'cardio_capacity_score', 'owner-a', 'old-cardio'),
    record('other-owner', 'upper_body_strength_score', 'owner-b'),
    record('generic-flexibility', 'flexibility_score'),
  ]

  const inputs = buildShadowCapacityInputs(records, 'owner-a', '2026-08-31')

  assert.deepEqual(inputs.map((input) => input.domain), ['cardiorespiratory'])
  assert.deepEqual(inputs[0].evidence_ids, ['new-cardio'])
})

test('rollout stays shadow-only without representative evidence and every explicit review', () => {
  const blocked = evaluateFitnessBrainRolloutGate({
    observation_count: 2_000,
    smallest_subgroup_count: 120,
    sufficient_coverage_rate: 0.9,
    disagreement_outlier_rate: 0.01,
    invariant_violation_count: 0,
    scientific_review_complete: true,
    privacy_review_complete: true,
    claim_review_complete: true,
    owner_activation_approved: false,
  })
  assert.equal(blocked.mode, 'shadow_only')
  assert.deepEqual(blocked.blockers, ['owner_activation_required'])

  const approved = evaluateFitnessBrainRolloutGate({
    observation_count: 2_000,
    smallest_subgroup_count: 120,
    sufficient_coverage_rate: 0.9,
    disagreement_outlier_rate: 0.01,
    invariant_violation_count: 0,
    scientific_review_complete: true,
    privacy_review_complete: true,
    claim_review_complete: true,
    owner_activation_approved: true,
  })
  assert.deepEqual(approved, { mode: 'eligible_for_controlled_activation', blockers: [] })
})

test('Avatar presentation remains on legacy snapshots and cannot import the shadow composer', () => {
  const webAvatar = readFileSync(new URL('../src/pages/AvatarPage.tsx', import.meta.url), 'utf8')
  const nativeAvatar = readFileSync(new URL(
    '../ios/APEXNative/APEX/Features/Avatar/AvatarView.swift',
    import.meta.url,
  ), 'utf8')

  assert.match(webAvatar, /const \{ data, snapshots, synergies \} = useStore\(\)/)
  assert.doesNotMatch(webAvatar, /fitnessBrainShadowValidation|composeFitnessBrainV2/)
  assert.match(nativeAvatar, /session\.data\.snapshots/)
  assert.doesNotMatch(nativeAvatar, /FitnessBrainShadow|FitnessBrainV2Semantics/)
})

test('runtime shadow input uses the latest owned legacy snapshot and never a future or foreign score', () => {
  const observation = buildFitnessBrainShadowRuntimeObservation({
    owner_id: 'owner-a',
    observed_on: '2026-08-31',
    platform: 'web',
    profile_kind: 'standard',
    birthdate: '1988-06-20',
    sex: 'female',
    legacy_snapshots: [
      { user_id: 'owner-a', date: '2026-08-29', overall: 31 },
      { user_id: 'owner-b', date: '2026-08-31', overall: 99 },
      { user_id: 'owner-a', date: '2026-08-31', overall: 52 },
      { user_id: 'owner-a', date: '2026-09-01', overall: 88 },
    ],
    fitness_evidence: [],
  })

  assert.equal(observation.legacy_overall_band, '40_59')
  assert.equal(observation.shadow_overall_band, 'building_baseline')
  assert.equal(observation.age_band, '30_44')
  assert.equal(observation.sex_group, 'female')
})

test('runtime persistence payload strips subgroup fields and has one daily outbox identity', () => {
  const observation = composeFitnessBrainShadowObservation(fixture.scenarios[1].input)
  const payload = fitnessBrainShadowRPCPayload(observation)
  const serialized = JSON.stringify(payload)

  assert.equal(
    fitnessBrainShadowOutboxKey(observation),
    'fitness-brain-shadow:2026-08-31:ios:2',
  )
  assert.deepEqual(Object.keys(payload).sort(), [
    'p_absolute_disagreement_band',
    'p_invariant_codes',
    'p_issue_codes',
    'p_legacy_overall_band',
    'p_observed_on',
    'p_overall_confidence',
    'p_overall_coverage_band',
    'p_platform',
    'p_presentation_model_version',
    'p_shadow_model_version',
    'p_shadow_overall_band',
    'p_source_distribution',
  ])
  for (const forbidden of ['profile_kind', 'age_band', 'sex_group', 'user_id', 'birthdate']) {
    assert.doesNotMatch(serialized, new RegExp(`"${forbidden}"`, 'i'))
  }
})

test('web and native runtimes enqueue shadow RPCs while Avatar presentation stays isolated', () => {
  const webStore = readFileSync(new URL('../src/store/AppStore.tsx', import.meta.url), 'utf8')
  const nativeSession = readFileSync(new URL(
    '../ios/APEXNative/APEX/App/AppSession.swift',
    import.meta.url,
  ), 'utf8')

  assert.match(webStore, /buildFitnessBrainShadowRuntimeObservation/)
  assert.match(webStore, /record_fitness_brain_shadow_observation/)
  assert.match(webStore, /dedupe_key:\s*fitnessBrainShadowOutboxKey/)
  assert.match(nativeSession, /scheduleFitnessBrainShadowObservation/)
  assert.match(nativeSession, /record_fitness_brain_shadow_observation/)
  assert.match(nativeSession, /enqueueLatestFitnessBrainShadowObservation/)
})
