import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import {
  composeFitnessBrainV2,
  summarizeFitnessBrainV2,
  type FitnessBrainV2Fixture,
} from '../src/lib/fitnessBrainV2.ts'

const fixture = JSON.parse(readFileSync(new URL(
  '../ios/APEXNative/APEXTests/Fixtures/fitness-brain-v2-semantics.json',
  import.meta.url,
), 'utf8')) as FitnessBrainV2Fixture

for (const scenario of fixture.scenarios) {
  test(`Fitness Brain v2 parity: ${scenario.name}`, () => {
    const inputBefore = structuredClone(scenario.input)
    const result = composeFitnessBrainV2(scenario.input)

    assert.deepEqual(summarizeFitnessBrainV2(result), scenario.expected)
    assert.deepEqual(scenario.input, inputBefore, 'composition must not mutate evidence input')
  })
}

test('readiness, adherence, adaptation and safety context cannot rewrite capacity', () => {
  const supported = fixture.scenarios.find((scenario) => scenario.name.startsWith('supported core'))
  assert.ok(supported)

  const first = composeFitnessBrainV2(supported.input)
  const altered = structuredClone(supported.input)
  altered.readiness_signals = [
    { kind: 'sleep', normalized_value: 10, confidence: 'low', freshness: 'current', evidence_id: 'sleep-low' },
    { kind: 'fatigue', normalized_value: 15, confidence: 'low', freshness: 'current', evidence_id: 'fatigue-low' },
  ]
  altered.adherence_events = []
  altered.adaptation_signals = [
    { kind: 'protein', status: 'limiting', receipt_id: 'protein-low' },
    { kind: 'hydration', status: 'limiting', receipt_id: 'hydration-low' },
  ]
  altered.health_context = { flags: ['acute_symptom', 'clearance_required'], receipt_ids: ['safety-1'] }
  const second = composeFitnessBrainV2(altered)

  assert.deepEqual(second.capacity, first.capacity)
  assert.notDeepEqual(second.readiness, first.readiness)
  assert.equal(second.adherence.xp, 0)
  assert.equal(second.health_context.field_test_eligible, false)
})

test('v2 is a shadow semantic model with no persona or protocol authority', () => {
  const source = readFileSync(new URL('../src/lib/fitnessBrainV2.ts', import.meta.url), 'utf8')
  const legacyTypes = readFileSync(new URL('../src/lib/types.ts', import.meta.url), 'utf8')
  const legacyEngine = readFileSync(new URL('../src/lib/rpg.ts', import.meta.url), 'utf8')
  const nativeSource = readFileSync(new URL(
    '../ios/APEXNative/APEX/Core/Engine/FitnessBrainV2Semantics.swift',
    import.meta.url,
  ), 'utf8')
  const nativeLegacyModels = readFileSync(new URL(
    '../ios/APEXNative/APEX/Core/Engine/FitnessBrainModels.swift',
    import.meta.url,
  ), 'utf8')

  assert.doesNotMatch(source, /\bpersona\b|bespoke_protocol|target_kcal|calibration_k/)
  assert.doesNotMatch(nativeSource, /FBPersona|ProfileIntegrityPolicy|bespokeProtocol|targetKcal|calibrationK/)
  assert.doesNotMatch(source, /\?\?\s*50|value:\s*50/)
  assert.match(source, /health_context/)
  assert.doesNotMatch(source, /health_context[^\n]*(score|value)/)
  assert.match(legacyTypes, /export interface RpgSnapshot/)
  assert.doesNotMatch(legacyTypes, /interface RpgSnapshot[\s\S]{0,500}model_version/)
  assert.doesNotMatch(legacyEngine, /from ['"]\.\/fitnessBrainV2/)
  assert.match(nativeLegacyModels, /public struct FBSnapshot/)
  assert.doesNotMatch(nativeLegacyModels, /public struct FBSnapshot[\s\S]{0,900}modelVersion/)
})
