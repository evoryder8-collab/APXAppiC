import type { PlannedDay } from './plan.ts'
import type { WorkoutSession } from './types.ts'

export interface DailyGuidedSession {
  plan: PlannedDay
  completedSessionID?: string
  resumeLite?: boolean
  status: 'Start' | 'Continue' | 'Completed'
}

/** Receives the active programme's resolved plans, never all weekday matches. */
export function dailyGuidedSessions(
  plans: PlannedDay[], sessions: WorkoutSession[], ownerID: string | undefined, date: string,
  resumableModes: ReadonlyMap<string, boolean> = new Map(),
): DailyGuidedSession[] {
  if (!ownerID) return []
  const seen = new Set<string>()
  return plans.flatMap((plan) => {
    const day = plan.programDay
    if (!day || day.user_id !== ownerID || day.is_active === false || seen.has(day.id)
      || !plan.exercises.some((exercise) => exercise.user_id === ownerID && exercise.program_day_id === day.id)) return []
    seen.add(day.id)
    const completed = sessions.filter((session) => session.user_id === ownerID && session.date === date
      && session.program_day_id === day.id && session.completed)
      .sort((left, right) => (right.completed_at ?? right.started_at ?? '').localeCompare(left.completed_at ?? left.started_at ?? '')
        || right.id.localeCompare(left.id))[0]
    const resumeLite = completed ? undefined : resumableModes.get(day.id)
    return [{ plan, completedSessionID: completed?.id, resumeLite,
      status: completed ? 'Completed' as const : resumeLite != null ? 'Continue' as const : 'Start' as const }]
  })
}

export interface GuidedPlayerDraftIdentity {
  ownerId: string
  slug: string
  date: string
  lite: boolean
  programDayId?: string
  exerciseIds: string[]
}

export function guidedPlayerDraftKey(identity: Omit<GuidedPlayerDraftIdentity, 'exerciseIds'>): string {
  return `apex.player.v2.${identity.ownerId}.${identity.slug}.${identity.date}.${identity.programDayId ?? 'default'}.${identity.lite ? 'lite' : 'full'}`
}

export function guidedPlayerDraftMatches(value: unknown, identity: GuidedPlayerDraftIdentity): boolean {
  if (!value || typeof value !== 'object') return false
  const draft = value as Record<string, unknown>
  return draft.ownerId === identity.ownerId && draft.slug === identity.slug && draft.date === identity.date
    && draft.lite === identity.lite && draft.programDayId === identity.programDayId
    && Array.isArray(draft.exerciseIds) && draft.exerciseIds.length === identity.exerciseIds.length
    && draft.exerciseIds.every((id, index) => id === identity.exerciseIds[index])
    && typeof draft.idx === 'number' && Number.isInteger(draft.idx) && draft.idx >= 0
    && typeof draft.elapsed === 'number' && Number.isFinite(draft.elapsed) && draft.elapsed >= 0
    && typeof draft.paused === 'boolean'
}
