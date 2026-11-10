import assert from 'node:assert/strict'
import test from 'node:test'
import { computeEngine } from '../src/lib/rpg.ts'
import {
  EMPTY_DATA,
  type AppData,
  type FitnessEvidenceRecord,
  type Profile,
} from '../src/lib/types.ts'

const ownerID = '11111111-2222-3333-4444-555555555555'

const profile: Profile = {
  id: 'profile',
  user_id: ownerID,
  persona: 'constantine',
  display_name: 'Owner',
  sex: 'male',
  weight_kg: 80,
  body_fat_pct: 15,
  custom_bmr: null,
  height_cm: 180,
  birthdate: '1990-01-01',
  activity_level: 'moderate',
  goal: 'maintain',
  target_kcal: null,
  target_protein_g: null,
  target_fat_g: null,
  target_carbs_g: null,
  training_time: '18:00',
  baseline_date: '2026-08-30',
  profile_note: '',
  seed_version: 1,
  calibration_k: 1,
  calibration_history: [],
  updated_at: '2026-08-31T00:00:00.000Z',
}

function evidence(
  metric: FitnessEvidenceRecord['metric'],
  userID = ownerID,
  value = 30,
  importedAt = '2026-08-31T08:00:01.000Z',
): FitnessEvidenceRecord {
  return {
    id: `${userID}:${metric}:${value}:${importedAt}`,
    user_id: userID,
    metric,
    value,
    unit: 'score_0_100',
    source: 'structured_self_report',
    protocol: 'apex_baseline_calibration_v1',
    device: null,
    measured_at: '2026-08-31T08:00:00.000Z',
    imported_at: importedAt,
    confidence: 'low',
    metadata: { answered_count: 3, display_precision: 'band_only' },
    supersedes_id: null,
    client_idempotency_key: `calibration-v1:${userID}:${metric}:${value}`,
  }
}

function dashboard(fitnessEvidence: FitnessEvidenceRecord[]): AppData {
  return { ...EMPTY_DATA, profile, fitness_evidence: fitnessEvidence }
}

test('account-owned baseline calibration changes only its visible Avatar capacity lanes', () => {
  const result = computeEngine(dashboard([
    evidence('cardio_capacity_score', ownerID, 77, '2026-08-31T07:00:01.000Z'),
    evidence('cardio_capacity_score'),
    evidence('upper_body_strength_score'),
    evidence('lower_body_strength_score'),
    evidence('flexibility_score'),
    evidence('cardio_capacity_score', 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', 99),
  ]), '2026-08-31')
  const snapshot = result.snapshots.at(-1)
  const uncalibrated = computeEngine(dashboard([]), '2026-08-31').snapshots.at(-1)

  assert.ok(snapshot)
  assert.ok(uncalibrated)
  assert.equal(snapshot.endurance, 64.9)
  assert.equal(snapshot.strength_upper, 39)
  assert.equal(snapshot.strength_lower, 39)
  assert.equal(snapshot.flexibility, 39)
  assert.equal(snapshot.health, uncalibrated.health)
  assert.equal(snapshot.joint, uncalibrated.joint)
})

test('chosen starting points replace the onboarding estimate and keep later capacity observations', () => {
  const data = dashboard([{ ...evidence('cardio_capacity_score'), measured_at: profile.baseline_date + 'T08:00:00Z', protocol: 'apex_onboarding_pulse_v1' }])
  data.profile = { ...profile, avatar_starting_points: { health: 35, joint: 50, flexibility: 50, endurance: 65, strength_lower: 50, strength_upper: 50 } }
  assert.equal(computeEngine(data, profile.baseline_date).snapshots.at(-1)?.endurance, 65)
  data.fitness_evidence.push(evidence('cardio_capacity_score', ownerID, 77))
  assert.ok(computeEngine(data, '2026-08-31').snapshots.at(-1)!.endurance > 65)
})

test('onboarding answers never alter chosen starting points, on the signup night or any day after', () => {
  const start = { health: 50, joint: 50, flexibility: 50, endurance: 35, strength_lower: 30, strength_upper: 85 }
  const endurance = (answeredAt: string, through: string) => {
    const data = dashboard([{
      ...evidence('cardio_capacity_score', ownerID, 77, answeredAt),
      measured_at: answeredAt,
      protocol: 'apex_onboarding_pulse_v1',
      metadata: { lower_bound: 70 },
    }])
    data.profile = { ...profile, avatar_starting_points: start }
    return computeEngine(data, through).snapshots.at(-1)?.endurance
  }
  // 20:00 in Los Angeles on the baseline day is already the next UTC day.
  assert.equal(endurance('2026-08-31T03:00:00.000Z', '2026-08-30'), 35)
  assert.equal(endurance('2026-08-31T03:00:00.000Z', '2026-08-31'), 35)
  assert.equal(endurance('2026-08-31T03:00:00.000Z', '2026-09-04'), 35)
  // 08:00 in Tokyo on the baseline day is still the previous UTC day.
  assert.equal(endurance('2026-08-29T23:00:00.000Z', '2026-09-04'), 35)
  // A pulse answered days after joining is new evidence.
  assert.equal(endurance('2026-09-02T08:00:00.000Z', '2026-09-04'), 49.7)
})

test('a later self-check lifts a score below its band once and never lowers an earned score', () => {
  const start = { health: 50, joint: 50, flexibility: 50, endurance: 35, strength_lower: 30, strength_upper: 85 }
  const answer = (metric: FitnessEvidenceRecord['metric'], value: number, lowerBound: number, day: string) => ({
    ...evidence(metric, ownerID, value, `${day}T08:00:01.000Z`),
    measured_at: `${day}T08:00:00.000Z`,
    metadata: { answered_count: 3, lower_bound: lowerBound },
  })
  const latest = (records: FitnessEvidenceRecord[]) => {
    const data = dashboard(records)
    data.profile = { ...profile, avatar_starting_points: start }
    return computeEngine(data, '2026-09-04').snapshots.at(-1)!
  }
  assert.equal(latest([answer('upper_body_strength_score', 77, 70, '2026-08-31')]).strength_upper, 85)
  assert.equal(latest([answer('upper_body_strength_score', 47, 40, '2026-08-31')]).strength_upper, 85)
  const once = latest([answer('cardio_capacity_score', 62, 55, '2026-08-31')]).endurance
  assert.equal(once, 49.9)
  assert.equal(latest([
    answer('cardio_capacity_score', 62, 55, '2026-08-31'),
    answer('cardio_capacity_score', 62, 55, '2026-09-02'),
    answer('cardio_capacity_score', 47, 40, '2026-09-03'),
  ]).endurance, once)
  assert.ok(latest([
    answer('cardio_capacity_score', 62, 55, '2026-08-31'),
    answer('cardio_capacity_score', 77, 70, '2026-09-02'),
  ]).endurance > once)
})

test('answers given on one day apply oldest first, so a repeat or a lower one changes nothing', () => {
  const balanced = { health: 50, joint: 50, flexibility: 50, endurance: 50, strength_lower: 50, strength_upper: 50 }
  const answer = (metric: FitnessEvidenceRecord['metric'], value: number, lowerBound: number, at: string) => ({
    ...evidence(metric, ownerID, value, at),
    measured_at: at,
    metadata: { answered_count: 3, lower_bound: lowerBound },
  })
  const latest = (records: FitnessEvidenceRecord[], startingPoints?: typeof balanced) => {
    const data = dashboard(records)
    if (startingPoints) data.profile = { ...profile, avatar_starting_points: startingPoints }
    return computeEngine(data, '2026-09-04').snapshots.at(-1)!
  }
  for (const day of ['2026-09-02', profile.baseline_date]) {
    const first = answer('upper_body_strength_score', 77, 70, `${day}T12:00:00.000Z`)
    const lower = answer('upper_body_strength_score', 47, 40, `${day}T13:00:00.000Z`)
    const repeat = answer('upper_body_strength_score', 77, 70, `${day}T14:00:00.000Z`)
    assert.equal(latest([first], balanced).strength_upper, 64.9)
    assert.equal(latest([first, lower], balanced).strength_upper, 64.9)
    assert.equal(latest([lower, first, repeat], balanced).strength_upper, 64.9)
    // A score with no evidence yet takes its first answer, and a higher one that day lifts it again.
    assert.equal(latest([
      answer('flexibility_score', 30, 20, `${day}T12:00:00.000Z`),
      answer('flexibility_score', 62, 55, `${day}T13:00:00.000Z`),
      answer('flexibility_score', 30, 20, `${day}T14:00:00.000Z`),
    ]).flexibility, 51.7)
  }
})
