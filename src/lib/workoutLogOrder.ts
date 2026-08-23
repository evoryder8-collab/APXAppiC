import type { AppData, WorkoutLog } from './types'
import { buildWorkSequence } from './workGrouping.ts'

function exerciseKey(log: WorkoutLog): string {
  return log.exercise_id
    ? `id:${log.exercise_id}`
    : `name:${log.exercise_name.trim().toLocaleLowerCase('en')}`
}

function timestamp(value: string): number | null {
  const parsed = Date.parse(value)
  return Number.isFinite(parsed) ? parsed : null
}

/**
 * Keeps completed receipts in the order the workout was performed. Logs are
 * grouped by exercise, each exercise is positioned by its earliest recorded
 * set, and planned order resolves legacy rows that share one timestamp.
 */
export function workoutLogsInPerformedOrder(
  data: Pick<AppData, 'exercises' | 'workout_logs' | 'workout_sessions'>,
  sessionId: string,
): WorkoutLog[] {
  const session = data.workout_sessions.find((candidate) => candidate.id === sessionId)
  const planned = data.exercises
    .filter((exercise) => (
      exercise.program_day_id === session?.program_day_id
        && exercise.is_lite === (session?.is_lite ?? false)
    ))
    .sort((left, right) => left.sort_order - right.sort_order)
  const sessionLogs = data.workout_logs.filter((log) => log.session_id === sessionId)
  const workSequence = buildWorkSequence(planned)
  if (workSequence.some((position) => position.groupId != null)) {
    const persistedRank = new Map<string, number>()
    workSequence.forEach((position, rank) => {
      const exercise = planned[position.exIdx]
      persistedRank.set(`id:${exercise.id}:${position.setNo}`, rank)
      persistedRank.set(`name:${exercise.name.trim().toLocaleLowerCase('en')}:${position.setNo}`, rank)
    })
    return sessionLogs
      .map((log, index) => ({ log, index }))
      .sort((left, right) => {
        const leftRank = persistedRank.get(`${exerciseKey(left.log)}:${left.log.set_no}`)
        const rightRank = persistedRank.get(`${exerciseKey(right.log)}:${right.log.set_no}`)
        if (leftRank != null && rightRank != null && leftRank !== rightRank) return leftRank - rightRank
        if (leftRank != null && rightRank == null) return -1
        if (leftRank == null && rightRank != null) return 1
        return left.index - right.index
      })
      .map(({ log }) => log)
  }
  const plannedById = new Map(planned.map((exercise, index) => [exercise.id, index]))
  const plannedByName = new Map(planned.map((exercise, index) => [exercise.name.trim().toLocaleLowerCase('en'), index]))
  const groups = new Map<string, {
    firstIndex: number
    firstTimestamp: number | null
    plannedOrder: number | null
    logs: WorkoutLog[]
  }>()

  sessionLogs.forEach((log, index) => {
    const key = exerciseKey(log)
    const recordedAt = timestamp(log.created_at)
    const plannedOrder = (log.exercise_id ? plannedById.get(log.exercise_id) : undefined)
      ?? plannedByName.get(log.exercise_name.trim().toLocaleLowerCase('en'))
      ?? null
    const group = groups.get(key)
    if (group) {
      group.logs.push(log)
      if (recordedAt != null && (group.firstTimestamp == null || recordedAt < group.firstTimestamp)) {
        group.firstTimestamp = recordedAt
      }
      if (group.plannedOrder == null && plannedOrder != null) group.plannedOrder = plannedOrder
      return
    }
    groups.set(key, {
      firstIndex: index,
      firstTimestamp: recordedAt,
      plannedOrder,
      logs: [log],
    })
  })

  return [...groups.values()]
    .sort((left, right) => {
      if (left.firstTimestamp != null && right.firstTimestamp != null && left.firstTimestamp !== right.firstTimestamp) {
        return left.firstTimestamp - right.firstTimestamp
      }
      if (left.plannedOrder != null && right.plannedOrder != null && left.plannedOrder !== right.plannedOrder) {
        return left.plannedOrder - right.plannedOrder
      }
      if (left.plannedOrder != null && right.plannedOrder == null) return -1
      if (left.plannedOrder == null && right.plannedOrder != null) return 1
      return left.firstIndex - right.firstIndex
    })
    .flatMap((group) => [...group.logs].sort((left, right) => (
      left.set_no - right.set_no
      || (timestamp(left.created_at) ?? 0) - (timestamp(right.created_at) ?? 0)
    )))
}
