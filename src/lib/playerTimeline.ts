/* Builds the guided player's block timeline from an adjusted plan. */
import type { PlannedDay, PlannedExercise } from './plan'
import { isConditioningFocusT25, isFocusT25Name } from './focusT25.ts'
import {
  movementForExercise,
  shouldCaptureLoad,
  sideSwitchSeconds,
  transitionSeconds,
} from './sessionShape.ts'
import {
  buildWorkSequence,
  workGroupRecoverySeconds,
  type WorkPosition,
} from './workGrouping.ts'

export { buildWorkSequence } from './workGrouping.ts'

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
      groupLabel: string | null
      round: number | null
    }
  | { kind: 'side_switch'; exIdx: number; setNo: number; duration: number; exercise: PlannedExercise; nextSide: 'right' }
  | {
      kind: 'rest'
      exIdx: number
      afterSet: number
      duration: number
      nextLabel: string
      exercise: PlannedExercise
      captureLoad: boolean
      reviewExercise?: boolean
      workGroupTransition: boolean
      groupLabel: string | null
      round: number | null
    }
  | { kind: 'log'; exIdx: number; exercise: PlannedExercise }
  | { kind: 'done' }

export function canAdvanceRest(
  block: Extract<Block, { kind: 'rest' }>,
  reviewFinalized: boolean | undefined,
): boolean {
  return !block.reviewExercise || reviewFinalized === true
}

export function canJumpToCheckpoint(
  current: Block,
  currentIndex: number,
  targetIndex: number,
  reviewFinalized: boolean | undefined,
): boolean {
  if (targetIndex <= currentIndex || current.kind !== 'rest') return true
  return canAdvanceRest(current, reviewFinalized)
}

/**
 * Passive blocks are allowed to keep counting while the PWA is backgrounded.
 * Active sets are intentionally excluded: a throttled/hidden browser must
 * never manufacture completed repetitions.
 */
export function isPassiveTimerBlock(block: Block | undefined): boolean {
  return block?.kind === 'warmup' || block?.kind === 'rest' || block?.kind === 'side_switch'
}

export function reconcilePlayerElapsed({
  block,
  elapsed,
  paused,
  persistedAt,
  now = Date.now(),
}: {
  block: Block | undefined
  elapsed: number
  paused: boolean
  persistedAt?: string | null
  now?: number
}): { elapsed: number; paused: boolean } {
  const safeElapsed = Math.max(0, Number.isFinite(elapsed) ? elapsed : 0)
  if (paused || !persistedAt) return { elapsed: safeElapsed, paused }
  const persistedMs = Date.parse(persistedAt)
  if (!Number.isFinite(persistedMs)) return { elapsed: safeElapsed, paused }
  if (isPassiveTimerBlock(block)) {
    return {
      elapsed: safeElapsed + Math.max(0, (now - persistedMs) / 1000),
      paused: false,
    }
  }
  /* A restored active set waits for an explicit resume. */
  if (block?.kind === 'set') return { elapsed: safeElapsed, paused: true }
  return { elapsed: safeElapsed, paused }
}

/**
 * The closest captured set is the least surprising default for the next set.
 * This scans backwards rather than falling through to the original 2.5 kg
 * recommendation after a person has already entered a real working load.
 */
export function prefillSetWeight(
  setWeights: Array<number | null | undefined>,
  setNo: number,
  exerciseWeight: number | null | undefined,
  recommendedWeight: number | null | undefined,
): number | null {
  const currentIndex = Math.max(0, setNo - 1)
  for (let index = Math.min(currentIndex, setWeights.length - 1); index >= 0; index -= 1) {
    const candidate = setWeights[index]
    if (candidate != null && Number.isFinite(candidate)) return candidate
  }
  if (exerciseWeight != null && Number.isFinite(exerciseWeight)) return exerciseWeight
  if (recommendedWeight != null && Number.isFinite(recommendedWeight)) return recommendedWeight
  return null
}

/**
 * Corrections entered during a break are the best starting point for the next
 * set. Fall back to the just-counted set only when no earlier correction
 * exists, then finally to the authored target.
 */
export function prefillSetReps(
  setReps: Array<number | null | undefined>,
  setNo: number,
  countedReps: number | null | undefined,
  targetReps: number | null | undefined,
): number {
  const currentIndex = Math.max(0, setNo - 1)
  for (let index = Math.min(currentIndex, setReps.length - 1); index >= 0; index -= 1) {
    const candidate = setReps[index]
    if (candidate != null && Number.isFinite(candidate)) return Math.max(0, Math.round(candidate))
  }
  if (countedReps != null && Number.isFinite(countedReps)) return Math.max(0, Math.round(countedReps))
  if (targetReps != null && Number.isFinite(targetReps)) return Math.max(0, Math.round(targetReps))
  return 0
}

/**
 * Safari occasionally starts speech but never emits `end` or `error`. The
 * player waits long enough for the full exercise announcement, then releases
 * the cadence gate so a completed set can never remain stuck on its last rep.
 */
export function speechAnnouncementFallbackMs(text: string): number {
  const estimated = 900 + text.trim().length * 90
  return Math.max(2_500, Math.min(9_000, estimated))
}

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

function workGroupRecovery(exercises: PlannedExercise[], groupId: string): number {
  return workGroupRecoverySeconds(exercises, groupId, (exercise) => exercise.rest_sec)
}

function nextWorkLabel(position: WorkPosition, exercise: PlannedExercise): string {
  return position.groupLabel
    ? `${position.groupLabel} · ${exercise.name}, round ${position.setNo}`
    : `${exercise.name}, set ${position.setNo}`
}

export function buildTimeline(plan: PlannedDay): Block[] {
  const movementOf = (e: PlannedExercise) => movementForExercise(e)
  const blocks: Block[] = []
  if (plan.warmup && plan.warmupDuration > 0) {
    blocks.push({ kind: 'warmup', text: plan.warmup, duration: plan.warmupDuration })
  }
  const sequence = buildWorkSequence(plan.exercises)
  sequence.forEach((position, sequenceIndex) => {
    const exIdx = position.exIdx
    const e = plan.exercises[exIdx]
    if (e.rep_unit === 'check') {
      blocks.push({ kind: 'check', exIdx, exercise: e })
    } else {
      const setNo = position.setNo
        const sides: Array<'left' | 'right' | null> = e.per_side ? ['left', 'right'] : [null]
        for (const [sideIndex, side] of sides.entries()) {
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
            groupLabel: position.groupLabel,
            round: position.groupId ? setNo : null,
          })
          if (side === 'left' && sideIndex < sides.length - 1) {
            blocks.push({
              kind: 'side_switch',
              exIdx,
              setNo,
              duration: sideSwitchSeconds(movementOf(e)),
              exercise: e,
              nextSide: 'right',
            })
          }
        }
      const nextPosition = sequence[sequenceIndex + 1]
      const next = nextPosition ? plan.exercises[nextPosition.exIdx] : undefined
      if (next && nextPosition) {
        const sameGroup = position.groupId != null && position.groupId === nextPosition.groupId
        const withinRound = sameGroup && position.setNo === nextPosition.setNo
        const betweenRounds = sameGroup && nextPosition.setNo > position.setNo
        const sameExercise = exIdx === nextPosition.exIdx
        const reviewExercise = setNo === e.planned_sets && !sameExercise
        const duration = withinRound
          ? 15
          : betweenRounds
            ? workGroupRecovery(plan.exercises, position.groupId!)
            : sameExercise
              ? e.rest_sec
              : transitionSeconds(movementOf(e), movementOf(next), e.rest_sec)
        if (duration > 0 || reviewExercise) {
        blocks.push({
          kind: 'rest',
          exIdx,
          afterSet: setNo,
          duration,
          nextLabel: nextWorkLabel(nextPosition, next),
          exercise: e,
          captureLoad: !reviewExercise && shouldCaptureLoad(e),
          reviewExercise,
          workGroupTransition: withinRound,
          groupLabel: position.groupLabel,
          round: position.groupId ? setNo : null,
        })
        }
      } else {
        blocks.push({ kind: 'log', exIdx, exercise: e })
      }
    }
  })
  blocks.push({ kind: 'done' })
  return blocks
}

/**
 * A variant-aware preview estimate. ProgramDay.est_minutes remains the
 * authored Full estimate, while Light may contain a 25-minute external T25
 * check and cannot be estimated from exercise count alone.
 */
export function estimatedTimelineMinutes(plan: PlannedDay): number {
  const seconds = buildTimeline(plan).reduce((total, block) => {
    if (block.kind === 'warmup' || block.kind === 'rest' || block.kind === 'side_switch') {
      return total + block.duration
    }
    if (block.kind === 'set') {
      if (block.timed != null) return total + block.timed
      return total + (block.targetReps ?? 12) * block.repDuration
    }
    if (block.kind === 'check') {
      if (!isFocusT25Name(block.exercise.name)) return total + 30
      const explicit = block.exercise.notes.match(/\|\s*(\d+)\s*min\s*\|/i)?.[1]
      return total + Math.max(1, Number(explicit) || 25) * 60
    }
    if (block.kind === 'log') return total + 20
    return total
  }, 0)
  return Math.max(1, Math.round(seconds / 60))
}

export function plannedWorkoutDurationBreakdown(
  plan: PlannedDay,
  authoredFullMinutes: number,
  lite: boolean,
): { total: number; primary: number; focusT25: number } {
  const total = Math.max(1, lite ? estimatedTimelineMinutes(plan) : authoredFullMinutes)
  const mixedConditioning = plan.programDay?.day_type !== 't25'
    && plan.exercises.some((exercise) => isConditioningFocusT25(exercise.name))
  const focusT25 = mixedConditioning ? 25 : 0
  return {
    total,
    primary: Math.max(1, total - focusT25),
    focusT25,
  }
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
