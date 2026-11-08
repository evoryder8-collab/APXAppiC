const dayMilliseconds = 86_400_000

/** Fractions along the same calendar scale for both observations and date labels. */
export function datedChartAxis(dates: string[], locale: string, maxTicks = 4) {
  if (!dates.length) return { positions: [], ticks: [] }
  const times = dates.map(date => Date.parse(date + 'T00:00:00Z'))
  const first = times[0]
  const spanDays = (times[times.length - 1] - first) / dayMilliseconds
  const formatter = new Intl.DateTimeFormat(locale, {
    day: 'numeric', month: 'short', year: spanDays > 365 ? '2-digit' : undefined, timeZone: 'UTC',
  })
  const count = Math.min(maxTicks, spanDays + 1)
  const ticks = Array.from({ length: count }, (_, i) => {
    const days = count > 1 ? Math.round(spanDays * i / (count - 1)) : 0
    return { fraction: spanDays ? days / spanDays : 0.5, label: formatter.format(first + days * dayMilliseconds) }
  })
  return { positions: times.map(time => spanDays ? (time - first) / (spanDays * dayMilliseconds) : 0.5), ticks }
}
