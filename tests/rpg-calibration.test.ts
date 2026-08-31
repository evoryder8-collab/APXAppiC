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
  assert.equal(snapshot.endurance, 36.7)
  assert.equal(snapshot.strength_upper, 43.5)
  assert.equal(snapshot.strength_lower, 35.4)
  assert.equal(snapshot.flexibility, 34.5)
  assert.equal(snapshot.health, uncalibrated.health)
  assert.equal(snapshot.joint, uncalibrated.joint)
})
