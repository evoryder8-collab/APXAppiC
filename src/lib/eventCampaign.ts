/*
 * Event campaigns: preparing for a race that is not a marathon.
 *
 * Orbit already builds marathon campaigns. This covers the two events people
 * ask for most and which need genuinely different preparation: a Hyrox race,
 * which is eight kilometres of running interleaved with eight strength and
 * carry stations, and a half-distance triathlon, which is a swim, a long bike
 * and a half marathon back to back.
 *
 * The shape follows Orbit's: a family chosen from where the person is now, a
 * sequence of phases, weekly session prescriptions, and readiness components
 * that say plainly what is on track and what is not.
 *
 * The event formats below are facts about the sport, not content taken from
 * anyone's programme. Weights and distances change between seasons, so they
 * carry a season marker and the app tells the athlete to confirm against the
 * current rulebook.
 */

export type EventKind = 'hyrox' | 'half_triathlon'

export type EventFamily =
  | 'foundation_first'   // not yet aerobically or structurally ready
  | 'first_finish'       // finish it, sensibly
  | 'first_performance'  // finish it well
  | 'personal_best'      // has done one, wants a number

export type EventPhase =
  | 'foundation'
  | 'base'
  | 'build'
  | 'specific'
  | 'peak'
  | 'taper'
  | 'race_week'

export interface HyroxStation {
  order: number
  id: string
  name: string
  /* Two of the eight stations are a distance on an erg, which is a cardio
   * modality under a prescription rather than a movement. The rest are
   * movements. A station carries whichever it actually is, so a session can
   * prescribe the real thing instead of a record invented to fit one field. */
  movementId?: string
  cardio?: { modality: string; prescription: string }
  measure: string
  openMen: string
  openWomen: string
}

/* Race order is fixed and identical at every event, with a kilometre of
 * running before each station. */
export const HYROX_STATIONS: HyroxStation[] = [
  { order: 1, id: 'ski', name: 'SkiErg', cardio: { modality: 'ski_erg', prescription: 'race_pace' }, measure: '1000 m', openMen: 'no load', openWomen: 'no load' },
  { order: 2, id: 'sled_push', name: 'Sled Push', movementId: 'sled_push', measure: '50 m', openMen: '152 kg', openWomen: '102 kg' },
  { order: 3, id: 'sled_pull', name: 'Sled Pull', movementId: 'sled_pull', measure: '50 m', openMen: '103 kg', openWomen: '78 kg' },
  { order: 4, id: 'burpee_broad_jump', name: 'Burpee Broad Jump', movementId: 'burpee_broad_jump', measure: '80 m', openMen: 'bodyweight', openWomen: 'bodyweight' },
  { order: 5, id: 'row', name: 'Row', cardio: { modality: 'row_erg', prescription: 'race_pace' }, measure: '1000 m', openMen: 'no load', openWomen: 'no load' },
  { order: 6, id: 'farmers_carry', name: "Farmer's Carry", movementId: 'farmers_carry', measure: '200 m', openMen: '2 x 24 kg', openWomen: '2 x 16 kg' },
  { order: 7, id: 'sandbag_lunge', name: 'Sandbag Lunges', movementId: 'sandbag_lunge', measure: '100 m', openMen: '20 kg', openWomen: '10 kg' },
  { order: 8, id: 'wall_balls', name: 'Wall Balls', movementId: 'wall_ball', measure: '100 reps', openMen: '9 kg to 10 ft', openWomen: '6 kg to 9 ft' },
]

export const HYROX_RUN_SEGMENTS = 8
export const HYROX_RUN_METRES = 1000
export const HYROX_SPEC_SEASON = '2026/27'

export const HALF_TRIATHLON_LEGS = {
  swimMetres: 1900,
  bikeKilometres: 90,
  runKilometres: 21.1,
} as const

/* What the person is hoping for. Ambition is asked for, honoured where it is
 * reachable, and reconciled out loud where it is not. */
export type EventAmbition = 'finish' | 'solid_time' | 'compete'

/* What this campaign is actually aimed at, once ambition meets the runway.
 * Never a refusal: every combination produces a real target. */
export type TargetOutcome =
  | 'finish_safely'   // arrive healthy, complete it, enjoy it
  | 'solid_finish'    // finish comfortably and respectably
  | 'performance'     // chase a time worth being proud of
  | 'competitive'     // genuinely contend

export interface EventIntake {
  kind: EventKind
  ambition?: EventAmbition
  raceDate: string
  today: string
  /* Longest continuous run in the last month, kilometres. */
  longestRunKm: number
  /* Sessions a week they can genuinely protect. */
  sessionsPerWeek: number
  /* Months of uninterrupted training behind them. */
  consistentMonths: number
  hasDoneOne: boolean
  /* Half triathlon only: can they swim 400 m continuously without stopping. */
  canSwimContinuously?: boolean
  /* Access to the specific kit. Missing kit does not block a campaign, it
     changes what the sessions look like. */
  hasSled?: boolean
  hasErg?: boolean
  hasPool?: boolean
  hasBike?: boolean
}

export interface CampaignWeek {
  weekNumber: number
  phase: EventPhase
  focus: string
  /* Session slots for the week, in the order they should fall. */
  sessions: string[]
  /* Roughly how many hours the week asks for. */
  hours: number
  isRecoveryWeek: boolean
}

export interface EventCampaignPlan {
  kind: EventKind
  family: EventFamily
  weeksAvailable: number
  weeks: CampaignWeek[]
  assignmentReason: string
  /* What this plan is aimed at, once ambition met the runway. */
  targetOutcome: TargetOutcome
  /* One plain sentence about what race day realistically looks like. Said
     upfront rather than discovered on the start line. */
  expectation: string
  /* Present only when ambition outruns the runway. It never blocks the
     campaign; it says what the bigger goal would need. */
  ambitionGap: string | null
  timelineWarning: string | null
}

function daysBetween(from: string, to: string): number {
  const a = Date.parse(`${from}T12:00:00Z`)
  const b = Date.parse(`${to}T12:00:00Z`)
  if (!Number.isFinite(a) || !Number.isFinite(b)) return 0
  return Math.round((b - a) / 86_400_000)
}

export function weeksUntil(intake: EventIntake): number {
  return Math.max(0, Math.floor(daysBetween(intake.today, intake.raceDate) / 7))
}

/*
 * Which campaign a person gets. The deciding question is not ambition, it is
 * whether the body has the aerobic and structural base to absorb the work.
 */
export function assignFamily(intake: EventIntake): { family: EventFamily; reason: string } {
  const weeks = weeksUntil(intake)
  const swimBlocked = intake.kind === 'half_triathlon' && intake.canSwimContinuously === false

  if (swimBlocked) {
    return {
      family: 'foundation_first',
      reason: 'Swimming 1.9 km in open water is the part of this race that is genuinely unsafe to improvise. The first block is swim technique and continuous distance, and the rest follows once that is there.',
    }
  }
  if (intake.consistentMonths < 2 || intake.longestRunKm < 5) {
    return {
      family: 'foundation_first',
      reason: 'There is not yet a base to build on, so the first block builds one. Trying to race on top of nothing is how people arrive injured rather than ready.',
    }
  }
  if (weeks < 12 && !intake.hasDoneOne) {
    return {
      family: 'first_finish',
      reason: 'A first event on a short runway is a finish, not a time. The plan protects that and does not chase a number.',
    }
  }
  if (!intake.hasDoneOne) {
    return {
      family: 'first_performance',
      reason: 'Enough runway and enough base to prepare properly for a first one, so the plan aims at finishing it well rather than merely finishing.',
    }
  }
  return {
    family: 'personal_best',
    reason: 'A repeat with a base already in place, so the plan spends its weeks on the specific weaknesses that cost time rather than on general fitness.',
  }
}

/* Phase lengths as a share of the runway. Base is the longest because it is
 * what everything else is built on, and taper is fixed because it does not
 * scale with the plan's length. */
function phasePlan(weeks: number, family: EventFamily): EventPhase[] {
  if (weeks <= 0) return []
  const taper = weeks >= 10 ? 2 : 1
  const raceWeek = 1
  const usable = Math.max(1, weeks - taper - raceWeek)
  const foundation = family === 'foundation_first' ? Math.round(usable * 0.3) : 0
  const rest = usable - foundation
  const base = Math.round(rest * 0.4)
  const build = Math.round(rest * 0.35)
  const specific = Math.max(0, rest - base - build)

  const out: EventPhase[] = []
  for (let i = 0; i < foundation; i += 1) out.push('foundation')
  for (let i = 0; i < base; i += 1) out.push('base')
  for (let i = 0; i < build; i += 1) out.push('build')
  for (let i = 0; i < specific; i += 1) out.push('specific')
  for (let i = 0; i < taper; i += 1) out.push('taper')
  for (let i = 0; i < raceWeek; i += 1) out.push('race_week')
  return out.slice(0, weeks)
}

const HYROX_FOCUS: Record<EventPhase, string> = {
  foundation: 'Run without pain, and learn the station movements unloaded',
  base: 'Aerobic volume, and strength in the patterns the stations demand',
  build: 'Compromised running: the run that follows a station is the race',
  specific: 'Race-order simulations at goal effort, station pacing rehearsed',
  peak: 'The hardest specific work, then nothing new',
  taper: 'Volume down, sharpness kept, nothing learned',
  race_week: 'Move, sleep, eat, arrive fresh',
}

const TRI_FOCUS: Record<EventPhase, string> = {
  foundation: 'Swim continuously, ride comfortably, run without pain',
  base: 'Aerobic hours across all three, technique in the water',
  build: 'Longer rides and runs, first bricks, some threshold work',
  specific: 'Race-effort bricks and the long ride at target intensity',
  peak: 'The longest sessions of the plan, then back off',
  taper: 'Volume down by a third, then two thirds. Intensity stays.',
  race_week: 'Short, sharp, and mostly rest',
}

/* Weekly hours by phase and family. Half triathlon asks more than Hyrox
 * because three sports take longer than two. */
function weeklyHours(kind: EventKind, phase: EventPhase, family: EventFamily, sessions: number): number {
  const base = kind === 'half_triathlon' ? 6 : 4
  const phaseScale: Record<EventPhase, number> = {
    foundation: 0.7, base: 1, build: 1.25, specific: 1.4,
    peak: 1.5, taper: 0.7, race_week: 0.35,
  }
  const familyScale = family === 'personal_best' ? 1.15
    : family === 'first_performance' ? 1
      : family === 'first_finish' ? 0.85 : 0.7
  const sessionScale = Math.max(0.6, Math.min(1.4, sessions / 4))
  return Math.round(base * phaseScale[phase] * familyScale * sessionScale * 10) / 10
}

function hyroxSessions(phase: EventPhase, intake: EventIntake): string[] {
  const sled = intake.hasSled ? 'sled push and pull intervals' : 'heavy carries and lunges standing in for the sleds'
  const erg = intake.hasErg ? 'erg intervals' : 'bike or run intervals standing in for the ergs'
  switch (phase) {
    case 'foundation':
      return ['easy run', 'full-body strength', 'easy run or bike', 'movement practice, unloaded']
    case 'base':
      return ['easy run', 'lower strength, hinge and squat', `${erg} at steady effort`, 'upper strength and carries', 'long easy run']
    case 'build':
      return ['run into station, repeated', 'lower strength', sled, 'upper strength and wall balls', 'long run with strength finish']
    case 'specific':
      return ['half race simulation, race order', 'lower strength, reduced volume', `${sled} at race weight`, 'compromised run intervals', 'long run at race effort']
    case 'peak':
      return ['full race simulation', 'light strength', 'station pacing practice', 'easy run']
    case 'taper':
      return ['short race-effort intervals', 'light full-body strength', 'easy run', 'station rehearsal, light']
    case 'race_week':
      return ['short shakeout run', 'a few reps at race weight, nothing hard', 'rest', 'race']
  }
}

function triathlonSessions(phase: EventPhase, intake: EventIntake): string[] {
  const swim = intake.hasPool === false ? 'open-water swim or technique drills on land' : 'swim technique'
  switch (phase) {
    case 'foundation':
      return [swim, 'easy bike', 'easy run or walk-run', 'full-body strength']
    case 'base':
      return [swim, 'endurance bike', 'easy run', 'second swim', 'long bike', 'strength']
    case 'build':
      return [`${swim} with intervals`, 'bike with tempo', 'run off the bike, short', 'long bike', 'long run', 'strength']
    case 'specific':
      return ['swim at race effort', 'bike at race effort', 'brick: long bike into run', 'long run', 'easy swim', 'strength, reduced']
    case 'peak':
      return ['longest brick of the plan', 'swim at race effort', 'easy bike', 'long run', 'easy swim']
    case 'taper':
      return ['short swim with race-effort pieces', 'bike with short efforts', 'short run at race pace', 'easy swim']
    case 'race_week':
      return ['short swim', 'short spin', 'shakeout jog', 'rest', 'race']
  }
}

export function buildCampaign(intake: EventIntake): EventCampaignPlan {
  const weeks = weeksUntil(intake)
  const { family, reason } = assignFamily(intake)
  const phases = phasePlan(weeks, family)

  const { outcome, expectation, ambitionGap } = reconcile(intake, family, weeks)
  const timelineWarning = weeks === 0
    ? 'That date is not in the future. Pick the race day and we will build back from it.'
    : null

  const built: CampaignWeek[] = phases.map((phase, index) => {
    const weekNumber = index + 1
    /* Every fourth week comes down, except inside the taper, which is
       already coming down. */
    const isRecoveryWeek = phase !== 'taper' && phase !== 'race_week' && weekNumber % 4 === 0
    const sessions = intake.kind === 'hyrox'
      ? hyroxSessions(phase, intake)
      : triathlonSessions(phase, intake)
    const hours = weeklyHours(intake.kind, phase, family, intake.sessionsPerWeek)
    return {
      weekNumber,
      phase,
      focus: intake.kind === 'hyrox' ? HYROX_FOCUS[phase] : TRI_FOCUS[phase],
      sessions: sessions.slice(0, Math.max(3, intake.sessionsPerWeek)),
      hours: isRecoveryWeek ? Math.round(hours * 0.65 * 10) / 10 : hours,
      isRecoveryWeek,
    }
  })

  return {
    kind: intake.kind,
    family,
    weeksAvailable: weeks,
    weeks: built,
    assignmentReason: reason,
    targetOutcome: outcome,
    expectation,
    ambitionGap,
    timelineWarning,
  }
}

/* Roughly what each outcome costs, in weeks of consistent training from a
 * reasonable base. Used to answer "what would it take" rather than to gate
 * anyone out of entering a race they have already paid for. */
const WEEKS_FOR_OUTCOME: Record<EventKind, Record<TargetOutcome, number>> = {
  hyrox: { finish_safely: 4, solid_finish: 10, performance: 20, competitive: 40 },
  half_triathlon: { finish_safely: 10, solid_finish: 18, performance: 30, competitive: 52 },
}

/*
 * Ambition meets the runway.
 *
 * Nobody is turned away from a race they want to do. What they get instead is
 * the truth about what this particular runway buys, a plan aimed squarely at
 * that, and a straight answer about what the bigger goal would have needed.
 * Someone who wants to contend and has six weeks should hear that they can
 * arrive healthy and finish well, and that contending is a year of work, not
 * that they should not go.
 */
export function reconcile(
  intake: EventIntake,
  family: EventFamily,
  weeks: number,
): { outcome: TargetOutcome; expectation: string; ambitionGap: string | null } {
  const kind = intake.kind
  /* Hyrox is a proper noun; a half-distance triathlon is not. */
  const event = kind === 'hyrox' ? 'Hyrox' : 'half-distance triathlon'
  const table = WEEKS_FOR_OUTCOME[kind]
  const ambition: EventAmbition = intake.ambition ?? 'solid_time'

  /* The base matters as much as the calendar. A long runway from nothing
     still does not buy a competitive result. */
  const basePenalty = family === 'foundation_first' ? 2 : family === 'first_finish' ? 1 : 0
  const reachable: TargetOutcome[] = (['competitive', 'performance', 'solid_finish', 'finish_safely'] as const)
    .filter((level, index) => weeks >= table[level] && index >= basePenalty)
  const best: TargetOutcome = reachable[0] ?? 'finish_safely'

  const wanted: TargetOutcome = ambition === 'compete' ? 'competitive'
    : ambition === 'solid_time' ? 'performance' : 'finish_safely'

  const order: TargetOutcome[] = ['finish_safely', 'solid_finish', 'performance', 'competitive']
  const outcome = order.indexOf(wanted) < order.indexOf(best) ? wanted : best

  const expectations: Record<TargetOutcome, string> = {
    finish_safely: `On this runway the goal is to arrive healthy and finish your ${event}. That is a real result, and it is the one this plan is built to deliver.`,
    solid_finish: `There is enough time here to finish your ${event} comfortably and well inside the field, rather than merely surviving it.`,
    performance: `There is enough runway to chase a time you will be pleased with, and the plan spends its later weeks on exactly that.`,
    competitive: `There is enough runway and enough base to prepare to genuinely contend, so the plan is built around the specific weaknesses that cost places.`,
  }

  let ambitionGap: string | null = null
  if (order.indexOf(wanted) > order.indexOf(outcome)) {
    const needed = table[wanted]
    const short = Math.max(0, needed - weeks)
    const wantedLabel = wanted === 'competitive' ? 'contending' : 'a time you would chase'
    ambitionGap = short > 0
      ? `You said you want ${ambition === 'compete' ? 'to compete' : 'a strong time'}. Honestly: ${wantedLabel} from where you are now takes about ${needed} weeks of consistent work, and there are ${weeks}. Do this one anyway, aim at the target above, and you will be ${short} weeks better placed for the next.`
      : `You said you want ${ambition === 'compete' ? 'to compete' : 'a strong time'}. The calendar allows it, but the base does not yet. Build this one properly and the next is a different conversation.`
  }

  return { outcome, expectation: expectations[outcome], ambitionGap }
}

export function outcomeLabel(outcome: TargetOutcome): string {
  const labels: Record<TargetOutcome, string> = {
    finish_safely: 'Arrive healthy and finish',
    solid_finish: 'Finish strong',
    performance: 'Race it',
    competitive: 'Contend',
  }
  return labels[outcome]
}

export function eventLabel(kind: EventKind): string {
  return kind === 'hyrox' ? 'Hyrox' : 'Half-distance triathlon'
}

export function phaseLabel(phase: EventPhase): string {
  const labels: Record<EventPhase, string> = {
    foundation: 'Foundation', base: 'Base', build: 'Build',
    specific: 'Race specific', peak: 'Peak', taper: 'Taper', race_week: 'Race week',
  }
  return labels[phase]
}
