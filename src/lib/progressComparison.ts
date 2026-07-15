import type { IntroLanguage } from './introLanguage'
import type { ComparisonView, ComparisonViews, ProgressPhoto } from './progressPhoto'
import type { AppData, WorkoutLog } from './types'

export interface ProgressStrengthComparison {
  averageLoadDeltaKg: number | null
  matchedExercises: number
  loadedSets: number
}

export interface ProgressPosterStats extends ProgressStrengthComparison {
  days: number
  workouts: number
}

function logKey(log: Pick<WorkoutLog, 'exercise_id' | 'exercise_name'>): string {
  return log.exercise_id ? `id:${log.exercise_id}` : `name:${log.exercise_name.trim().toLocaleLowerCase('en')}`
}

function mean(values: number[]): number {
  return values.reduce((sum, value) => sum + value, 0) / Math.max(1, values.length)
}

/* Compare like with like: each movement contributes one delta between its
   earliest and latest recorded session inside the photo window. This avoids a
   squat-heavy day overpowering the result simply because it has more sets. */
export function progressStrengthComparison(data: AppData, firstDate: string, secondDate: string): ProgressStrengthComparison {
  const from = firstDate <= secondDate ? firstDate : secondDate
  const to = firstDate <= secondDate ? secondDate : firstDate
  const sessions = new Map(data.workout_sessions
    .filter((session) => session.completed && session.date >= from && session.date <= to)
    .map((session) => [session.id, session.date]))
  const logs = data.workout_logs.filter((log) => !log.skipped && log.weight_kg != null && log.weight_kg > 0 && sessions.has(log.session_id))
  const grouped = new Map<string, Map<string, number[]>>()

  for (const log of logs) {
    const key = logKey(log)
    const bySession = grouped.get(key) ?? new Map<string, number[]>()
    bySession.set(log.session_id, [...(bySession.get(log.session_id) ?? []), Number(log.weight_kg)])
    grouped.set(key, bySession)
  }

  const deltas: number[] = []
  for (const bySession of grouped.values()) {
    const points = [...bySession.entries()]
      .map(([sessionId, weights]) => ({ sessionId, date: sessions.get(sessionId)!, average: mean(weights) }))
      .sort((a, b) => a.date.localeCompare(b.date) || a.sessionId.localeCompare(b.sessionId))
    if (points.length < 2) continue
    deltas.push(points.at(-1)!.average - points[0].average)
  }

  return {
    averageLoadDeltaKg: deltas.length > 0 ? Math.round(mean(deltas) * 10) / 10 : null,
    matchedExercises: deltas.length,
    loadedSets: logs.length,
  }
}

const POSTER_COPY = {
  en: {
    kicker: 'APEX • PRIVATE PROGRESS', title: 'THE WORK, MADE VISIBLE.', before: 'BEFORE', after: 'AFTER', days: 'DAYS', workouts: 'WORKOUTS', load: 'AVG LOAD / SET', baseline: 'BASELINE', matched: 'MATCHED EXERCISES', loaded: 'WEIGHTED SETS', weight: 'BODY WEIGHT', private: 'CREATED PRIVATELY ON DEVICE', profile: 'PROFILE', side: 'SIDE', back: 'BACK', front: 'FRONT',
  },
  ro: {
    kicker: 'APEX • PROGRES PRIVAT', title: 'MUNCA DEVINE VIZIBILĂ.', before: 'ÎNAINTE', after: 'DUPĂ', days: 'ZILE', workouts: 'ANTRENAMENTE', load: 'MEDIE KG / SET', baseline: 'REPER', matched: 'EXERCIȚII COMPARATE', loaded: 'SETURI CU GREUTATE', weight: 'GREUTATE', private: 'CREAT PRIVAT PE DISPOZITIV', profile: 'PROFIL', side: 'PROFIL', back: 'SPATE', front: 'FAȚĂ',
  },
  th: {
    kicker: 'APEX • ความก้าวหน้าส่วนตัว', title: 'ให้ผลงานพูดแทนคุณ', before: 'ก่อน', after: 'หลัง', days: 'วัน', workouts: 'การฝึก', load: 'กก. เฉลี่ย / เซต', baseline: 'ค่าฐาน', matched: 'ท่าที่เปรียบเทียบ', loaded: 'เซตมีน้ำหนัก', weight: 'น้ำหนักตัว', private: 'สร้างแบบส่วนตัวบนอุปกรณ์', profile: 'ด้านข้าง', side: 'ด้านข้าง', back: 'ด้านหลัง', front: 'ด้านหน้า',
  },
} satisfies Record<IntroLanguage, Record<string, string>>

interface DecodedPosterImage {
  source: CanvasImageSource
  width: number
  height: number
  close: () => void
}

async function decodePosterImage(url: string): Promise<DecodedPosterImage> {
  const response = await fetch(url)
  if (!response.ok) throw new Error('A private comparison photo could not be loaded for export.')
  const blob = await response.blob()
  if (typeof createImageBitmap === 'function') {
    try {
      const bitmap = await createImageBitmap(blob, { imageOrientation: 'from-image' })
      return { source: bitmap, width: bitmap.width, height: bitmap.height, close: () => bitmap.close() }
    } catch {
      try {
        const bitmap = await createImageBitmap(blob)
        return { source: bitmap, width: bitmap.width, height: bitmap.height, close: () => bitmap.close() }
      } catch {
        /* Some mobile browsers expose createImageBitmap without supporting
           every image type. The HTMLImageElement path below is slower but
           dependable for a private on-device export. */
      }
    }
  }
  const objectUrl = URL.createObjectURL(blob)
  const image = new Image()
  image.decoding = 'async'
  await new Promise<void>((resolve, reject) => {
    image.onload = () => resolve()
    image.onerror = () => reject(new Error('A private comparison photo could not be decoded for export.'))
    image.src = objectUrl
  })
  return { source: image, width: image.naturalWidth, height: image.naturalHeight, close: () => URL.revokeObjectURL(objectUrl) }
}

function roundedPath(context: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, radius: number): void {
  const r = Math.min(radius, width / 2, height / 2)
  context.beginPath()
  context.moveTo(x + r, y)
  context.lineTo(x + width - r, y)
  context.quadraticCurveTo(x + width, y, x + width, y + r)
  context.lineTo(x + width, y + height - r)
  context.quadraticCurveTo(x + width, y + height, x + width - r, y + height)
  context.lineTo(x + r, y + height)
  context.quadraticCurveTo(x, y + height, x, y + height - r)
  context.lineTo(x, y + r)
  context.quadraticCurveTo(x, y, x + r, y)
  context.closePath()
}

function drawCover(
  context: CanvasRenderingContext2D,
  image: DecodedPosterImage,
  photo: ProgressPhoto,
  view: ComparisonView,
  x: number,
  y: number,
  width: number,
  height: number,
): void {
  context.save()
  context.beginPath()
  context.rect(x, y, width, height)
  context.clip()
  context.translate(x + width / 2 + view.x / 100 * width, y + height / 2 + view.y / 100 * height)
  const userScale = Math.max(1, view.scale * photo.crop_scale)
  context.scale(userScale, userScale)
  const coverScale = Math.max(width / image.width, height / image.height)
  const drawWidth = image.width * coverScale
  const drawHeight = image.height * coverScale
  const drawX = -width / 2 - Math.max(0, drawWidth - width) * photo.crop_x
  const drawY = -height / 2 - Math.max(0, drawHeight - height) * photo.crop_y
  context.imageSmoothingEnabled = true
  context.imageSmoothingQuality = 'high'
  context.drawImage(image.source, drawX, drawY, drawWidth, drawHeight)
  context.restore()
}

function fitText(context: CanvasRenderingContext2D, text: string, maxWidth: number, startSize: number, weight = 800, family = 'Space Grotesk Variable, Arial, sans-serif'): number {
  let size = startSize
  do {
    context.font = `${weight} ${size}px ${family}`
    if (context.measureText(text).width <= maxWidth) return size
    size -= 2
  } while (size >= 20)
  return size
}

function formatDate(date: string, language: IntroLanguage): string {
  const locale = language === 'ro' ? 'ro-RO' : language === 'th' ? 'th-TH' : 'en-GB'
  return new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' }).format(new Date(`${date}T12:00:00`))
}

function poseText(photo: ProgressPhoto, language: IntroLanguage): string {
  const copy = POSTER_COPY[language]
  return copy[photo.pose]
}

function canvasPng(canvas: HTMLCanvasElement): Promise<Blob> {
  return new Promise((resolve, reject) => canvas.toBlob((blob) => blob ? resolve(blob) : reject(new Error('The progress card could not be encoded.')), 'image/png', 1))
}

export async function createProgressComparisonPoster(input: {
  left: ProgressPhoto
  right: ProgressPhoto
  leftUrl: string
  rightUrl: string
  views: ComparisonViews
  stats: ProgressPosterStats
  athleteName: string
  language: IntroLanguage
}): Promise<Blob> {
  await document.fonts?.ready
  const [leftImage, rightImage] = await Promise.all([decodePosterImage(input.leftUrl), decodePosterImage(input.rightUrl)])
  try {
    const canvas = document.createElement('canvas')
    canvas.width = 1080
    canvas.height = 1350
    const context = canvas.getContext('2d')
    if (!context) throw new Error('Canvas is unavailable.')
    const copy = POSTER_COPY[input.language]
    const outer = { x: 20, y: 20, width: 1040, height: 1310, radius: 62 }

    context.clearRect(0, 0, canvas.width, canvas.height)
    context.save()
    roundedPath(context, outer.x, outer.y, outer.width, outer.height, outer.radius)
    context.clip()
    const background = context.createLinearGradient(40, 30, 1040, 1320)
    background.addColorStop(0, '#070a12')
    background.addColorStop(0.5, '#101126')
    background.addColorStop(1, '#07141a')
    context.fillStyle = background
    context.fillRect(outer.x, outer.y, outer.width, outer.height)
    const violetGlow = context.createRadialGradient(900, 120, 0, 900, 120, 430)
    violetGlow.addColorStop(0, 'rgba(139,92,246,.43)')
    violetGlow.addColorStop(1, 'rgba(139,92,246,0)')
    context.fillStyle = violetGlow
    context.fillRect(outer.x, outer.y, outer.width, outer.height)
    const cyanGlow = context.createRadialGradient(120, 1160, 0, 120, 1160, 420)
    cyanGlow.addColorStop(0, 'rgba(34,211,238,.24)')
    cyanGlow.addColorStop(1, 'rgba(34,211,238,0)')
    context.fillStyle = cyanGlow
    context.fillRect(outer.x, outer.y, outer.width, outer.height)

    context.fillStyle = '#b8a7ff'
    context.font = '800 24px JetBrains Mono Variable, monospace'
    context.fillText(copy.kicker, 72, 90)
    context.fillStyle = '#ffffff'
    fitText(context, copy.title, 760, input.language === 'th' ? 48 : 58)
    context.fillText(copy.title, 72, 157)
    context.fillStyle = 'rgba(255,255,255,.58)'
    fitText(context, input.athleteName, 420, 28, 700)
    context.fillText(input.athleteName, 72, 204)

    const photoX = 64
    const photoY = 246
    const photoWidth = 952
    const photoHeight = 674
    const paneWidth = photoWidth / 2
    context.save()
    roundedPath(context, photoX, photoY, photoWidth, photoHeight, 44)
    context.clip()
    drawCover(context, leftImage, input.left, input.views.left, photoX, photoY, paneWidth, photoHeight)
    drawCover(context, rightImage, input.right, input.views.right, photoX + paneWidth, photoY, paneWidth, photoHeight)
    const topShade = context.createLinearGradient(0, photoY, 0, photoY + 150)
    topShade.addColorStop(0, 'rgba(3,5,12,.78)')
    topShade.addColorStop(1, 'rgba(3,5,12,0)')
    context.fillStyle = topShade
    context.fillRect(photoX, photoY, photoWidth, 150)
    const bottomShade = context.createLinearGradient(0, photoY + photoHeight - 160, 0, photoY + photoHeight)
    bottomShade.addColorStop(0, 'rgba(3,5,12,0)')
    bottomShade.addColorStop(1, 'rgba(3,5,12,.86)')
    context.fillStyle = bottomShade
    context.fillRect(photoX, photoY + photoHeight - 160, photoWidth, 160)
    context.restore()

    context.strokeStyle = 'rgba(255,255,255,.18)'
    context.lineWidth = 2
    roundedPath(context, photoX, photoY, photoWidth, photoHeight, 44)
    context.stroke()
    const divider = context.createLinearGradient(0, photoY, 0, photoY + photoHeight)
    divider.addColorStop(0, 'rgba(255,255,255,.05)')
    divider.addColorStop(0.5, 'rgba(255,255,255,.95)')
    divider.addColorStop(1, 'rgba(255,255,255,.05)')
    context.fillStyle = divider
    context.fillRect(photoX + paneWidth - 1, photoY, 2, photoHeight)

    const labels = [
      { x: photoX + 26, align: 'left' as const, label: copy.before, photo: input.left },
      { x: photoX + photoWidth - 26, align: 'right' as const, label: copy.after, photo: input.right },
    ]
    for (const item of labels) {
      context.textAlign = item.align
      context.fillStyle = '#ffffff'
      context.font = '800 23px JetBrains Mono Variable, monospace'
      context.fillText(item.label, item.x, photoY + 46)
      context.fillStyle = 'rgba(255,255,255,.72)'
      context.font = '700 18px JetBrains Mono Variable, monospace'
      context.fillText(`${formatDate(item.photo.local_date, input.language)} • ${poseText(item.photo, input.language)}`, item.x, photoY + photoHeight - 30)
    }
    context.textAlign = 'left'

    const statsX = 64
    const statsY = 952
    const statsWidth = 952
    const statsHeight = 220
    roundedPath(context, statsX, statsY, statsWidth, statsHeight, 36)
    context.fillStyle = 'rgba(255,255,255,.065)'
    context.fill()
    context.strokeStyle = 'rgba(255,255,255,.12)'
    context.stroke()
    const columns = [
      { label: copy.days, value: String(input.stats.days), detail: `${formatDate(input.left.local_date, input.language)} — ${formatDate(input.right.local_date, input.language)}` },
      { label: copy.workouts, value: String(input.stats.workouts), detail: `${input.stats.loadedSets} ${copy.loaded}` },
      { label: copy.load, value: input.stats.averageLoadDeltaKg == null ? copy.baseline : `${input.stats.averageLoadDeltaKg > 0 ? '+' : ''}${input.stats.averageLoadDeltaKg} KG`, detail: input.stats.matchedExercises > 0 ? `${input.stats.matchedExercises} ${copy.matched}` : `${input.stats.loadedSets} ${copy.loaded}` },
    ]
    const columnWidth = statsWidth / columns.length
    columns.forEach((column, index) => {
      const x = statsX + index * columnWidth + 26
      if (index > 0) {
        context.fillStyle = 'rgba(255,255,255,.10)'
        context.fillRect(statsX + index * columnWidth, statsY + 34, 1, statsHeight - 68)
      }
      context.fillStyle = index === 2 ? '#8ff4dd' : 'rgba(255,255,255,.55)'
      fitText(context, column.label, columnWidth - 52, 18, 800, 'JetBrains Mono Variable, monospace')
      context.fillText(column.label, x, statsY + 52)
      context.fillStyle = '#ffffff'
      fitText(context, column.value, columnWidth - 52, 43, 800, 'JetBrains Mono Variable, monospace')
      context.fillText(column.value, x, statsY + 112)
      context.fillStyle = 'rgba(255,255,255,.42)'
      fitText(context, column.detail, columnWidth - 52, 14, 700, 'JetBrains Mono Variable, monospace')
      context.fillText(column.detail, x, statsY + 154)
    })

    if (input.left.weight_kg != null && input.right.weight_kg != null) {
      const delta = Math.round((input.right.weight_kg - input.left.weight_kg) * 10) / 10
      const weightLine = `${copy.weight}  ${input.left.weight_kg} → ${input.right.weight_kg} KG  (${delta > 0 ? '+' : ''}${delta} KG)`
      context.fillStyle = 'rgba(184,167,255,.13)'
      roundedPath(context, 72, 1194, 550, 54, 27)
      context.fill()
      context.fillStyle = '#d9d0ff'
      context.font = '800 17px JetBrains Mono Variable, monospace'
      context.fillText(weightLine, 94, 1228)
    }

    context.fillStyle = 'rgba(255,255,255,.38)'
    context.font = '700 16px JetBrains Mono Variable, monospace'
    context.fillText(copy.private, 72, 1281)
    context.textAlign = 'right'
    context.fillStyle = '#ffffff'
    context.font = '900 26px Space Grotesk Variable, Arial, sans-serif'
    context.fillText('A P E X', 1008, 1283)
    context.restore()
    return canvasPng(canvas)
  } finally {
    leftImage.close()
    rightImage.close()
  }
}
