import type { AppData, JointCheckin, WorkoutLog } from './types'

export type JointRegion = 'arms' | 'core' | 'legs'
export type DeloadState = 'clear' | 'watch' | 'regional_deload' | 'whole_deload' | 'stop_and_review'

export interface StrengthPoint {
  sessionId: string
  date: string
  topWeight: number
  estimated1rm: number
  volume: number
  setWeights: Record<number, number>
}

export interface ExerciseStrengthSeries {
  key: string
  exerciseId: string | null
  name: string
  points: StrengthPoint[]
}

export interface SessionStrengthInsight {
  key: string
  name: string
  current: StrengthPoint
  previous: StrengthPoint | null
  reference: StrengthPoint | null
  daysCompared: number | null
  loadDelta: number | null
  estimated1rmDelta: number | null
}

export interface JointAssessment {
  state: DeloadState
  affected: JointRegion[]
  average: number
  highest: number
  rising: JointRegion[]
}

function exerciseKey(log: Pick<WorkoutLog, 'exercise_id' | 'exercise_name'>): string {
  return log.exercise_id ? `id:${log.exercise_id}` : `name:${log.exercise_name.trim().toLocaleLowerCase('en')}`
}

function daysBetween(earlier: string, later: string): number {
  return Math.max(0, Math.round((Date.parse(`${later}T12:00:00Z`) - Date.parse(`${earlier}T12:00:00Z`)) / 86_400_000))
}

export function estimatedOneRepMax(weight: number, reps: number | null): number {
  if (!Number.isFinite(weight) || weight <= 0) return 0
  if (reps == null || reps <= 1) return Math.round(weight * 10) / 10
  /* Epley is intentionally capped at 15 reps; higher-rep sets are poor
     maximal-strength estimators and should not create spectacular fake gains. */
  const boundedReps = Math.min(15, reps)
  return Math.round(weight * (1 + boundedReps / 30) * 10) / 10
}

export function buildStrengthSeries(data: AppData): ExerciseStrengthSeries[] {
  const sessions = new Map(data.workout_sessions.filter((session) => session.completed).map((session) => [session.id, session]))
  const grouped = new Map<string, {
    exerciseId: string | null
    name: string
    sessions: Map<string, WorkoutLog[]>
  }>()

  for (const log of data.workout_logs) {
    if (log.skipped || log.weight_kg == null || log.weight_kg <= 0 || !sessions.has(log.session_id)) continue
    const key = exerciseKey(log)
    const group = grouped.get(key) ?? {
      exerciseId: log.exercise_id,
      name: log.exercise_name,
      sessions: new Map<string, WorkoutLog[]>(),
    }
    const logs = group.sessions.get(log.session_id) ?? []
    logs.push(log)
    group.sessions.set(log.session_id, logs)
    grouped.set(key, group)
  }

  return [...grouped.entries()]
    .map(([key, group]) => {
      const points = [...group.sessions.entries()].map(([sessionId, logs]) => {
        const session = sessions.get(sessionId)!
        const usable = logs.filter((log) => log.weight_kg != null && log.weight_kg > 0)
        const topWeight = Math.max(...usable.map((log) => Number(log.weight_kg)))
        const estimated1rm = Math.max(...usable.map((log) => estimatedOneRepMax(Number(log.weight_kg), log.reps)))
        const volume = usable.reduce((sum, log) => sum + Number(log.weight_kg) * Math.max(0, log.reps ?? 0), 0)
        const setWeights = Object.fromEntries(usable.map((log) => [log.set_no, Number(log.weight_kg)]))
        return { sessionId, date: session.date, topWeight, estimated1rm, volume, setWeights }
      }).sort((a, b) => a.date.localeCompare(b.date) || a.sessionId.localeCompare(b.sessionId))
      return { key, exerciseId: group.exerciseId, name: group.name, points }
    })
    .filter((series) => series.points.length > 0)
    .sort((a, b) => a.name.localeCompare(b.name))
}

export function sessionStrengthInsights(data: AppData, sessionId: string): SessionStrengthInsight[] {
  const currentSession = data.workout_sessions.find((session) => session.id === sessionId)
  if (!currentSession) return []

  return buildStrengthSeries(data).flatMap((series) => {
    const current = series.points.find((point) => point.sessionId === sessionId)
    if (!current) return []
    const prior = series.points.filter((point) => point.date < currentSession.date)
    const previous = prior.at(-1) ?? null
    /* Prefer a meaningful 30-90 day comparison. If history is newer, the
       earliest prior point is still more honest than fabricating a horizon. */
    const inNinetyDays = prior.filter((point) => daysBetween(point.date, currentSession.date) <= 90)
    const reference = inNinetyDays[0] ?? previous
    return [{
      key: series.key,
      name: series.name,
      current,
      previous,
      reference,
      daysCompared: reference ? daysBetween(reference.date, currentSession.date) : null,
      loadDelta: reference ? Math.round((current.topWeight - reference.topWeight) * 10) / 10 : null,
      estimated1rmDelta: reference ? Math.round((current.estimated1rm - reference.estimated1rm) * 10) / 10 : null,
    }]
  }).sort((a, b) => (b.loadDelta ?? -Infinity) - (a.loadDelta ?? -Infinity))
}

export function assessJointCheckin(current: JointCheckin, previous?: JointCheckin | null): JointAssessment {
  const regions: JointRegion[] = ['arms', 'core', 'legs']
  const scores = regions.map((region) => current[region])
  const affected = regions.filter((region) => current[region] >= 5)
  const rising = previous
    ? regions.filter((region) => current[region] - previous[region] >= 2)
    : []
  const highest = Math.max(...scores)
  const average = Math.round((scores.reduce((sum, score) => sum + score, 0) / scores.length) * 10) / 10
  const severe = regions.filter((region) => current[region] >= 9)
  const high = regions.filter((region) => current[region] >= 7)
  const elevated = regions.filter((region) => current[region] >= 6)

  let state: DeloadState = 'clear'
  if (severe.length > 0) state = 'stop_and_review'
  else if (high.length >= 2 || elevated.length >= 2 || average >= 7) state = 'whole_deload'
  else if (high.length === 1) state = 'regional_deload'
  else if (affected.length > 0 || rising.length > 0) state = 'watch'

  return { state, affected: severe.length > 0 ? severe : affected, average, highest, rising }
}

export function checkinDue(checkins: JointCheckin[], today: string, intervalDays = 7): boolean {
  const latest = [...checkins].sort((a, b) => b.date.localeCompare(a.date))[0]
  return !latest || daysBetween(latest.date, today) >= intervalDays
}
