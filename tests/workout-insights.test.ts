import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import type { ImportedActivity, WorkoutLog, WorkoutSession } from '../src/lib/types.ts'
import {
  anniversaryYearsForWorkoutRange,
  workoutInsights,
} from '../src/lib/workoutInsights.ts'

function session(id: string, overrides: Partial<WorkoutSession> = {}): WorkoutSession {
  return {
    id,
    user_id: overrides.user_id ?? 'owner',
    date: overrides.date ?? '2026-08-29',
    program_day_id: overrides.program_day_id ?? 'day',
    is_lite: false,
    is_deload: false,
    is_event_recovery: false,
    completed: overrides.completed ?? true,
    quality_score: 1,
    started_at: 'started_at' in overrides ? overrides.started_at ?? null : '2026-08-29T10:00:00.000Z',
    completed_at: 'completed_at' in overrides ? overrides.completed_at ?? null : '2026-08-29T11:00:00.000Z',
    notes: '',
  }
}

function log(id: string, sessionId: string, overrides: Partial<WorkoutLog> = {}): WorkoutLog {
  return {
    id,
    user_id: overrides.user_id ?? 'owner',
    session_id: sessionId,
    exercise_id: null,
    exercise_name: overrides.exercise_name ?? 'Squat',
    set_no: overrides.set_no ?? 1,
    weight_kg: 'weight_kg' in overrides ? overrides.weight_kg ?? null : 50,
    reps: 'reps' in overrides ? overrides.reps ?? null : 10,
    rir: null,
    duration_seconds: overrides.duration_seconds ?? null,
    distance_meters: overrides.distance_meters ?? null,
    skipped: overrides.skipped ?? false,
    override_flag: false,
    created_at: '2026-08-29T10:15:00.000Z',
  }
}

function activity(id: string, overrides: Partial<ImportedActivity> = {}): ImportedActivity {
  return {
    id,
    user_id: overrides.user_id ?? 'owner',
    date: overrides.date ?? '2026-08-29',
    kind: overrides.kind ?? 'strength',
    activity: 'Traditional Strength Training',
    duration_min: overrides.duration_min ?? 58,
    source: 'Apple Watch',
    source_bundle_id: overrides.source_bundle_id ?? 'com.apple.health',
    active_energy_kcal: overrides.active_energy_kcal,
    distance_km: overrides.distance_km,
    apex_workout_session_id: overrides.apex_workout_session_id ?? null,
    hidden_at: overrides.hidden_at ?? null,
  }
}

test('linked wearable evidence replaces duration and energy without becoming a second workout', () => {
  const result = workoutInsights({
    ownerID: 'owner',
    from: '2026-08-23',
    to: '2026-08-29',
    sessions: [session('apex')],
    logs: [log('set-1', 'apex'), log('set-2', 'apex', { set_no: 2, weight_kg: 60, reps: 5 })],
    importedActivities: [activity('watch', {
      apex_workout_session_id: 'apex',
      active_energy_kcal: 420,
      distance_km: 1.2,
    })],
  })

  assert.equal(result.workouts, 1)
  assert.equal(result.activeDays, 1)
  assert.equal(result.durationMinutes, 58)
  assert.equal(result.activeEnergyKcal, 420)
  assert.equal(result.sets, 2)
  assert.equal(result.reps, 15)
  assert.equal(result.volumeKg, 800)
  assert.equal(result.distanceKm, 1.2)
})

test('standalone imports count once while hidden, mirrored, foreign, skipped, and out-of-range facts do not', () => {
  const result = workoutInsights({
    ownerID: 'owner',
    from: '2026-08-23',
    to: '2026-08-29',
    sessions: [
      session('apex'),
      session('unfinished', { completed: false }),
      session('foreign', { user_id: 'other' }),
    ],
    logs: [
      log('kept', 'apex'),
      log('skipped', 'apex', { skipped: true }),
      log('foreign-log', 'apex', { user_id: 'other' }),
    ],
    importedActivities: [
      activity('standalone', { active_energy_kcal: 200 }),
      activity('hidden', { hidden_at: '2026-08-29T12:00:00.000Z', active_energy_kcal: 900 }),
      activity('mirror', { source_bundle_id: 'ch.apexperformance.APEX.watchkitapp', active_energy_kcal: 900 }),
      activity('foreign', { user_id: 'other', active_energy_kcal: 900 }),
      activity('old', { date: '2026-08-22', active_energy_kcal: 900 }),
    ],
  })

  assert.equal(result.workouts, 2)
  assert.equal(result.activeEnergyKcal, 200)
  assert.equal(result.sets, 1)
  assert.equal(result.reps, 10)
  assert.equal(result.volumeKg, 500)
})

test('missing optional workout facts stay absent instead of becoming invented zeroes', () => {
  const result = workoutInsights({
    ownerID: 'owner',
    from: '2026-08-29',
    to: '2026-08-29',
    sessions: [session('external', { started_at: null, completed_at: null })],
    logs: [log('timed', 'external', { weight_kg: null, reps: null, duration_seconds: 90 })],
    importedActivities: [],
  })

  assert.equal(result.activeEnergyKcal, null)
  assert.equal(result.distanceKm, null)
  assert.equal(result.volumeKg, null)
  assert.equal(result.durationMinutes, 2)
})

test('anniversary treatment requires both selected range and real evidence tenure', () => {
  assert.equal(anniversaryYearsForWorkoutRange('2016-08-29', '2016-08-29', '2026-08-29'), 10)
  assert.equal(anniversaryYearsForWorkoutRange('2021-08-29', '2021-08-29', '2026-08-29'), 5)
  assert.equal(anniversaryYearsForWorkoutRange('2025-08-29', '2025-08-29', '2026-08-29'), 1)
  assert.equal(anniversaryYearsForWorkoutRange('2016-08-29', '2026-08-22', '2026-08-29'), null)
  assert.equal(anniversaryYearsForWorkoutRange('2026-01-01', '2025-08-29', '2026-08-29'), null)
})

test('web and native surfaces provide range controls and rounded PNG export', () => {
  const web = readFileSync(new URL('../src/components/workout/WorkoutInsightsCard.tsx', import.meta.url), 'utf8')
  const canvas = readFileSync(new URL('../src/lib/workoutInsightsCard.ts', import.meta.url), 'utf8')
  const native = readFileSync(new URL('../ios/APEXNative/APEX/Features/Training/WorkoutInsightsCard.swift', import.meta.url), 'utf8')

  for (const label of ['Day', 'Week', 'Year', 'Custom']) {
    assert.match(web, new RegExp(label))
    assert.match(native, new RegExp(label))
  }
  assert.match(canvas, /canvas\.toBlob/)
  assert.match(canvas, /roundRect/)
  assert.match(native, /ImageRenderer/)
  assert.match(native, /ShareLink/)
})

test('multi-year native insights load complete paginated workout facts', () => {
  const service = readFileSync(new URL('../ios/APEXNative/APEX/Core/Networking/SupabaseService.swift', import.meta.url), 'utf8')
  const dashboard = service.slice(service.indexOf('func loadDashboard()'), service.indexOf('func startRealtime'))

  assert.match(dashboard, /async let workoutSessions = loadAllWorkoutSessions/)
  assert.match(dashboard, /async let workoutLogs = loadAllWorkoutLogs/)
  assert.match(service, /private func loadAllWorkoutSessions[\s\S]*?Self\.collectPaginatedRows/)
  assert.match(service, /private func loadAllWorkoutLogs[\s\S]*?Self\.collectPaginatedRows/)
  assert.doesNotMatch(dashboard, /client\.from\("workout_sessions"\)\.select\(\)\.order\("date", ascending: false\)\.limit\(180\)/)
  assert.doesNotMatch(dashboard, /client\.from\("workout_logs"\)\.select\(\)\.order\("created_at", ascending: false\)\.limit\(2000\)/)
})
