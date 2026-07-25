/* Builds the guided player's block timeline from an adjusted plan. */
import type { PlannedDay, PlannedExercise } from './plan'

export type Block =
  | { kind: 'warmup'; text: string; duration: number }
  | { kind: 'check'; exIdx: number; exercise: PlannedExercise }
  | {
      kind: 'set'
      exIdx: number
      exercise: PlannedExercise
      setNo: number
      totalSets: number
      side: 'left' | 'right' | null
      resultKey: string
      targetReps: number | null // null = max/failure set, count up
      repDuration: number // seconds per rep for the cadence engine
      timed: number | null // seconds, for holds/videos, replaces rep counting
    }
  | { kind: 'rest'; exIdx: number; afterSet: number; duration: number; nextLabel: string; exercise: PlannedExercise; captureLoad: boolean }
  | { kind: 'log'; exIdx: number; exercise: PlannedExercise }
  | { kind: 'done' }

export function repTarget(e: PlannedExercise): number | null {
  if (e.rep_unit === 'max') return null
  return Math.round((e.rep_min + e.rep_max) / 2)
}

export function repDuration(e: PlannedExercise): number {
  return Math.max(1.6, e.tempo_up_s + e.tempo_down_s + e.tempo_pause_s + 0.4)
}

export function timedSeconds(e: PlannedExercise): number | null {
  const mid = Math.round((e.rep_min + e.rep_max) / 2)
  if (e.rep_unit === 'seconds') return mid
  if (e.rep_unit === 'minutes') return mid * 60
  return null
}

export function buildTimeline(plan: PlannedDay): Block[] {
  const blocks: Block[] = []
  if (plan.warmup && plan.warmupDuration > 0) {
    blocks.push({ kind: 'warmup', text: plan.warmup, duration: plan.warmupDuration })
  }
  plan.exercises.forEach((e, exIdx) => {
    if (e.rep_unit === 'check') {
      blocks.push({ kind: 'check', exIdx, exercise: e })
    } else {
      for (let setNo = 1; setNo <= e.planned_sets; setNo++) {
        const sides: Array<'left' | 'right' | null> = e.per_side ? ['left', 'right'] : [null]
        for (const side of sides) {
          blocks.push({
            kind: 'set',
            exIdx,
            exercise: e,
            setNo,
            totalSets: e.planned_sets,
            side,
            resultKey: `${exIdx}-${setNo}${side ? `-${side}` : ''}`,
            targetReps: repTarget(e),
            repDuration: repDuration(e),
            timed: timedSeconds(e),
          })
        }
        const isLast = setNo === e.planned_sets
        if (!isLast && e.rest_sec > 0) {
          blocks.push({
            kind: 'rest',
            exIdx,
            afterSet: setNo,
            duration: e.rest_sec,
            nextLabel: `${e.name}, set ${setNo + 1}`,
            exercise: e,
            captureLoad: e.increment_kg > 0,
          })
        }
      }
      blocks.push({ kind: 'log', exIdx, exercise: e })
      const next = plan.exercises[exIdx + 1]
      if (next && e.rest_sec > 0) {
        blocks.push({
          kind: 'rest',
          exIdx,
          afterSet: e.planned_sets,
          duration: e.rest_sec,
          nextLabel: next.name,
          exercise: e,
          captureLoad: false,
        })
      }
    }
  })
  blocks.push({ kind: 'done' })
  return blocks
}

export function countedRepsForSet(
  counted: Record<string, number>,
  exIdx: number,
  setNo: number,
  perSide: boolean,
): number | undefined {
  const explicit = counted[`${exIdx}-${setNo}`]
  if (explicit != null) return explicit
  if (!perSide) return counted[`${exIdx}-${setNo}`]
  const left = counted[`${exIdx}-${setNo}-left`]
  const right = counted[`${exIdx}-${setNo}-right`]
  if (left == null && right == null) return undefined
  if (left == null) return right
  if (right == null) return left
  return Math.min(left, right)
}

export function plannedSetCount(plan: PlannedDay): number {
  return plan.exercises.reduce((sum, e) => sum + (e.optional ? 0 : e.planned_sets), 0)
}
