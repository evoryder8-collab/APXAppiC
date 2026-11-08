import type { AppData, RpgSnapshot } from './types'
import type { OrbitRun } from '../orbit/domain/types'
import { isIsoDate } from './activeDate.ts'
import { visibleImportedActivitiesForOwner } from './importedActivityVisibility.ts'

export const reportPeriods = { month: '1 month', quarter: '3 months', half: '6 months', year: '1 year', all: 'All time', custom: 'Custom' } as const
export type ReportPeriod = keyof typeof reportPeriods
export type AvatarReportRange = { from: string; to: string; allTime: boolean }

export function avatarReportRange(period: ReportPeriod, today: string, earliest: string, customFrom: string, customTo: string): AvatarReportRange | null {
  if (period === 'custom') {
    return isIsoDate(customFrom) && isIsoDate(customTo) && customFrom <= customTo && customTo <= today
      ? { from: customFrom, to: customTo, allTime: false } : null
  }
  if (period === 'all') return { from: earliest, to: today, allTime: true }
  const months = { month: 1, quarter: 3, half: 6, year: 12 }[period]
  const first = new Date(today + 'T12:00:00Z')
  const day = first.getUTCDate()
  // Day zero of the following month gives the last valid day of the target month.
  first.setUTCMonth(first.getUTCMonth() - months + 1, 0)
  first.setUTCDate(Math.min(day, first.getUTCDate()) + 1)
  return { from: first.toISOString().slice(0, 10), to: today, allTime: false }
}

export function earliestReportDate(data: AppData, runs: OrbitRun[], snapshots: RpgSnapshot[], today: string): string {
  const owner = data.profile?.user_id
  const sessions = new Map(data.workout_sessions.filter(s => s.user_id === owner && s.completed).map(s => [s.id, s.date]))
  const dates = [...sessions.values(),
    ...visibleImportedActivitiesForOwner(data).flatMap(a => {
      const date = a.apex_workout_session_id ? sessions.get(a.apex_workout_session_id) : a.date
      return date && a.duration_min > 0 ? [date] : []
    }),
    ...runs.filter(r => r.user_id === owner && r.status === 'completed' && r.metrics.distance_m > 0).map(r => r.local_date),
    ...snapshots.filter(s => s.user_id === owner).map(s => s.date),
  ]
  return dates.reduce((first, date) => isIsoDate(date) && date < first ? date : first, today)
}
