import type { ImportedActivity, WorkoutLog, WorkoutSession } from './types.ts'
import { isAPEXWorkoutSourceBundle } from './wearableWorkoutLinking.ts'

export interface WorkoutInsightInput {
  ownerID: string
  from: string
  to: string
  sessions: WorkoutSession[]
  logs: WorkoutLog[]
  importedActivities: ImportedActivity[]
}

export interface WorkoutInsightSummary {
  from: string
  to: string
  workouts: number
  activeDays: number
  durationMinutes: number
  activeEnergyKcal: number | null
  sets: number
  reps: number
  volumeKg: number | null
  distanceKm: number | null
  anniversaryYears: 1 | 5 | 10 | null
}

function inRange(date: string, from: string, to: string): boolean {
  return date >= from && date <= to
}

function validDurationMinutes(startedAt?: string | null, completedAt?: string | null): number | null {
  if (!startedAt || !completedAt) return null
  const start = Date.parse(startedAt)
  const end = Date.parse(completedAt)
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return null
  return Math.max(1, Math.round((end - start) / 60_000))
}

function subtractCalendarYears(isoDate: string, years: number): string | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(isoDate)
  if (!match) return null
  const year = Number(match[1]) - years
  const month = Number(match[2])
  const day = Number(match[3])
  const result = new Date(Date.UTC(year, month - 1, day))
  if (result.getUTCMonth() !== month - 1) result.setUTCDate(0)
  return result.toISOString().slice(0, 10)
}

export function anniversaryYearsForWorkoutRange(
  oldestEvidenceDate: string | null,
  from: string,
  to: string,
): 1 | 5 | 10 | null {
  if (!oldestEvidenceDate || from > to) return null
  for (const years of [10, 5, 1] as const) {
    const boundary = subtractCalendarYears(to, years)
    if (boundary && from <= boundary && oldestEvidenceDate <= boundary) return years
  }
  return null
}

function isVisibleExternal(activity: ImportedActivity, ownerID: string): boolean {
  return activity.user_id === ownerID
    && !activity.hidden_at
    && !isAPEXWorkoutSourceBundle(activity.source_bundle_id)
}

export function workoutInsights(input: WorkoutInsightInput): WorkoutInsightSummary {
  const from = input.from <= input.to ? input.from : input.to
  const to = input.from <= input.to ? input.to : input.from
  const allOwnedSessions = input.sessions.filter((session) => session.user_id === input.ownerID && session.completed)
  const allExternal = input.importedActivities.filter((activity) => isVisibleExternal(activity, input.ownerID))
  const sessions = allOwnedSessions.filter((session) => inRange(session.date, from, to))
  const sessionIDs = new Set(sessions.map((session) => session.id))
  const external = allExternal.filter((activity) => inRange(activity.date, from, to))
  const linkedSessionIDs = new Set(external.flatMap((activity) => (
    activity.apex_workout_session_id && sessionIDs.has(activity.apex_workout_session_id)
      ? [activity.apex_workout_session_id]
      : []
  )))
  const logs = input.logs.filter((entry) => (
    entry.user_id === input.ownerID
    && sessionIDs.has(entry.session_id)
    && !entry.skipped
  ))

  let durationMinutes = external.reduce((total, activity) => (
    total + (Number.isFinite(activity.duration_min) && activity.duration_min > 0 ? activity.duration_min : 0)
  ), 0)
  for (const session of sessions) {
    if (linkedSessionIDs.has(session.id)) continue
    const timestampDuration = validDurationMinutes(session.started_at, session.completed_at)
    if (timestampDuration != null) {
      durationMinutes += timestampDuration
      continue
    }
    const loggedSeconds = logs
      .filter((entry) => entry.session_id === session.id)
      .reduce((total, entry) => total + Math.max(0, entry.duration_seconds ?? 0), 0)
    if (loggedSeconds > 0) durationMinutes += Math.max(1, Math.round(loggedSeconds / 60))
  }

  const energyFacts = external
    .map((activity) => activity.active_energy_kcal)
    .filter((value): value is number => value != null && Number.isFinite(value) && value >= 0)
  const externalDistanceFacts = external
    .map((activity) => activity.distance_km)
    .filter((value): value is number => value != null && Number.isFinite(value) && value >= 0)
  const loggedDistanceFacts = logs
    .filter((entry) => !linkedSessionIDs.has(entry.session_id))
    .map((entry) => entry.distance_meters)
    .filter((value): value is number => value != null && Number.isFinite(value) && value >= 0)

  const reps = logs.reduce((total, entry) => total + Math.max(0, entry.reps ?? 0), 0)
  const volumeFacts = logs.flatMap((entry) => {
    const weight = entry.weight_kg
    const repetitions = entry.reps
    return weight != null && repetitions != null && weight > 0 && repetitions > 0
      ? [weight * repetitions]
      : []
  })
  const activeDates = new Set([
    ...sessions.map((session) => session.date),
    ...external.map((activity) => activity.date),
  ])
  const standaloneExternal = external.filter((activity) => (
    !activity.apex_workout_session_id || !sessionIDs.has(activity.apex_workout_session_id)
  ))
  const oldestEvidenceDate = [...allOwnedSessions.map((session) => session.date), ...allExternal.map((activity) => activity.date)]
    .sort()[0] ?? null

  return {
    from,
    to,
    workouts: sessions.length + standaloneExternal.length,
    activeDays: activeDates.size,
    durationMinutes,
    activeEnergyKcal: energyFacts.length > 0 ? energyFacts.reduce((total, value) => total + value, 0) : null,
    sets: logs.length,
    reps,
    volumeKg: volumeFacts.length > 0 ? volumeFacts.reduce((total, value) => total + value, 0) : null,
    distanceKm: externalDistanceFacts.length + loggedDistanceFacts.length > 0
      ? externalDistanceFacts.reduce((total, value) => total + value, 0)
        + loggedDistanceFacts.reduce((total, value) => total + value, 0) / 1_000
      : null,
    anniversaryYears: anniversaryYearsForWorkoutRange(oldestEvidenceDate, from, to),
  }
}
