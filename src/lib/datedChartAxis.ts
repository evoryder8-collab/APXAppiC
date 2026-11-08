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

/** Separate same-day sessions within the gap to the next distinct date. */
export function distinctSessionPositions(positions: number[]) {
  const result = positions.slice()
  for (let start = 0; start < positions.length;) {
    const center = positions[start]
    let end = start + 1
    while (end < positions.length && positions[end] === center) end++
    const count = end - start
    if (count > 1) {
      const spread = Math.min(0.08, (count - 1) * 0.015)
      const left = Math.max(center - spread, start ? (positions[start - 1] + center) / 2 : 0)
      const right = Math.min(center + spread, end < positions.length ? (center + positions[end]) / 2 : 1)
      for (let i = 0; i < count; i++) result[start + i] = left + (right - left) * i / (count - 1)
    }
    start = end
  }
  return result
}
