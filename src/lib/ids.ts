/* Deterministic per-date ids so cross-device upserts merge instead of duplicating. */

function dateDigits(date: string): string {
  return date.replaceAll('-', '').padStart(12, '0')
}

export function dailyLogId(date: string): string {
  return `33333333-0000-4000-8000-${dateDigits(date)}`
}

export function healthMetricId(date: string): string {
  return `44444444-0000-4000-8000-${dateDigits(date)}`
}
