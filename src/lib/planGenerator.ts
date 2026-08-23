/**
 * Turns intake answers into a week of sessions drawn from the movement library.
 *
 * The previous generator held a handful of hand-written session templates and
 * branched on two or three equipment flags. That works until someone answers
 * the questionnaire in a way nobody wrote a template for -- bands and a pull-up
 * bar but no dumbbells, a sore shoulder, twenty-five minutes, four days a week.
 * There are more combinations than templates, so the honest approach is to pick
 * from the library against constraints rather than to guess in advance.
 *
 * The generator never invents a movement, never prescribes one the user cannot
 * physically perform, and never silently drops a pattern it could not fill: an
 * unfillable pillar comes back as a stated limitation.
 */

import {
  MOVEMENTS,
  MOVEMENT_BY_ID,
  TRAINING_PILLARS,
  KIT_LIMITATIONS,
  type Movement,
} from '../data/movements.ts'
import type { TrainingGoal, TrainingPainArea } from './types.ts'
import {
  restSecondsFor,
  setSeconds,
  tempoFor,
  tempoRationale,
  repRangeFor,
  classRationale,
  holdFor,
  bodyweightRange,
  contactCue,
  tempoFieldsFor,
  type TempoFields,
  type TrainingIntent,
  type Tempo,
} from './liftingTempo.ts'

/* Keep the account-facing answer vocabulary separate from generator intent.
 * Fat loss uses conservative rebuild timing; endurance has its own prescription. */
export const GOAL_INTENT: Record<TrainingGoal, TrainingIntent> = {
  rebuild: 'rebuild',
  muscle: 'hypertrophy',
  fat_loss: 'rebuild',
  strength: 'strength',
  endurance: 'endurance',
}

/* Which movement restrictions each reported body area rules out. The intake
 * asks about six areas, so all six must map onto tags the library actually
 * carries -- otherwise the question looks answered and filters nothing. */
export const PAIN_AREA_CONTRA: Record<TrainingPainArea, string[]> = {
  shoulders: ['shoulder_overhead', 'shoulder_press'],
  elbows: ['elbow'],
  wrists: ['wrist'],
  hips: ['hip_deep_flexion', 'hip_end_range', 'groin'],
  knees: ['knee_deep_flexion', 'knee_impact'],
  ankles: ['ankle_impact', 'ankle_dorsiflexion', 'ankle_loaded', 'achilles'],
}

export type Experience = 'novice' | 'intermediate' | 'advanced'

export interface GeneratorIntake {
  goal: TrainingGoal
  /* Overrides the goal mapping for generator-only intent such as power. */
  intent?: TrainingIntent
  sessionsPerWeek: 2 | 3 | 4
  minutesPerSession: number
  equipment: string[]
  painAreas: TrainingPainArea[]
  age: number
  experience: Experience
  /* A qualified coach has assigned the work, which unlocks the lifts that
   * need coaching before a first attempt. */
  coached?: boolean
  /* Training alone with nothing to catch a failed rep. */
  hasSpotter?: boolean
  hasRackSafeties?: boolean
}

export interface Prescription {
  movementId: string
  name: string
  pattern: string
  sets: number
  repLow: number
  repHigh: number
  unit: string
  perSide: boolean
  restSeconds: number
  incrementKg: number | null
  /* Reps left in the tank at the end of a set. Higher on anything that cannot
   * be failed safely, which is a real constraint rather than a caution. */
  repsInReserve: number
  estimatedSeconds: number
  /* A main slot fills one of the session's pillars; accessory work is what
   * gets added when there is time left after the pillars are covered. */
  slot: 'main' | 'accessory'
  /* Movements sharing a group are alternated. Each one still gets its full
   * rest, because the other one is what fills it. */
  supersetGroup: number | null
  /* How the rep itself is performed. Null where timing a rep is meaningless:
   * a jump, an Olympic lift, a plank, a breath-paced flow. */
  tempo: Tempo | null
  /* Which muscle-group mechanism this is timed by, and how well supported
   * that choice is, so the prescription can be questioned rather than trusted. */
  tempoClass: string
  evidence: 'strong' | 'moderate' | 'extrapolated'
  rationale: string
  /* What counts as a good rep on this movement specifically. */
  rangeCue: string
  /* The three fields the live cadence engine counts from, so the timing the
   * user hears is the one the library reasoned about rather than a default. */
  tempoFields: TempoFields
  note: string
}

export interface GeneratedSession {
  name: string
  pillars: string[]
  targetMinutes: number
  estimatedMinutes: number
  blocks: Prescription[]
}

export interface Limitation {
  pillar: string
  message: string
}

export interface GeneratedWeek {
  /* Why the reps are timed the way they are, so the plan can defend itself. */
  tempoRationale: string
  sessions: GeneratedSession[]
  limitations: Limitation[]
  /* Movements excluded and why, so the plan can explain itself rather than
   * quietly being smaller than the user expected. */
  excluded: { reason: string; count: number }[]
}

/* Set and rep schemes by goal. Rebuild deliberately sits in a rep range where
 * technique survives fatigue; strength sits low enough to actually be strength
 * work; muscle sits where most of the evidence for hypertrophy lives. */
const SCHEMES: Record<TrainingIntent, {
  sets: number; repLow: number; repHigh: number; rir: number
}> = {
  rebuild: { sets: 2, repLow: 8, repHigh: 15, rir: 4 },
  hypertrophy: { sets: 3, repLow: 8, repHigh: 12, rir: 2 },
  strength: { sets: 4, repLow: 4, repHigh: 6, rir: 3 },
  // Work capacity lives in higher reps against a shorter clock.
  endurance: { sets: 3, repLow: 15, repHigh: 25, rir: 3 },
  // Quality per rep, so the set ends long before form does.
  power: { sets: 4, repLow: 3, repHigh: 5, rir: 4 },
}

function intentOf(intake: GeneratorIntake): TrainingIntent {
  return intake.intent ?? GOAL_INTENT[intake.goal]
}

/* Which pillars each session covers. Two sessions a week means both must be
 * full body or half the patterns never get trained; four allows a split. */
const TEMPLATES: Record<2 | 3 | 4, { name: string; pillars: string[] }[]> = {
  2: [
    { name: 'Full Body A', pillars: ['squat', 'push_horizontal', 'pull_horizontal', 'core'] },
    { name: 'Full Body B', pillars: ['hinge', 'push_vertical', 'pull_vertical', 'carry_or_balance'] },
  ],
  3: [
    { name: 'Full Body A', pillars: ['squat', 'push_horizontal', 'pull_horizontal', 'core'] },
    { name: 'Full Body B', pillars: ['hinge', 'push_vertical', 'pull_vertical', 'carry_or_balance'] },
    { name: 'Full Body C', pillars: ['squat', 'push_horizontal', 'pull_horizontal', 'hinge'] },
  ],
  4: [
    { name: 'Lower A', pillars: ['squat', 'hinge', 'core', 'carry_or_balance'] },
    { name: 'Upper A', pillars: ['push_horizontal', 'pull_horizontal', 'push_vertical', 'pull_vertical'] },
    { name: 'Lower B', pillars: ['hinge', 'squat', 'carry_or_balance', 'core'] },
    { name: 'Upper B', pillars: ['pull_horizontal', 'push_horizontal', 'pull_vertical', 'push_vertical'] },
  ],
}

const MAX_SKILL: Record<Experience, number> = { novice: 2, intermediate: 3, advanced: 5 }

/** True when the user's kit satisfies every hard requirement and each any-of group. */
export function available(m: Movement, owned: Set<string>): boolean {
  if (!m.equipment.every((e) => owned.has(e))) return false
  return m.equipmentAnyOf.every((group) => group.some((e) => owned.has(e)))
}

/* Only these can fill a strength pillar. A yoga pose and a mobility drill are
 * real work, but neither is a horizontal pull. */
const SELECTABLE = new Set(['resistance_dynamic', 'resistance_isometric', 'balance_drill'])

function contraindicatedBy(m: Movement, painAreas: TrainingPainArea[]): boolean {
  const blocked = new Set(painAreas.flatMap((area) => PAIN_AREA_CONTRA[area]))
  return m.contraindications.some((c) => blocked.has(c))
}

/* A movement that cannot be failed alone is not banned -- it is prescribed
 * further from failure, unless the setup makes failing safe. */
function failureSafe(m: Movement, intake: GeneratorIntake): boolean {
  if (m.canFailSafely) return true
  if (intake.hasSpotter && m.needsSpotter) return true
  if (intake.hasRackSafeties && m.failSafeConditions.includes('rack_safeties_set')) return true
  return false
}

interface Eligible { movement: Movement; score: number }

/**
 * Everything the user can actually be given, with the reasons for exclusion
 * counted rather than discarded. A plan that is quietly short of options is
 * worse than one that says why.
 */
export function eligibleMovements(intake: GeneratorIntake): {
  eligible: Movement[]
  excluded: { reason: string; count: number }[]
} {
  const owned = new Set(intake.equipment)
  const youth = intake.age < 18
  const counts = new Map<string, number>()
  const bump = (reason: string) => counts.set(reason, (counts.get(reason) ?? 0) + 1)

  const eligible = MOVEMENTS.filter((m) => {
    if (!SELECTABLE.has(m.entityType)) return false
    if (!available(m, owned)) { bump('equipment you do not have'); return false }
    if (contraindicatedBy(m, intake.painAreas)) { bump('the areas you flagged'); return false }
    if (m.coachedOnly && !intake.coached) { bump('needs a coach before a first attempt'); return false }
    if (youth && !m.youthAutoAssignable) { bump('held back until 18 without supervision'); return false }
    if (!youth && !m.adultAutoAssignable) { bump('needs a coach before a first attempt'); return false }
    if (m.technicalComplexity > MAX_SKILL[intake.experience]) {
      bump('more technical than your stated experience'); return false
    }
    return true
  })

  const excluded = [...counts.entries()]
    .map(([reason, count]) => ({ reason, count }))
    .sort((a, b) => b.count - a.count)
  return { eligible, excluded }
}

/**
 * How well a movement suits this slot. Deliberately boring: the generator
 * should prefer the loadable, low-setup, appropriately-skilled option, because
 * that is what people actually keep doing.
 */
function score(
  m: Movement,
  intake: GeneratorIntake,
  used: Set<string>,
  minutesLeft: number,
  patterns: string[],
): number {
  let s = 0
  // An accessory can sit inside a pillar without being what the pillar is
  // about. A pullover is not the answer to "train a vertical pull" when there
  // is a bar on the wall.
  if (m.role === 'accessory') s -= 8
  // Pillars list their patterns most-central first, so a squat beats a lunge
  // for the squat slot and a lunge still fills it when no squat is available.
  const rank = patterns.indexOf(m.pattern)
  if (rank >= 0) s -= rank * 2
  // Progress needs somewhere for the load to go.
  if (m.loadable) s += intake.goal === 'rebuild' ? 2 : 4

  // A small increment means the next session can actually be heavier.
  if (m.minIncrementKg !== null && m.minIncrementKg <= 2.5) s += 2
  // Prefer what suits the goal.
  const intent = intentOf(intake)
  if (intent === 'strength' && m.technicalComplexity >= 2 && m.loadable) s += 2
  if (intent === 'rebuild' && m.technicalComplexity <= 2) s += 3
  if (intent === 'rebuild' && m.stabilityDemand >= 4) s -= 2
  // Work capacity wants movements that can be repeated for twenty honest reps,
  // which rules out the ones limited by balance or by a slow setup.
  if (intent === 'endurance' && m.stabilityDemand >= 4) s -= 3
  if (intent === 'power' && !m.ballistic && m.entityType !== 'plyometric') s -= 2
  // Setup time is real time. A ninety-second setup in a twenty-minute session
  // is a quarter of the session spent moving benches.
  s -= (m.setupSeconds / 60) * (minutesLeft < 30 ? 2 : 1)
  // Variety across the week, so the same movement is not the answer to
  // every slot it happens to fit.
  if (used.has(m.family)) s -= 6
  // Two brutal movements in one short session is how people stop turning up.
  s -= m.fatigueCost * (minutesLeft < 30 ? 0.8 : 0.3)
  // All else equal, the simplest movement that does the job. This is what
  // separates a reverse lunge from a forward one when nothing else does.
  s -= m.technicalComplexity * 0.5
  return s
}

/** Seconds a prescription costs, setup included, so session length is honest. */
function estimateSeconds(
  m: Movement, sets: number, repHigh: number, unit: string, intent: TrainingIntent,
): number {
  const perSide = m.unilateral ? 2 : 1
  // A tempo makes the work half of a set exact rather than a guess: three
  // seconds down plus a pause plus a second up is a number, not an estimate.
  const workPerSet = unit === 'seconds' ? repHigh * perSide
    : unit === 'minutes' ? repHigh * 60
      : setSeconds(m, repHigh, intent)
  return m.setupSeconds + sets * (workPerSet + restSecondsFor(m, intent))
}

function prescribe(m: Movement, intake: GeneratorIntake): Prescription {
  const intent = intentOf(intake)
  const scheme = SCHEMES[intent]
  const youth = intake.age < 18
  const unit = m.repUnit

  const note: string[] = []
  let repLow = m.repLow ?? scheme.repLow
  let repHigh = m.repHigh ?? scheme.repHigh
  if (unit === 'reps' && m.loadable) {
    // The rep range comes from the movement's own class under this goal, not
    // from one blanket scheme. A soleus raise and a barbell squat are both
    // hypertrophy work and they are not the same prescription.
    ;[repLow, repHigh] = repRangeFor(m, intent)
  } else if (unit === 'reps') {
    // No load to adjust, but reps are still available -- so the goal may raise
    // the target and never lower it past what the movement can deliver.
    const bodyweight = bodyweightRange(m, intent)
    ;[repLow, repHigh] = bodyweight.range
    if (bodyweight.note) note.push(bodyweight.note)
  }
  // Under-18s are never given maximal singles, whatever the goal asks for.
  if (youth && m.youthRepFloor !== null && repLow < m.youthRepFloor) {
    repLow = m.youthRepFloor
    repHigh = Math.max(repHigh, m.youthRepFloor + 2)
  }

  // Reps in reserve is where "cannot be failed alone" actually shows up.
  let rir = scheme.rir
  if (!failureSafe(m, intake)) {
    rir = Math.max(rir, 3)
    note.push('Leave three reps in reserve: this one cannot be failed safely on your setup.')
  }
  if (m.entityType === 'balance_drill') {
    note.push('Stop the set when the wobble starts, not when the clock does.')
  }
  if (m.notes) note.push(m.notes)

  const tempo = tempoFor(m, intent)
  if (tempo) note.unshift(tempo.cue)
  const hold = holdFor(m, intent)
  if (hold) {
    repLow = hold.seconds
    repHigh = hold.seconds
    note.unshift(hold.cue)
  }
  if (m.prescriptionMode === 'contacts') note.unshift(contactCue(m))
  const cls = classRationale(m)
  const sets = m.entityType === 'balance_drill' ? 2 : scheme.sets
  return {
    movementId: m.id,
    name: m.name,
    pattern: m.pattern,
    sets,
    repLow,
    repHigh,
    unit,
    perSide: m.unilateral,
    restSeconds: hold ? hold.restSeconds : restSecondsFor(m, intent),
    incrementKg: m.minIncrementKg,
    repsInReserve: rir,
    estimatedSeconds: estimateSeconds(m, sets, repHigh, unit, intent),
    supersetGroup: null,
    slot: 'main',
    tempo,
    tempoClass: cls.label,
    evidence: cls.evidence,
    rationale: cls.why,
    rangeCue: cls.rom,
    tempoFields: tempoFieldsFor(m, intent),
    note: note.join(' '),
  }
}

/* Which part of the body a pattern taxes, so the generator can tell whether
 * two movements genuinely compete for recovery or only for the clock. */
function region(pattern: string): string {
  if (pattern === 'horizontal_push' || pattern === 'vertical_push') return 'upper_push'
  if (pattern === 'horizontal_pull' || pattern === 'vertical_pull') return 'upper_pull'
  if (['squat', 'lunge', 'hip_hinge', 'calf', 'isolation_lower'].includes(pattern)) return 'lower'
  if (pattern.startsWith('core_')) return 'core'
  return 'other'
}

/* Two movements can share a rest interval when they do not tax the same thing
 * and neither is systemically brutal on its own. */
function pairable(a: Movement, b: Movement): boolean {
  if (region(a.pattern) === region(b.pattern)) return false
  if (a.fatigueCost >= 4 && b.fatigueCost >= 4) return false
  const aMuscles = new Set([...a.primaryMuscles, ...a.secondaryMuscles])
  return !b.primaryMuscles.some((muscle) => aMuscles.has(muscle))
}

const TRANSITION_SECONDS = 15

/**
 * What a pair costs when alternated. This is the honest way to fit a balanced
 * session into a short window: the rest is not shortened, it is spent doing the
 * other movement. Each lift still gets its full interval before it repeats, and
 * where the partner does not fill that interval the shortfall is waited out.
 */
function pairSeconds(a: Prescription, b: Prescription, ma: Movement, mb: Movement,
  intent: TrainingIntent): number {
  const sets = Math.max(a.sets, b.sets)
  const workA = setSeconds(ma, a.repHigh, intent)
  const workB = setSeconds(mb, b.repHigh, intent)
  const perRound = workA + workB + TRANSITION_SECONDS * 2
  const needed = Math.max(a.restSeconds, b.restSeconds)
  const shortfall = Math.max(0, needed - perRound)
  return ma.setupSeconds + mb.setupSeconds + sets * (perRound + shortfall)
}

/**
 * Builds the week. Sessions are filled pillar by pillar rather than movement by
 * movement, because the thing that makes a programme balanced is the pattern
 * coverage, not the exercise count.
 */
export function generateWeek(intake: GeneratorIntake, kitName?: string): GeneratedWeek {
  const { eligible, excluded } = eligibleMovements(intake)
  const byPillar = new Map<string, Movement[]>()
  for (const [pillar, patterns] of Object.entries(TRAINING_PILLARS)) {
    byPillar.set(pillar, eligible.filter((m) => patterns.includes(m.pattern)))
  }

  const usedFamilies = new Set<string>()
  const limitations: Limitation[] = []
  const seenGaps = new Set<string>()
  const sessions: GeneratedSession[] = []

  for (const template of TEMPLATES[intake.sessionsPerWeek]) {
    const blocks: Prescription[] = []
    const chosen: { p: Prescription; m: Movement }[] = []

    // Choose the best movement for each pillar first, without worrying about
    // the clock. Fitting comes next, and dropping a pattern is the last resort
    // rather than the first thing time pressure does.
    for (const pillar of template.pillars) {
      const candidates = byPillar.get(pillar) ?? []
      if (candidates.length === 0) {
        if (!seenGaps.has(pillar)) {
          seenGaps.add(pillar)
          limitations.push({
            pillar,
            message: KIT_LIMITATIONS[kitName ?? '']?.[pillar]
              ?? `Nothing in your kit and restrictions can fill the ${pillar.replace(/_/g, ' ')} pattern, so this plan is short one movement pattern rather than pretending otherwise.`,
          })
        }
        continue
      }
      const patterns = TRAINING_PILLARS[pillar] ?? []
      const ranked: Eligible[] = candidates
        .map((m) => ({ movement: m, score: score(m, intake, usedFamilies, intake.minutesPerSession, patterns) }))
        .sort((a, b) => b.score - a.score || a.movement.id.localeCompare(b.movement.id))
      const best = ranked[0].movement
      if (chosen.some((c) => c.m.family === best.family)) continue
      chosen.push({ p: prescribe(best, intake), m: best })
      usedFamilies.add(best.family)
    }

    let secondsLeft = intake.minutesPerSession * 60
    const sequential = chosen.reduce((sum, c) => sum + c.p.estimatedSeconds, 0)

    if (sequential <= secondsLeft) {
      for (const c of chosen) blocks.push(c.p)
      secondsLeft -= sequential
    } else {
      // Too long run back to back. Alternate what does not compete, which buys
      // the time back without taking a second off anyone's recovery.
      const remaining = [...chosen]
      let group = 0
      while (remaining.length > 0) {
        const first = remaining.shift()!
        const partnerIndex = remaining.findIndex((c) => pairable(first.m, c.m))
        if (partnerIndex === -1) {
          if (first.p.estimatedSeconds <= secondsLeft) {
            blocks.push(first.p)
            secondsLeft -= first.p.estimatedSeconds
          } else if (first.p.sets > 1) {
            const trimmed = { ...first.p, sets: first.p.sets - 1 }
            trimmed.estimatedSeconds = Math.round(
              first.p.estimatedSeconds * (trimmed.sets / first.p.sets))
            if (trimmed.estimatedSeconds <= secondsLeft) {
              blocks.push(trimmed)
              secondsLeft -= trimmed.estimatedSeconds
            }
          }
          continue
        }
        const second = remaining.splice(partnerIndex, 1)[0]
        const cost = pairSeconds(first.p, second.p, first.m, second.m, intentOf(intake))
        if (cost <= secondsLeft) {
          group += 1
          blocks.push({ ...first.p, supersetGroup: group, estimatedSeconds: Math.round(cost / 2) })
          blocks.push({ ...second.p, supersetGroup: group, estimatedSeconds: Math.round(cost / 2) })
          secondsLeft -= cost
        } else if (first.p.sets > 1) {
          const sets = first.p.sets - 1
          const trimmed = Math.round(cost * (sets / first.p.sets))
          if (trimmed <= secondsLeft) {
            group += 1
            blocks.push({ ...first.p, sets, supersetGroup: group, estimatedSeconds: Math.round(trimmed / 2) })
            blocks.push({ ...second.p, sets, supersetGroup: group, estimatedSeconds: Math.round(trimmed / 2) })
            secondsLeft -= trimmed
          }
        }
      }
    }

    // Shorter rest and shorter sets can leave real time on the table. Fill it
    // with accessory work rather than handing back a half-length session or
    // padding the main lifts past the point where they are still quality.
    if (secondsLeft > 5 * 60) {
      const already = new Set(blocks.map((b) => b.movementId))
      const accessories = eligible
        .filter((m) => m.role === 'accessory' && !already.has(m.id)
          && !usedFamilies.has(m.family) && m.repUnit === 'reps')
        .map((m) => ({ movement: m, score: -m.setupSeconds / 60 - m.fatigueCost * 0.5 }))
        .sort((a, b) => b.score - a.score || a.movement.id.localeCompare(b.movement.id))
      for (const candidate of accessories) {
        if (secondsLeft <= 4 * 60) break
        const p = prescribe(candidate.movement, intake)
        if (p.estimatedSeconds > secondsLeft) continue
        blocks.push({ ...p, slot: 'accessory' })
        usedFamilies.add(candidate.movement.family)
        secondsLeft -= p.estimatedSeconds
      }
    }

    sessions.push({
      name: template.name,
      pillars: template.pillars,
      targetMinutes: intake.minutesPerSession,
      estimatedMinutes: Math.round(
        blocks.reduce((sum, b) => sum + b.estimatedSeconds, 0) / 60),
      blocks,
    })
  }

  return { tempoRationale: tempoRationale(intentOf(intake)), sessions, limitations, excluded }
}

/** Patterns the finished week actually trains, for checking it against itself. */
export function weeklyPatternCoverage(week: GeneratedWeek): Record<string, number> {
  const counts: Record<string, number> = {}
  for (const session of week.sessions) {
    for (const block of session.blocks) {
      const m = MOVEMENT_BY_ID.get(block.movementId)!
      for (const pattern of [m.pattern, ...m.secondaryPatterns]) {
        counts[pattern] = (counts[pattern] ?? 0) + block.sets
      }
    }
  }
  return counts
}
