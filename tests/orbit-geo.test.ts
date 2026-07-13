import test from 'node:test'
import assert from 'node:assert/strict'
import { calculateRunMetrics, filterGpsSamples, geographicDistanceM, routeDeviationM, routeNavigationCue, trimRoutePrivacy } from '../src/orbit/domain/geo.ts'
import { exportGpx, importGpx } from '../src/orbit/domain/gpx.ts'
import { posterMetadata, posterSvg } from '../src/orbit/domain/poster.ts'
import type { OrbitRun, TrackSample } from '../src/orbit/domain/types.ts'

function track(count = 180): TrackSample[] {
  return Array.from({ length: count }, (_, index) => ({
    lat: 47.37,
    lng: 8.54 + index * 0.00009,
    elevation_m: 410 + index * 0.08,
    recorded_at: 1_720_000_000_000 + index * 10_000,
    accuracy_m: 5,
    heart_rate_bpm: 135 + Math.floor(index / 40),
    cadence_spm: 168,
  }))
}

function runWith(samples: TrackSample[]): OrbitRun {
  const metrics = calculateRunMetrics(samples, [], 70)
  return {
    id: '00000000-0000-4000-8000-000000000101', user_id: '00000000-0000-4000-8000-000000000001', client_idempotency_key: 'run-1',
    local_date: '2026-07-13', started_at: new Date(samples[0].recorded_at).toISOString(), ended_at: new Date(samples.at(-1)!.recorded_at).toISOString(),
    mission: 'aerobic_base', route_id: null, campaign_session_id: null, shoe_id: null, samples, pauses: [], manual_laps_m: [], metrics,
    check_in: { perceived_effort: 4, legs: 'normal', discomfort: 'none', note: '' }, status: 'completed', sync_state: 'local',
    created_at: '2026-07-13T08:00:00.000Z', updated_at: '2026-07-13T09:00:00.000Z',
  }
}

test('GPS engine rejects impossible jumps but keeps defensible running samples', () => {
  const samples = track()
  samples.splice(30, 0, { ...samples[29], lat: 50, lng: 12, recorded_at: samples[29].recorded_at + 3_000 })
  const filtered = filterGpsSamples(samples)
  assert.equal(filtered.rejected.length, 1)
  assert.equal(filtered.accepted.length, samples.length - 1)
  const metrics = calculateRunMetrics(samples, [], 70)
  assert.ok(metrics.distance_m > 1_000 && metrics.distance_m < 1_500)
  assert.ok(metrics.splits.length >= 1)
  assert.equal(metrics.calories_kcal, Math.round(70 * metrics.distance_m / 1000))
  assert.notEqual(metrics.gps_confidence, 'low')
})

test('pause intervals reduce elapsed time and missing sensor facts remain missing', () => {
  const samples = track(40).map((sample) => ({ ...sample, heart_rate_bpm: null, cadence_spm: null, elevation_m: null }))
  const pause = { started_at: samples[10].recorded_at, ended_at: samples[16].recorded_at }
  const metrics = calculateRunMetrics(samples, [pause], 58)
  assert.equal(metrics.elapsed_s, 330)
  assert.equal(metrics.heart_rate_avg, null)
  assert.equal(metrics.cadence_avg, null)
  assert.equal(metrics.elevation_gain_m, null)
})

test('route deviation and navigation cues are factual and deterministic', () => {
  const route = track(20)
  const onRoute = { lat: route[8].lat, lng: route[8].lng }
  const farAway = { lat: route[8].lat + 0.01, lng: route[8].lng }
  assert.ok((routeDeviationM(onRoute, route) ?? 999) < 2)
  assert.ok((routeDeviationM(farAway, route) ?? 0) > 500)
  const cue = routeNavigationCue(onRoute, route)
  assert.ok(cue)
  assert.match(cue.instruction, /Continue|finish/)
  assert.ok(cue.remaining_m > 0)
})

test('privacy trimming removes both exact ends before poster export', () => {
  const samples = track(160)
  const trimmed = trimRoutePrivacy(samples, 200)
  assert.ok(trimmed.length < samples.length)
  assert.ok(geographicDistanceM(samples[0], trimmed[0]) >= 190)
  assert.ok(geographicDistanceM(samples.at(-1)!, trimmed.at(-1)!) >= 190)
  const run = runWith(samples)
  const metadata = posterMetadata(run, 'constellation', '<Constantine>', 200, true)
  const svg = posterSvg(metadata, '<private note>')
  assert.ok(metadata.visible_points.length > 1)
  assert.doesNotMatch(svg, /<private note>/)
  assert.match(svg, /&lt;private note&gt;/)
  assert.match(svg, /TRIMMED 200 M/)
  assert.match(svg, /cx="55\.0" cy="585\.0" r="11" fill="#34d399"/)
  assert.match(svg, /cx="825\.0" cy="585\.0" r="11" fill="#fbbf24"/)
})

test('GPX import and export preserve usable private route geometry', () => {
  const points = track(6)
  const xml = exportGpx('River & Hill', points)
  assert.match(xml, /River &amp; Hill/)
  const restored = importGpx(xml)
  assert.equal(restored.name, 'River & Hill')
  assert.equal(restored.points.length, points.length)
  assert.ok(Math.abs(restored.points[2].lng - points[2].lng) < 0.000001)
  assert.throws(() => importGpx('<gpx></gpx>'), /No usable route points/)
})
