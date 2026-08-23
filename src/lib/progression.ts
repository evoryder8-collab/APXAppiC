/* Smart progression: next-load recommendation + Overload Guardian. */
import type { AppData, Exercise } from './types'
import type { WorkoutLog } from './types'
import {
  derivePaceSecondsPerKilometre,
  descriptorForExercise,
  type ExerciseLoggingDescriptor,
} from './exerciseLogging.ts'

export type ExerciseProgress = 'improved' | 'maintained' | 'regressed' | 'adherence' | 'incomparable'

function pareto(improving: boolean[], regressing: boolean[]): ExerciseProgress {
  if (regressing.some(Boolean)) return 'regressed'
  if (improving.some(Boolean)) return 'improved'
  return 'maintained'
}

export function compareExerciseProgress(
  previous: WorkoutLog,
  current: WorkoutLog,
  descriptor: ExerciseLoggingDescriptor,
): ExerciseProgress {
  if (previous.skipped || current.skipped) return 'incomparable'
  const oneLoadMissing = (previous.weight_kg == null) !== (current.weight_kg == null)
  const oldLoad = previous.weight_kg
  const newLoad = current.weight_kg

  switch (descriptor.kind) {
    case 'strength':
    case 'bodyweight': {
      if (descriptor.fields.length === 1 && descriptor.fields[0] === 'contacts') return 'adherence'
      if (previous.reps == null || current.reps == null) return 'incomparable'
      if (previous.rir == null || current.rir == null || oneLoadMissing) return 'incomparable'
      if (current.rir < previous.rir) return 'regressed'
      return pareto(
        [current.reps > previous.reps, oldLoad != null && newLoad != null && newLoad > oldLoad],
        [current.reps < previous.reps, oldLoad != null && newLoad != null && newLoad < oldLoad],
      )
    }
    case 'isometric': {
      if (previous.duration_seconds == null || current.duration_seconds == null || oneLoadMissing) return 'incomparable'
      return pareto(
        [current.duration_seconds > previous.duration_seconds, oldLoad != null && newLoad != null && newLoad > oldLoad],
        [current.duration_seconds < previous.duration_seconds, oldLoad != null && newLoad != null && newLoad < oldLoad],
      )
    }
    case 'carry': {
      let oldDose: number
      let newDose: number
      if (previous.distance_meters != null && current.distance_meters != null
        && previous.duration_seconds == null && current.duration_seconds == null) {
        oldDose = previous.distance_meters
        newDose = current.distance_meters
      } else if (previous.duration_seconds != null && current.duration_seconds != null
        && previous.distance_meters == null && current.distance_meters == null) {
        oldDose = previous.duration_seconds
        newDose = current.duration_seconds
      } else return 'incomparable'
      if (oneLoadMissing) return 'incomparable'
      return pareto(
        [newDose > oldDose, oldLoad != null && newLoad != null && newLoad > oldLoad],
        [newDose < oldDose, oldLoad != null && newLoad != null && newLoad < oldLoad],
      )
    }
    case 'cardio': {
      if (previous.distance_meters == null || current.distance_meters == null
        || previous.duration_seconds == null || current.duration_seconds == null) return 'incomparable'
      const oldPace = derivePaceSecondsPerKilometre(previous.distance_meters, previous.duration_seconds)
      const newPace = derivePaceSecondsPerKilometre(current.distance_meters, current.duration_seconds)
      if (oldPace == null || newPace == null) return 'incomparable'
      return pareto(
        [current.distance_meters > previous.distance_meters, newPace < oldPace],
        [current.distance_meters < previous.distance_meters, newPace > oldPace],
      )
    }
    case 'interval': {
      if (previous.rounds == null || current.rounds == null
        || previous.work_seconds == null || current.work_seconds == null
        || previous.recovery_seconds == null || current.recovery_seconds == null) return 'incomparable'
      return pareto(
        [current.rounds > previous.rounds, current.work_seconds > previous.work_seconds, current.recovery_seconds < previous.recovery_seconds],
        [current.rounds < previous.rounds, current.work_seconds < previous.work_seconds, current.recovery_seconds > previous.recovery_seconds],
      )
    }
    case 'mobility': return 'adherence'
    case 'circuit': return 'incomparable'
  }
}

function sameLoggedMovement(left: WorkoutLog, right: WorkoutLog): boolean {
  if (left.user_id !== right.user_id) return false
  const leftMovement = descriptorForExercise({ name: left.exercise_name, movement_id: left.movement_id }).movementId
  const rightMovement = descriptorForExercise({ name: right.exercise_name, movement_id: right.movement_id }).movementId
  if (leftMovement && rightMovement) return leftMovement === rightMovement
  if (left.exercise_id && right.exercise_id && left.exercise_id === right.exercise_id) return true
  return movementKey(left.exercise_name) === movementKey(right.exercise_name)
}

export function progressForWorkoutLog(data: AppData, current: WorkoutLog): ExerciseProgress | null {
  const sessions = new Map(data.workout_sessions.map((session) => [session.id, session]))
  const currentSession = sessions.get(current.session_id)
  if (!currentSession) return null
  const previous = data.workout_logs
    .filter((candidate) => {
      if (candidate.id === current.id || candidate.session_id === current.session_id || candidate.skipped) return false
      if (candidate.set_no !== current.set_no || !sameLoggedMovement(candidate, current)) return false
      const session = sessions.get(candidate.session_id)
      if (!session || session.date > currentSession.date) return false
      return session.date < currentSession.date || candidate.created_at < current.created_at
    })
    .sort((left, right) => {
      const dateOrder = (sessions.get(left.session_id)?.date ?? '').localeCompare(sessions.get(right.session_id)?.date ?? '')
      return dateOrder || left.created_at.localeCompare(right.created_at)
    })
    .at(-1)
  if (!previous) return null
  return compareExerciseProgress(
    previous,
    current,
    descriptorForExercise({ name: current.exercise_name, movement_id: current.movement_id }),
  )
}

export interface ExerciseHistoryPoint {
  date: string
  topWeight: number
  allTopReps: boolean // hit top of rep range on all sets
  atTargetRir: boolean
}

export interface Recommendation {
  weight: number | null
  reason: string
  previous: { weight: number; date: string } | null
  history: ExerciseHistoryPoint[]
  typicalIncrement: number
}

function movementKey(name: string): string {
  return name
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase()
    .trim()
    .replace(/\s+/g, ' ')
}

export function exerciseHistory(data: AppData, exercise: Exercise): ExerciseHistoryPoint[] {
  const sessionsById = new Map(data.workout_sessions.map((s) => [s.id, s]))
  const byDate = new Map<string, { weights: number[]; reps: Array<{ reps: number | null; rir: number | null; skipped: boolean }> }>()
  const targetMovement = movementKey(exercise.name)
  for (const log of data.workout_logs) {
    const sameMovement = log.exercise_id === exercise.id || (
      log.user_id === exercise.user_id && movementKey(log.exercise_name) === targetMovement
    )
    if (!sameMovement || log.skipped) continue
    const session = sessionsById.get(log.session_id)
    if (!session) continue
    const entry = byDate.get(session.date) ?? { weights: [], reps: [] }
    if (log.weight_kg != null) entry.weights.push(log.weight_kg)
    entry.reps.push({ reps: log.reps, rir: log.rir, skipped: log.skipped })
    byDate.set(session.date, entry)
  }
  return [...byDate.entries()]
    .map(([date, e]) => ({
      date,
      topWeight: e.weights.length ? Math.max(...e.weights) : 0,
      allTopReps:
        e.reps.length > 0 &&
        e.reps.every((r) => r.reps != null && r.reps >= exercise.rep_max && exercise.rep_max > 0),
      atTargetRir: e.reps.length > 0 && e.reps.every((r) => r.rir != null && r.rir >= 2),
    }))
    .sort((a, b) => a.date.localeCompare(b.date))
}

export function typicalIncrement(history: ExerciseHistoryPoint[], fallback: number): number {
  const diffs: number[] = []
  for (let i = 1; i < history.length; i++) {
    const d = history[i].topWeight - history[i - 1].topWeight
    if (d > 0) diffs.push(d)
  }
  if (!diffs.length) return fallback || 2.5
  diffs.sort((a, b) => a - b)
  return diffs[Math.floor(diffs.length / 2)]
}

/*
 * Universal rule: top of rep range on ALL sets with clean form (target RIR)
 * recommends +increment next session. +2.5 kg compounds and backpack moves,
 * +1-2 kg isolations.
 */
export function recommendLoad(data: AppData, exercise: Exercise): Recommendation {
  const history = exerciseHistory(data, exercise)
  const inc = exercise.increment_kg
  const typical = typicalIncrement(history, inc)
  if (!history.length) {
    return { weight: null, reason: 'First session, pick a comfortable load', previous: null, history, typicalIncrement: typical }
  }
  const last = history[history.length - 1]
  if (inc > 0 && last.allTopReps && last.atTargetRir) {
    return {
      weight: last.topWeight + inc,
      reason: `Top of rep range on all sets last time. +${inc} kg earned`,
      previous: { weight: last.topWeight, date: last.date },
      history,
      typicalIncrement: typical,
    }
  }
  return {
    weight: last.topWeight || null,
    reason: 'Repeat last load and chase the top of the rep range',
    previous: { weight: last.topWeight, date: last.date },
    history,
    typicalIncrement: typical,
  }
}

export interface GuardianVerdict {
  triggered: boolean
  safeLoad: number
  jump: number
  typical: number
}

/*
 * Overload Guardian: manual entries that spike past ~1.5x the typical
 * increment get a science note before they count. Muscle adapts faster than
 * tendon; collagen remodels over weeks to months.
 */
export function guardianCheck(
  entered: number,
  rec: Recommendation,
  factor: number,
): GuardianVerdict {
  const lastWeight = rec.previous?.weight ?? null
  const typical = Math.max(rec.typicalIncrement, 1)
  if (lastWeight == null || entered <= lastWeight) {
    return { triggered: false, safeLoad: entered, jump: 0, typical }
  }
  const jump = entered - lastWeight
  const triggered = jump > typical * factor
  const safeLoad = triggered ? Math.round((lastWeight + typical) * 2) / 2 : entered
  return { triggered, safeLoad, jump, typical }
}
