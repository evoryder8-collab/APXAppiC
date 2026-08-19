/*
 * Golden parity fixtures for ProgressPhotoEngine and ProgressComparison.
 *
 *   node --experimental-strip-types ios/APEXNative/Tools/generate-progress-fixtures.mts
 */
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  comparisonAspectRatio, coverCrop, daysBetweenPhotos, fitWithin, normalizeComparisonView,
  normalizeCrop, preferSamePose, progressCaptureAspectRatio, progressFramingMode,
  progressStoragePaths, snapshotForProgressDate, updateComparisonViews, zoomComparisonView,
  type ProgressPhoto,
} from '../../../src/lib/progressPhoto.ts'
import { progressStrengthComparison, progressPosterContent, resolveProgressExportMode } from '../../../src/lib/progressComparison.ts'
import type { AppData } from '../../../src/lib/types.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
const OUT = join(HERE, '..', 'APEXTests', 'Fixtures', 'progress-parity.json')

const USER = '99999999-0000-4000-8000-000000000001'
const photo = (id: string, date: string, pose: string, ratio: number, key: string): ProgressPhoto => ({
  id, user_id: USER, local_date: date, captured_at: `${date}T09:00:00.000Z`,
  pose, storage_path: '', thumbnail_path: '', width: 1080, height: 1620,
  aspect_ratio: ratio, crop_x: 0.5, crop_y: 0.5, crop_scale: 1,
  reference_photo_id: null, weight_kg: null, note: '',
  client_idempotency_key: key, created_at: '', updated_at: '',
} as unknown as ProgressPhoto)

const photos = [
  photo('44444444-0000-4000-8000-000000000001', '2026-05-04', 'front', 0.667, 'framing:full:a'),
  photo('44444444-0000-4000-8000-000000000002', '2026-06-15', 'side', 0.8, 'framing:torso:b'),
  photo('44444444-0000-4000-8000-000000000003', '2026-08-10', 'front', 0.75, 'framing:free:c'),
  photo('44444444-0000-4000-8000-000000000004', '2026-08-17', 'back', 0.667, 'no-framing-prefix'),
]

let seq = 0
const fid = () => { seq += 1; return `33333333-0000-4000-8000-${String(seq).padStart(12, '0')}` }
const sessions: unknown[] = []
const logs: unknown[] = []
function session(date: string, completed = true): string {
  const id = fid()
  sessions.push({ id, user_id: USER, date, completed })
  return id
}
function set(sessionId: string, exerciseId: string | null, name: string, weight: number | null, skipped = false): void {
  logs.push({ id: fid(), session_id: sessionId, exercise_id: exerciseId, exercise_name: name, set_no: 1, weight_kg: weight, reps: 8, skipped })
}
const early = session('2026-05-10')
set(early, 'ex-bench', 'Bench press', 60); set(early, 'ex-bench', 'Bench press', 62.5)
set(early, 'ex-squat', 'Back squat', 90)
set(early, null, 'One-off machine', 40)
const late = session('2026-08-02')
set(late, 'ex-bench', 'Bench press', 70); set(late, 'ex-bench', 'Bench press', 72.5)
set(late, 'ex-squat', 'Back squat', 100)
set(late, 'ex-curl', 'Biceps curl', 15, true)
const outside = session('2026-09-01')
set(outside, 'ex-bench', 'Bench press', 90)
const abandoned = session('2026-06-01', false)
set(abandoned, 'ex-squat', 'Back squat', 200)

const data = { workout_sessions: sessions, workout_logs: logs } as unknown as AppData
const snapshots = [
  { date: '2026-05-01', level: 4 }, { date: '2026-06-20', level: 6 }, { date: '2026-09-01', level: 9 },
] as never[]

mkdirSync(dirname(OUT), { recursive: true })
writeFileSync(OUT, `${JSON.stringify({
  photos: photos.map((value) => ({
    id: value.id, local_date: value.local_date, pose: value.pose,
    aspect_ratio: value.aspect_ratio, client_idempotency_key: value.client_idempotency_key,
  })),
  fit_within: [
    { w: 4000, h: 3000, maxW: 1600, maxH: 1600 },
    { w: 800, h: 600, maxW: 1600, maxH: 1600 },
    { w: 1080, h: 1620, maxW: 1080, maxH: 1080 },
  ].map((c) => ({ ...c, expected: fitWithin(c.w, c.h, c.maxW, c.maxH) })),
  normalize_crop: [
    { x: 0.5, y: 0.5, scale: 1 }, { x: -3, y: 9, scale: 0.2 }, { x: 0.3, y: 0.7, scale: 7 },
  ].map((c) => ({ ...c, expected: normalizeCrop(c.x, c.y, c.scale) })),
  comparison_view: [
    { scale: 1, x: 30, y: -30 }, { scale: 2, x: 100, y: -100 },
    { scale: 3.5, x: 5, y: 5 }, { scale: 9, x: 0, y: 0 },
  ].map((v) => ({ input: v, expected: normalizeComparisonView(v) })),
  zoom: [{ from: { scale: 1, x: 0, y: 0 }, delta: 0.5 }, { from: { scale: 3.9, x: 10, y: 10 }, delta: 1 }]
    .map((z) => ({ ...z, expected: zoomComparisonView(z.from, z.delta) })),
  update_views: [true, false].map((synced) => ({
    synced,
    expected: updateComparisonViews(
      { left: { scale: 1, x: 0, y: 0 }, right: { scale: 1, x: 0, y: 0 } },
      'left', { scale: 2, x: 10, y: -10 }, synced,
    ),
  })),
  cover_crop: [
    { w: 1600, h: 900, ratio: 2 / 3 }, { w: 900, h: 1600, ratio: 2 / 3 }, { w: 1000, h: 1000, ratio: 4 / 5 },
  ].map((c) => ({ ...c, expected: coverCrop(c.w, c.h, c.ratio) })),
  comparison_ratio: [[0, 1], [0, 2], [1, 2]].map(([a, b]) => ({
    a: photos[a].id, b: photos[b].id, expected: comparisonAspectRatio(photos[a], photos[b]),
  })),
  framing: photos.map((value) => ({ id: value.id, expected: progressFramingMode(value) })),
  capture_ratio: (['full', 'torso', 'free'] as const).map((mode) => ({
    mode, preview: 0.75, expected: progressCaptureAspectRatio(mode, 0.75),
  })),
  days_between: [[0, 2], [2, 3], [0, 0]].map(([a, b]) => ({
    a: photos[a].id, b: photos[b].id, expected: daysBetweenPhotos(photos[a], photos[b]),
  })),
  prefer_same_pose: preferSamePose(photos[0], photos).map((value) => value.id),
  snapshot_for_date: ['2026-04-01', '2026-05-04', '2026-08-10', '2026-12-01']
    .map((date) => ({ date, expected: snapshotForProgressDate(date, snapshots)?.date ?? null })),
  storage_paths: progressStoragePaths('99999999-0000-4000-8000-000000000001', '44444444-0000-4000-8000-000000000001'),
  export_mode: [['minimal', resolveProgressExportMode('minimal')], ['detailed', resolveProgressExportMode('detailed')], ['nonsense', resolveProgressExportMode('nonsense')], ['null', resolveProgressExportMode(null)]],
  poster_content: (['detailed', 'minimal'] as const).map((mode) => ({ mode, expected: progressPosterContent(mode) })),
  strength: [
    { first: '2026-05-04', second: '2026-08-10' },
    { first: '2026-08-10', second: '2026-05-04' },
    { first: '2026-05-04', second: '2026-05-20' },
  ].map((range) => ({ ...range, expected: progressStrengthComparison(data, range.first, range.second) })),
  sessions, logs,
}, null, 2)}\n`)
console.log(`wrote ${OUT}`)
