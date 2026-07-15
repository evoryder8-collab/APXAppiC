import type { Settings } from './types.ts'

export type UiMode = 'simple' | 'advanced'

export function uiModeFromSettings(settings: Settings | null): UiMode {
  return settings?.addons.uiMode === 'simple' ? 'simple' : 'advanced'
}

export function settingsForUiMode(settings: Settings, uiMode: UiMode): Pick<Settings, 'addons'> {
  return { addons: { ...settings.addons, uiMode } }
}

export interface TimedSimpleAction {
  time: number
}

export interface SimpleSwipePoint {
  x: number
  y: number
}

/* Horizontal gestures that begin inside a component-owned gesture zone must
   never escape into Simple Mode's day navigation. */
export function simpleDaySwipeOffset(
  start: SimpleSwipePoint,
  end: SimpleSwipePoint,
  blockedByLocalGesture = false,
): -1 | 0 | 1 {
  if (blockedByLocalGesture) return 0
  const dx = end.x - start.x
  const dy = end.y - start.y
  if (Math.abs(dx) < 55 || Math.abs(dx) < Math.abs(dy) * 1.35) return 0
  return dx < 0 ? 1 : -1
}

/* Prefer the most recently due unfinished action. If nothing is due yet,
   surface the earliest upcoming action. This avoids nagging users about a
   05:30 item at dinner while still keeping the next decision obvious. */
export function selectNextSimpleAction<T extends TimedSimpleAction>(candidates: T[], nowMinutes: number): T | null {
  const ordered = [...candidates].sort((a, b) => a.time - b.time)
  const due = ordered.filter((candidate) => candidate.time <= nowMinutes)
  return due.at(-1) ?? ordered[0] ?? null
}

export function simpleCompletion(completed: number, total: number): number {
  if (total <= 0) return 100
  return Math.max(0, Math.min(100, Math.round((completed / total) * 100)))
}

export function simpleWaterTargetComplete(waterLitres: number, targetLitres: number): boolean {
  const target = Math.max(0, targetLitres)
  return target > 0 && Math.max(0, waterLitres) >= target * 0.9
}

/* The checklist is a binary promise, while the hydration action remains a
   250 ml stepper. Checking sets today's target once; unchecking clears it. */
export function toggleSimpleWaterTarget(waterLitres: number, targetLitres: number): number {
  if (simpleWaterTargetComplete(waterLitres, targetLitres)) return 0
  return Math.round(Math.max(0, targetLitres) * 100) / 100
}
