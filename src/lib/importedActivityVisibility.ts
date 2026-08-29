import type { AppData, ImportedActivity } from './types.ts'

const APEX_BUNDLE_ID = 'ch.apexperformance.APEX'
const APEX_MIRROR_WINDOW_MS = 5 * 60 * 1000

type ImportedActivityVisibilityData = Pick<
  AppData,
  'profile' | 'settings' | 'workout_sessions' | 'imported_activities'
>

function isAPEXBundleIdentifier(value: string | null | undefined): boolean {
  return value === APEX_BUNDLE_ID || value?.startsWith(`${APEX_BUNDLE_ID}.`) === true
}

function hasNearbySession(sortedSessionTimes: readonly number[], activityTime: number): boolean {
  let lower = 0
  let upper = sortedSessionTimes.length
  while (lower < upper) {
    const middle = (lower + upper) >>> 1
    if (sortedSessionTimes[middle] <= activityTime - APEX_MIRROR_WINDOW_MS) lower = middle + 1
    else upper = middle
  }
  return lower < sortedSessionTimes.length
    && Math.abs(sortedSessionTimes[lower] - activityTime) < APEX_MIRROR_WINDOW_MS
}

/**
 * Resolve the imported activity rows that may affect this APEX account. Hidden
 * rows remain stored for HealthKit deduplication, foreign rows never cross the
 * account boundary, and an APEX session mirrored into HealthKit is not treated
 * as a second workout.
 */
export function visibleImportedActivitiesForOwner(
  data: ImportedActivityVisibilityData,
): ImportedActivity[] {
  const ownerID = data.profile?.user_id ?? data.settings?.user_id ?? null
  if (!ownerID) return []

  const ownedSessions = data.workout_sessions.filter((session) => session.user_id === ownerID)
  const ownedSessionIDs = new Set(ownedSessions.map((session) => session.id))
  const ownedSessionTimes = ownedSessions
    .map((session) => Date.parse(session.started_at ?? session.completed_at ?? ''))
    .filter(Number.isFinite)
    .sort((left, right) => left - right)

  return data.imported_activities.filter((activity) => {
    if (activity.user_id !== ownerID || activity.hidden_at != null) return false
    if (
      activity.apex_workout_session_id
      && ownedSessionIDs.has(activity.apex_workout_session_id)
      && isAPEXBundleIdentifier(activity.source_bundle_id)
    ) return false
    if (!isAPEXBundleIdentifier(activity.source_bundle_id) || !activity.started_at) return true
    const activityTime = Date.parse(activity.started_at)
    return !Number.isFinite(activityTime) || !hasNearbySession(ownedSessionTimes, activityTime)
  })
}

/**
 * Imported workouts that may independently affect fitness scoring. A wearable
 * activity linked to an APEX receipt is evidence for that receipt, not a second
 * workout signal.
 */
export function signalBearingImportedActivitiesForOwner(
  data: ImportedActivityVisibilityData,
): ImportedActivity[] {
  return visibleImportedActivitiesForOwner(data).filter(
    (activity) => activity.apex_workout_session_id == null,
  )
}
