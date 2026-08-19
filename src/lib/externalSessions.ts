/*
 * Sessions APEX did not write.
 *
 * People follow programmes the app has nothing to do with: a DVD series, a
 * studio class, a video on a phone propped against a water bottle. When one of
 * those is marked done, the day should reflect what it actually cost and what
 * it actually built, rather than showing an empty training slot.
 *
 * The catalogue here is deliberately generic. APEX ships no third-party
 * programme or session names, so it distributes no marks it has no right to.
 * A person may label their own session however they like, including with a
 * brand name, and that label is their data. The app learns the pairing between
 * their label and a type, per user, so the second time they log it there is
 * nothing to choose.
 */

export type SessionQuality =
  | 'hiit'
  | 'steady_cardio'
  | 'circuit_resistance'
  | 'yoga_flow'
  | 'yoga_restorative'
  | 'pilates_core'
  | 'barre'
  | 'dance_cardio'
  | 'martial_cardio'
  | 'plyometric'
  | 'stretch_recovery'
  | 'sport_practice'
  | 'walk_hike'
  | 'swim'
  | 'cycle'
  | 'run'

/* What one minute of the session contributes, on a 0 to 1 scale, to each
 * quality the brain already tracks. These are contribution weights rather
 * than measurements: a minute of HIIT does more for endurance than a minute
 * of restorative yoga, and far less for flexibility. */
export interface SessionContribution {
  endurance: number
  strength: number
  flexibility: number
  power: number
  /* Systemic cost per minute, which feeds recovery and the next day's plan. */
  fatigue: number
}

export interface ExternalSessionType {
  id: SessionQuality
  label: string
  /* What the person is likely to call it, shown as a hint rather than a claim. */
  hint: string
  typicalMinutes: number
  contribution: SessionContribution
  /* Counts as a resistance exposure for weekly frequency purposes. */
  countsAsResistance: boolean
  impact: 'none' | 'low' | 'high'
}

export const EXTERNAL_SESSION_TYPES: ExternalSessionType[] = [
  {
    id: 'hiit', label: 'HIIT cardio', hint: 'Short intervals, hard efforts, little rest',
    typicalMinutes: 25, countsAsResistance: false, impact: 'high',
    contribution: { endurance: 0.9, strength: 0.15, flexibility: 0.05, power: 0.35, fatigue: 0.9 },
  },
  {
    id: 'circuit_resistance', label: 'Resistance circuit', hint: 'Weights or bands, moving between exercises',
    typicalMinutes: 35, countsAsResistance: true, impact: 'low',
    contribution: { endurance: 0.5, strength: 0.6, flexibility: 0.1, power: 0.2, fatigue: 0.75 },
  },
  {
    id: 'plyometric', label: 'Jump and plyometric', hint: 'Jumping, bounding, explosive work',
    typicalMinutes: 25, countsAsResistance: true, impact: 'high',
    contribution: { endurance: 0.6, strength: 0.3, flexibility: 0.1, power: 0.85, fatigue: 0.85 },
  },
  {
    id: 'steady_cardio', label: 'Steady cardio', hint: 'One continuous effort you could hold a conversation through',
    typicalMinutes: 40, countsAsResistance: false, impact: 'low',
    contribution: { endurance: 0.8, strength: 0.05, flexibility: 0.05, power: 0.05, fatigue: 0.45 },
  },
  {
    id: 'dance_cardio', label: 'Dance cardio', hint: 'Choreographed, continuous, music-led',
    typicalMinutes: 30, countsAsResistance: false, impact: 'high',
    contribution: { endurance: 0.75, strength: 0.1, flexibility: 0.25, power: 0.2, fatigue: 0.6 },
  },
  {
    id: 'martial_cardio', label: 'Martial arts cardio', hint: 'Striking or kicking combinations for conditioning',
    typicalMinutes: 30, countsAsResistance: false, impact: 'high',
    contribution: { endurance: 0.8, strength: 0.15, flexibility: 0.3, power: 0.4, fatigue: 0.7 },
  },
  {
    id: 'yoga_flow', label: 'Yoga flow', hint: 'Continuous, held postures, some strength',
    typicalMinutes: 40, countsAsResistance: false, impact: 'none',
    contribution: { endurance: 0.25, strength: 0.25, flexibility: 0.85, power: 0.05, fatigue: 0.35 },
  },
  {
    id: 'yoga_restorative', label: 'Restorative yoga', hint: 'Long holds, breathing, no sweat',
    typicalMinutes: 30, countsAsResistance: false, impact: 'none',
    contribution: { endurance: 0.05, strength: 0.05, flexibility: 0.9, power: 0, fatigue: 0.1 },
  },
  {
    id: 'pilates_core', label: 'Pilates or core class', hint: 'Controlled, core-led, low load',
    typicalMinutes: 35, countsAsResistance: false, impact: 'none',
    contribution: { endurance: 0.25, strength: 0.35, flexibility: 0.5, power: 0.05, fatigue: 0.4 },
  },
  {
    id: 'barre', label: 'Barre', hint: 'Small range, high repetition, legs and glutes',
    typicalMinutes: 45, countsAsResistance: false, impact: 'none',
    contribution: { endurance: 0.4, strength: 0.3, flexibility: 0.45, power: 0.05, fatigue: 0.45 },
  },
  {
    id: 'stretch_recovery', label: 'Stretch or recovery', hint: 'Mobility, foam rolling, cooling down',
    typicalMinutes: 20, countsAsResistance: false, impact: 'none',
    contribution: { endurance: 0.05, strength: 0, flexibility: 0.85, power: 0, fatigue: 0.05 },
  },
  {
    id: 'sport_practice', label: 'Sport or class', hint: 'A game, a match, a team session',
    typicalMinutes: 60, countsAsResistance: false, impact: 'high',
    contribution: { endurance: 0.7, strength: 0.15, flexibility: 0.2, power: 0.45, fatigue: 0.7 },
  },
  {
    id: 'walk_hike', label: 'Walk or hike', hint: 'On your feet, easy effort',
    typicalMinutes: 45, countsAsResistance: false, impact: 'low',
    contribution: { endurance: 0.45, strength: 0.05, flexibility: 0.05, power: 0, fatigue: 0.2 },
  },
  {
    id: 'run', label: 'Run', hint: 'Outdoors or treadmill',
    typicalMinutes: 35, countsAsResistance: false, impact: 'high',
    contribution: { endurance: 0.9, strength: 0.1, flexibility: 0.05, power: 0.15, fatigue: 0.6 },
  },
  {
    id: 'cycle', label: 'Cycle', hint: 'Road, trainer or studio bike',
    typicalMinutes: 45, countsAsResistance: false, impact: 'none',
    contribution: { endurance: 0.85, strength: 0.15, flexibility: 0.05, power: 0.15, fatigue: 0.5 },
  },
  {
    id: 'swim', label: 'Swim', hint: 'Pool or open water',
    typicalMinutes: 40, countsAsResistance: false, impact: 'none',
    contribution: { endurance: 0.85, strength: 0.2, flexibility: 0.35, power: 0.1, fatigue: 0.5 },
  },
]

export const SESSION_TYPE_BY_ID = new Map(EXTERNAL_SESSION_TYPES.map((t) => [t.id, t]))

export interface LoggedExternalSession {
  /* Whatever the person called it. Their words, their data. */
  label: string
  type: SessionQuality
  minutes: number
  /* How hard it felt, 1 to 10. Optional, and it scales the credit when given. */
  effort?: number | null
}

export interface SessionCredit {
  endurance: number
  strength: number
  flexibility: number
  power: number
  fatigue: number
  resistanceExposure: boolean
  impactMinutes: number
}

/**
 * What a completed session contributed. Minutes drive the size of the credit,
 * effort scales it, and the type decides its shape.
 */
export function creditForSession(session: LoggedExternalSession): SessionCredit {
  const type = SESSION_TYPE_BY_ID.get(session.type)
  if (!type) {
    return { endurance: 0, strength: 0, flexibility: 0, power: 0, fatigue: 0, resistanceExposure: false, impactMinutes: 0 }
  }
  const minutes = Number.isFinite(session.minutes) && session.minutes > 0
    ? Math.min(240, session.minutes)
    : type.typicalMinutes
  /* Effort of 7 is the neutral point, because that is what a person means by
     "a normal session". Below it the credit shrinks, above it it grows, and
     the range is deliberately narrow so one heroic self-report cannot
     rewrite a week. */
  const effort = session.effort == null ? 7 : Math.max(1, Math.min(10, session.effort))
  const scale = minutes * (0.7 + (effort - 7) * 0.06)
  const round = (value: number) => Math.round(value * scale * 10) / 10
  return {
    endurance: round(type.contribution.endurance),
    strength: round(type.contribution.strength),
    flexibility: round(type.contribution.flexibility),
    power: round(type.contribution.power),
    fatigue: round(type.contribution.fatigue),
    resistanceExposure: type.countsAsResistance,
    impactMinutes: type.impact === 'high' ? minutes : type.impact === 'low' ? minutes * 0.4 : 0,
  }
}

/**
 * Remembers what a person means by their own label, so the second time they
 * write it there is nothing to choose. Stored per user, never shipped.
 */
export function rememberLabel(
  memory: Record<string, SessionQuality>,
  label: string,
  type: SessionQuality,
): Record<string, SessionQuality> {
  const key = label.trim().toLocaleLowerCase()
  if (!key) return memory
  return { ...memory, [key]: type }
}

export function recallLabel(
  memory: Record<string, SessionQuality>,
  label: string,
): SessionQuality | null {
  const key = label.trim().toLocaleLowerCase()
  if (!key) return null
  if (memory[key]) return memory[key]
  /* A near match is worth offering: "pure cardio 2" after "pure cardio". */
  const known = Object.keys(memory).find((candidate) => (
    key.startsWith(candidate) || candidate.startsWith(key)
  ))
  return known ? memory[known] : null
}
