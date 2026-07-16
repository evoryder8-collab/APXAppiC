import type { RpgSnapshot } from './types'
import type { IntroLanguage } from './introLanguage'

export type ProgressPose = 'front' | 'side' | 'back'
export type ProgressFramingMode = 'full' | 'torso' | 'free'
export type PhotoSyncStatus = 'local' | 'queued' | 'syncing' | 'synced' | 'failed'

export interface ProgressPhoto {
  id: string
  user_id: string
  local_date: string
  captured_at: string
  pose: ProgressPose
  framing_mode?: ProgressFramingMode
  storage_path: string
  thumbnail_path: string
  width: number
  height: number
  aspect_ratio: number
  crop_x: number
  crop_y: number
  crop_scale: number
  reference_photo_id: string | null
  weight_kg: number | null
  note: string
  client_idempotency_key: string
  created_at: string
  updated_at: string
  sync_status: PhotoSyncStatus
}

export interface ProcessedProgressPhoto {
  full: Blob
  thumbnail: Blob
  width: number
  height: number
  aspect_ratio: number
  mime_type: string
}

export interface NormalizedCrop {
  x: number
  y: number
  scale: number
}

export interface ComparisonView {
  scale: number
  x: number
  y: number
}

export interface ComparisonViews {
  left: ComparisonView
  right: ComparisonView
}

export type ComparisonSide = keyof ComparisonViews

export interface CoverCrop {
  sx: number
  sy: number
  width: number
  height: number
}

export function formatProgressPhotoMoment(
  photo: Pick<ProgressPhoto, 'captured_at' | 'local_date'>,
  language: IntroLanguage,
  timeZone?: string,
): string {
  const locale = language === 'ro' ? 'ro-RO' : language === 'th' ? 'th-TH' : 'en-GB'
  const captured = new Date(photo.captured_at)
  const value = Number.isNaN(captured.getTime()) ? new Date(`${photo.local_date}T12:00:00`) : captured
  return new Intl.DateTimeFormat(locale, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    ...(timeZone ? { timeZone } : {}),
  }).format(value)
}

export function fitWithin(
  width: number,
  height: number,
  maxWidth: number,
  maxHeight: number,
): { width: number; height: number; scale: number } {
  if (width <= 0 || height <= 0) throw new Error('Invalid image dimensions')
  const scale = Math.min(1, maxWidth / width, maxHeight / height)
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
    scale,
  }
}

export function normalizeCrop(x: number, y: number, scale: number): NormalizedCrop {
  return {
    x: Math.max(0, Math.min(1, Number.isFinite(x) ? x : 0.5)),
    y: Math.max(0, Math.min(1, Number.isFinite(y) ? y : 0.5)),
    scale: Math.max(1, Math.min(3, Number.isFinite(scale) ? scale : 1)),
  }
}

export function normalizeComparisonView(view: ComparisonView): ComparisonView {
  const scale = Math.max(1, Math.min(4, Number.isFinite(view.scale) ? view.scale : 1))
  const limit = scale === 1 ? 0 : Math.min(42, (scale - 1) * 22)
  if (limit === 0) return { scale, x: 0, y: 0 }
  return {
    scale,
    x: Math.max(-limit, Math.min(limit, Number.isFinite(view.x) ? view.x : 0)),
    y: Math.max(-limit, Math.min(limit, Number.isFinite(view.y) ? view.y : 0)),
  }
}

export function zoomComparisonView(view: ComparisonView, delta: number): ComparisonView {
  return normalizeComparisonView({ ...view, scale: view.scale + delta })
}

export function updateComparisonViews(
  views: ComparisonViews,
  side: ComparisonSide,
  view: ComparisonView,
  synced: boolean,
): ComparisonViews {
  const normalized = normalizeComparisonView(view)
  return synced
    ? { left: normalized, right: normalized }
    : { ...views, [side]: normalized }
}

/* Source rectangle that exactly matches an object-cover preview at the target
   aspect ratio. Camera capture uses this so the saved image matches the guide
   the user aligned against on screen. */
export function coverCrop(width: number, height: number, targetAspectRatio: number): CoverCrop {
  if (width <= 0 || height <= 0 || !Number.isFinite(targetAspectRatio) || targetAspectRatio <= 0) {
    throw new Error('Invalid cover-crop dimensions')
  }
  const sourceRatio = width / height
  if (sourceRatio > targetAspectRatio) {
    const cropWidth = height * targetAspectRatio
    return { sx: (width - cropWidth) / 2, sy: 0, width: cropWidth, height }
  }
  const cropHeight = width / targetAspectRatio
  return { sx: 0, sy: (height - cropHeight) / 2, width, height: cropHeight }
}

export function comparisonAspectRatio(a: ProgressPhoto, b: ProgressPhoto): number {
  const ratios = [a.aspect_ratio, b.aspect_ratio].filter((value) => Number.isFinite(value) && value > 0)
  return ratios.length === 0 ? 2 / 3 : Math.min(...ratios)
}

export function progressFramingMode(photo: Pick<ProgressPhoto, 'framing_mode' | 'client_idempotency_key'>): ProgressFramingMode {
  if (photo.framing_mode === 'torso' || photo.framing_mode === 'free') return photo.framing_mode
  const encoded = typeof photo.client_idempotency_key === 'string'
    ? photo.client_idempotency_key.match(/^framing:(full|torso|free):/i)?.[1]
    : undefined
  return encoded === 'torso' || encoded === 'free' ? encoded : 'full'
}

export function progressPhotoIdempotencyKey(mode: ProgressFramingMode, id = crypto.randomUUID()): string {
  return `framing:${mode}:${id}`
}

/* Full-body and Free retain the camera preview crop used before framing modes
   existed. Torso deliberately saves a wider 4:5 source for room around the
   shoulders and arms in side-by-side comparisons. */
export function progressCaptureAspectRatio(mode: ProgressFramingMode, previewAspectRatio: number): number {
  return mode === 'torso' ? 4 / 5 : previewAspectRatio
}

export function isProgressCameraShutterKey(key: string, code = ''): boolean {
  return ['AudioVolumeUp', 'AudioVolumeDown', 'VolumeUp', 'VolumeDown'].includes(key)
    || ['AudioVolumeUp', 'AudioVolumeDown', 'VolumeUp', 'VolumeDown'].includes(code)
}

export function daysBetweenPhotos(a: ProgressPhoto, b: ProgressPhoto): number {
  const first = new Date(`${a.local_date}T12:00:00`).getTime()
  const second = new Date(`${b.local_date}T12:00:00`).getTime()
  return Math.round(Math.abs(second - first) / 86_400_000)
}

export function preferSamePose(reference: ProgressPhoto, photos: ProgressPhoto[]): ProgressPhoto[] {
  return [...photos].sort((a, b) => {
    const poseDifference = Number(b.pose === reference.pose) - Number(a.pose === reference.pose)
    return poseDifference || b.local_date.localeCompare(a.local_date)
  })
}

/* A comparison must never borrow a future score for an older photo. Use the
   latest known daily snapshot at or before capture, or report no history. */
export function snapshotForProgressDate(date: string, snapshots: RpgSnapshot[]): RpgSnapshot | null {
  let match: RpgSnapshot | null = null
  for (const snapshot of snapshots) {
    if (snapshot.date > date) continue
    if (!match || snapshot.date > match.date) match = snapshot
  }
  return match
}

function safePathPart(value: string): string {
  if (!/^[a-zA-Z0-9-]+$/.test(value)) throw new Error('Unsafe progress-photo identifier')
  return value
}

export function progressStoragePaths(userId: string, photoId: string): { full: string; thumbnail: string } {
  const owner = safePathPart(userId)
  const photo = safePathPart(photoId)
  return {
    full: `${owner}/${photo}/photo.webp`,
    thumbnail: `${owner}/${photo}/thumbnail.webp`,
  }
}

function canvasBlob(canvas: HTMLCanvasElement, type: string, quality: number): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => blob ? resolve(blob) : reject(new Error('Image encoding failed')), type, quality)
  })
}

async function tryImageBitmap(blob: Blob): Promise<ImageBitmap | null> {
  if (typeof createImageBitmap !== 'function') return null
  try {
    return await createImageBitmap(blob, { imageOrientation: 'from-image' })
  } catch {
    try {
      // Older Safari versions expose createImageBitmap but reject the options
      // object. The default decode still applies embedded image orientation.
      return await createImageBitmap(blob)
    } catch {
      return null
    }
  }
}

async function imageSource(blob: Blob): Promise<{ source: CanvasImageSource; width: number; height: number; close: () => void }> {
  const bitmap = await tryImageBitmap(blob)
  if (bitmap) {
    return { source: bitmap, width: bitmap.width, height: bitmap.height, close: () => bitmap.close() }
  }
  const url = URL.createObjectURL(blob)
  const image = new Image()
  image.decoding = 'async'
  try {
    await new Promise<void>((resolve, reject) => {
      image.onload = () => resolve()
      image.onerror = () => reject(new Error('This photo format could not be decoded. Try exporting it as JPEG, PNG, or WebP.'))
      image.src = url
    })
    if (!image.naturalWidth || !image.naturalHeight) throw new Error('The selected photo has no readable image data.')
    return { source: image, width: image.naturalWidth, height: image.naturalHeight, close: () => URL.revokeObjectURL(url) }
  } catch (error) {
    URL.revokeObjectURL(url)
    throw error
  }
}

function drawResized(source: CanvasImageSource, width: number, height: number): HTMLCanvasElement {
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const context = canvas.getContext('2d', { alpha: false })
  if (!context) throw new Error('Canvas is unavailable')
  context.imageSmoothingEnabled = true
  context.imageSmoothingQuality = 'high'
  context.drawImage(source, 0, 0, width, height)
  return canvas
}

/* Re-encoding through canvas applies orientation, strips EXIF/GPS metadata,
   normalizes dimensions and produces a compact comparison asset locally. */
export async function processProgressPhoto(blob: Blob): Promise<ProcessedProgressPhoto> {
  if (!blob || blob.size === 0) throw new Error('The selected photo is empty. Choose another image.')
  const decoded = await imageSource(blob)
  try {
    const fitted = fitWithin(decoded.width, decoded.height, 1600, 2400)
    const fullCanvas = drawResized(decoded.source, fitted.width, fitted.height)
    const thumbFit = fitWithin(decoded.width, decoded.height, 360, 540)
    const thumbCanvas = drawResized(decoded.source, thumbFit.width, thumbFit.height)
    let mime = 'image/webp'
    let full = await canvasBlob(fullCanvas, mime, 0.86)
    let thumbnail = await canvasBlob(thumbCanvas, mime, 0.76)
    if (full.type !== 'image/webp') {
      mime = 'image/jpeg'
      full = await canvasBlob(fullCanvas, mime, 0.88)
      thumbnail = await canvasBlob(thumbCanvas, mime, 0.78)
    }
    return {
      full,
      thumbnail,
      width: fitted.width,
      height: fitted.height,
      aspect_ratio: fitted.width / fitted.height,
      mime_type: mime,
    }
  } finally {
    decoded.close()
  }
}

export interface ProgressPhotoSyncFailure<T> {
  operation: T
  cause: unknown
}

/* A damaged or permanently rejected photo must not block later captures in
   the offline outbox. Every operation is attempted independently; failed
   work remains queued for an explicit or lifecycle retry. */
export async function runProgressPhotoSyncBatch<T>(
  operations: T[],
  send: (operation: T) => Promise<void>,
): Promise<{ succeeded: T[]; failed: ProgressPhotoSyncFailure<T>[] }> {
  const succeeded: T[] = []
  const failed: ProgressPhotoSyncFailure<T>[] = []
  for (const operation of operations) {
    try {
      await send(operation)
      succeeded.push(operation)
    } catch (cause) {
      failed.push({ operation, cause })
    }
  }
  return { succeeded, failed }
}

export function progressPhotoSaveError(cause: unknown): Error {
  const name = cause instanceof DOMException ? cause.name : cause instanceof Error ? cause.name : ''
  const message = cause instanceof Error ? cause.message : ''
  if (name === 'QuotaExceededError' || /quota|storage.*full/i.test(message)) {
    return new Error('Private photo storage is full on this device. Remove an older progress photo, then try again.')
  }
  if (/decode|image data|photo format|image encoding/i.test(message)) {
    return new Error(message || 'This photo could not be decoded. Try a JPEG, PNG, or WebP image.')
  }
  if (/indexeddb|database|transaction|private storage|invalidstate/i.test(`${name} ${message}`)) {
    return new Error('Private photo storage was temporarily unavailable. Your photo is still on this review screen, so you can retry safely.')
  }
  return cause instanceof Error ? cause : new Error('The photo could not be saved. It is still available on this review screen.')
}

export function mergePhotoUploadsIdempotently<T extends { entity_id: string; operation: string }>(
  current: T[],
  incoming: T,
): T[] {
  const next = current.filter((operation) => !(
    operation.entity_id === incoming.entity_id && operation.operation === incoming.operation
  ))
  next.push(incoming)
  return next
}
