import { differenceInCalendarDays } from 'date-fns'
import type { AppData } from './types'

/*
 * Streak = consecutive days with a completed session (event recovery
 * micro-sessions count). Today only counts once it is done, and an unfinished
 * today does not break yesterday's run.
 */
export function currentStreak(data: AppData, todayIso: string): number {
  const done = new Set(data.workout_sessions.filter((s) => s.completed).map((s) => s.date))
  let streak = 0
  let cursor = done.has(todayIso) ? todayIso : previousDay(todayIso)
  while (done.has(cursor)) {
    streak += 1
    cursor = previousDay(cursor)
  }
  return streak
}

export function bestStreak(data: AppData): number {
  const dates = [...new Set(data.workout_sessions.filter((s) => s.completed).map((s) => s.date))].sort()
  let best = 0
  let run = 0
  for (let i = 0; i < dates.length; i++) {
    if (i > 0 && differenceInCalendarDays(new Date(dates[i] + 'T12:00:00'), new Date(dates[i - 1] + 'T12:00:00')) === 1) {
      run += 1
    } else {
      run = 1
    }
    best = Math.max(best, run)
  }
  return best
}

function previousDay(dateIso: string): string {
  const d = new Date(dateIso + 'T12:00:00')
  d.setDate(d.getDate() - 1)
  return d.toISOString().slice(0, 10)
}
