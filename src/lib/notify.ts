/*
 * Meal + supplement reminders via the Notification API. A static SPA has no
 * push server, so reminders fire while APEX is open in a tab (foreground or
 * background). Checked every 30 seconds, deduped per day in localStorage.
 */
import type { Meal, Supplement } from './types'

const FIRED_KEY = 'apex.notified'

export async function ensurePermission(): Promise<boolean> {
  if (!('Notification' in window)) return false
  if (Notification.permission === 'granted') return true
  if (Notification.permission === 'denied') return false
  return (await Notification.requestPermission()) === 'granted'
}

function firedToday(id: string): boolean {
  const date = new Date().toISOString().slice(0, 10)
  try {
    const map = JSON.parse(localStorage.getItem(FIRED_KEY) ?? '{}') as Record<string, string>
    return map[id] === date
  } catch {
    return false
  }
}

function markFired(id: string): void {
  const date = new Date().toISOString().slice(0, 10)
  try {
    const map = JSON.parse(localStorage.getItem(FIRED_KEY) ?? '{}') as Record<string, string>
    /* keep the map small: only today's entries survive */
    const next: Record<string, string> = {}
    for (const [k, v] of Object.entries(map)) if (v === date) next[k] = v
    next[id] = date
    localStorage.setItem(FIRED_KEY, JSON.stringify(next))
  } catch {
    /* noop */
  }
}

function nowHm(): string {
  const d = new Date()
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

function minutesOf(hm: string): number {
  const [h, m] = hm.split(':').map(Number)
  return h * 60 + m
}

export function startReminderLoop(
  getState: () => { meals: Meal[]; supplements: Supplement[]; trainingTime: string; enabled: boolean },
): () => void {
  const check = (): void => {
    const { meals, supplements, trainingTime, enabled } = getState()
    if (!enabled || !('Notification' in window) || Notification.permission !== 'granted') return
    const now = minutesOf(nowHm())

    for (const meal of meals) {
      const t = minutesOf(meal.time)
      if (now >= t && now < t + 2 && !firedToday(`meal-${meal.id}`)) {
        markFired(`meal-${meal.id}`)
        new Notification(`${meal.name} time`, {
          body: meal.foods,
          tag: `meal-${meal.id}`,
        })
      }
    }
    for (const sup of supplements) {
      const t =
        sup.timing === 'clock' && sup.clock_time
          ? minutesOf(sup.clock_time)
          : minutesOf(trainingTime) + (sup.offset_min ?? 0)
      if (now >= t && now < t + 2 && !firedToday(`sup-${sup.group_label}`)) {
        markFired(`sup-${sup.group_label}`)
        new Notification(`Supplements: ${sup.group_label}`, {
          body: 'Open APEX to check off the window.',
          tag: `sup-${sup.group_label}`,
        })
      }
    }
  }
  const id = window.setInterval(check, 30_000)
  check()
  return () => window.clearInterval(id)
}
