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

/* How each goal bends the class's own tempo. The class supplies the shape --
 * a four second hamstring eccentric, a two second calf pause -- and the goal
 * adjusts it. Every resulting duration sits inside the band the evidence
 * treats as equivalent, so these are coaching choices rather than a claimed
 * optimum the research does not show. */
const INTENT_RULES: Record<TrainingIntent, {
  intent: Tempo['concentricIntent']; why: string
}> = {
  rebuild: {
    intent: 'controlled',
    why: 'Slow enough that position is never in doubt, because the first block is about earning the range back rather than loading it.',
  },
  hypertrophy: {
    intent: 'accelerate',
    why: 'A long eccentric and a pause where the muscle is actually loaded, then drive back with intent. Each muscle group is timed by its own mechanism rather than one blanket rule.',
  },
  strength: {
    intent: 'maximal',
    why: 'Controlled down, then as hard as you can up. The bar will move slowly on a heavy set; the intent is what recruits.',
  },
  endurance: {
    intent: 'controlled',
    why: 'A steady repeatable rhythm with shorter rest. Lighter and faster than the hypertrophy prescription, because the point is the twentieth rep rather than the second.',
  },
  power: {
    intent: 'maximal',
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
  const spec = TEMPO_CLASSES[m.tempoClass] ?? TEMPO_CLASSES.standard_compound
  const rule = INTENT_RULES[intent]

  // The pause only earns its place where the movement actually loads the
  // muscle. Holding the top of a squat rests the legs; holding the top of a
  // hip thrust is the hardest part of the lift.
  const position = m.peakTension === 'held' ? 'mid' : m.peakTension

  let eccentric = spec.eccentric
  let pause = spec.pause
  const concentric = spec.concentric

  // Goals that chase load or speed shorten the eccentric and drop pauses --
  // unless the pause is the mechanism. Bouncing a calf raise is not a faster
  // calf raise, it is a different and worse exercise, so that pause survives.
  if (intent === 'strength') {
    eccentric = Math.max(2, eccentric - 1)
    if (!spec.pauseIsMechanism) pause = 0
  } else if (intent === 'endurance') {
    eccentric = spec.pauseIsMechanism ? Math.min(2, eccentric) : 1
    pause = spec.pauseIsMechanism ? 1 : 0
  } else if (intent === 'power') {
    eccentric = 1
    pause = spec.pauseIsMechanism ? 1 : 0
  } else if (intent === 'rebuild') {
    pause = Math.max(1, pause)
  }

  const pausePosition: Tempo['pausePosition'] = pause > 0 ? position : 'none'
  const repSeconds = eccentric + pause + concentric

  const secs = (n: number) => `${n} second${n === 1 ? '' : 's'}`
  const parts = [`${secs(eccentric)} down`]
  if (pause > 0) parts.push(`${secs(pause)} ${POSITION_CUE[position]}`)
  parts.push(rule.intent === 'controlled'
    ? `${secs(concentric)} up`
    : rule.intent === 'accelerate' ? 'drive back up with intent'
      : 'then up as fast as you can make it move')

  return {
    eccentricSeconds: eccentric,
    pauseSeconds: pause,
    pausePosition,
    concentricSeconds: concentric,
    concentricIntent: rule.intent,
    endPauseSeconds: 0,
    cue: parts.join(', ') + '.',
    repSeconds,
  }
}

/** Why this tempo, in one sentence, so the plan can defend itself. */
export function tempoRationale(intent: TrainingIntent): string {
  return INTENT_RULES[intent].why
}

/**
 * Rest between sets. This is where the goal genuinely changes the prescription,
 * and where the popular advice is backwards for one of the goals.
 */
export function restSecondsFor(m: Movement, intent: TrainingIntent): number {
  const scale = (TEMPO_CLASSES[m.tempoClass] ?? TEMPO_CLASSES.standard_compound).restScale
  return Math.round(baseRest(m, intent) * scale)
}

function baseRest(m: Movement, intent: TrainingIntent): number {
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

/* ------------------------------------------------------------------ CLASSES
 *
 * Which muscle a movement trains changes how it should be trained, but not in
 * every respect and not equally everywhere. Two rules keep this table honest.
 *
 * Where the evidence differentiates, it is followed. The soleus is roughly
 * eighty per cent type I fibre, the most fatigue-resistant major muscle in the
 * body, and it earns higher reps *for hypertrophy* rather than being pushed
 * toward endurance work. The calf has a powerful stretch-shortening cycle, so
 * bouncing out of the bottom substitutes elastic recoil for muscle work, which
 * is why its pause survives into every goal instead of being a hypertrophy
 * nicety. Eccentric-emphasis hamstring work carries the strongest injury
 * reduction evidence of any single exercise. The triceps long head grows more
 * from overhead work than from pushdowns because only the overhead position
 * lengthens it.
 *
 * Where the evidence does not differentiate, one profile is used and that is
 * said plainly. For ordinary multi-joint pressing, pulling and squatting there
 * is no good evidence that tempo should vary by muscle, so inventing a
 * different number per exercise would be decoration wearing a lab coat.
 */

export type Evidence = 'strong' | 'moderate' | 'extrapolated'

interface ClassSpec {
  label: string
  evidence: Evidence
  why: string
  /* Tempo under a hypertrophy goal. Other goals derive from it. */
  eccentric: number
  pause: number
  concentric: number
  /* True where the pause is the mechanism rather than a refinement, so it
   * survives into goals that otherwise drop pauses. */
  pauseIsMechanism: boolean
  /* Rep ranges per goal. This is where the calves differ most from everything
   * else, and where the user's goal genuinely changes the prescription. */
  reps: Record<TrainingIntent, [number, number]>
  /* Multiplies the rest computed from role and fatigue. A cuff drill does not
   * need three minutes; a heavy hinge does. */
  restScale: number
  /* What "a good rep" means here. Full range beats partial range for
   * hypertrophy, and the advantage comes from the lengthened end, so this is
   * where execution genuinely differs between movements -- more so than tempo,
   * which is why it is stated per class rather than invented per exercise. */
  rom: string
}

export const TEMPO_CLASSES: Record<string, ClassSpec> = {
  standard_compound: {
    label: 'Multi-joint strength work',
    evidence: 'strong',
    why: 'No good evidence differentiates rep tempo by muscle for ordinary pressing, pulling and squatting, so one controlled profile is used rather than a different invented number for each.',
    eccentric: 3, pause: 1, concentric: 1, pauseIsMechanism: false,
    reps: { rebuild: [8, 15], hypertrophy: [6, 12], strength: [4, 6], endurance: [15, 25], power: [3, 5] },
    restScale: 1,
    rom: 'Full range every rep. Partial range costs growth, and the part usually skipped is the stretched half, which is the half that matters most.',
  },
  calf_soleus: {
    label: 'Soleus, bent knee',
    evidence: 'strong',
    why: 'The soleus is around eighty per cent slow-twitch fibre, the most fatigue-resistant major muscle in the body. High reps here are the hypertrophy prescription, not an endurance compromise.',
    eccentric: 2, pause: 2, concentric: 1, pauseIsMechanism: true,
    reps: { rebuild: [12, 20], hypertrophy: [12, 25], strength: [10, 15], endurance: [25, 40], power: [8, 12] },
    restScale: 0.6,
    rom: 'All the way down until the heel is below the step and the calf is genuinely long, then all the way up. Half-range calf raises are why calves are thought not to respond.',
  },
  calf_gastroc: {
    label: 'Gastrocnemius, straight knee',
    evidence: 'moderate',
    why: 'The calf stores and returns elastic energy, so bouncing out of the bottom replaces muscle work with recoil. The pause in the stretch is the exercise, which is why it stays in place whatever the goal.',
    eccentric: 2, pause: 2, concentric: 1, pauseIsMechanism: true,
    reps: { rebuild: [10, 15], hypertrophy: [10, 20], strength: [8, 12], endurance: [20, 30], power: [6, 10] },
    restScale: 0.7,
    rom: 'Full stretch at the bottom with a straight knee, full contraction at the top. No bouncing: the tendon will happily do the work the muscle should be doing.',
  },
  hamstring_eccentric: {
    label: 'Hamstring, eccentric-led',
    evidence: 'strong',
    why: 'Eccentric hamstring work has the strongest injury-reduction evidence of any single exercise, and the lengthening is where the adaptation lives. The lowering is the set.',
    eccentric: 4, pause: 1, concentric: 1, pauseIsMechanism: false,
    reps: { rebuild: [8, 12], hypertrophy: [6, 12], strength: [4, 8], endurance: [12, 20], power: [3, 6] },
    restScale: 1,
    rom: 'Push the hips back until the hamstring is genuinely long, and stop the moment the lower back starts to round rather than chasing another inch.',
  },
  glute_lockout: {
    label: 'Hip extension to lockout',
    evidence: 'moderate',
    why: 'Peak hip-extension torque occurs at full extension, so the top is the hardest part of the lift rather than a rest. This is the one family where squeezing the top is the mechanism.',
    eccentric: 2, pause: 2, concentric: 1, pauseIsMechanism: true,
    reps: { rebuild: [10, 15], hypertrophy: [8, 15], strength: [5, 8], endurance: [15, 25], power: [4, 6] },
    restScale: 0.9,
    rom: 'Finish with the hips fully extended and the ribs down. Arching the lower back to fake the last few degrees moves the work off the glutes.',
  },
  spinal_erector: {
    label: 'Spinal erectors',
    evidence: 'moderate',
    why: 'Postural, fatigue-resistant muscle that responds to reps rather than load. No pause at the top: holding end-range extension is where the risk is, not where the stimulus is.',
    eccentric: 3, pause: 0, concentric: 1, pauseIsMechanism: false,
    reps: { rebuild: [10, 15], hypertrophy: [10, 20], strength: [8, 12], endurance: [15, 25], power: [6, 10] },
    restScale: 0.8,
    rom: 'Move through a comfortable range and stop level with the torso. There is nothing to gain past neutral and that is where the risk sits.',
  },
  single_joint: {
    label: 'Single-joint work',
    evidence: 'strong',
    why: 'One joint moves, so the load stays light enough to control and the range is what matters. Where the muscle crosses a second joint -- the triceps long head overhead, the biceps on an incline -- only the lengthened position trains it fully, and the stretch is worth more than the squeeze.',
    eccentric: 3, pause: 1, concentric: 1, pauseIsMechanism: false,
    reps: { rebuild: [10, 15], hypertrophy: [8, 15], strength: [6, 10], endurance: [15, 25], power: [6, 10] },
    restScale: 0.7,
    rom: 'Control the lengthened end rather than cutting it short. Where the muscle crosses two joints, an overhead or inclined position is what actually lengthens it.',
  },
  lateral_delt: {
    label: 'Lateral deltoid',
    evidence: 'moderate',
    why: 'The lever is longest near the top, so that is where the tension is. Small muscle, light load, and controlling the lowering is exactly where the reps are usually thrown away.',
    eccentric: 3, pause: 1, concentric: 1, pauseIsMechanism: true,
    reps: { rebuild: [12, 18], hypertrophy: [12, 20], strength: [10, 15], endurance: [20, 30], power: [8, 12] },
    restScale: 0.6,
    rom: 'Lead with the elbow to about shoulder height. Swinging higher recruits the traps and takes the work off the muscle being trained.',
  },
  rotator_cuff: {
    label: 'Rotator cuff',
    evidence: 'strong',
    why: 'The cuff stabilises rather than produces force. It is trained light and controlled at every goal, because loading it heavily trains the wrong thing and provokes the shoulder it is meant to protect.',
    eccentric: 2, pause: 1, concentric: 1, pauseIsMechanism: true,
    reps: { rebuild: [12, 20], hypertrophy: [12, 20], strength: [12, 20], endurance: [15, 25], power: [12, 20] },
    restScale: 0.5,
    rom: 'Small, precise range with the elbow pinned to the side. Load light enough that nothing else joins in.',
  },
  grip_and_small: {
    label: 'Grip, neck and lower leg',
    evidence: 'moderate',
    why: 'Small, fatigue-resistant, highly tolerant of frequent work. Reps and short rest do more here than load does.',
    eccentric: 2, pause: 1, concentric: 1, pauseIsMechanism: false,
    reps: { rebuild: [12, 20], hypertrophy: [15, 25], strength: [10, 15], endurance: [20, 35], power: [10, 15] },
    restScale: 0.5,
    rom: 'Through the full available range, held briefly at the end. These respond to time and frequency rather than to load.',
  },
  adductor: {
    label: 'Adductors',
    evidence: 'moderate',
    why: 'Trained through range for groin resilience as much as size, so the stretched position is the point and the load stays controlled.',
    eccentric: 3, pause: 1, concentric: 1, pauseIsMechanism: false,
    reps: { rebuild: [10, 15], hypertrophy: [10, 15], strength: [8, 12], endurance: [15, 25], power: [6, 10] },
    restScale: 0.7,
    rom: 'Into a real stretch without forcing it, and back under control. The range is the training effect here.',
  },
  loaded_carry: {
    label: 'Loaded carry',
    evidence: 'moderate',
    why: 'Bracing under load while staying upright. The limit is grip and posture rather than the muscle being loaded, and both recover quickly, so these are held for time and rested briefly.',
    eccentric: 2, pause: 0, concentric: 1, pauseIsMechanism: false,
    reps: { rebuild: [20, 40], hypertrophy: [30, 60], strength: [20, 40], endurance: [45, 90], power: [15, 30] },
    restScale: 0.6,
    rom: 'Tall and square with the ribs down. There is no range to move through here; the work is refusing to bend.',
  },
  core_braced: {
    label: 'Braced trunk',
    evidence: 'strong',
    why: 'Anti-extension and anti-rotation work is about resisting movement, not producing it. Quality of the brace decides the set, which is why the reps stay moderate and the tempo stays deliberate.',
    eccentric: 2, pause: 1, concentric: 1, pauseIsMechanism: false,
    reps: { rebuild: [8, 15], hypertrophy: [8, 15], strength: [8, 12], endurance: [15, 25], power: [6, 10] },
    restScale: 0.6,
    rom: 'Nothing moves except what is supposed to. The set ends when the position changes, not when the count does.',
  },
}

/** The rep range for this movement under this goal, from its class. */
export function repRangeFor(m: Movement, intent: TrainingIntent): [number, number] {
  return (TEMPO_CLASSES[m.tempoClass] ?? TEMPO_CLASSES.standard_compound).reps[intent]
}

/** Why this class is prescribed the way it is, and how well supported that is. */
const MODE_ROM: Partial<Record<Movement['prescriptionMode'], string>> = {
  contacts: 'Land quietly through the whole foot with the knee tracking the toes. Height is not the goal; a landing you can control is.',
  breath: 'Paced by the breath rather than by a count. Move to the first point of real resistance and stay there, not past it.',
  quality: 'Stopped on quality. The last good repetition is the end of the set, whatever the target said.',
  quality_reps: 'Judged on speed, not on effort. When the bar slows noticeably the set is finished, regardless of reps left.',
  interval: 'Held at a pace that survives the last round. Going out hard on the first round is how these get abandoned.',
  distance: 'Through the full available range, unhurried.',
  hold: 'Held in one position, so the work is resisting the change rather than moving through a range. The set ends when the shape does.',
}

/* Classes whose own cue already speaks about holding, so the mode should not
 * overwrite something more specific with something more generic. */
const HOLD_NATIVE_CLASSES = new Set(['core_braced', 'loaded_carry'])

export function classRationale(m: Movement): {
  label: string; evidence: Evidence; why: string; rom: string
} {
  const spec = TEMPO_CLASSES[m.tempoClass] ?? TEMPO_CLASSES.standard_compound
  // A static hold has no range to move through, and a jump is judged on the
  // landing, so how the movement is dosed overrides its muscle group here.
  return {
    label: spec.label,
    evidence: spec.evidence,
    why: spec.why,
    rom: HOLD_NATIVE_CLASSES.has(m.tempoClass)
      ? spec.rom
      : MODE_ROM[m.prescriptionMode] ?? spec.rom,
  }
}

/* --------------------------------------------------------------- HOLDS
 *
 * A third of the library is not sets of reps, and it was being dosed as though
 * it were: a farmer's carry was given a compound lift's two and a half minute
 * rest after a thirty second effort.
 *
 * Isometric work does build muscle, and the useful finding is that it does so
 * best at long muscle lengths with meaningful accumulated time under tension
 * (Oranchuk et al., 2019). Braced trunk work is the exception that proves it:
 * a plank held until it sags trains sagging, so those are prescribed short and
 * repeated rather than long and degrading.
 */
export interface HoldPrescription {
  seconds: number
  restSeconds: number
  cue: string
}

export function holdFor(m: Movement, intent: TrainingIntent): HoldPrescription | null {
  if (m.prescriptionMode !== 'hold' && m.prescriptionMode !== 'carry') return null
  const low = m.repLow ?? 20
  const high = m.repHigh ?? 45
  const braced = m.tempoClass === 'core_braced'

  // Longer holds for work capacity, shorter and harder for everything else.
  // Braced trunk work never chases duration, because the failing rep of a
  // plank is a worse position rather than a deeper one.
  const seconds = intent === 'endurance' ? high
    : braced ? Math.max(low, Math.round(high * 0.6))
      : Math.round((low + high) / 2)

  // A carry or a hold is limited by grip and bracing, which recover quickly.
  // Nothing here needs three minutes.
  const restSeconds = intent === 'endurance' ? 45
    : intent === 'strength' ? 120
      : m.prescriptionMode === 'carry' ? 90 : 60

  const cue = m.prescriptionMode === 'carry'
    ? 'Tall and square, ribs down. The set ends when the posture goes, not when the grip does.'
    : braced
      ? 'Hold the shape rather than the clock. Stop the moment the position starts to sag.'
      : 'Hold the loaded position, breathing steadily. Length under tension is what is being trained.'

  return { seconds, restSeconds, cue }
}

/* ------------------------------------------------------------ GROUND CONTACTS
 *
 * Plyometrics are dosed in landings, not in sets, and the limit is a volume
 * one rather than a fatigue one: the reason to stop is that the landings stop
 * being sharp. Beginners are held well below the commonly cited ceilings
 * because the tissue tolerance, not the effort, is what is being built.
 */
export const CONTACT_CAPS: Record<'novice' | 'intermediate' | 'advanced', number> = {
  novice: 40,
  intermediate: 80,
  advanced: 120,
}

export function contactCue(m: Movement): string {
  return m.impact === 'high'
    ? 'Stopped on landing quality. The moment a landing gets noisy or slow, the set is over regardless of the number.'
    : 'Quick off the ground. Reset fully between reps rather than rushing them together.'
}

/**
 * The rep range for a movement whose load cannot be changed.
 *
 * Fixing this exposed a real gap: a push-up was prescribed 10-20 reps whether
 * the goal was hypertrophy or work capacity, because the rule said the
 * movement's own range wins when there is no load to adjust. That is right for
 * strength -- there is no way to make a push-up heavy enough for a set of five,
 * and the honest answer is a harder variation -- but wrong for everything else,
 * because more reps is always available.
 */
export function bodyweightRange(m: Movement, intent: TrainingIntent): {
  range: [number, number]; note: string
} {
  const own: [number, number] = [m.repLow ?? 8, m.repHigh ?? 15]
  const cls = repRangeFor(m, intent)

  if (intent === 'strength' || intent === 'power') {
    return {
      range: own,
      note: `Load cannot be added here, so progress by moving to a harder variation rather than by adding reps.${m.substitutions.length ? '' : ''}`,
    }
  }
  // Reps are always available, so the goal is allowed to raise the target --
  // never to lower it below what the movement can actually deliver.
  return {
    range: [Math.max(own[0], cls[0]), Math.max(own[1], cls[1])],
    note: '',
  }
}
