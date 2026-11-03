import { activityLogId } from './ids.ts'
import type { WorkoutSession } from './types.ts'

const TIMING_LINE = /\nFITR_WORKOUT_TIMING_V1\|(\d{4}-\d{2}-\d{2})(?=\n|$)/g

export function isWorkoutDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const instant = new Date(`${value}T12:00:00.000Z`)
  return Number.isFinite(instant.getTime()) && instant.toISOString().slice(0, 10) === value
}

export function workoutTimingMetadataDate(notes: string): string | null {
  for (const match of notes.matchAll(TIMING_LINE)) if (isWorkoutDate(match[1])) return match[1]
  return null
}

export function withoutWorkoutTimingMetadata(notes: string): string {
  return notes.replace(TIMING_LINE, (line, date: string) => isWorkoutDate(date) ? '' : line)
}

export function withWorkoutTimingMetadata(notes: string, originalDate: string): string {
  return `${withoutWorkoutTimingMetadata(notes)}\nFITR_WORKOUT_TIMING_V1|${workoutTimingMetadataDate(notes) ?? originalDate}`
}

export function workoutGeneratedActivityIDs(session: Pick<WorkoutSession, 'id' | 'user_id' | 'date' | 'notes'>): string[] {
  const originalDate = workoutTimingMetadataDate(session.notes) ?? session.date
  return ['', ':focus-t25'].map((suffix) => activityLogId(originalDate, session.user_id, `workout:${session.id}${suffix}`))
}
