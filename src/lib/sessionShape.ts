/**
 * The timings a live follow-along session actually runs on.
 *
 * A guided session is a sequence of waits as much as it is a sequence of sets,
 * and until now most of those waits were guesses. Side switches fired only for
 * exercises whose *name* matched a regex for Bulgarian split squats, so every
 * other single-sided movement sent the follower straight from the left leg to
 * the right with no pause at all. Moving between exercises reused the
 * between-sets rest and ignored that the next movement has to be set up. And
 * the last set of every exercise never asked what was lifted.
 *
 * Each interval here is derived from the movement rather than assumed, so the
 * session paces itself the way a coach standing next to you would.
 */

import { MOVEMENTS, MOVEMENT_ALIASES, type Movement } from '../data/movements.ts'
import type { SessionMode } from './types.ts'
import { buildWorkSequence, workGroupRecoverySeconds } from './workGrouping.ts'
import {
  holdFor,
  resolveMovement,
  restSecondsFor,
  tempoFieldsFor,
  type TrainingIntent,
} from './liftingTempo.ts'

/* Programme rows are authored with their own names, so the movement behind one
 * is found by id where it is recorded and by name where it is not. */
export function movementForExercise(
  exercise: { name: string; movement_id?: string | null },
): Movement | null {
  if (exercise.movement_id) {
    const byId = MOVEMENTS.find((m) => m.id === exercise.movement_id)
    if (byId) return byId
  }
  return resolveMovement(exercise.name, MOVEMENTS, MOVEMENT_ALIASES)
}

/* Kit that has to be physically moved, re-pinned or walked around before the
 * second side can start. */
const REPOSITIONING = new Set([
  'bench', 'adjustable_bench', 'plyo_box', 'step', 'cable_stack', 'rack',
  'smith_machine', 'landmine', 'reformer', 'chair', 'anchor_point',
])

/**
 * How long switching sides genuinely takes.
 *
 * Two things are happening and only one of them is transition. The working
 * limb does need to be swapped over, which takes as long as the equipment
 * makes it take -- resetting a rear foot on a bench is not the same as moving
 * a dumbbell to the other hand. But on anything systemically hard the limiter
 * is breathing rather than the limb, and a Bulgarian split squat leaves most
 * people needing a moment before the second leg is worth training. The three
 * seconds the player used for every switch covered neither.
 */
export function sideSwitchSeconds(movement: Movement | null): number {
  if (!movement) return 10
  const kit = new Set([...movement.equipment, ...movement.equipmentAnyOf.flat()])
  const repositioning = [...kit].some((item) => REPOSITIONING.has(item)) ? 12 : 4
  // The second side is not fresh if the first one left you out of breath.
  const breather = movement.fatigueCost >= 4 ? 15 : movement.fatigueCost >= 3 ? 8 : 0
  return Math.min(30, repositioning + breather)
}

/**
 * How long the gap between two exercises should be.
 *
 * The previous exercise still needs its recovery -- the last set is not free
 * just because it was the last -- and the next one needs setting up. Those
 * overlap rather than stack, because setting up is what you do while resting,
 * so this is the longer of the two rather than the sum of them.
 */
export function transitionSeconds(
  finished: Movement | null,
  next: Movement | null,
  authoredRest: number,
): number {
  const setup = next?.setupSeconds ?? 30
  let recovery = authoredRest > 0 ? authoredRest : 60
  // Walking away from a heavy hinge into the next exercise is where sessions
  // quietly become harder than they were written to be.
  if (finished && finished.fatigueCost >= 4) recovery = Math.max(recovery, 90)
  return Math.max(recovery, setup)
}

/**
 * Whether the player should ask what was lifted after this set.
 *
 * It asked after every set except the last one of each exercise, which is the
 * set most likely to be the heaviest and the one whose number the next session
 * is built from.
 */
export function shouldCaptureLoad(exercise: { increment_kg: number }): boolean {
  return exercise.increment_kg > 0
}

/** Sets on a single-sided movement are performed twice, once per side. */
export function isPerSide(
  exercise: { per_side: boolean },
  movement: Movement | null,
): boolean {
  return exercise.per_side || movement?.unilateral === true
}

/**
 * The fields that make an exercise row work in a live follow-along, derived
 * from the movement rather than typed in by hand.
 *
 * Every path that creates a workout used to fill these itself: the custom
 * builder wrote 2-0-1 and whatever rest the picker defaulted to, the induction
 * generator wrote 2-0-1 and a per-template rest, and the seeds wrote their own.
 * A session is only as well paced as whichever of those produced it, which is
 * why a hand-built plan and a generated one felt like different products.
 */
export interface FollowAlongFields {
  movement_id: string | null
  tempo_down_s: number
  tempo_pause_s: number
  tempo_up_s: number
  tempo_note: string
  rest_sec: number
  per_side: boolean
  increment_kg: number
}

export function followAlongFields(
  name: string,
  intent: TrainingIntent,
  authored: Partial<Pick<FollowAlongFields, 'rest_sec' | 'per_side' | 'increment_kg'>> = {},
  /* Whoever built the session may have chosen the rest deliberately. A
   * generator's template numbers are placeholders and should give way to the
   * movement; a trainer typing ninety seconds means ninety seconds. */
  options: { keepAuthoredRest?: boolean } = {},
): FollowAlongFields {
  const movement = resolveMovement(name, MOVEMENTS, MOVEMENT_ALIASES)
  if (!movement) {
    // Nothing to derive from, so the authored values stand rather than being
    // replaced with a guess dressed up as a recommendation.
    return {
      movement_id: null,
      tempo_down_s: 2, tempo_pause_s: 0, tempo_up_s: 1, tempo_note: '',
      rest_sec: authored.rest_sec ?? 60,
      per_side: authored.per_side ?? false,
      increment_kg: authored.increment_kg ?? 0,
    }
  }
  const tempo = tempoFieldsFor(movement, intent)
  const hold = holdFor(movement, intent)
  return {
    movement_id: movement.id,
    ...tempo,
    rest_sec: options.keepAuthoredRest && authored.rest_sec != null
      ? authored.rest_sec
      : hold ? hold.restSeconds : restSecondsFor(movement, intent),
    // A movement the library knows to be single-sided is single-sided even
    // when whoever typed the row did not tick the box.
    per_side: authored.per_side || movement.unilateral,
    increment_kg: authored.increment_kg && authored.increment_kg > 0
      ? authored.increment_kg
      : movement.minIncrementKg ?? 0,
  }
}

/** What the rest picker should start on when an exercise is added by hand. */
export function suggestedRestSeconds(name: string, intent: TrainingIntent): number | null {
  const movement = resolveMovement(name, MOVEMENTS, MOVEMENT_ALIASES)
  if (!movement) return null
  const hold = holdFor(movement, intent)
  return hold ? hold.restSeconds : restSecondsFor(movement, intent)
}

/**
 * How long a session will really take, from the same intervals the player
 * counts down.
 *
 * The duration on a session card used to be a number typed into the template,
 * so a plan could advertise thirty-eight minutes and run twenty-seven. This
 * mirrors the player's arithmetic deliberately -- a test asserts the two agree
 * -- and lives here rather than in the timeline because the plan module and
 * the induction generator already import each other.
 */
export function estimateSessionSeconds(
  exercises: Array<{
    name: string
    movement_id?: string | null
    sets: number
    rep_min: number
    rep_max: number
    rep_unit: string
    per_side: boolean
    rest_sec: number
    increment_kg: number
    tempo_down_s: number
    tempo_pause_s: number
    tempo_up_s: number
    work_group_id?: string | null
    work_group_position?: number | null
  }>,
  warmupSeconds = 0,
): number {
  let total = warmupSeconds
  const sequence = buildWorkSequence(exercises)
  sequence.forEach((position, index) => {
    const e = exercises[position.exIdx]
    if (e.rep_unit === 'check') return
    const movement = movementForExercise(e)
    const perRep = Math.max(1.6, e.tempo_up_s + e.tempo_down_s + e.tempo_pause_s + 0.4)
    const mid = Math.round((e.rep_min + e.rep_max) / 2)
    const timed = e.rep_unit === 'seconds' ? mid
      : e.rep_unit === 'minutes' ? mid * 60 : null
    const sides = isPerSide(e, movement) ? 2 : 1

    total += (timed ?? mid * perRep) * sides
    if (sides === 2) total += sideSwitchSeconds(movement)
    const nextPosition = sequence[index + 1]
    const next = nextPosition ? exercises[nextPosition.exIdx] : undefined
    if (next && nextPosition) {
      const sameGroup = position.groupId != null && position.groupId === nextPosition.groupId
      if (sameGroup && position.setNo === nextPosition.setNo) {
        total += 15
      } else if (sameGroup && nextPosition.setNo > position.setNo) {
        total += workGroupRecoverySeconds(exercises, position.groupId!, (exercise) => exercise.rest_sec)
      } else if (position.exIdx === nextPosition.exIdx) {
        total += e.rest_sec
      } else {
        total += transitionSeconds(movement, movementForExercise(next), e.rest_sec)
      }
    } else {
      total += 20 // logging the last exercise
    }
  })
  return total
}

/* ------------------------------------------------------- MODE PREFERENCE
 *
 * Which of the two ways to train somebody wants is a preference, not something
 * to be inferred. It was briefly derived from the questionnaire -- already
 * training and chasing size meant the list, coming back from a layoff meant
 * the paced player -- which made the app decide something about the user that
 * the user is better placed to decide, and made the behaviour unpredictable
 * from the outside.
 *
 * So both are offered on every session, equally, and the last choice is
 * remembered so the option that is about to happen is the one that happened
 * last time. The day's own mode is only the starting point for someone who
 * has never chosen.
 */

const MODE_KEY = 'apex.session-mode'

export function rememberedSessionMode(): SessionMode | null {
  try {
    const stored = globalThis.localStorage?.getItem(MODE_KEY)
    return stored === 'guided' || stored === 'tracked' ? stored : null
  } catch {
    return null
  }
}

export function rememberSessionMode(mode: SessionMode): void {
  try {
    globalThis.localStorage?.setItem(MODE_KEY, mode)
  } catch {
    /* A private window that refuses storage is not a reason to fail a workout. */
  }
}

/** What a given day should open on: the last choice, then the day's own. */
export function preferredSessionMode(dayMode: SessionMode | null | undefined): SessionMode {
  return rememberedSessionMode() ?? dayMode ?? 'guided'
}
