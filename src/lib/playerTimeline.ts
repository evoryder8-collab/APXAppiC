/* Builds the guided player's block timeline from an adjusted plan. */
import type { PlannedDay, PlannedExercise } from './plan'

export type Block =
  | { kind: 'warmup'; text: string; duration: number }
  | {
      kind: 'set'
      exIdx: number
      exercise: PlannedExercise
      setNo: number
      totalSets: number
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
  const blocks: Block[] = [{ kind: 'warmup', text: plan.warmup, duration: 60 }]
  plan.exercises.forEach((e, exIdx) => {
    const sides = e.per_side ? 2 : 1
    const sets = e.planned_sets * (sides === 2 && e.rep_unit !== 'reps' ? 2 : 1)
    const totalSets = e.rep_unit === 'reps' ? e.planned_sets : sets
    for (let s = 1; s <= totalSets; s++) {
      blocks.push({
        kind: 'set',
        exIdx,
        exercise: e,
        setNo: s,
        totalSets,
        targetReps: repTarget(e),
        repDuration: repDuration(e),
        timed: timedSeconds(e),
      })
      const isLast = s === totalSets
      if (!isLast && e.rest_sec > 0) {
        blocks.push({
          kind: 'rest',
          exIdx,
          afterSet: s,
          duration: e.rest_sec,
          nextLabel: `${e.name}, set ${s + 1}`,
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
        afterSet: totalSets,
        duration: Math.min(e.rest_sec, 90),
        nextLabel: next.name,
        exercise: e,
        captureLoad: false,
      })
    }
  })
  blocks.push({ kind: 'done' })
  return blocks
}

export function plannedSetCount(plan: PlannedDay): number {
  return plan.exercises.reduce((sum, e) => sum + e.planned_sets, 0)
}
