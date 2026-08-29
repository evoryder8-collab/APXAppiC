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

export function workoutInsightsCardBlob(
  summary: WorkoutInsightSummary,
  options: WorkoutInsightsCardOptions,
): Promise<Blob> {
  const canvas = document.createElement('canvas')
  canvas.width = 1200
  canvas.height = 1500
  const context = canvas.getContext('2d')
  if (!context) return Promise.reject(new Error('Canvas is unavailable.'))

  const backdrop = context.createLinearGradient(0, 0, 1200, 1500)
  backdrop.addColorStop(0, '#07111f')
  backdrop.addColorStop(0.48, '#111827')
  backdrop.addColorStop(1, '#04070d')
  context.fillStyle = backdrop
  context.fillRect(0, 0, 1200, 1500)

  const aurora = context.createRadialGradient(960, 170, 10, 960, 170, 620)
  aurora.addColorStop(0, `${options.accent.soft}aa`)
  aurora.addColorStop(0.38, `${options.accent.bright}42`)
  aurora.addColorStop(1, 'rgba(0,0,0,0)')
  context.fillStyle = aurora
  context.fillRect(0, 0, 1200, 900)

  context.save()
  roundedRect(context, 54, 54, 1092, 1392, 72)
  context.clip()
  context.strokeStyle = 'rgba(255,255,255,.20)'
  context.lineWidth = 3
  context.stroke()
  context.restore()

  context.fillStyle = options.accent.soft
  context.font = '700 28px ui-monospace, SFMono-Regular, Menlo, monospace'
  context.letterSpacing = '8px'
  context.fillText('APEX', 108, 145)
  context.letterSpacing = '0px'
  context.fillStyle = '#f8fafc'
  context.font = '800 72px ui-rounded, -apple-system, BlinkMacSystemFont, sans-serif'
  context.fillText(options.labels.title, 108, 245)
  context.fillStyle = 'rgba(226,232,240,.76)'
  context.font = '600 31px -apple-system, BlinkMacSystemFont, sans-serif'
  context.fillText(options.athleteName, 108, 305)
  context.font = '600 27px ui-monospace, SFMono-Regular, Menlo, monospace'
  context.fillText(options.rangeLabel, 108, 355)

  if (summary.anniversaryYears) {
    const crest = context.createLinearGradient(830, 96, 1080, 300)
    crest.addColorStop(0, options.accent.soft)
    crest.addColorStop(1, options.accent.bright)
    context.fillStyle = crest
    roundedRect(context, 820, 102, 258, 156, 42)
    context.fill()
    context.fillStyle = '#06101b'
    context.textAlign = 'center'
    context.font = '900 48px ui-rounded, -apple-system, BlinkMacSystemFont, sans-serif'
    context.fillText(`${summary.anniversaryYears} ${summary.anniversaryYears === 1 ? 'YEAR' : 'YEARS'}`, 949, 171)
    context.font = '800 21px ui-monospace, SFMono-Regular, Menlo, monospace'
    context.fillText(options.labels.anniversary.toUpperCase(), 949, 215)
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
    const x = 108 + column * 504
    const y = 430 + row * 218
    context.fillStyle = 'rgba(255,255,255,.075)'
    roundedRect(context, x, y, 456, 174, 38)
    context.fill()
    context.strokeStyle = 'rgba(255,255,255,.12)'
    context.lineWidth = 2
    context.stroke()
    context.fillStyle = 'rgba(203,213,225,.72)'
    context.font = '700 22px ui-monospace, SFMono-Regular, Menlo, monospace'
    context.fillText(label.toUpperCase(), x + 34, y + 48)
    context.fillStyle = index < 3 ? options.accent.soft : '#f8fafc'
    context.font = '800 44px ui-rounded, -apple-system, BlinkMacSystemFont, sans-serif'
    context.fillText(value, x + 34, y + 116)
  })

  context.fillStyle = 'rgba(148,163,184,.72)'
  context.font = '600 23px -apple-system, BlinkMacSystemFont, sans-serif'
  context.fillText(options.labels.verified, 108, 1370)
  context.fillStyle = options.accent.soft
  context.beginPath()
  context.arc(1065, 1362, 12, 0, Math.PI * 2)
  context.fill()

  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) resolve(blob)
      else reject(new Error('The workout card could not be rendered.'))
    }, 'image/png')
  })
}
