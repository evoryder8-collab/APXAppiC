import assert from 'node:assert/strict'
import test from 'node:test'
import { assessBodyState, computeEngine, whatYourBodyNeeds } from '../src/lib/rpg.ts'
import {
  EMPTY_DATA,
  type AppData,
  type DailyLog,
  type Profile,
  type RpgSnapshot,
} from '../src/lib/types.ts'

const ownerID = '11111111-2222-4333-8444-555555555555'
const day = '2026-09-02'

function profile(overrides: Partial<Profile> = {}): Profile {
  return {
    id: 'profile',
    user_id: ownerID,
    persona: 'iulian',
    display_name: 'Owner',
    sex: 'male',
    weight_kg: 80,
    body_fat_pct: null,
    height_cm: 180,
    birthdate: '1990-01-01',
    activity_level: 'moderate',
    goal: 'maintain',
    target_kcal: null,
    target_protein_g: null,
    target_fat_g: null,
    target_carbs_g: null,
    training_time: '18:00',
    baseline_date: day,
    profile_note: '',
    seed_version: 1,
    calibration_k: 1,
    calibration_history: [],
    updated_at: `${day}T00:00:00.000Z`,
    ...overrides,
  }
}

function nutritionLog(
  date = day,
  userID = ownerID,
  kcal = 0,
  proteinG = 0,
): DailyLog {
  return {
    id: `log:${userID}:${date}`,
    user_id: userID,
    date,
    kcal,
    protein_g: proteinG,
    fat_g: 0,
    carbs_g: 0,
    water_l: 0,
    estimated_tdee: null,
    computed_pal: null,
    activity_mode: 'quick',
    weight_kg: null,
  }
}

function strengthDay(subject: Profile, logs: DailyLog[] = []): AppData {
  return {
    ...EMPTY_DATA,
    profile: subject,
    daily_logs: logs,
    program_days: [{
      id: 'upper-day',
      user_id: subject.user_id,
      program_id: 'program',
      weekday: 3,
      name: 'Upper',
      day_type: 'upper',
      est_minutes: 45,
      warmup_note: '',
      sort_order: 1,
    }],
    workout_sessions: [{
      id: 'session',
      user_id: subject.user_id,
      date: day,
      program_day_id: 'upper-day',
      is_lite: false,
      is_deload: false,
      is_event_recovery: false,
      completed: true,
      quality_score: 1,
      started_at: `${day}T18:00:00.000Z`,
      completed_at: `${day}T18:45:00.000Z`,
      notes: '',
    }],
  }
}

function snapshot(date = day): RpgSnapshot {
  return {
    id: `snapshot:${date}`,
    user_id: ownerID,
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

test('zeroed blocked targets cannot amplify strength or feed Health', () => {
  const subject = profile({ birthdate: 'not-a-date' })
  const withoutNutrition = computeEngine(strengthDay(subject), day)
  const withZeroLog = computeEngine(strengthDay(subject, [nutritionLog()]), day)

  assert.equal(withZeroLog.synergies.some((event) => event.kind === 'protein_strength'), false)
  assert.equal(withZeroLog.synergies.some((event) => event.kind === 'deficit_strength'), false)
  assert.equal(withZeroLog.snapshots.at(-1)?.strength, withoutNutrition.snapshots.at(-1)?.strength)
  assert.equal(withZeroLog.snapshots.at(-1)?.health, withoutNutrition.snapshots.at(-1)?.health)
})

test('a non-publishable target with calories cannot amplify or temper strength', () => {
  const subject = profile({
    sex: 'female',
    weight_kg: 160,
    height_cm: 165,
    birthdate: '1981-01-01',
    custom_bmr: 800,
    activity_level: 'sedentary',
  })
  const withoutNutrition = computeEngine(strengthDay(subject), day)
  const withUnsafeNutrition = computeEngine(strengthDay(subject, [nutritionLog()]), day)

  assert.equal(withUnsafeNutrition.synergies.some((event) => event.kind === 'protein_strength'), false)
  assert.equal(withUnsafeNutrition.synergies.some((event) => event.kind === 'deficit_strength'), false)
  assert.equal(withUnsafeNutrition.snapshots.at(-1)?.strength, withoutNutrition.snapshots.at(-1)?.strength)
})

test('blocked targets never report a protein hit percentage', () => {
  const subject = profile({ birthdate: 'not-a-date' })
  const logs = [
    '2026-08-24', '2026-08-25', '2026-08-26', '2026-08-27', '2026-08-28',
    '2026-08-29', '2026-08-30', '2026-08-31', '2026-09-01', '2026-09-02',
  ].map((date) => nutritionLog(date))
  const assessment = assessBodyState(
    { ...EMPTY_DATA, profile: subject, daily_logs: logs },
    [snapshot()],
  )

  assert.ok(assessment)
  assert.equal(assessment.strengths.some((line) => line.startsWith('Protein was on target')), false)
  assert.equal(assessment.priorities.some((line) => line.startsWith('Protein reached target')), false)
})

test('foreign nutrition cannot earn an owner target synergy', () => {
  const subject = profile()
  const withoutNutrition = computeEngine(strengthDay(subject), day)
  const withForeignNutrition = computeEngine(strengthDay(subject, [
    nutritionLog(day, 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', 2_600, 200),
  ]), day)

  assert.equal(withForeignNutrition.synergies.some((event) => event.kind === 'protein_strength'), false)
  assert.equal(withForeignNutrition.snapshots.at(-1)?.strength, withoutNutrition.snapshots.at(-1)?.strength)
  assert.equal(withForeignNutrition.snapshots.at(-1)?.health, withoutNutrition.snapshots.at(-1)?.health)
})

test('publishable bespoke targets retain their authored nutrition synergy', () => {
  const subject = profile({
    user_id: '9a0fffbc-bb02-40ac-834a-d4e339b32574',
    persona: 'constantine',
    profile_kind: 'bespoke',
    bespoke_protocol_id: 'constantine-v8.5',
    birthdate: 'malformed',
    goal: 'recomp',
  })
  const result = computeEngine(strengthDay(subject, [
    nutritionLog(day, subject.user_id, 2_450, 150),
  ]), day)

  assert.equal(result.synergies.some((event) => event.kind === 'protein_strength'), true)
})

test('foreign training and health cache rows cannot alter the owner brain', () => {
  const subject = profile()
  const clean: AppData = { ...EMPTY_DATA, profile: subject }
  const otherID = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
  const contaminated: AppData = {
    ...clean,
    program_days: [{
      id: 'foreign-upper',
      user_id: otherID,
      program_id: 'foreign-program',
      weekday: 3,
      name: 'Foreign upper',
      day_type: 'upper',
      est_minutes: 90,
      warmup_note: '',
      sort_order: 1,
    }],
    workout_sessions: [{
      id: 'foreign-session',
      user_id: otherID,
      date: day,
      program_day_id: 'foreign-upper',
      is_lite: false,
      is_deload: false,
      is_event_recovery: false,
      completed: true,
      quality_score: 1,
      started_at: `${day}T08:00:00.000Z`,
      completed_at: `${day}T09:30:00.000Z`,
      notes: '',
    }],
    workout_logs: [{
      id: 'foreign-set',
      user_id: otherID,
      session_id: 'foreign-session',
      exercise_id: null,
      exercise_name: 'Foreign press',
      set_no: 1,
      weight_kg: 300,
      reps: 20,
      rir: 0,
      skipped: false,
      override_flag: true,
      created_at: `${day}T08:10:00.000Z`,
    }],
    health_metrics: [{
      id: 'foreign-metric',
      user_id: otherID,
      date: day,
      weight_kg: 130,
      vo2max: 75,
      resting_hr: 35,
    }],
  }

  const cleanResult = computeEngine(clean, day)
  const contaminatedResult = computeEngine(contaminated, day)
  assert.deepEqual(contaminatedResult, cleanResult)
  assert.deepEqual(
    whatYourBodyNeeds(contaminated, contaminatedResult.snapshots),
    whatYourBodyNeeds(clean, cleanResult.snapshots),
  )
})

test('foreign evidence days cannot inflate an owner assessment confidence', () => {
  const subject = profile()
  const foreignID = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
  const dates = [
    '2026-08-24', '2026-08-25', '2026-08-26', '2026-08-27', '2026-08-28',
    '2026-08-29', '2026-08-30', '2026-08-31', '2026-09-01', '2026-09-02',
  ]
  const data: AppData = {
    ...EMPTY_DATA,
    profile: subject,
    workout_sessions: dates.map((date, index) => ({
      id: `foreign-session-${index}`,
      user_id: foreignID,
      date,
      program_day_id: 'foreign-day',
      is_lite: false,
      is_deload: false,
      is_event_recovery: false,
      completed: true,
      quality_score: 1,
      started_at: `${date}T08:00:00.000Z`,
      completed_at: `${date}T09:00:00.000Z`,
      notes: '',
    })),
    health_metrics: dates.map((date, index) => ({
      id: `foreign-metric-${index}`,
      user_id: foreignID,
      date,
      weight_kg: null,
      vo2max: 60,
      resting_hr: 45,
    })),
  }

  assert.equal(assessBodyState(data, [snapshot()])?.confidence, 'Building signal')
})
