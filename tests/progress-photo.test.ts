import assert from 'node:assert/strict'
import test from 'node:test'
import {
  comparisonAspectRatio,
  coverCrop,
  daysBetweenPhotos,
  fitWithin,
  mergePhotoUploadsIdempotently,
  normalizeCrop,
  normalizeComparisonView,
  preferSamePose,
  progressStoragePaths,
  snapshotForProgressDate,
  updateComparisonViews,
  zoomComparisonView,
  type ProgressPhoto,
} from '../src/lib/progressPhoto.ts'
import type { RpgSnapshot } from '../src/lib/types.ts'

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
