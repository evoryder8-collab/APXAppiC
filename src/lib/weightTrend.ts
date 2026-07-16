import type { DailyLog } from './types'

export type WeightTrendRange = 7 | 30 | 90 | 365

export interface WeightTrendPoint {
  date: string
  weightKg: number
}

const DAY_MS = 86_400_000

function timestamp(date: string): number {
  return Date.parse(`${date}T12:00:00Z`)
}

/**
 * Builds a stable, chronological weight series from the synced daily log.
 * Multiple rows for a date should not normally exist, but keeping the final
 * valid value makes the graph resilient to older imports and interrupted syncs.
 */
export function buildWeightTrend(
  logs: Pick<DailyLog, 'date' | 'weight_kg'>[],
  anchorDate: string,
  rangeDays: WeightTrendRange,
): WeightTrendPoint[] {
  const anchor = timestamp(anchorDate)
  if (!Number.isFinite(anchor)) return []
  const start = anchor - (rangeDays - 1) * DAY_MS
  const byDate = new Map<string, number>()

  for (const log of logs) {
    const dateTime = timestamp(log.date)
    const weight = Number(log.weight_kg)
    if (!Number.isFinite(dateTime) || dateTime < start || dateTime > anchor) continue
    if (!Number.isFinite(weight) || weight < 25 || weight > 300) continue
    byDate.set(log.date, Math.round(weight * 10) / 10)
  }

  return [...byDate.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([date, weightKg]) => ({ date, weightKg }))
}

export function weightTrendChange(points: WeightTrendPoint[]): number | null {
  if (points.length < 2) return null
  return Math.round((points.at(-1)!.weightKg - points[0].weightKg) * 10) / 10
}
