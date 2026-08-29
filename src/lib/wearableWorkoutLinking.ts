import type { ImportedActivity, WorkoutSession } from './types.ts'

const AUTOMATIC_LEAD_WINDOW_MS = 5 * 60 * 1000
const APEX_BUNDLE_ID = 'ch.apexperformance.APEX'

export function isAPEXWorkoutSourceBundle(value: string | null | undefined): boolean {
  return value === APEX_BUNDLE_ID || value?.startsWith(`${APEX_BUNDLE_ID}.`) === true
}

function validTime(value: string | null | undefined): number | null {
  if (!value) return null
  const parsed = Date.parse(value)
  return Number.isFinite(parsed) ? parsed : null
}

function isSelectableExternalActivity(
  activity: ImportedActivity,
  ownerId: string,
  date: string,
): boolean {
  return activity.user_id === ownerId
    && activity.date === date
    && Boolean(activity.healthkit_workout_id)
    && activity.hidden_at == null
    && activity.apex_workout_session_id == null
    && !isAPEXWorkoutSourceBundle(activity.source_bundle_id)
}

function chronologicalTime(activity: ImportedActivity): number {
  return validTime(activity.started_at)
    ?? validTime(activity.ended_at)
    ?? validTime(`${activity.date}T00:00:00.000Z`)
    ?? 0
}

/** Same-day choices for the deliberate recovery flow, newest first. */
export function wearableCandidatesForDay(
  activities: readonly ImportedActivity[],
  ownerId: string,
  date: string,
): ImportedActivity[] {
  return activities
    .filter((activity) => isSelectableExternalActivity(activity, ownerId, date))
    .sort((left, right) => chronologicalTime(right) - chronologicalTime(left) || right.id.localeCompare(left.id))
}

export function explicitWearableLink(
  activity: ImportedActivity,
  session: WorkoutSession,
): ImportedActivity | null {
  if (activity.apex_workout_session_id === session.id) return activity
  if (!isSelectableExternalActivity(activity, session.user_id, session.date)) return null
  return { ...activity, apex_workout_session_id: session.id }
}

function overlapsAutomaticWindow(session: WorkoutSession, activity: ImportedActivity): boolean {
  const sessionStart = validTime(session.started_at)
  const sessionEnd = validTime(session.completed_at)
  const activityStart = validTime(activity.started_at)
  const activityEnd = validTime(activity.ended_at)
  if (sessionStart == null || sessionEnd == null || activityStart == null) return false
  if (activityStart < sessionStart - AUTOMATIC_LEAD_WINDOW_MS || activityStart > sessionEnd) return false
  // A workout that ended before APEX began was already over and cannot be the
  // simultaneous effort. If no end exists, only a start during APEX proves overlap.
  return activityEnd == null ? activityStart >= sessionStart : activityEnd >= sessionStart
}

/**
 * Produce only bi-unique associations: one candidate for the APEX session and
 * one candidate session for the wearable activity. Ambiguity is resolved by
 * the explicit chooser instead of a timing guess.
 */
export function automaticWearableLinks(
  sessions: readonly WorkoutSession[],
  activities: readonly ImportedActivity[],
  ownerId: string,
): ImportedActivity[] {
  const linkedSessionIds = new Set(activities.flatMap((activity) => (
    activity.user_id === ownerId
      && activity.apex_workout_session_id
      && !isAPEXWorkoutSourceBundle(activity.source_bundle_id)
      ? [activity.apex_workout_session_id]
      : []
  )))
  const eligibleSessions = sessions.filter((session) => (
    session.user_id === ownerId
    && session.completed
    && !linkedSessionIds.has(session.id)
    && validTime(session.started_at) != null
    && validTime(session.completed_at) != null
  ))
  const eligibleActivities = activities.filter((activity) => (
    isSelectableExternalActivity(activity, ownerId, activity.date)
  ))
  const activityIdsBySession = new Map<string, string[]>()
  const sessionIdsByActivity = new Map<string, string[]>()

  for (const session of eligibleSessions) {
    for (const activity of eligibleActivities) {
      if (session.date !== activity.date || !overlapsAutomaticWindow(session, activity)) continue
      activityIdsBySession.set(session.id, [...(activityIdsBySession.get(session.id) ?? []), activity.id])
      sessionIdsByActivity.set(activity.id, [...(sessionIdsByActivity.get(activity.id) ?? []), session.id])
    }
  }

  const activitiesById = new Map(eligibleActivities.map((activity) => [activity.id, activity]))
  return eligibleSessions.flatMap((session) => {
    const candidateIds = activityIdsBySession.get(session.id) ?? []
    if (candidateIds.length !== 1) return []
    const activityId = candidateIds[0]
    if ((sessionIdsByActivity.get(activityId) ?? []).length !== 1) return []
    const activity = activitiesById.get(activityId)
    return activity ? [{ ...activity, apex_workout_session_id: session.id }] : []
  })
}
