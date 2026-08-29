import { manualWorkoutTitle } from './manualWorkout.ts'
import type { IntroLanguage } from './introLanguage.ts'
import { visibleImportedActivitiesForOwner } from './importedActivityVisibility.ts'
import type { AppData, ImportedActivity, WorkoutSession } from './types.ts'

export interface CompletedWorkoutHistoryItem {
  session: WorkoutSession
  title: string
  isQuickLog: boolean
}

export interface CompletedWorkoutDeletionPlan {
  sessionId: string
  logIds: string[]
}

export type FinishedWorkoutHistoryItem =
  | (CompletedWorkoutHistoryItem & {
      kind: 'apex'
      id: string
      sortTime: string
    })
  | {
      kind: 'external'
      id: string
      sortTime: string
      activity: ImportedActivity
    }

export interface ExternalWorkoutReceiptPresentation {
  title: string
  moment: string
  duration: string
  energy: string | null
  distance: string | null
}

const WORKOUT_RECEIPT_LOCALE: Record<IntroLanguage, string> = {
  en: 'en-GB',
  ro: 'ro-RO',
  th: 'th-TH',
}

/**
 * Build the visible Apple Health receipt using the language selected inside
 * APEX. The stored fallback name remains authoritative for English and for a
 * future HealthKit key that has not reached the web translation table yet.
 */
export function externalWorkoutReceiptPresentation(
  activity: ImportedActivity,
  language: IntroLanguage,
  timeZone: string,
  translate: (value: string) => string,
): ExternalWorkoutReceiptPresentation {
  const locale = WORKOUT_RECEIPT_LOCALE[language]
  const nameKey = activity.workout_name_key?.trim() ?? ''
  const keyedTitle = nameKey ? translate(nameKey) : ''
  const title = nameKey && keyedTitle !== nameKey ? keyedTitle : translate(activity.activity)
  const integer = new Intl.NumberFormat(locale, { maximumFractionDigits: 0 })
  const decimal = new Intl.NumberFormat(locale, { maximumFractionDigits: 2 })
  const started = activity.started_at ? new Date(activity.started_at) : null
  let moment = activity.date

  if (started && !Number.isNaN(started.getTime())) {
    moment = new Intl.DateTimeFormat(locale, {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
      timeZone,
    }).format(started)
  } else {
    const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(activity.date)
    if (parts) {
      const dateOnly = new Date(Date.UTC(Number(parts[1]), Number(parts[2]) - 1, Number(parts[3]), 12))
      moment = new Intl.DateTimeFormat(locale, {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
        timeZone: 'UTC',
      }).format(dateOnly)
    }
  }

  return {
    title,
    moment,
    duration: `${integer.format(Math.round(activity.duration_min))} ${translate('min')}`,
    energy: activity.active_energy_kcal == null
      ? null
      : `${integer.format(Math.round(activity.active_energy_kcal))} ${translate('kcal')}`,
    distance: activity.distance_km == null
      ? null
      : `${decimal.format(activity.distance_km)} ${translate('km')}`,
  }
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

/**
 * HealthKit workouts share the finished-workout timeline, but remain read-only
 * receipts. A rich HealthKit UUID distinguishes event-driven imports from old
 * XML activity summaries. Mirrored APEX workouts are omitted when their owned
 * session is already present, and the limit is applied only after both sources
 * have been merged chronologically.
 */
export function finishedWorkoutHistoryForDate(
  data: Pick<AppData, 'profile' | 'settings' | 'program_days' | 'workout_sessions' | 'imported_activities'>,
  date?: string,
  limit?: number,
): FinishedWorkoutHistoryItem[] {
  const apex: FinishedWorkoutHistoryItem[] = completedWorkoutHistoryForDate(data, date).map((item) => ({
    ...item,
    kind: 'apex',
    id: item.session.id,
    sortTime: item.session.completed_at ?? item.session.started_at ?? `${item.session.date}T00:00:00.000Z`,
  }))
  const external: FinishedWorkoutHistoryItem[] = visibleImportedActivitiesForOwner(data)
    .filter((activity) => (
      Boolean(activity.healthkit_workout_id)
      && (date == null || activity.date === date)
    ))
    .map((activity) => ({
      kind: 'external',
      id: activity.id,
      activity,
      sortTime: activity.ended_at ?? activity.started_at ?? `${activity.date}T00:00:00.000Z`,
    }))

  const history = [...apex, ...external].sort((left, right) => (
    right.sortTime.localeCompare(left.sortTime) || right.id.localeCompare(left.id)
  ))
  return limit == null ? history : history.slice(0, Math.max(0, limit))
}

/**
 * Hiding is an APEX-owned preference update. It deliberately returns the full
 * imported row for upsert and never exposes an Apple Health deletion plan.
 */
export function externalWorkoutHidePlan(
  data: Pick<AppData, 'profile' | 'settings' | 'imported_activities'>,
  activityId: string,
  hiddenAt = new Date().toISOString(),
): ImportedActivity | null {
  const ownerId = data.profile?.user_id ?? data.settings?.user_id ?? null
  if (!ownerId) return null
  const activity = data.imported_activities.find((candidate) => (
    candidate.id === activityId
    && candidate.user_id === ownerId
    && Boolean(candidate.healthkit_workout_id)
    && candidate.hidden_at == null
  ))
  return activity ? { ...activity, hidden_at: hiddenAt } : null
}
