import { manualWorkoutTitle } from './manualWorkout.ts'
import type { AppData, WorkoutSession } from './types.ts'

export interface CompletedWorkoutHistoryItem {
  session: WorkoutSession
  title: string
  isQuickLog: boolean
}

export interface CompletedWorkoutDeletionPlan {
  sessionId: string
  logIds: string[]
}

/**
 * The destructive tray is not part of a resting compact card. Render it only
 * while a deliberate leftward reveal is in progress or has settled open.
 * Expanded cards own their separate, compact corner action.
 */
export function collapsedWorkoutDeleteTrayVisible(isExpanded: boolean, revealOffset: number): boolean {
  return !isExpanded && revealOffset < 0
}

/**
 * A destructive action must resolve from the signed-in owner, never merely
 * from a session id supplied by the interface. Set rows are independently
 * owner-checked so a malformed foreign row cannot be deleted with the workout.
 */
export function completedWorkoutDeletionPlan(
  data: Pick<AppData, 'profile' | 'settings' | 'workout_sessions' | 'workout_logs'>,
  sessionId: string,
): CompletedWorkoutDeletionPlan | null {
  const ownerId = data.profile?.user_id ?? data.settings?.user_id ?? null
  if (!ownerId) return null
  const session = data.workout_sessions.find((candidate) => (
    candidate.id === sessionId
    && candidate.user_id === ownerId
    && candidate.completed
  ))
  if (!session) return null
  return {
    sessionId: session.id,
    logIds: data.workout_logs
      .filter((log) => log.session_id === session.id && log.user_id === ownerId)
      .map((log) => log.id),
  }
}

/**
 * A day owns every completed workout recorded on it, regardless of whether
 * the current generated plan still contains the session's programme row.
 * That keeps regenerated plans from making old tracked receipts disappear and
 * gives Quick Log sessions the same first-class history as guided work.
 */
export function completedWorkoutHistoryForDate(
  data: Pick<AppData, 'profile' | 'settings' | 'program_days' | 'workout_sessions'>,
  date?: string,
  limit?: number,
): CompletedWorkoutHistoryItem[] {
  const ownerId = data.profile?.user_id ?? data.settings?.user_id ?? null
  const days = new Map(data.program_days.map((day) => [day.id, day]))

  const history = data.workout_sessions
    .filter((session) => (
      session.completed
      && (date == null || session.date === date)
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
  return limit == null ? history : history.slice(0, Math.max(0, limit))
}
