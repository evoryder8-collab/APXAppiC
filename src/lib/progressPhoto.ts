export type ProgressPose = 'front' | 'side' | 'back'
export type PhotoSyncStatus = 'local' | 'queued' | 'syncing' | 'synced' | 'failed'

export interface ProgressPhoto {
  id: string
  user_id: string
  local_date: string
  captured_at: string
  pose: ProgressPose
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

export function comparisonAspectRatio(a: ProgressPhoto, b: ProgressPhoto): number {
  const ratios = [a.aspect_ratio, b.aspect_ratio].filter((value) => Number.isFinite(value) && value > 0)
  return ratios.length === 0 ? 2 / 3 : Math.min(...ratios)
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

async function imageSource(blob: Blob): Promise<{ source: CanvasImageSource; width: number; height: number; close: () => void }> {
  if ('createImageBitmap' in globalThis) {
    const bitmap = await createImageBitmap(blob, { imageOrientation: 'from-image' })
    return { source: bitmap, width: bitmap.width, height: bitmap.height, close: () => bitmap.close() }
  }
  const url = URL.createObjectURL(blob)
  const image = new Image()
  image.decoding = 'async'
  image.src = url
  await image.decode()
  return { source: image, width: image.naturalWidth, height: image.naturalHeight, close: () => URL.revokeObjectURL(url) }
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
