const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/

export function isIsoDate(value: unknown): value is string {
  if (typeof value !== 'string' || !ISO_DATE.test(value)) return false
  const parsed = new Date(`${value}T12:00:00.000Z`)
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value
}

export function activeDateStorageKey(userId: string | null | undefined): string {
  return `apex-active-date:${userId || 'local'}`
}

export function resolveActiveDate(input: {
  today: string
  requestedDate?: string | null
  storedDate?: string | null
}): string {
  if (isIsoDate(input.requestedDate)) return input.requestedDate
  if (isIsoDate(input.storedDate)) return input.storedDate
  return input.today
}

export interface CalendarDayState {
  isSelected: boolean
  isToday: boolean
  ariaCurrent: 'date' | undefined
}

export function calendarDayState(input: {
  date: string
  selectedDate: string
  today: string
}): CalendarDayState {
  const isToday = input.date === input.today
  return {
    isSelected: input.date === input.selectedDate,
    isToday,
    ariaCurrent: isToday ? 'date' : undefined,
  }
}

export function loadActiveDate(
  userId: string | null | undefined,
  today: string,
  requestedDate?: string | null,
): string {
  let storedDate: string | null = null
  try {
    storedDate = typeof sessionStorage === 'undefined'
      ? null
      : sessionStorage.getItem(activeDateStorageKey(userId))
  } catch {
    storedDate = null
  }
  return resolveActiveDate({ today, requestedDate, storedDate })
}

export function rememberActiveDate(userId: string | null | undefined, date: string): void {
  if (!isIsoDate(date)) return
  try {
    if (typeof sessionStorage !== 'undefined') {
      sessionStorage.setItem(activeDateStorageKey(userId), date)
    }
  } catch {
    // Private browsing or storage restrictions must never block date navigation.
  }
}
