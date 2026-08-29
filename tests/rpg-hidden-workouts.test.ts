import assert from 'node:assert/strict'
import test from 'node:test'
import { assessBodyState, computeEngine, whatYourBodyNeeds } from '../src/lib/rpg.ts'
import {
  EMPTY_DATA,
  type AppData,
  type ImportedActivity,
  type Profile,
  type RpgSnapshot,
  type WorkoutSession,
} from '../src/lib/types.ts'

const userId = '77777777-aaaa-4bbb-8ccc-777777777777'

const profile: Profile = {
  id: 'profile',
  user_id: userId,
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
  baseline_date: '2026-08-20',
  profile_note: '',
  seed_version: 1,
  calibration_k: 1,
  calibration_history: [],
  updated_at: '2026-08-20T00:00:00.000Z',
}

function importedWorkout(
  id: string,
  date: string,
  hiddenAt: string | null,
  kind: ImportedActivity['kind'] = 'endurance',
): ImportedActivity {
  return {
    id,
    user_id: userId,
    date,
    kind,
    activity: 'Outdoor Run',
    duration_min: 42,
    source: 'Apple Watch',
    healthkit_workout_id: `hk-${id}`,
    hidden_at: hiddenAt,
  }
}

function appData(importedActivities: ImportedActivity[], baselineDate = profile.baseline_date): AppData {
  return {
    ...EMPTY_DATA,
    profile: { ...profile, baseline_date: baselineDate },
    imported_activities: importedActivities,
  }
}

function snapshot(date = '2026-08-29'): RpgSnapshot {
  return {
    id: `snap-${date}`,
    user_id: userId,
    date,
    overall: 60,
    health: 60,
    joint: 60,
    flexibility: 60,
    endurance: 60,
    strength: 60,
    strength_upper: 60,
    strength_lower: 60,
  }
}

function apexSession(id = 'apex-session'): WorkoutSession {
  return {
    id,
    user_id: userId,
    date: '2026-08-29',
    program_day_id: 'unmapped-day',
    is_lite: false,
    is_deload: false,
    is_event_recovery: false,
    completed: true,
    quality_score: 1,
    started_at: '2026-08-29T10:00:00.000Z',
    completed_at: '2026-08-29T10:45:00.000Z',
    notes: '',
  }
}

test('a hidden imported workout gives no daily RPG stat or synergy credit while a visible workout still does', () => {
  const hidden = importedWorkout('hidden-daily', '2026-08-29', '2026-08-29T23:00:00.000Z')
  const visible = { ...hidden, id: 'visible-daily', hidden_at: null }
  const withoutImport = computeEngine(appData([]), '2026-08-29')
  const withHidden = computeEngine(appData([hidden]), '2026-08-29')
  const withVisible = computeEngine(appData([visible]), '2026-08-29')

  assert.deepEqual(withHidden, withoutImport)
  assert.ok((withVisible.snapshots.at(-1)?.endurance ?? 0) > (withoutImport.snapshots.at(-1)?.endurance ?? 0))
  assert.ok(withVisible.synergies.some((event) => event.kind === 'import_feed'))
})

test('foreign and APEX-mirrored imported workouts give no RPG credit while an owned external workout still does', () => {
  const session = apexSession()
  const ownedExternal = {
    ...importedWorkout('owned-external', '2026-08-29', null),
    started_at: '2026-08-29T12:00:00.000Z',
    source_bundle_id: 'com.apple.health',
  }
  const metadataMirror = {
    ...importedWorkout('metadata-mirror', '2026-08-29', null),
    apex_workout_session_id: session.id,
    started_at: '2026-08-29T10:00:00.000Z',
    source_bundle_id: 'ch.apexperformance.APEX.watchkitapp',
  }
  const timedMirror = {
    ...importedWorkout('timed-mirror', '2026-08-29', null),
    started_at: '2026-08-29T10:04:59.000Z',
    source_bundle_id: 'ch.apexperformance.APEX.watchkitapp',
  }
  const foreign = {
    ...ownedExternal,
    id: 'foreign-external',
    user_id: 'someone-else',
    healthkit_workout_id: 'hk-foreign-external',
  }
  const base = { ...appData([]), workout_sessions: [session] }
  const withoutImports = computeEngine(base, '2026-08-29')
  const withRejectedImports = computeEngine({
    ...base,
    imported_activities: [metadataMirror, timedMirror, foreign],
  }, '2026-08-29')
  const withOwnedExternal = computeEngine({
    ...base,
    imported_activities: [ownedExternal],
  }, '2026-08-29')

  assert.deepEqual(withRejectedImports, withoutImports)
  assert.ok((withOwnedExternal.snapshots.at(-1)?.endurance ?? 0) > (withoutImports.snapshots.at(-1)?.endurance ?? 0))
})

test('wearable evidence linked to an APEX receipt does not award a second fitness signal', () => {
  const session = apexSession()
  const base = { ...appData([]), workout_sessions: [session] }
  const linkedWearable = {
    ...importedWorkout('linked-wearable', '2026-08-29', null),
    apex_workout_session_id: session.id,
    started_at: '2026-08-29T10:01:00.000Z',
    source_bundle_id: 'com.apple.health',
  }

  assert.deepEqual(
    computeEngine({ ...base, imported_activities: [linkedWearable] }, '2026-08-29'),
    computeEngine(base, '2026-08-29'),
  )
})

test('a hidden pre-baseline workout gives no RPG baseline credit while a visible workout still does', () => {
  const hidden = importedWorkout('hidden-baseline', '2026-08-28', '2026-08-29T23:00:00.000Z')
  const visible = { ...hidden, id: 'visible-baseline', hidden_at: null }
  const withoutImport = computeEngine(appData([], '2026-08-29'), '2026-08-29')
  const withHidden = computeEngine(appData([hidden], '2026-08-29'), '2026-08-29')
  const withVisible = computeEngine(appData([visible], '2026-08-29'), '2026-08-29')

  assert.deepEqual(withHidden, withoutImport)
  assert.ok((withVisible.snapshots[0]?.endurance ?? 0) > (withoutImport.snapshots[0]?.endurance ?? 0))
  assert.ok(withVisible.synergies.some((event) => event.label.startsWith('Baseline credit:')))
})

test('a hidden imported workout does not satisfy RPG advice recency while a visible workout still does', () => {
  const hidden = importedWorkout('hidden-advice', '2026-08-29', '2026-08-29T23:00:00.000Z')
  const visible = { ...hidden, id: 'visible-advice', hidden_at: null }
  const snapshots = [snapshot()]
  const withoutImport = whatYourBodyNeeds(appData([]), snapshots)
  const withHidden = whatYourBodyNeeds(appData([hidden]), snapshots)
  const withVisible = whatYourBodyNeeds(appData([visible]), snapshots)

  assert.deepEqual(withHidden, withoutImport)
  assert.ok(withoutImport.some((advice) => advice.headline === 'No cardio logged yet'))
  assert.equal(withVisible.some((advice) => advice.headline === 'No cardio logged yet'), false)
})

test('hidden imported workouts do not raise RPG assessment confidence while visible workouts still do', () => {
  const recentDates = ['2026-08-25', '2026-08-26', '2026-08-27', '2026-08-28', '2026-08-29']
  const hidden = recentDates.map((date, index) => importedWorkout(
    `hidden-confidence-${index}`,
    date,
    '2026-08-29T23:00:00.000Z',
  ))
  const visible = hidden.map((activity, index) => ({
    ...activity,
    id: `visible-confidence-${index}`,
    hidden_at: null,
  }))
  const snapshots = [snapshot()]

  assert.equal(assessBodyState(appData([]), snapshots)?.confidence, 'Building signal')
  assert.equal(assessBodyState(appData(hidden), snapshots)?.confidence, 'Building signal')
  assert.equal(assessBodyState(appData(visible), snapshots)?.confidence, 'Moderate signal')
})
