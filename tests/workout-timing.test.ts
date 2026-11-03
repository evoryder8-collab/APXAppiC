import assert from 'node:assert/strict'
import test from 'node:test'
import { buildSeedData } from '../src/data/seed.ts'
import { activityLogId } from '../src/lib/ids.ts'
import { manualWorkoutNotes, manualWorkoutTitle, manualWorkoutHasAutomaticTitle } from '../src/lib/manualWorkout.ts'
import { completedWorkoutDeletionPlan, finishedWorkoutHistoryForDate } from '../src/lib/completedWorkoutHistory.ts'
import { workoutInsights } from '../src/lib/workoutInsights.ts'
import { timedWorkout } from '../src/lib/mealTiming.ts'
import { recordedWorkoutQuality } from '../src/lib/performedWorkoutAttribution.ts'
import { buildReport } from '../src/lib/exportReport.ts'
import * as sessionModel from '../src/lib/workoutSession.ts'
import * as timing from '../src/lib/workoutTiming.ts'
import type { ActivityLog, AppData, ImportedActivity, WorkoutLog, WorkoutSession } from '../src/lib/types.ts'

const owner = '10000000-0000-4000-8000-000000000085'
const originalDate = '2026-10-14'
const date = '2026-11-01'
const now = new Date('2026-11-03T20:00:00Z')
const timeZone = 'Europe/Zurich'
const receipt: WorkoutSession = {
  id: 'receipt', user_id: owner, date: originalDate, program_day_id: 'retired-day',
  is_lite: false, is_deload: false, is_event_recovery: false, completed: true,
  quality_score: 1, started_at: '2026-10-14T10:00:00Z', completed_at: '2026-10-14T11:00:00Z', notes: manualWorkoutNotes('Legs & glutes'),
}
const wearable: ImportedActivity = {
  id: 'wearable', user_id: owner, date: originalDate, kind: 'strength', activity: 'Strength training',
  source: 'Apple Watch', healthkit_workout_id: 'health-uuid', source_bundle_id: 'com.apple.workout',
  started_at: receipt.started_at, ended_at: receipt.completed_at, duration_min: 60,
  active_energy_kcal: 300, apex_workout_session_id: receipt.id,
}
const log: WorkoutLog = {
  id: 'set-one', user_id: owner, session_id: receipt.id, exercise_id: null, exercise_name: 'Goblet Squat',
  set_no: 1, weight_kg: 20, reps: 10, rir: 2, skipped: false, override_flag: false,
  created_at: '2026-10-14T11:00:00.001Z',
}
function fixture(): AppData {
  const activity = (suffix: string, duration: number): ActivityLog => ({
    id: activityLogId(originalDate, owner, `workout:${receipt.id}${suffix}`), user_id: owner, date: originalDate,
    type_id: suffix ? 'focus-hiit' : 'apex-strength', quantity: 1, duration_min: duration,
    distance_km: null, watch_kcal: null, computed_kcal: 120, source: 'workout_module', reconciled: true,
    created_at: receipt.completed_at!, updated_at: receipt.completed_at!,
  })
  return { ...buildSeedData(owner, 'constantine'), workout_sessions: [receipt],
    workout_logs: [log, { ...log, id: 'set-two', set_no: 2, created_at: '2026-10-14T11:00:00.101Z' }],
    imported_activities: [wearable], activity_logs: [activity('', 40), activity(':focus-t25', 20)] }
}

test('private timing metadata never leaks into Quick Log titles and survives subsequent title edits', () => {
  const suffix = `\nFITR_WORKOUT_TIMING_V1|${originalDate}`
  assert.equal(manualWorkoutTitle(`${manualWorkoutNotes('Legs & glutes')}${suffix}`), 'Legs & glutes')
  assert.ok(manualWorkoutHasAutomaticTitle(`${manualWorkoutNotes('')}${suffix}`))
  assert.equal(manualWorkoutNotes('Updated title', `${receipt.notes}${suffix}`), `${manualWorkoutNotes('Updated title')}${suffix}`)
})

test('a moved receipt keeps its linked wearable once in history and insights without rewriting Health', () => {
  const data = fixture()
  data.workout_sessions = [{ ...receipt, date }]
  assert.deepEqual(finishedWorkoutHistoryForDate(data, originalDate), [])
  const moved = finishedWorkoutHistoryForDate(data, date)
  assert.equal(moved.length, 1)
  assert.equal(moved[0].kind, 'apex')
  if (moved[0].kind === 'apex') assert.equal(moved[0].linkedWearable?.id, wearable.id)
  for (const [from, expectedCount] of [[originalDate, 0], [date, 1]] as const) {
    const insights = workoutInsights({ ownerID: owner, from, to: from, sessions: data.workout_sessions,
      logs: data.workout_logs, importedActivities: data.imported_activities })
    assert.equal(insights.workouts, expectedCount)
    assert.equal(insights.activeDays, expectedCount)
    if (expectedCount) assert.equal(insights.activeEnergyKcal, 300)
  }
  assert.equal(data.imported_activities[0], wearable)
})

test('timing edits atomically move the same receipt, set and generated activity IDs while preserving facts and original identity', () => {
  assert.equal(typeof timing.stageWorkoutTimingEdit, 'function')
  const data = fixture()
  const draft = { date, startedLocal: `${date}T12:00`, finishedLocal: `${date}T13:30`, includeStart: true }
  const changed = timing.stageWorkoutTimingEdit(data, { ownerID: owner, sessionID: receipt.id, draft, timeZone, now })
  const saved = changed.data.workout_sessions[0]
  assert.equal(saved.id, receipt.id)
  assert.equal(saved.date, date)
  assert.equal(saved.started_at, '2026-11-01T11:00:00.000Z')
  assert.equal(saved.completed_at, '2026-11-01T12:30:00.000Z')
  assert.equal(manualWorkoutTitle(saved.notes), 'Legs & glutes')
  assert.ok(saved.notes.endsWith(`\nFITR_WORKOUT_TIMING_V1|${originalDate}`))
  assert.deepEqual(changed.data.workout_logs.map((item) => item.id), ['set-one', 'set-two'])
  assert.equal(changed.data.workout_logs[0].created_at, '2026-11-01T12:30:00.001Z')
  assert.equal(changed.data.workout_logs[1].created_at, '2026-11-01T12:30:00.101Z')
  assert.equal(changed.data.workout_logs[0].weight_kg, 20)
  assert.equal(changed.data.workout_logs[0].reps, 10)
  assert.deepEqual(changed.data.activity_logs.map((item) => item.id), data.activity_logs.map((item) => item.id))
  assert.deepEqual(changed.data.activity_logs.map((item) => item.duration_min), [60, 30])
  assert.ok(changed.data.activity_logs.every((item) => item.date === date))
  assert.deepEqual(completedWorkoutDeletionPlan(changed.data, receipt.id)?.activityLogIds, data.activity_logs.map((item) => item.id))
  assert.equal(changed.data.imported_activities, data.imported_activities)
  assert.ok(changed.writes.every((write) => write.ownerID === owner && write.table !== 'imported_activities'))
  assert.equal(timedWorkout(saved, timeZone)?.completedTime, '13:30')

  const second = timing.stageWorkoutTimingEdit(changed.data, { ownerID: owner, sessionID: receipt.id,
    draft: { ...draft, date: '2026-11-02', startedLocal: '', finishedLocal: '2026-11-02T13:30', includeStart: false }, timeZone, now })
  assert.equal(second.data.workout_sessions[0].started_at, null)
  assert.ok(second.data.workout_sessions[0].notes.endsWith(`\nFITR_WORKOUT_TIMING_V1|${originalDate}`))
  assert.deepEqual(second.data.activity_logs.map((item) => item.duration_min), [60, 30], 'No start means no invented duration')
  assert.deepEqual(completedWorkoutDeletionPlan(second.data, receipt.id)?.activityLogIds, data.activity_logs.map((item) => item.id))
  assert.throws(() => timing.stageWorkoutTimingEdit(data, { ownerID: 'foreign', sessionID: receipt.id, draft, timeZone, now }))
  assert.equal(data.workout_sessions[0], receipt)

  const measured = fixture()
  measured.activity_logs[0] = { ...measured.activity_logs[0], watch_kcal: 233, computed_kcal: 233 }
  const measuredEdit = timing.stageWorkoutTimingEdit(measured, { ownerID: owner, sessionID: receipt.id, draft, timeZone, now })
  assert.equal(measuredEdit.data.activity_logs[0].watch_kcal, 233)
  assert.equal(measuredEdit.data.activity_logs[0].computed_kcal, 233, 'A corrected clock cannot replace measured wearable energy')

  const finishOnly = timing.stageWorkoutFinishEdit(data, { ownerID: owner, sessionID: receipt.id,
    completedAt: '2026-10-14T11:30:00Z', timeZone, now })
  assert.equal(finishOnly.result.completed_at, '2026-10-14T11:30:00.000Z')
  assert.equal(finishOnly.data.workout_logs[0].created_at, '2026-10-14T11:30:00.001Z')
  assert.equal(finishOnly.data.imported_activities, data.imported_activities)
})

test('timing edits reject invalid chronology, future finishes and nonexistent DST times; date changes preserve local clocks', () => {
  assert.equal(typeof timing.stageWorkoutTimingEdit, 'function')
  const draft = { date, startedLocal: `${date}T12:00`, finishedLocal: `${date}T13:30`, includeStart: true }
  for (const invalid of [
    { ...draft, date: '2026-02-30' }, { ...draft, startedLocal: `${date}T14:00` },
    { ...draft, date: '2026-11-02' },
    { ...draft, finishedLocal: '2026-11-04T12:00' }, { ...draft, finishedLocal: '2026-03-29T02:30' },
  ]) assert.throws(() => timing.stageWorkoutTimingEdit(fixture(), { ownerID: owner, sessionID: receipt.id, draft: invalid, timeZone, now }))
  assert.deepEqual(timing.shiftWorkoutTimingDraftDate(draft, '2026-11-02'), {
    ...draft, date: '2026-11-02', startedLocal: '2026-11-02T12:00', finishedLocal: '2026-11-02T13:30',
  })
})

test('timing metadata stays private in human reports and retains explicit external-completion attribution', () => {
  const data = fixture()
  const notes = `Completed externally from the FITR MAX guided player\nFITR_WORKOUT_TIMING_V1|${originalDate}`
  data.workout_sessions = [{ ...receipt, notes, quality_score: 0 }]
  assert.equal(recordedWorkoutQuality(data.workout_sessions[0], [{ ...log, reps: null, weight_kg: null }]), 1)
  const report = buildReport(data, 'main', originalDate, originalDate)
  assert.ok(report.includes('Completed externally from the FITR MAX guided player'))
  assert.ok(!report.includes('FITR_WORKOUT_TIMING_V1'))
})

test('early-morning and overnight receipts remain on their explicitly assigned workout day', () => {
  const early = { ...receipt, date, started_at: `${date}T00:30:00+01:00`, completed_at: `${date}T01:00:00+01:00` }
  assert.equal(timedWorkout(early, timeZone)?.completedTime, '01:00')
  assert.equal(timedWorkout(early, timeZone)?.startedTime, '00:30')
  const overnight = { ...early, started_at: `${date}T23:30:00+01:00`, completed_at: '2026-11-02T04:00:00+01:00' }
  assert.equal(timedWorkout(overnight, timeZone)?.completedTime, '04:00')
})

test('historical receipt editor keeps its saved day and recovered finished drafts keep their original completion instant', () => {
  const savedToday = { ...receipt, started_at: '2026-11-02T22:30:00Z', completed_at: '2026-11-02T23:30:00Z' }
  assert.deepEqual(timing.workoutTimingDraft(savedToday, timeZone), {
    date: originalDate, startedLocal: `${originalDate}T23:30`, finishedLocal: '2026-10-15T00:30', includeStart: true,
  })
  assert.equal(typeof sessionModel.restoredPlayerCompletedAt, 'function')
  assert.equal(sessionModel.restoredPlayerCompletedAt(true, receipt.completed_at, now), receipt.completed_at)
  assert.equal(sessionModel.restoredPlayerCompletedAt(false, receipt.completed_at, now), null)
  assert.equal(sessionModel.restoredPlayerCompletedAt(true, undefined, now), null, 'An older draft does not invent a finish from its retry time')
  const legacy = sessionModel.buildSessionRecords({ sessionId: receipt.id, userId: owner, date: originalDate,
    programDayId: 'retired-day', isLite: false, isDeload: false, isEventRecovery: false, qualityScore: 1,
    startedAt: receipt.started_at!, completedAt: null, exercises: [] })
  assert.equal(legacy.session.completed_at, null)
})
