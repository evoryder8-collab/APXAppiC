import type { AppData, WorkoutSession } from './types.ts'
import type { OwnerBoundMutationWrite } from './ownerBoundMutation.ts'
import { activityCatalogMap, blockFromActivityLog, netKcalForBlock } from './activity.ts'
import { zonedClock, zonedDateTimeToIso } from './mealTiming.ts'
import { isWorkoutDate, withWorkoutTimingMetadata, workoutGeneratedActivityIDs } from './workoutTimingMetadata.ts'

export interface WorkoutTimingDraft {
  date: string
  startedLocal: string
  finishedLocal: string
  includeStart: boolean
}

export class WorkoutTimingValidationError extends Error {
  constructor() { super('Choose a valid workout date and time.') }
}

export function workoutLocalDateTime(instant: string | null | undefined, timeZone: string): string {
  if (!instant || !Number.isFinite(Date.parse(instant))) return ''
  const clock = zonedClock(instant, timeZone)
  return `${clock.date}T${clock.time}`
}

export function workoutTimingDraft(session: WorkoutSession, timeZone: string): WorkoutTimingDraft {
  const startedLocal = workoutLocalDateTime(session.started_at, timeZone)
  const finishedLocal = workoutLocalDateTime(session.completed_at, timeZone)
  const anchorDate = (startedLocal || finishedLocal).slice(0, 10)
  return shiftWorkoutTimingDraftDate({ date: isWorkoutDate(anchorDate) ? anchorDate : session.date,
    startedLocal, finishedLocal, includeStart: startedLocal.length > 0 }, session.date)
}

export function shiftWorkoutTimingDraftDate(draft: WorkoutTimingDraft, date: string): WorkoutTimingDraft {
  if (!isWorkoutDate(draft.date) || !isWorkoutDate(date)) return { ...draft, date }
  const delta = Date.parse(`${date}T12:00Z`) - Date.parse(`${draft.date}T12:00Z`)
  const shift = (value: string): string => {
    if (!isWorkoutDate(value.slice(0, 10))) return value
    return new Date(Date.parse(`${value.slice(0, 10)}T12:00Z`) + delta).toISOString().slice(0, 10) + value.slice(10)
  }
  return { ...draft, date, startedLocal: shift(draft.startedLocal), finishedLocal: shift(draft.finishedLocal) }
}

function editedInstant(value: string, timeZone: string, original?: string | null): string {
  const match = /^(\d{4}-\d{2}-\d{2})T([0-2]\d:[0-5]\d)$/.exec(value)
  if (!match || !isWorkoutDate(match[1]) || Number(match[2].slice(0, 2)) > 23) throw new WorkoutTimingValidationError()
  // An untouched value retains seconds and the precise side of a repeated DST hour.
  if (original && workoutLocalDateTime(original, timeZone) === value) return original
  const instant = zonedDateTimeToIso(match[1], match[2], timeZone)
  if (workoutLocalDateTime(instant, timeZone) !== value) throw new WorkoutTimingValidationError()
  return instant
}

export function stageWorkoutTimingEdit(current: AppData, input: {
  ownerID: string; sessionID: string; draft: WorkoutTimingDraft; timeZone: string; now?: Date
}): { data: AppData; writes: OwnerBoundMutationWrite[]; result: WorkoutSession } {
  const { ownerID, sessionID, draft, timeZone } = input
  const now = input.now ?? new Date()
  const session = current.workout_sessions.find((row) => row.id === sessionID && row.user_id === ownerID && row.completed)
  if ((current.profile?.user_id ?? current.settings?.user_id) !== ownerID || !session) throw new Error('Workout is no longer available for this account.')
  if (!isWorkoutDate(draft.date)) throw new WorkoutTimingValidationError()
  const finishedAt = editedInstant(draft.finishedLocal, timeZone, session.completed_at)
  const startedAt = draft.includeStart ? editedInstant(draft.startedLocal, timeZone, session.started_at) : null
  const finish = Date.parse(finishedAt)
  const start = startedAt ? Date.parse(startedAt) : null
  const anchorDay = zonedClock(startedAt ?? finishedAt, timeZone).date
  if (draft.date !== anchorDay || finish > now.getTime() + 60_000 || (start != null && start > finish)) throw new WorkoutTimingValidationError()
  const corrected: WorkoutSession = { ...session, date: draft.date, started_at: startedAt, completed_at: finishedAt,
    notes: withWorkoutTimingMetadata(session.notes, session.date) }

  const ownedLogs = current.workout_logs.filter((row) => row.user_id === ownerID && row.session_id === sessionID)
  const oldFinish = session.completed_at ? Date.parse(session.completed_at) : NaN
  const logAnchors = ownedLogs.map((row) => Date.parse(row.created_at)).filter(Number.isFinite)
  const oldAnchor = Number.isFinite(oldFinish) ? oldFinish : logAnchors.length ? Math.max(...logAnchors) : finish
  const delta = finish - oldAnchor
  const shifted = (value: string): string => Number.isFinite(Date.parse(value))
    ? new Date(Date.parse(value) + delta).toISOString() : value
  const logs = ownedLogs.map((row) => ({ ...row, created_at: shifted(row.created_at) }))
  const generatedIDs = new Set(workoutGeneratedActivityIDs(session))
  const generated = current.activity_logs.filter((row) => row.user_id === ownerID
    && row.source === 'workout_module' && generatedIDs.has(row.id))
  const elapsedMinutes = start == null ? null : Math.floor((finish - start) / 60_000)
  const positiveDuration = (value: number | null): number => value != null && Number.isFinite(value) && value > 0 ? value : 0
  const positiveMinutes = generated.reduce((sum, row) => sum + positiveDuration(row.duration_min), 0)
  const updatesDuration = elapsedMinutes != null && (generated.length === 1 || positiveMinutes > 0)
  const catalog = activityCatalogMap(current.activity_types)
  let allocated = 0
  const activities = generated.map((row, index) => {
    let correctedDuration = row.duration_min
    if (updatesDuration) {
      correctedDuration = index === generated.length - 1 ? elapsedMinutes - allocated
        : Math.floor(elapsedMinutes * positiveDuration(row.duration_min) / positiveMinutes)
      allocated += correctedDuration
    }
    const canEstimate = updatesDuration && row.watch_kcal == null && correctedDuration != null && Number.isFinite(correctedDuration) && current.profile
      && Number.isFinite(current.profile.weight_kg) && current.profile.weight_kg > 0 && catalog.has(row.type_id)
    const computed = canEstimate ? Math.round(netKcalForBlock({ ...blockFromActivityLog(row, catalog),
      durationMin: correctedDuration, watchKcal: null }, current.profile!.weight_kg, catalog)) : row.computed_kcal
    return { ...row, date: draft.date, duration_min: correctedDuration, computed_kcal: computed,
      created_at: shifted(row.created_at), updated_at: now.toISOString() }
  })
  const logByID = new Map(logs.map((row) => [row.id, row]))
  const activityByID = new Map(activities.map((row) => [row.id, row]))
  const writes: OwnerBoundMutationWrite[] = [{ ownerID, table: 'workout_sessions', type: 'upsert', payload: { ...corrected } }]
  if (logs.length) writes.push({ ownerID, table: 'workout_logs', type: 'upsert', payload: logs.map((row) => ({ ...row })) })
  if (activities.length) writes.push({ ownerID, table: 'activity_logs', type: 'upsert', payload: activities.map((row) => ({ ...row })) })
  return { data: { ...current,
    workout_sessions: current.workout_sessions.map((row) => row.id === sessionID && row.user_id === ownerID ? corrected : row),
    workout_logs: current.workout_logs.map((row) => row.user_id === ownerID ? logByID.get(row.id) ?? row : row),
    activity_logs: current.activity_logs.map((row) => row.user_id === ownerID ? activityByID.get(row.id) ?? row : row),
  }, writes, result: corrected }
}

/** Existing dayline finish controls use the same owner-bound correction. */
export function stageWorkoutFinishEdit(current: AppData, input: {
  ownerID: string; sessionID: string; completedAt: string; timeZone: string; now?: Date
}): ReturnType<typeof stageWorkoutTimingEdit> {
  const session = current.workout_sessions.find((row) => row.id === input.sessionID && row.user_id === input.ownerID && row.completed)
  if (!session) throw new Error('Workout is no longer available for this account.')
  const draft = workoutTimingDraft(session, input.timeZone)
  draft.finishedLocal = workoutLocalDateTime(input.completedAt, input.timeZone)
  if (!draft.includeStart) draft.date = draft.finishedLocal.slice(0, 10)
  return stageWorkoutTimingEdit(current, { ...input, draft })
}
