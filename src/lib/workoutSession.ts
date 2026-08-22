/**
 * Turning a finished session into the rows that get stored.
 *
 * There are two ways to train and they have to produce identical history. A
 * guided follow-along counts the reps for you and asks what you lifted between
 * sets; a tracked session shows the list and lets you type it in afterwards.
 * If those two wrote subtly different records then progressive overload, the
 * workout receipt and every strength comparison would quietly depend on which
 * screen somebody happened to use, which is the kind of bug nobody finds for
 * months.
 *
 * So both call this. It is pure: it builds rows and returns them, and the
 * caller does the storing.
 */

import type { WorkoutLog, WorkoutSession } from './types.ts'

export interface SetEntry {
  weight: number | null
  reps: number | null
  rir: number | null
}

export interface LoggedSetEntry extends SetEntry {
  skipped: boolean
}

/** Preserve a guided session's report for each set independently. */
export function serializeExerciseSets(
  weights: Array<number | null>,
  rirs: Array<number | null>,
  reps: Array<number | null>,
  skipped: boolean,
): LoggedSetEntry[] {
  return reps.map((rep, index) => ({
    weight: skipped ? null : (weights[index] ?? null),
    reps: skipped ? null : rep,
    rir: skipped ? null : (rirs[index] ?? null),
    skipped,
  }))
}

export interface ExerciseEntry {
  /* Null for anything not in the user's own exercise table, which is how the
   * guided player already treats substituted or ad-hoc movements. */
  exerciseId: string | null
  name: string
  plannedSets: number
  sets: SetEntry[]
  skipped: boolean
  override: boolean
}

export interface SessionDraft {
  sessionId: string
  userId: string
  date: string
  programDayId: string
  isLite: boolean
  isDeload: boolean
  isEventRecovery: boolean
  qualityScore: number
  startedAt: string
  completedAt: string
  notes?: string
  exercises: ExerciseEntry[]
}

export interface SessionRecords {
  session: WorkoutSession
  logs: WorkoutLog[]
}

/**
 * One row per planned set, in the order they were performed.
 *
 * Every set of every exercise is written even when it was skipped, because a
 * missing row and a skipped row mean different things: the first is an
 * absence of data and the second is a decision. The timestamps step by one
 * millisecond so the stored order survives a database that would otherwise be
 * free to return them in any order it likes.
 */
export function buildSessionRecords(
  draft: SessionDraft,
  newId: () => string = () => crypto.randomUUID(),
): SessionRecords {
  const session: WorkoutSession = {
    id: draft.sessionId,
    user_id: draft.userId,
    date: draft.date,
    program_day_id: draft.programDayId,
    is_lite: draft.isLite,
    is_deload: draft.isDeload,
    is_event_recovery: draft.isEventRecovery,
    completed: true,
    quality_score: Math.round(draft.qualityScore * 100) / 100,
    started_at: draft.startedAt,
    completed_at: draft.completedAt,
    notes: draft.notes ?? '',
  }

  const base = Date.parse(draft.completedAt)
  const logs: WorkoutLog[] = []
  let order = 0
  for (const exercise of draft.exercises) {
    for (let setNo = 1; setNo <= exercise.plannedSets; setNo += 1) {
      const entry = exercise.sets[setNo - 1]
      logs.push({
        id: newId(),
        user_id: draft.userId,
        session_id: draft.sessionId,
        exercise_id: exercise.exerciseId,
        exercise_name: exercise.name,
        set_no: setNo,
        weight_kg: exercise.skipped ? null : entry?.weight ?? null,
        reps: exercise.skipped ? null : entry?.reps ?? null,
        rir: exercise.skipped ? null : entry?.rir ?? null,
        skipped: exercise.skipped,
        override_flag: exercise.override,
        created_at: new Date(base + order++).toISOString(),
      })
    }
  }
  return { session, logs }
}

/**
 * How complete the session was, on the same scale the guided player uses: the
 * share of planned sets that were actually performed. A tracked session has no
 * cadence engine to judge quality from, so this is what both can agree on.
 */
export function sessionQuality(exercises: ExerciseEntry[]): number {
  const planned = exercises.reduce((sum, e) => sum + e.plannedSets, 0)
  if (planned === 0) return 0
  const done = exercises.reduce((sum, e) => e.skipped
    ? sum
    : sum + e.sets.filter((s) => (s.reps ?? 0) > 0).length, 0)
  return Math.min(1, done / planned)
}
