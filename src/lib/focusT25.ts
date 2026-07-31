import { differenceInCalendarDays } from 'date-fns'
import type { PersonaSlug } from './persona'

export const FOCUS_T25_PREFIX = 'Focus T25'

export interface FocusT25Prescription {
  episode: string
  minutes: 25
  rpe: string
  kind: 'core' | 'conditioning' | 'mobility'
  note: string
}

function parseIso(value: string): Date {
  return new Date(`${value}T12:00:00`)
}

export function trainingProtocolWeek(startDate: string, date: string): number {
  return Math.max(1, Math.floor(differenceInCalendarDays(parseIso(date), parseIso(startDate)) / 7) + 1)
}

export function isProtocolDeloadWeek(week: number): boolean {
  return week === 4 || week === 8 || week === 12
}

export function isProtocolPushupTestWeek(week: number): boolean {
  return week === 1 || week === 5 || week === 9 || week === 13
}

export function isFocusT25Name(name: string): boolean {
  return name.toLocaleLowerCase().startsWith(FOCUS_T25_PREFIX.toLocaleLowerCase())
}

export function isConditioningFocusT25(name: string): boolean {
  return isFocusT25Name(name) && !/stretch/i.test(name)
}

export function resolveFocusT25(
  persona: PersonaSlug,
  weekday: number,
  week: number,
): FocusT25Prescription | null {
  if (persona !== 'constantine' && persona !== 'june') return null
  const deload = isProtocolDeloadWeek(week)
  if (deload && weekday !== 2 && weekday !== 4) return null

  const month = week <= 4 ? 1 : week <= 8 ? 2 : 3
  if (weekday === 4) {
    return {
      episode: 'Stretch',
      minutes: 25,
      rpe: 'easy',
      kind: 'mobility',
      note: 'Keep this restorative. No loaded work and no effort target.',
    }
  }

  if (weekday === 2) {
    const episode = month === 1 ? 'Ab Intervals' : month === 2 ? 'Dynamic Core' : 'Core Speed'
    return {
      episode,
      minutes: 25,
      rpe: persona === 'constantine' ? 'RPE 6–7' : 'controlled',
      kind: 'core',
      note: isProtocolPushupTestWeek(week)
        ? 'Optional after the push-up test. Keep it easy enough to preserve recovery.'
        : 'Strength first, then Focus T25. Separate them by several hours when practical.',
    }
  }

  if (weekday === 3) {
    const episode = month === 1 ? 'Lower Focus' : month === 2 ? 'Speed 2.0' : 'Speed 3.0'
    return {
      episode,
      minutes: 25,
      rpe: month === 2 && persona === 'constantine' ? 'RPE 7–8' : 'RPE 7 cap',
      kind: 'conditioning',
      note: month === 3 && week === 9
        ? 'Use the modifier this week. Strength first and separate sessions by at least four hours when possible.'
        : 'Strength first and separate sessions by at least four hours when possible. If consecutive, use the modifier and cap effort.',
    }
  }

  if (persona === 'constantine' && weekday === 5) {
    const episode = month === 1 ? 'Speed 1.0' : month === 2 ? 'Core Cardio' : 'The Pyramid'
    return {
      episode,
      minutes: 25,
      rpe: 'RPE 7',
      kind: 'conditioning',
      note: 'This belongs to the Light option only. Use low-impact modifications and stop at RPE 6–7. Full Legs B ends after strength.',
    }
  }

  return null
}
