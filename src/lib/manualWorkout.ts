import { differenceInCalendarDays, format, getISODay, parseISO, subDays } from 'date-fns'
import { catalogExerciseByName, type ExerciseCatalogItem } from '../data/exerciseCatalog.ts'
import type { AppData, WorkoutLog, WorkoutSession } from './types'

export const MANUAL_WORKOUT_PREFIX = 'APEX_MANUAL_V1'
const AUTOMATIC_TITLE = '__APEX_AUTOMATIC_TITLE__'

export interface ManualSetDraft {
  id: string
  reps: number
  weightKg: number
}

export interface TreadmillDraft {
  distanceKm: number
  inclineDeg: number
  durationMin: number
}

export interface ManualExerciseDraft {
  id: string
  catalogId: string | null
  canonicalName: string
  sets: ManualSetDraft[]
  treadmill: TreadmillDraft | null
}

export interface ManualWorkoutPreset {
  signature: string
  title: string
  automaticTitle: boolean
  exercises: ManualExerciseDraft[]
  lastUsedDate: string
  timesUsed: number
  sameWeekdayUses: number
  sequenceMatches: number
  reason: 'same-weekday' | 'sequence' | 'recent'
  score: number
}

export interface ManualWorkoutEditorDraft {
  session: WorkoutSession
  title: string
  exercises: ManualExerciseDraft[]
}

export interface ManualExerciseOrderReference {
  sessionId: string
  canonicalName: string
}

export interface ManualExerciseTimelineEntry extends ManualExerciseOrderReference {
  key: string
  session: WorkoutSession
  exercise: ManualExerciseDraft
  firstCreatedAt: string
}

export function manualWorkoutNotes(title: string): string {
  return `${MANUAL_WORKOUT_PREFIX}|${encodeURIComponent(title.trim() || AUTOMATIC_TITLE)}`
}

export function manualWorkoutTitle(notes: string): string | null {
  if (!notes.startsWith(`${MANUAL_WORKOUT_PREFIX}|`)) return null
  try {
    const decoded = decodeURIComponent(notes.slice(MANUAL_WORKOUT_PREFIX.length + 1))
    return !decoded || decoded === AUTOMATIC_TITLE ? 'Workout' : decoded
  } catch {
    return 'Workout'
  }
}

export function manualWorkoutHasAutomaticTitle(notes: string): boolean {
  if (!notes.startsWith(`${MANUAL_WORKOUT_PREFIX}|`)) return false
  try {
    return decodeURIComponent(notes.slice(MANUAL_WORKOUT_PREFIX.length + 1)) === AUTOMATIC_TITLE
  } catch {
    return false
  }
}

export function encodeTreadmillLog(name: string, metrics: TreadmillDraft): string {
  const distance = Math.max(0, metrics.distanceKm)
  const incline = Math.max(0, metrics.inclineDeg)
  const duration = Math.max(0, Math.round(metrics.durationMin))
  return `${name} · ${distance} km · ${incline}° · ${duration} min`
}

export function parseTreadmillLog(value: string): { name: string; metrics: TreadmillDraft } | null {
  const match = value.match(/^(.+?) · ([\d.,]+) km · ([\d.,]+)° · ([\d.,]+) min$/)
  if (!match) return null
  const numbers = match.slice(2).map((part) => Number(part.replace(',', '.')))
  if (numbers.some((number) => !Number.isFinite(number))) return null
  return {
    name: match[1],
    metrics: { distanceKm: numbers[0], inclineDeg: numbers[1], durationMin: numbers[2] },
  }
}

export function baseExerciseName(value: string): string {
  return parseTreadmillLog(value)?.name ?? value
}

export function workoutSignature(exercises: ManualExerciseDraft[]): string {
  return exercises
    .map((exercise) => exercise.catalogId ?? exercise.canonicalName.trim().toLocaleLowerCase('en'))
    .join('>')
}

function draftFromLogs(logs: WorkoutLog[]): ManualExerciseDraft[] {
  const grouped = new Map<string, WorkoutLog[]>()
  const order: string[] = []
  for (const log of [...logs].sort((a, b) => a.created_at.localeCompare(b.created_at) || a.set_no - b.set_no)) {
    const key = baseExerciseName(log.exercise_name)
    if (!grouped.has(key)) order.push(key)
    grouped.set(key, [...(grouped.get(key) ?? []), log])
  }
  return order.map((canonicalName, exerciseIndex) => {
    const rows = grouped.get(canonicalName) ?? []
    const treadmill = rows.map((row) => parseTreadmillLog(row.exercise_name)).find(Boolean) ?? null
    const catalog = catalogExerciseByName(canonicalName)
    return {
      id: `preset-${exerciseIndex}-${catalog?.id ?? canonicalName}`,
      catalogId: catalog?.id ?? null,
      canonicalName,
      treadmill: treadmill?.metrics ?? null,
      sets: treadmill ? [] : rows
        .filter((row) => !row.skipped)
        .sort((a, b) => a.set_no - b.set_no)
        .map((row, setIndex) => ({
          id: `preset-set-${exerciseIndex}-${setIndex}`,
          reps: Math.max(0, row.reps ?? 0),
          weightKg: Math.max(0, row.weight_kg ?? 0),
        })),
    }
  })
}

export function workoutDraftForSession(data: AppData, sessionId: string): ManualExerciseDraft[] {
  return draftFromLogs(data.workout_logs.filter((log) => log.session_id === sessionId))
}

export function manualExerciseOrderKey(sessionId: string, canonicalName: string): string {
  return `${sessionId}:${encodeURIComponent(canonicalName)}`
}

export function manualExerciseTimelineForDate(data: AppData, dateIso: string): ManualExerciseTimelineEntry[] {
  const timeline = manualSessionsForDate(data, dateIso).flatMap((session, sessionIndex) => {
    const sessionLogs = data.workout_logs.filter((log) => log.session_id === session.id)
    const exercises = workoutDraftForSession(data, session.id)
    return exercises.map((exercise, exerciseIndex) => {
      const exerciseLogs = sessionLogs.filter((log) => baseExerciseName(log.exercise_name) === exercise.canonicalName)
      const firstCreatedAt = exerciseLogs
        .map((log) => log.created_at)
        .filter(Boolean)
        .sort((a, b) => a.localeCompare(b))[0]
        ?? session.started_at
        ?? session.completed_at
        ?? `${session.date}T00:00:00.000Z`
      return {
        key: manualExerciseOrderKey(session.id, exercise.canonicalName),
        sessionId: session.id,
        canonicalName: exercise.canonicalName,
        session,
        exercise,
        firstCreatedAt,
        fallbackOrder: sessionIndex * 1_000 + exerciseIndex,
      }
    })
  })

  return timeline
    .sort((a, b) => a.firstCreatedAt.localeCompare(b.firstCreatedAt) || a.fallbackOrder - b.fallbackOrder)
    .map(({ fallbackOrder: _fallbackOrder, ...entry }) => entry)
}

export function resequenceManualWorkoutLogs(
  logs: WorkoutLog[],
  order: ManualExerciseOrderReference[],
): WorkoutLog[] {
  const rank = new Map(order.map((entry, index) => [manualExerciseOrderKey(entry.sessionId, entry.canonicalName), index]))
  const orderedLogs = logs.filter((log) => rank.has(manualExerciseOrderKey(log.session_id, baseExerciseName(log.exercise_name))))
  const validTimes = orderedLogs.map((log) => Date.parse(log.created_at)).filter(Number.isFinite)
  const baseTime = validTimes.length > 0 ? Math.min(...validTimes) : Date.now()

  return logs.map((log) => {
    const index = rank.get(manualExerciseOrderKey(log.session_id, baseExerciseName(log.exercise_name)))
    if (index == null) return log
    const setOffset = Math.max(0, log.set_no - 1) * 100
    return { ...log, created_at: new Date(baseTime + index * 60_000 + setOffset).toISOString() }
  })
}

export function manualWorkoutEditorDraft(data: AppData, sessionId: string): ManualWorkoutEditorDraft | null {
  const session = data.workout_sessions.find((candidate) => candidate.id === sessionId)
  if (!session || manualWorkoutTitle(session.notes) == null) return null
  return {
    session,
    title: manualWorkoutHasAutomaticTitle(session.notes) ? '' : manualWorkoutTitle(session.notes) ?? '',
    exercises: workoutDraftForSession(data, session.id),
  }
}

export function catalogForDraft(exercise: ManualExerciseDraft): ExerciseCatalogItem | null {
  return catalogExerciseByName(exercise.canonicalName)
}

interface SessionDraft {
  session: WorkoutSession
  title: string
  automaticTitle: boolean
  exercises: ManualExerciseDraft[]
  signature: string
}

function manualSessionDrafts(data: AppData): SessionDraft[] {
  return data.workout_sessions
    .filter((session) => session.completed && manualWorkoutTitle(session.notes) != null)
    .map((session) => {
      const exercises = workoutDraftForSession(data, session.id)
      return {
        session,
        title: manualWorkoutTitle(session.notes) ?? 'Workout',
        automaticTitle: manualWorkoutHasAutomaticTitle(session.notes),
        exercises,
        signature: workoutSignature(exercises),
      }
    })
    .filter((entry) => entry.exercises.length > 0 && entry.signature.length > 0)
}

function safeDate(value: string): Date {
  const parsed = parseISO(value)
  return Number.isNaN(parsed.getTime()) ? new Date(0) : parsed
}

/* Presets are learned from completed manual workouts. A recurring workout on
   the same weekday ranks first. When the weekday pattern changes, the workout
   that historically followed yesterday's exercise sequence receives the
   strongest fallback boost. */
export function rankManualWorkoutPresets(data: AppData, dateIso: string): ManualWorkoutPreset[] {
  const sessions = manualSessionDrafts(data).sort((a, b) => a.session.date.localeCompare(b.session.date))
  const targetDate = safeDate(dateIso)
  const weekday = getISODay(targetDate)
  const yesterday = format(subDays(targetDate, 1), 'yyyy-MM-dd')
  const yesterdaySignatures = new Set(sessions.filter((entry) => entry.session.date === yesterday).map((entry) => entry.signature))
  const sequenceCounts = new Map<string, number>()
  for (let index = 1; index < sessions.length; index++) {
    const previous = sessions[index - 1]
    const current = sessions[index]
    if (!yesterdaySignatures.has(previous.signature)) continue
    const gap = differenceInCalendarDays(safeDate(current.session.date), safeDate(previous.session.date))
    if (gap >= 0 && gap <= 2) sequenceCounts.set(current.signature, (sequenceCounts.get(current.signature) ?? 0) + 1)
  }

  const grouped = new Map<string, SessionDraft[]>()
  for (const entry of sessions) grouped.set(entry.signature, [...(grouped.get(entry.signature) ?? []), entry])

  return [...grouped.entries()].map(([signature, uses]) => {
    const recent = uses.at(-1)!
    const sameWeekdayUses = uses.filter((entry) => getISODay(safeDate(entry.session.date)) === weekday).length
    const sequenceMatches = sequenceCounts.get(signature) ?? 0
    const ageDays = Math.max(0, differenceInCalendarDays(targetDate, safeDate(recent.session.date)))
    const recency = Math.max(0, 30 - ageDays)
    const score = sameWeekdayUses * 45 + sequenceMatches * 60 + uses.length * 8 + recency
    return {
      signature,
      title: recent.title,
      automaticTitle: recent.automaticTitle,
      exercises: recent.exercises,
      lastUsedDate: recent.session.date,
      timesUsed: uses.length,
      sameWeekdayUses,
      sequenceMatches,
      reason: sameWeekdayUses > 0 ? 'same-weekday' as const : sequenceMatches > 0 ? 'sequence' as const : 'recent' as const,
      score,
    }
  }).sort((a, b) => b.score - a.score || b.lastUsedDate.localeCompare(a.lastUsedDate)).slice(0, 6)
}

export function manualSessionsForDate(data: AppData, dateIso: string): WorkoutSession[] {
  return data.workout_sessions
    .filter((session) => session.completed && session.date === dateIso && manualWorkoutTitle(session.notes) != null)
    .sort((a, b) => {
      const left = a.started_at ?? a.completed_at ?? `${a.date}T00:00:00.000Z`
      const right = b.started_at ?? b.completed_at ?? `${b.date}T00:00:00.000Z`
      return left.localeCompare(right) || a.id.localeCompare(b.id)
    })
}
