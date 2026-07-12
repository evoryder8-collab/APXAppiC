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
