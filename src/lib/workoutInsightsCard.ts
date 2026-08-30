import type { Accent } from './theme'
import type { WorkoutInsightSummary } from './workoutInsights'

export interface WorkoutInsightsCardOptions {
  accent: Accent
  athleteName: string
  locale: string
  rangeLabel: string
  labels: {
    title: string
    workouts: string
    activeDays: string
    time: string
    energy: string
    reps: string
    sets: string
    volume: string
    distance: string
    anniversary: string
    verified: string
  }
}
function roundedRect(
  context: CanvasRenderingContext2D,
  x: number,
  y: number,
  width: number,
  height: number,
  radius: number,
): void {
  context.beginPath()
  context.roundRect(x, y, width, height, radius)
}

function metricValue(value: number | null, locale: string, digits = 0): string {
  if (value == null) return '\u2014'
  return new Intl.NumberFormat(locale, { maximumFractionDigits: digits }).format(value)
}

function durationLabel(minutes: number, locale: string): string {
  const hours = Math.floor(minutes / 60)
  const remainder = minutes % 60
  if (hours === 0) return `${metricValue(remainder, locale)} min`
  if (remainder === 0) return `${metricValue(hours, locale)} h`
  return `${metricValue(hours, locale)} h ${metricValue(remainder, locale)} min`
}

const CARD_WIDTH = 1200
const CARD_HEIGHT = 1500
const SAFE_INSET = 72
const roundedFont = 'ui-rounded, -apple-system, BlinkMacSystemFont, sans-serif'
const monoFont = 'ui-monospace, SFMono-Regular, Menlo, monospace'

function fitText(
  context: CanvasRenderingContext2D,
  text: string,
  maxWidth: number,
  weight: number,
  preferredSize: number,
  minimumSize: number,
  family = roundedFont,
): number {
  let size = preferredSize
  do {
    context.font = `${weight} ${size}px ${family}`
    if (context.measureText(text).width <= maxWidth || size <= minimumSize) return size
    size -= 1
  } while (size >= minimumSize)
  return minimumSize
}

function wrapText(context: CanvasRenderingContext2D, text: string, maxWidth: number): string[] {
  const words = text.trim().split(/\s+/u)
  const tokens = words.flatMap((word) => {
    if (context.measureText(word).width <= maxWidth) return [word]
    return Array.from(word)
  })
  const lines: string[] = []
  let line = ''
  for (const token of tokens) {
    const separator = line && token.length > 1 ? ' ' : ''
    const candidate = `${line}${separator}${token}`
    if (line && context.measureText(candidate).width > maxWidth) {
      lines.push(line)
      line = token
    } else {
      line = candidate
    }
  }
  if (line) lines.push(line)
  return lines
}

export function workoutInsightsCardBlob(
  summary: WorkoutInsightSummary,
  options: WorkoutInsightsCardOptions,
): Promise<Blob> {
  const canvas = document.createElement('canvas')
  canvas.width = CARD_WIDTH
  canvas.height = CARD_HEIGHT
  const context = canvas.getContext('2d')
  if (!context) return Promise.reject(new Error('Canvas is unavailable.'))

  const backdrop = context.createLinearGradient(0, 0, CARD_WIDTH, CARD_HEIGHT)
  backdrop.addColorStop(0, '#fffdf8')
  backdrop.addColorStop(0.46, '#fff8df')
  backdrop.addColorStop(1, '#f7efff')
  context.fillStyle = backdrop
  context.fillRect(0, 0, CARD_WIDTH, CARD_HEIGHT)

  const aurora = context.createRadialGradient(1010, 160, 20, 1010, 160, 650)
  aurora.addColorStop(0, 'rgba(177, 112, 255, .42)')
  aurora.addColorStop(0.42, 'rgba(255, 220, 70, .30)')
  aurora.addColorStop(1, 'rgba(0,0,0,0)')
  context.fillStyle = aurora
  context.fillRect(0, 0, CARD_WIDTH, 900)

  const sunshine = context.createRadialGradient(90, 1300, 10, 90, 1300, 520)
  sunshine.addColorStop(0, 'rgba(255, 214, 40, .36)')
  sunshine.addColorStop(1, 'rgba(255,255,255,0)')
  context.fillStyle = sunshine
  context.fillRect(0, 850, 700, 650)

  roundedRect(context, SAFE_INSET, SAFE_INSET, CARD_WIDTH - SAFE_INSET * 2, CARD_HEIGHT - SAFE_INSET * 2, 64)
  context.strokeStyle = 'rgba(84, 45, 132, .18)'
  context.lineWidth = 4
  context.stroke()

  context.fillStyle = '#7c3aed'
  context.font = `800 28px ${monoFont}`
  context.letterSpacing = '8px'
  context.fillText('APEX', 120, 154)
  context.letterSpacing = '0px'
  context.fillStyle = '#24133d'
  fitText(context, options.labels.title, 650, 900, 72, 42)
  context.fillText(options.labels.title, 120, 252)
  context.fillStyle = '#5f526d'
  fitText(context, options.athleteName, 650, 700, 32, 21)
  context.fillText(options.athleteName, 120, 315)
  fitText(context, options.rangeLabel, 650, 700, 27, 18, monoFont)
  context.fillText(options.rangeLabel, 120, 365)

  if (summary.anniversaryYears) {
    const crest = context.createLinearGradient(840, 104, 1080, 286)
    crest.addColorStop(0, '#ffe55c')
    crest.addColorStop(1, '#bf7cff')
    context.fillStyle = crest
    roundedRect(context, 824, 104, 264, 168, 44)
    context.fill()
    context.fillStyle = '#2c1648'
    context.textAlign = 'center'
    const years = `${summary.anniversaryYears} ${summary.anniversaryYears === 1 ? 'YEAR' : 'YEARS'}`
    fitText(context, years, 224, 900, 46, 26)
    context.fillText(years, 956, 176)
    fitText(context, options.labels.anniversary.toUpperCase(), 224, 800, 20, 13, monoFont)
    context.fillText(options.labels.anniversary.toUpperCase(), 956, 225)
    context.textAlign = 'left'
  }

  const metrics = [
    [options.labels.workouts, metricValue(summary.workouts, options.locale)],
    [options.labels.activeDays, metricValue(summary.activeDays, options.locale)],
    [options.labels.time, durationLabel(summary.durationMinutes, options.locale)],
    [options.labels.energy, summary.activeEnergyKcal == null ? '\u2014' : `${metricValue(summary.activeEnergyKcal, options.locale)} kcal`],
    [options.labels.reps, metricValue(summary.reps, options.locale)],
    [options.labels.sets, metricValue(summary.sets, options.locale)],
    [options.labels.volume, summary.volumeKg == null ? '\u2014' : `${metricValue(summary.volumeKg, options.locale)} kg`],
    [options.labels.distance, summary.distanceKm == null ? '\u2014' : `${metricValue(summary.distanceKm, options.locale, 2)} km`],
  ]

  metrics.forEach(([label, value], index) => {
    const column = index % 2
    const row = Math.floor(index / 2)
    const x = 120 + column * 504
    const y = 430 + row * 218
    const tileGradient = context.createLinearGradient(x, y, x + 456, y + 174)
    tileGradient.addColorStop(0, index % 3 === 0 ? 'rgba(255, 225, 80, .45)' : 'rgba(255,255,255,.80)')
    tileGradient.addColorStop(1, index % 3 === 1 ? 'rgba(193, 132, 255, .30)' : 'rgba(255,255,255,.58)')
    context.fillStyle = tileGradient
    roundedRect(context, x, y, 456, 174, 38)
    context.fill()
    context.strokeStyle = 'rgba(88, 45, 132, .13)'
    context.lineWidth = 2
    context.stroke()
    context.fillStyle = '#665876'
    fitText(context, label.toUpperCase(), 388, 800, 22, 14, monoFont)
    const labelLines = wrapText(context, label.toUpperCase(), 388)
    labelLines.forEach((line, lineIndex) => context.fillText(line, x + 34, y + 43 + lineIndex * 24))
    context.fillStyle = index < 3 ? '#7c3aed' : '#28163f'
    fitText(context, value, 388, 900, 44, 25)
    context.fillText(value, x + 34, y + 116)
  })

  context.fillStyle = '#74677f'
  fitText(context, options.labels.verified, 900, 650, 23, 16)
  const footerLines = wrapText(context, options.labels.verified, 900)
  footerLines.forEach((line, index) => context.fillText(line, 120, 1360 + index * 30))
  context.fillStyle = '#f5c518'
  context.beginPath()
  context.arc(1060, 1352, 12, 0, Math.PI * 2)
  context.fill()

  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) resolve(blob)
      else reject(new Error('The workout card could not be rendered.'))
    }, 'image/png')
  })
}
