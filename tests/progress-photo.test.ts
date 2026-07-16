import assert from 'node:assert/strict'
import test from 'node:test'
import {
  comparisonAspectRatio,
  coverCrop,
  daysBetweenPhotos,
  fitWithin,
  formatProgressPhotoMoment,
  mergePhotoUploadsIdempotently,
  normalizeCrop,
  normalizeComparisonView,
  preferSamePose,
  processProgressPhoto,
  progressCaptureAspectRatio,
  progressFramingMode,
  progressPhotoIdempotencyKey,
  progressPhotoSaveError,
  progressStoragePaths,
  isProgressCameraShutterKey,
  runProgressPhotoSyncBatch,
  snapshotForProgressDate,
  updateComparisonViews,
  zoomComparisonView,
  type ProgressPhoto,
} from '../src/lib/progressPhoto.ts'
import type { RpgSnapshot } from '../src/lib/types.ts'
import { progressPosterContent, progressStrengthComparison, resolveProgressExportMode } from '../src/lib/progressComparison.ts'
import { buildSeedData } from '../src/data/seed.ts'
import { openPrivateDb, resetPrivateDbConnection } from '../src/lib/privateDb.ts'

function photo(id: string, date: string, pose: ProgressPhoto['pose'], ratio = 2 / 3): ProgressPhoto {
  return {
    id, user_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', local_date: date,
    captured_at: `${date}T08:00:00Z`, pose, storage_path: `x/${id}.webp`, thumbnail_path: `x/${id}-t.webp`,
    width: 1000, height: 1500, aspect_ratio: ratio, crop_x: 0.5, crop_y: 0.5, crop_scale: 1,
    reference_photo_id: null, weight_kg: null, note: '', client_idempotency_key: id,
    created_at: `${date}T08:00:00Z`, updated_at: `${date}T08:00:00Z`, sync_status: 'synced',
  }
}

test('image helpers resize without upscaling and clamp comparison crop', () => {
  assert.deepEqual(fitWithin(4000, 3000, 1600, 2400), { width: 1600, height: 1200, scale: 0.4 })
  assert.deepEqual(fitWithin(800, 600, 1600, 2400), { width: 800, height: 600, scale: 1 })
  assert.deepEqual(normalizeCrop(-2, 4, 9), { x: 0, y: 1, scale: 3 })
})

test('camera cover crop matches a portrait preview without stretching', () => {
  assert.deepEqual(coverCrop(1920, 1080, 3 / 4), { sx: 555, sy: 0, width: 810, height: 1080 })
  assert.deepEqual(coverCrop(1080, 1920, 3 / 4), { sx: 0, sy: 240, width: 1080, height: 1440 })
})

test('comparison zoom and pan clamp safely and sync only when requested', () => {
  const identity = { scale: 1, x: 0, y: 0 }
  assert.deepEqual(normalizeComparisonView({ scale: 0, x: 50, y: -50 }), identity)
  const zoomed = zoomComparisonView(identity, 0.5)
  assert.deepEqual(zoomed, { scale: 1.5, x: 0, y: 0 })
  const views = { left: identity, right: identity }
  assert.deepEqual(updateComparisonViews(views, 'left', { scale: 2, x: 12, y: -8 }, true), {
    left: { scale: 2, x: 12, y: -8 }, right: { scale: 2, x: 12, y: -8 },
  })
  assert.deepEqual(updateComparisonViews(views, 'right', { scale: 2, x: 12, y: -8 }, false), {
    left: identity, right: { scale: 2, x: 12, y: -8 },
  })
})

test('private storage paths are deterministic and reject unsafe owner segments', () => {
  const paths = progressStoragePaths('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')
  assert.equal(paths.full.split('/')[0], 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
  assert.throws(() => progressStoragePaths('../other-user', 'safe'))
})

test('comparison helpers prefer same poses and report elapsed days', () => {
  const before = photo('a', '2026-06-01', 'front', 0.67)
  const after = photo('b', '2026-06-29', 'front', 0.66)
  const side = photo('c', '2026-07-01', 'side')
  assert.equal(daysBetweenPhotos(before, after), 28)
  assert.equal(comparisonAspectRatio(before, after), 0.66)
  assert.equal(preferSamePose(before, [side, after])[0].id, 'b')
})

test('photo moments retain the capture time for timeline and export labels', () => {
  const captured = photo('time', '2026-06-01', 'front')
  assert.match(formatProgressPhotoMoment(captured, 'en', 'UTC'), /08:00/)
  assert.match(formatProgressPhotoMoment(captured, 'ro', 'UTC'), /08:00/)
  assert.match(formatProgressPhotoMoment(captured, 'th', 'UTC'), /08:00/)
})

test('progress framing stays backward compatible and supports torso and free capture', () => {
  const legacy = photo('legacy', '2026-06-01', 'front')
  const torso = { ...legacy, client_idempotency_key: progressPhotoIdempotencyKey('torso', 'torso-id') }
  const free = { ...legacy, framing_mode: 'free' as const }
  assert.equal(progressFramingMode(legacy), 'full')
  assert.equal(progressFramingMode(torso), 'torso')
  assert.equal(progressFramingMode(free), 'free')
  assert.equal(progressCaptureAspectRatio('full', 3 / 4), 3 / 4)
  assert.equal(progressCaptureAspectRatio('free', 3 / 4), 3 / 4)
  assert.equal(progressCaptureAspectRatio('torso', 3 / 4), 4 / 5)
})

test('camera shutter key helper recognises exposed volume controls only', () => {
  assert.equal(isProgressCameraShutterKey('AudioVolumeUp'), true)
  assert.equal(isProgressCameraShutterKey('', 'VolumeDown'), true)
  assert.equal(isProgressCameraShutterKey('Enter'), false)
})

test('comparison export mode defaults safely and keeps minimal cards free of stats', () => {
  assert.equal(resolveProgressExportMode('minimal'), 'minimal')
  assert.equal(resolveProgressExportMode('detailed'), 'detailed')
  assert.equal(resolveProgressExportMode('unexpected'), 'detailed')
  assert.deepEqual(progressPosterContent('minimal'), {
    stats: false, athlete: false, pose: false, privateFooter: false,
  })
  assert.deepEqual(progressPosterContent('detailed'), {
    stats: true, athlete: true, pose: true, privateFooter: true,
  })
})

test('comparison strength uses matched movements instead of letting extra sets dominate', () => {
  const userId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  const data = buildSeedData(userId, 'constantine')
  data.workout_sessions = [
    { id: 'before', user_id: userId, date: '2026-06-02', program_day_id: 'p1', is_lite: false, is_deload: false, is_event_recovery: false, completed: true, quality_score: 1, started_at: '2026-06-02T08:00:00Z', completed_at: '2026-06-02T09:00:00Z', notes: '' },
    { id: 'after', user_id: userId, date: '2026-06-28', program_day_id: 'p1', is_lite: false, is_deload: false, is_event_recovery: false, completed: true, quality_score: 1, started_at: '2026-06-28T08:00:00Z', completed_at: '2026-06-28T09:00:00Z', notes: '' },
  ]
  const log = (id: string, sessionId: string, exerciseName: string, setNo: number, weight: number) => ({
    id, user_id: userId, session_id: sessionId, exercise_id: null, exercise_name: exerciseName,
    set_no: setNo, weight_kg: weight, reps: 8, rir: 2, skipped: false, override_flag: false,
    created_at: `${sessionId === 'before' ? '2026-06-02' : '2026-06-28'}T09:00:00Z`,
  })
  data.workout_logs = [
    log('a1', 'before', 'Squat', 1, 80), log('a2', 'before', 'Squat', 2, 80), log('a3', 'after', 'Squat', 1, 90),
    log('b1', 'before', 'Bench press', 1, 60), log('b2', 'after', 'Bench press', 1, 64), log('b3', 'after', 'Bench press', 2, 64), log('b4', 'after', 'Bench press', 3, 64),
  ]
  assert.deepEqual(progressStrengthComparison(data, '2026-06-01', '2026-06-30'), {
    averageLoadDeltaKg: 7,
    matchedExercises: 2,
    loadedSets: 7,
  })
})

test('photo stat overlays use the latest snapshot on or before capture and never borrow from the future', () => {
  const snapshot = (date: string, overall: number): RpgSnapshot => ({
    id: `snap-${date}`, user_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', date,
    overall, health: 60, joint: 55, flexibility: 50, endurance: 52,
    strength: 58, strength_upper: 60, strength_lower: 56,
  })
  const history = [snapshot('2026-06-01', 50), snapshot('2026-06-14', 55), snapshot('2026-06-30', 62)]
  assert.equal(snapshotForProgressDate('2026-06-14', history)?.overall, 55)
  assert.equal(snapshotForProgressDate('2026-06-20', history)?.overall, 55)
  assert.equal(snapshotForProgressDate('2026-05-20', history), null)
})

test('offline photo upload queue de-duplicates retries', () => {
  const first = { entity_id: 'photo-1', operation: 'upload_photo', attempt: 0 }
  const retry = { entity_id: 'photo-1', operation: 'upload_photo', attempt: 1 }
  const merged = mergePhotoUploadsIdempotently([first], retry)
  assert.deepEqual(merged, [retry])
})

test('one rejected photo sync does not block later queued captures', async () => {
  const operations = [{ id: 'broken' }, { id: 'healthy' }]
  const attempted: string[] = []
  const result = await runProgressPhotoSyncBatch(operations, async (operation) => {
    attempted.push(operation.id)
    if (operation.id === 'broken') throw new Error('metadata rejected')
  })
  assert.deepEqual(attempted, ['broken', 'healthy'])
  assert.deepEqual(result.succeeded, [{ id: 'healthy' }])
  assert.equal(result.failed.length, 1)
  assert.equal(result.failed[0].operation.id, 'broken')
})

test('photo storage errors are recoverable and user-facing', () => {
  assert.match(progressPhotoSaveError(new DOMException('full', 'QuotaExceededError')).message, /storage is full/i)
  assert.match(progressPhotoSaveError(new Error('IndexedDB transaction failed')).message, /temporarily unavailable/i)
  assert.match(progressPhotoSaveError(new Error('photo format could not be decoded')).message, /could not be decoded/i)
})

test('a rejected IndexedDB open is not cached for the next photo save', async () => {
  const original = globalThis.indexedDB
  let opens = 0
  const database = {
    close() {},
    onclose: null,
    onversionchange: null,
  } as unknown as IDBDatabase
  const fakeIndexedDb = {
    open() {
      opens += 1
      const request: Record<string, unknown> = { result: database, error: null }
      queueMicrotask(() => {
        if (opens === 1) {
          request.error = new DOMException('temporary open failure', 'UnknownError')
          ;(request.onerror as (() => void) | null)?.()
        } else {
          ;(request.onsuccess as (() => void) | null)?.()
        }
      })
      return request as unknown as IDBOpenDBRequest
    },
  } as IDBFactory
  Object.defineProperty(globalThis, 'indexedDB', { configurable: true, value: fakeIndexedDb })
  resetPrivateDbConnection()
  try {
    await assert.rejects(openPrivateDb(), /temporary open failure/)
    assert.equal(await openPrivateDb(), database)
    assert.equal(opens, 2)
  } finally {
    resetPrivateDbConnection()
    Object.defineProperty(globalThis, 'indexedDB', { configurable: true, value: original })
  }
})

test('gallery processing falls back when Safari exposes but rejects createImageBitmap', async () => {
  const originalBitmap = Object.getOwnPropertyDescriptor(globalThis, 'createImageBitmap')
  const originalImage = Object.getOwnPropertyDescriptor(globalThis, 'Image')
  const originalDocument = Object.getOwnPropertyDescriptor(globalThis, 'document')
  let bitmapAttempts = 0
  class FakeImage {
    decoding = ''
    naturalWidth = 3024
    naturalHeight = 4032
    onload: (() => void) | null = null
    onerror: (() => void) | null = null
    set src(_value: string) { queueMicrotask(() => this.onload?.()) }
  }
  const fakeDocument = {
    createElement(name: string) {
      assert.equal(name, 'canvas')
      return {
        width: 0,
        height: 0,
        getContext: () => ({
          imageSmoothingEnabled: false,
          imageSmoothingQuality: 'low',
          drawImage() {},
        }),
        toBlob(callback: (blob: Blob) => void, type: string) {
          callback(new Blob(['normalized'], { type }))
        },
      }
    },
  }
  Object.defineProperty(globalThis, 'createImageBitmap', {
    configurable: true,
    value: async () => { bitmapAttempts += 1; throw new TypeError('options unsupported') },
  })
  Object.defineProperty(globalThis, 'Image', { configurable: true, value: FakeImage })
  Object.defineProperty(globalThis, 'document', { configurable: true, value: fakeDocument })
  try {
    const processed = await processProgressPhoto(new Blob(['iphone-photo'], { type: 'image/heic' }))
    assert.equal(bitmapAttempts, 2)
    assert.equal(processed.width, 1600)
    assert.equal(processed.height, 2133)
    assert.equal(processed.full.type, 'image/webp')
    assert.equal(processed.thumbnail.type, 'image/webp')
  } finally {
    if (originalBitmap) Object.defineProperty(globalThis, 'createImageBitmap', originalBitmap)
    else delete (globalThis as { createImageBitmap?: unknown }).createImageBitmap
    if (originalImage) Object.defineProperty(globalThis, 'Image', originalImage)
    else delete (globalThis as { Image?: unknown }).Image
    if (originalDocument) Object.defineProperty(globalThis, 'document', originalDocument)
    else delete (globalThis as { document?: unknown }).document
  }
})
