import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { EMPTY_DATA, type AppData, type WorkoutLog, type WorkoutSession } from '../src/lib/types.ts'
import {
  collapsedWorkoutDeleteTrayVisible,
  completedWorkoutDeletionPlan,
  completedWorkoutHistoryForDate,
} from '../src/lib/completedWorkoutHistory.ts'
import { manualWorkoutNotes } from '../src/lib/manualWorkout.ts'

function session(overrides: Partial<WorkoutSession> & Pick<WorkoutSession, 'id' | 'date' | 'program_day_id'>): WorkoutSession {
  return {
    id: overrides.id,
    user_id: overrides.user_id ?? 'owner',
    date: overrides.date,
    program_day_id: overrides.program_day_id,
    is_lite: false,
    is_deload: false,
    is_event_recovery: false,
    completed: overrides.completed ?? true,
    quality_score: 1,
    started_at: overrides.started_at ?? `${overrides.date}T08:00:00.000Z`,
    completed_at: overrides.completed_at ?? `${overrides.date}T09:00:00.000Z`,
    notes: overrides.notes ?? 'Completed in tracked mode',
  }
}

function log(id: string, sessionId: string, userId = 'owner'): WorkoutLog {
  return {
    id, user_id: userId, session_id: sessionId, exercise_id: null,
    exercise_name: 'Front Lunge', set_no: 1, weight_kg: 25, reps: 12, rir: 2,
    skipped: false, override_flag: false, created_at: '2026-08-26T08:15:00.000Z',
  }
}

test('history returns every completed quick and tracked workout on the date, independent of the active plan day', () => {
  const tracked = session({
    id: 'tracked', date: '2026-08-26', program_day_id: 'old-generated-day',
    completed_at: '2026-08-26T09:00:00.000Z',
  })
  const quick = session({
    id: 'quick', date: '2026-08-26', program_day_id: 'custom-day',
    notes: manualWorkoutNotes('Lunch break lift'),
    completed_at: '2026-08-26T12:00:00.000Z',
  })
  const incomplete = session({
    id: 'unfinished', date: '2026-08-26', program_day_id: 'active-day', completed: false,
  })
  const otherDate = session({
    id: 'yesterday', date: '2026-08-25', program_day_id: 'active-day',
  })
  const foreign = session({
    id: 'foreign', user_id: 'someone-else', date: '2026-08-26', program_day_id: 'active-day',
  })
  const data: AppData = {
    ...EMPTY_DATA,
    profile: {
      id: 'profile', user_id: 'owner', persona: 'constantine', display_name: 'Owner', sex: 'male',
      weight_kg: 80, body_fat_pct: 15, custom_bmr: null, height_cm: 180, birthdate: '1990-01-01',
      activity_level: 'moderate', goal: 'maintain', target_kcal: null, target_protein_g: null,
      target_fat_g: null, target_carbs_g: null, training_time: '18:00', baseline_date: '2026-01-01',
      profile_note: '', seed_version: 1, calibration_k: 1, calibration_history: [],
      updated_at: '2026-08-26T00:00:00.000Z',
    },
    program_days: [{
      id: 'old-generated-day', user_id: 'owner', program_id: 'program', weekday: 3,
      name: 'Tracked legs', day_type: 'legs_a', est_minutes: 45, warmup_note: '', sort_order: 0,
    }],
    workout_sessions: [tracked, quick, incomplete, otherDate, foreign],
  }

  const history = completedWorkoutHistoryForDate(data, '2026-08-26')
  assert.deepEqual(history.map((item) => item.session.id), ['quick', 'tracked'])
  assert.equal(history[0]?.title, 'Lunch break lift')
  assert.equal(history[0]?.isQuickLog, true)
  assert.equal(history[1]?.title, 'Tracked legs')
  assert.equal(history[1]?.isQuickLog, false)
})

test('recent history crosses calendar dates while remaining owner-scoped and bounded', () => {
  const data: AppData = {
    ...EMPTY_DATA,
    settings: {
      user_id: 'owner',
      theme: 'dark',
      language: 'en',
      addons: { endurance1: false, endurance2: false, endurance3: false },
    },
    workout_sessions: [
      session({ id: 'newest', date: '2026-08-27', program_day_id: 'day', completed_at: '2026-08-27T19:00:00.000Z' }),
      session({ id: 'older', date: '2026-08-25', program_day_id: 'day', completed_at: '2026-08-25T19:00:00.000Z' }),
      session({ id: 'foreign', user_id: 'someone-else', date: '2026-08-28', program_day_id: 'day' }),
    ],
  }

  assert.deepEqual(
    completedWorkoutHistoryForDate(data, undefined, 1).map((item) => item.session.id),
    ['newest'],
  )
})

test('unbounded recent history returns every owned completed workout instead of hiding older receipts', () => {
  const workouts = Array.from({ length: 10 }, (_, index) => session({
    id: `workout-${index + 1}`,
    date: `2026-08-${String(index + 1).padStart(2, '0')}`,
    program_day_id: 'day',
    completed_at: `2026-08-${String(index + 1).padStart(2, '0')}T19:00:00.000Z`,
  }))
  const data: AppData = {
    ...EMPTY_DATA,
    settings: {
      user_id: 'owner',
      theme: 'dark',
      language: 'en',
      addons: { endurance1: false, endurance2: false, endurance3: false },
    },
    workout_sessions: workouts,
  }

  const history = completedWorkoutHistoryForDate(data)

  assert.equal(history.length, 10)
  assert.deepEqual(history.map((item) => item.session.id), workouts.toReversed().map((item) => item.id))
})

test('completed workout history is rendered without a visibility cap below Simple Mode metrics and in phase pages', () => {
  const simple = readFileSync(new URL('../src/pages/SimpleHome.tsx', import.meta.url), 'utf8')
  const phase = readFileSync(new URL('../src/pages/WorkoutSection.tsx', import.meta.url), 'utf8')
  const nativeSimple = readFileSync(new URL('../ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift', import.meta.url), 'utf8')
  const nativePhase = readFileSync(new URL('../ios/APEXNative/APEX/Features/Training/TrainingProgramView.swift', import.meta.url), 'utf8')
  assert.match(simple, /simple-summary-actions[\s\S]*CompletedWorkoutHistoryCards/)
  assert.match(phase, /CompletedWorkoutHistoryCards/)
  assert.match(simple, /CompletedWorkoutHistoryCards date=\{undefined\} accent=\{ACCENTS\.teal\}/)
  assert.match(phase, /CompletedWorkoutHistoryCards date=\{undefined\} accent=\{accent\} includeQuickLogs=\{false\}/)
  assert.doesNotMatch(simple, /CompletedWorkoutHistoryCards date=\{undefined\} limit=/)
  assert.doesNotMatch(phase, /CompletedWorkoutHistoryCards date=\{undefined\} limit=/)
  assert.match(nativeSimple, /CompletedWorkoutHistoryCards\(date: nil, accent: APEXColor\.teal\)/)
  assert.match(nativePhase, /CompletedWorkoutHistoryCards\(date: nil, accent: accent\)/)
  assert.doesNotMatch(nativeSimple, /CompletedWorkoutHistoryCards\(date: nil,[^\n]*limit:/)
  assert.doesNotMatch(nativePhase, /CompletedWorkoutHistoryCards\(date: nil,[^\n]*limit:/)
})

test("Nutrition Today's Activities reuses the same date-owned finished workout receipts", () => {
  const nutrition = readFileSync(new URL('../src/pages/Nutrition.tsx', import.meta.url), 'utf8')
  const activities = readFileSync(new URL('../src/components/TodaysActivities.tsx', import.meta.url), 'utf8')
  const native = readFileSync(new URL('../ios/APEXNative/APEX/Features/Nutrition/NutritionView.swift', import.meta.url), 'utf8')

  assert.match(nutrition, /<TodaysActivities[\s\S]*date=\{selectedLogDate\}/)
  assert.match(activities, /<CompletedWorkoutHistoryCards date=\{date\}/)
  assert.match(native, /TodaysActivitiesPanel\([\s\S]*CompletedWorkoutHistoryCards\(\s*date: date\.apexDateKey/)
})

test('deleting a finished workout targets the owned session and all of its owned set rows only', () => {
  const owned = session({ id: 'owned', date: '2026-08-26', program_day_id: 'day' })
  const foreign = session({ id: 'foreign', user_id: 'someone-else', date: '2026-08-26', program_day_id: 'day' })
  const data: AppData = {
    ...EMPTY_DATA,
    profile: {
      id: 'profile', user_id: 'owner', persona: 'constantine', display_name: 'Owner', sex: 'male',
      weight_kg: 80, body_fat_pct: 15, custom_bmr: null, height_cm: 180, birthdate: '1990-01-01',
      activity_level: 'moderate', goal: 'maintain', target_kcal: null, target_protein_g: null,
      target_fat_g: null, target_carbs_g: null, training_time: '18:00', baseline_date: '2026-01-01',
      profile_note: '', seed_version: 1, calibration_k: 1, calibration_history: [],
      updated_at: '2026-08-26T00:00:00.000Z',
    },
    workout_sessions: [owned, foreign],
    workout_logs: [log('set-a', 'owned'), log('set-b', 'owned'), log('foreign-set', 'owned', 'someone-else')],
  }

  assert.deepEqual(completedWorkoutDeletionPlan(data, 'owned'), {
    sessionId: 'owned',
    logIds: ['set-a', 'set-b'],
  })
  assert.equal(completedWorkoutDeletionPlan(data, 'foreign'), null)
})

test('a collapsed workout delete tray does not exist until a deliberate left swipe reveals it', () => {
  assert.equal(collapsedWorkoutDeleteTrayVisible(false, 0), false)
  assert.equal(collapsedWorkoutDeleteTrayVisible(false, 18), false)
  assert.equal(collapsedWorkoutDeleteTrayVisible(false, -1), true)
  assert.equal(collapsedWorkoutDeleteTrayVisible(true, -88), false)
})

test('expanded finished-workout cards show the receipt inline with one edit action and confirmed deletion', () => {
  const cards = readFileSync(new URL('../src/components/workout/CompletedWorkoutHistoryCards.tsx', import.meta.url), 'utf8')
  assert.match(cards, /workoutLogFactSummary/)
  assert.match(cards, /Delete this finished workout\?/)
  assert.match(cards, /onPointerDown/)
  assert.match(cards, /collapsedWorkoutDeleteTrayVisible\(open, swipeOffset\)/)
  assert.match(cards, />\{t\('Edit receipt'\)\}</)
  assert.doesNotMatch(cards, /View & edit receipt|Edit workout structure/)
})
