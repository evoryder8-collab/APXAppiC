/**
 * How a rep is actually performed, and how long to rest afterwards.
 *
 * Two things this deliberately does not do.
 *
 * It does not claim a single optimal tempo. The best available synthesis
 * (Schoenfeld, Ogborn & Krieger, 2015) found hypertrophy essentially
 * equivalent across rep durations from roughly half a second to eight seconds,
 * falling off only past about ten. Shipping "3-1-1-0" as *the* correct tempo
 * would be false precision, and the first knowledgeable user to look would be
 * right to say so. What the evidence does support is a controlled eccentric,
 * an intent to accelerate the concentric, and a pause that lands where the
 * movement actually loads the muscle. That is what is prescribed here.
 *
 * It does not shorten rest to chase hypertrophy. The older idea that short
 * rests drive growth through metabolic stress did not survive testing:
 * Schoenfeld et al. (2016) found three minutes beat one minute for *both*
 * size and strength. Rest is shortened here only when the adaptation being
 * trained is genuinely work capacity, because that is the one case where the
 * incomplete recovery is the point rather than a cost.
 */

import type { Movement } from '../data/movements.ts'

/* The generator's own goal set. Wider than the induction questionnaire's three
 * options, and mapped onto them, so adding a goal here cannot change what the
 * existing web questionnaire renders. */
export type TrainingIntent =
  | 'rebuild'
  | 'hypertrophy'
  | 'strength'
  | 'endurance'
  | 'power'

export interface Tempo {
  /* Seconds lowering under control. */
  eccentricSeconds: number
  /* Seconds held at the loaded end of the range, which is the stretched
   * position for most movements and the top for hip extension. */
  pauseSeconds: number
  /* Where the pause happens, so the cue can name it rather than say "pause". */
  pausePosition: 'lengthened' | 'shortened' | 'mid' | 'none'
  /* Seconds lifting. Intent matters more than the clock: on a heavy set the
   * bar moves slowly no matter how hard it is driven. */
  concentricSeconds: number
  concentricIntent: 'controlled' | 'accelerate' | 'maximal'
  /* Seconds held at the unloaded end, which is almost always zero. */
  endPauseSeconds: number
  /* The written cue, in the order a lifter experiences it. */
  cue: string
  /* Seconds one rep costs, used for honest session length. */
  repSeconds: number
}

/* Eccentric, pause and concentric by intent. Every duration sits inside the
 * band the evidence treats as equivalent, so these are chosen for coaching
 * reasons -- control, position, intent -- rather than pretending to an
 * optimum that the research does not show. */
const PROFILES: Record<TrainingIntent, {
  eccentric: number; pause: number; concentric: number
  intent: Tempo['concentricIntent']; why: string
}> = {
  rebuild: {
    eccentric: 3, pause: 1, concentric: 2, intent: 'controlled',
    why: 'Slow enough that position is never in doubt, because the first block is about earning the range back rather than loading it.',
  },
  hypertrophy: {
    eccentric: 3, pause: 1, concentric: 1, intent: 'accelerate',
    why: 'A long eccentric and a pause where the muscle is loaded, then drive back with intent.',
  },
  strength: {
    eccentric: 2, pause: 0, concentric: 1, intent: 'maximal',
    why: 'Controlled down, then as hard as you can up. The bar will move slowly on a heavy set; the intent is what recruits.',
  },
  endurance: {
    eccentric: 1, pause: 0, concentric: 1, intent: 'controlled',
    why: 'A steady repeatable rhythm. Nothing forced, because the point is the twentieth rep, not the second.',
  },
  power: {
    eccentric: 1, pause: 0, concentric: 1, intent: 'maximal',
    why: 'Absorb and reverse quickly. Time spent under load is the enemy here.',
  },
}

const POSITION_CUE: Record<'lengthened' | 'shortened' | 'mid', string> = {
  lengthened: 'in the stretch at the bottom',
  shortened: 'squeezed hard at the top',
  mid: 'at the hardest point of the range',
}

/**
 * The tempo for one movement under one intent, or null when timing a rep would
 * be meaningless: a jump, an Olympic lift, a plank, a breath-paced flow.
 */
export function tempoFor(m: Movement, intent: TrainingIntent): Tempo | null {
  if (!m.tempoApplies) return null
  const profile = PROFILES[intent]

  // The pause only earns its place where the movement actually loads the
  // muscle. Holding the top of a squat rests the legs; holding the top of a
  // hip thrust is the hardest part of the lift.
  const position = m.peakTension === 'held' ? 'mid' : m.peakTension
  let pause = profile.pause
  // A pause at a joint's end range is the wrong place to load someone who is
  // rebuilding, and pure endurance work has no pause at all.
  if (intent === 'endurance' || intent === 'power') pause = 0
  const pausePosition: Tempo['pausePosition'] = pause > 0 ? position : 'none'

  const eccentric = profile.eccentric
  const concentric = profile.concentric
  const repSeconds = eccentric + pause + concentric

  const secs = (n: number) => `${n} second${n === 1 ? '' : 's'}`
  const parts = [`${secs(eccentric)} down`]
  if (pause > 0) parts.push(`${secs(pause)} ${POSITION_CUE[position]}`)
  parts.push(profile.intent === 'controlled'
    ? `${secs(concentric)} up`
    : profile.intent === 'accelerate' ? 'drive back up with intent'
      : 'then up as fast as you can make it move')

  return {
    eccentricSeconds: eccentric,
    pauseSeconds: pause,
    pausePosition,
    concentricSeconds: concentric,
    concentricIntent: profile.intent,
    endPauseSeconds: 0,
    cue: parts.join(', ') + '.',
    repSeconds,
  }
}

/** Why this tempo, in one sentence, so the plan can defend itself. */
export function tempoRationale(intent: TrainingIntent): string {
  return PROFILES[intent].why
}

/**
 * Rest between sets. This is where the goal genuinely changes the prescription,
 * and where the popular advice is backwards for one of the goals.
 */
export function restSecondsFor(m: Movement, intent: TrainingIntent): number {
  const compound = m.role === 'primary'
  // Systemically expensive movements need more regardless of goal: nobody
  // repeats a heavy hinge well after ninety seconds.
  const heavy = m.fatigueCost >= 4

  switch (intent) {
    case 'strength':
      // Long enough that the next set is limited by strength, not by breath.
      return compound ? (heavy ? 300 : 210) : 120
    case 'hypertrophy':
      // Deliberately not short. Three minutes beat one minute for both size
      // and strength when this was actually tested, so cutting rest here would
      // cost the user the thing they came for.
      return compound ? (heavy ? 180 : 150) : 90
    case 'power':
      // Quality is the whole point; a tired jump is a different exercise.
      return compound ? 180 : 120
    case 'endurance':
      // The only goal where incomplete recovery is the adaptation rather than
      // a cost, so this is the one place shortening rest is correct.
      return compound ? (heavy ? 75 : 60) : 40
    case 'rebuild':
      return compound ? 90 : 60
  }
}

/** Seconds a full set costs, tempo included, so session length is not a guess. */
export function setSeconds(m: Movement, reps: number, intent: TrainingIntent): number {
  const tempo = tempoFor(m, intent)
  const perRep = tempo ? tempo.repSeconds : 3.5
  const sides = m.unilateral ? 2 : 1
  return reps * perRep * sides
}
