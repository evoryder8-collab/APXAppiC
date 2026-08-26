import { manualWorkoutTitle } from './manualWorkout.ts'
import type { AppData, WorkoutSession } from './types.ts'

export interface CompletedWorkoutHistoryItem {
  session: WorkoutSession
  title: string
  isQuickLog: boolean
}

/**
 * A day owns every completed workout recorded on it, regardless of whether
 * the current generated plan still contains the session's programme row.
 * That keeps regenerated plans from making old tracked receipts disappear and
 * gives Quick Log sessions the same first-class history as guided work.
 */
export function completedWorkoutHistoryForDate(
  data: Pick<AppData, 'profile' | 'settings' | 'program_days' | 'workout_sessions'>,
  date: string,
): CompletedWorkoutHistoryItem[] {
  const ownerId = data.profile?.user_id ?? data.settings?.user_id ?? null
  const days = new Map(data.program_days.map((day) => [day.id, day]))

  return data.workout_sessions
    .filter((session) => (
      session.completed
      && session.date === date
      && (!ownerId || session.user_id === ownerId)
    ))
    .sort((left, right) => {
      const leftTime = left.completed_at ?? left.started_at ?? `${left.date}T00:00:00.000Z`
      const rightTime = right.completed_at ?? right.started_at ?? `${right.date}T00:00:00.000Z`
      return rightTime.localeCompare(leftTime) || right.id.localeCompare(left.id)
    })
    .map((session) => {
      const quickTitle = manualWorkoutTitle(session.notes)
      return {
        session,
        title: quickTitle ?? days.get(session.program_day_id)?.name ?? 'Completed workout',
        isQuickLog: quickTitle != null,
      }
    })
}
