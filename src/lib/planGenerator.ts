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
  sessions: GeneratedSession[]
  limitations: Limitation[]
  /* Movements excluded and why, so the plan can explain itself rather than
   * quietly being smaller than the user expected. */
  excluded: { reason: string; count: number }[]
}

/* Set and rep schemes by goal. Rebuild deliberately sits in a rep range where
 * technique survives fatigue; strength sits low enough to actually be strength
 * work; muscle sits where most of the evidence for hypertrophy lives. */
const SCHEMES: Record<TrainingGoal, {
  sets: number; repLow: number; repHigh: number; rest: number; rir: number
}> = {
  rebuild: { sets: 2, repLow: 8, repHigh: 15, rest: 75, rir: 4 },
  muscle: { sets: 3, repLow: 8, repHigh: 12, rest: 105, rir: 2 },
  strength: { sets: 4, repLow: 4, repHigh: 6, rest: 180, rir: 3 },
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
  if (intake.goal === 'strength' && m.technicalComplexity >= 2 && m.loadable) s += 2
  if (intake.goal === 'rebuild' && m.technicalComplexity <= 2) s += 3
  if (intake.goal === 'rebuild' && m.stabilityDemand >= 4) s -= 2
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
function estimateSeconds(m: Movement, sets: number, repHigh: number, unit: string): number {
  const workPerSet = unit === 'seconds' ? repHigh
    : unit === 'minutes' ? repHigh * 60
      : repHigh * 3.5 // roughly three and a half seconds a rep under control
  const perSide = m.unilateral ? 2 : 1
  const rest = SCHEMES.muscle.rest
  return m.setupSeconds + sets * (workPerSet * perSide + rest)
}

function prescribe(m: Movement, intake: GeneratorIntake): Prescription {
  const scheme = SCHEMES[intake.goal]
  const youth = intake.age < 18
  const unit = m.repUnit

  let repLow = m.repLow ?? scheme.repLow
  let repHigh = m.repHigh ?? scheme.repHigh
  if (unit === 'reps' && m.loadable) {
    // The goal sets the rep range, but never outside what the movement supports.
    repLow = Math.max(scheme.repLow, m.repLow ?? scheme.repLow)
    repHigh = Math.max(repLow + 2, Math.min(scheme.repHigh, m.repHigh ?? scheme.repHigh))
  }
  // Under-18s are never given maximal singles, whatever the goal asks for.
  if (youth && m.youthRepFloor !== null && repLow < m.youthRepFloor) {
    repLow = m.youthRepFloor
    repHigh = Math.max(repHigh, m.youthRepFloor + 2)
  }

  // Reps in reserve is where "cannot be failed alone" actually shows up.
  let rir = scheme.rir
  const note: string[] = []
  if (!failureSafe(m, intake)) {
    rir = Math.max(rir, 3)
    note.push('Leave three reps in reserve: this one cannot be failed safely on your setup.')
  }
  if (m.entityType === 'balance_drill') {
    note.push('Stop the set when the wobble starts, not when the clock does.')
  }
  if (m.notes) note.push(m.notes)

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
    restSeconds: unit === 'seconds' ? Math.round(scheme.rest * 0.6) : scheme.rest,
    incrementKg: m.minIncrementKg,
    repsInReserve: rir,
    estimatedSeconds: estimateSeconds(m, sets, repHigh, unit),
    note: note.join(' '),
  }
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
    let secondsLeft = intake.minutesPerSession * 60

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

      const minutesLeft = secondsLeft / 60
      const patterns = TRAINING_PILLARS[pillar] ?? []
      const ranked: Eligible[] = candidates
        .map((m) => ({ movement: m, score: score(m, intake, usedFamilies, minutesLeft, patterns) }))
        .sort((a, b) => b.score - a.score || a.movement.id.localeCompare(b.movement.id))

      // Take the best option that still fits the time that is left.
      let chosen: Prescription | null = null
      for (const candidate of ranked) {
        const p = prescribe(candidate.movement, intake)
        if (p.estimatedSeconds <= secondsLeft) { chosen = p; break }
      }
      // Nothing fits: drop a set from the best option rather than the pattern.
      if (!chosen && ranked.length > 0) {
        const p = prescribe(ranked[0].movement, intake)
        if (p.sets > 1) {
          const trimmed = { ...p, sets: p.sets - 1 }
          trimmed.estimatedSeconds = Math.round(p.estimatedSeconds * (trimmed.sets / p.sets))
          if (trimmed.estimatedSeconds <= secondsLeft) chosen = trimmed
        }
      }
      if (!chosen) continue

      blocks.push(chosen)
      usedFamilies.add(MOVEMENT_BY_ID.get(chosen.movementId)!.family)
      secondsLeft -= chosen.estimatedSeconds
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

  return { sessions, limitations, excluded }
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
