import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { EMPTY_DATA, type AppData, type WorkoutSession } from '../src/lib/types.ts'
import { completedWorkoutHistoryForDate } from '../src/lib/completedWorkoutHistory.ts'
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

test('completed workout history is rendered directly below Simple Mode metrics and in phase pages', () => {
  const simple = readFileSync(new URL('../src/pages/SimpleHome.tsx', import.meta.url), 'utf8')
  const phase = readFileSync(new URL('../src/pages/WorkoutSection.tsx', import.meta.url), 'utf8')
  assert.match(simple, /simple-summary-actions[\s\S]*CompletedWorkoutHistoryCards/)
  assert.match(phase, /CompletedWorkoutHistoryCards/)
})
