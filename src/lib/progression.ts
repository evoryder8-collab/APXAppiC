/* Smart progression: next-load recommendation + Overload Guardian. */
import type { AppData, Exercise } from './types'

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

export function exerciseHistory(data: AppData, exercise: Exercise): ExerciseHistoryPoint[] {
  const sessionsById = new Map(data.workout_sessions.map((s) => [s.id, s]))
  const byDate = new Map<string, { weights: number[]; reps: Array<{ reps: number | null; rir: number | null; skipped: boolean }> }>()
  for (const log of data.workout_logs) {
    if (log.exercise_id !== exercise.id || log.skipped) continue
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
      atTargetRir: e.reps.every((r) => r.rir == null || r.rir <= 2),
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
