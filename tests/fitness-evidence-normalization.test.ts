import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import {
  normalizeFitnessEvidence,
  summarizeFitnessEvidenceNormalization,
  type FitnessEvidenceNormalizationFixture,
} from '../src/lib/fitnessEvidence.ts'

const fixture = JSON.parse(readFileSync(new URL(
  '../ios/APEXNative/APEXTests/Fixtures/fitness-evidence-normalization.json',
  import.meta.url,
), 'utf8')) as FitnessEvidenceNormalizationFixture

for (const scenario of fixture.scenarios) {
  test(`fitness evidence parity: ${scenario.name}`, () => {
    const inputBefore = structuredClone(scenario.input)
    const predecessorBefore = structuredClone(scenario.predecessor ?? null)
    const result = normalizeFitnessEvidence(
      scenario.input,
      scenario.admission,
      fixture.reference_now,
      scenario.predecessor ?? null,
    )

    assert.deepEqual(summarizeFitnessEvidenceNormalization(result), scenario.expected)
    assert.deepEqual(scenario.input, inputBefore, 'normalization must not mutate the submitted evidence')
    assert.deepEqual(scenario.predecessor ?? null, predecessorBefore, 'normalization must not mutate its predecessor')
  })
}

test('user admission never manufactures a trusted source or elevated confidence', () => {
  const trustedSources = new Set([
    'indirect_calorimetry',
    'dexa_measurement',
    'dexa_derived_estimate',
    'clinical_measurement',
    'supported_device',
    'guided_apex_field_test',
  ])

  for (const scenario of fixture.scenarios.filter(({ admission }) => admission === 'user')) {
    const result = normalizeFitnessEvidence(
      scenario.input,
      scenario.admission,
      fixture.reference_now,
      scenario.predecessor ?? null,
    )
    if (result.status !== 'accepted') continue
    assert.equal(trustedSources.has(result.evidence.source), false)
    assert.equal(result.evidence.confidence, 'low')
  }
})
