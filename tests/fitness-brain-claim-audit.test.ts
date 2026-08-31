import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import test from 'node:test'

const ledgerURL = new URL('../docs/fitness-brain/CLAIM-LEDGER.json', import.meta.url)
const webAvatarURL = new URL('../src/pages/AvatarPage.tsx', import.meta.url)
const nativeAvatarURL = new URL(
  '../ios/APEXNative/APEX/Features/Avatar/AvatarView.swift',
  import.meta.url,
)

const productionClaimURLs = [
  webAvatarURL,
  nativeAvatarURL,
  new URL('../src/pages/Login.tsx', import.meta.url),
  new URL('../src/pages/SimpleHome.tsx', import.meta.url),
  new URL('../src/pages/Portal.tsx', import.meta.url),
  new URL('../ios/APEXNative/APEX/Resources/de.lproj/Localizable.strings', import.meta.url),
]

test('Fitness Brain claim ledger keeps shadow validation separate from user-visible activation', () => {
  assert.equal(existsSync(ledgerURL), true, 'the reviewed claim ledger must be committed')
  const ledger = JSON.parse(readFileSync(ledgerURL, 'utf8')) as {
    rollout_status: string
    visible_model_version: number
    shadow_model_version: number
    approved_concepts: string[]
    prohibited_claims: string[]
    activation_constraints: string[]
  }

  assert.equal(ledger.rollout_status, 'shadow_validation')
  assert.equal(ledger.visible_model_version, 1)
  assert.equal(ledger.shadow_model_version, 2)
  assert.ok(ledger.approved_concepts.includes('training estimate'))
  assert.ok(ledger.approved_concepts.includes('uncertainty'))
  assert.ok(ledger.prohibited_claims.includes('clinical diagnosis'))
  assert.ok(ledger.prohibited_claims.includes('guaranteed accuracy'))
  assert.ok(ledger.activation_constraints.includes('explicit owner activation approval'))
})

test('Fitness Brain production surfaces contain no prohibited accuracy or medical claims', () => {
  const claims = productionClaimURLs.map((url) => readFileSync(url, 'utf8')).join('\n')
  const prohibitedPatterns = [
    /clinically accurate/i,
    /clinical diagnosis/i,
    /predicts? injuries/i,
    /injury prediction/i,
    /guaranteed accuracy/i,
    /scientifically proven (?:score|exact)/i,
    /medical-grade fitness/i,
    /perfectly accurate/i,
    /ultra[- ]accurate/i,
  ]

  for (const pattern of prohibitedPatterns) assert.doesNotMatch(claims, pattern)
})

test('Avatar visibly identifies legacy scores as estimates without exposing the shadow model', () => {
  const webAvatar = readFileSync(webAvatarURL, 'utf8')
  const nativeAvatar = readFileSync(nativeAvatarURL, 'utf8')

  for (const source of [webAvatar, nativeAvatar]) {
    assert.match(source, /TRAINING ESTIMATE|Training estimate/)
    assert.match(source, /Legacy game scores\. Not medical measurements\./)
    assert.doesNotMatch(source, /FitnessBrainShadow|FitnessBrainV2Semantics/)
  }
})
