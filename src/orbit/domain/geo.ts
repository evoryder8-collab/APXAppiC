import { GPS_CONFIG } from './config.ts'
import type { GeoPoint, PauseInterval, RunMetrics, RunSplit, TrackSample } from './types.ts'

const EARTH_RADIUS_M = 6_371_000

function radians(value: number): number {
  return value * Math.PI / 180
}

export function geographicDistanceM(a: GeoPoint, b: GeoPoint): number {
  const lat1 = radians(a.lat)
  const lat2 = radians(b.lat)
  const dLat = lat2 - lat1
  const dLng = radians(b.lng - a.lng)
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)))
}

export function polylineDistanceM(points: GeoPoint[]): number {
  let total = 0
  for (let index = 1; index < points.length; index += 1) total += geographicDistanceM(points[index - 1], points[index])
  return total
}

export interface FilteredTrack {
  accepted: TrackSample[]
  rejected: TrackSample[]
}

export function filterGpsSamples(samples: TrackSample[]): FilteredTrack {
  const accepted: TrackSample[] = []
  const rejected: TrackSample[] = []
  for (const sample of [...samples].sort((a, b) => a.recorded_at - b.recorded_at)) {
    if (!Number.isFinite(sample.lat) || !Number.isFinite(sample.lng) || sample.accuracy_m > GPS_CONFIG.maximumAccuracyM) {
      rejected.push(sample)
      continue
    }
    const previous = accepted.at(-1)
    if (!previous) {
      accepted.push(sample)
      continue
    }
    const elapsedS = (sample.recorded_at - previous.recorded_at) / 1000
    if (elapsedS <= 0) {
      rejected.push(sample)
      continue
    }
    const distanceM = geographicDistanceM(previous, sample)
    const speedMps = distanceM / elapsedS
    const impossibleJump = distanceM > GPS_CONFIG.jumpDistanceM && elapsedS < GPS_CONFIG.jumpWindowS
    if (speedMps > GPS_CONFIG.impossibleSpeedMps || impossibleJump) {
      rejected.push(sample)
      continue
    }
    accepted.push(sample)
  }
  return { accepted, rejected }
}

export function pauseDurationS(pauses: PauseInterval[], through: number): number {
  return pauses.reduce((total, pause) => {
    const end = pause.ended_at ?? through
    return total + Math.max(0, end - pause.started_at) / 1000
  }, 0)
}

export function movingTimeS(samples: TrackSample[]): number {
  let moving = 0
  for (let index = 1; index < samples.length; index += 1) {
    const previous = samples[index - 1]
    const current = samples[index]
    const elapsedS = (current.recorded_at - previous.recorded_at) / 1000
    if (elapsedS <= 0 || elapsedS > GPS_CONFIG.maximumMovingGapS) continue
    const speed = geographicDistanceM(previous, current) / elapsedS
    if (speed >= GPS_CONFIG.movingSpeedMps && speed <= GPS_CONFIG.impossibleSpeedMps) moving += elapsedS
  }
  return moving
}

export function smoothElevations(samples: TrackSample[], radius = 2): Array<number | null> {
  return samples.map((sample, index) => {
    if (sample.elevation_m == null || !Number.isFinite(sample.elevation_m)) return null
    const values = samples
      .slice(Math.max(0, index - radius), index + radius + 1)
      .map((point) => point.elevation_m)
      .filter((value): value is number => value != null && Number.isFinite(value))
    return values.length > 0 ? values.reduce((sum, value) => sum + value, 0) / values.length : null
  })
}

export function elevationGainM(samples: TrackSample[]): number | null {
  const elevations = smoothElevations(samples)
  if (elevations.filter((value) => value != null).length < 3) return null
  let gain = 0
  let anchor: number | null = null
  for (const elevation of elevations) {
    if (elevation == null) continue
    if (anchor == null) {
      anchor = elevation
      continue
    }
    const delta = elevation - anchor
    if (Math.abs(delta) < GPS_CONFIG.elevationNoiseM) continue
    if (delta > 0) gain += delta
    anchor = elevation
  }
  return Math.round(gain)
}

function average(values: Array<number | null | undefined>): number | null {
  const numbers = values.filter((value): value is number => value != null && Number.isFinite(value))
  return numbers.length > 0 ? numbers.reduce((sum, value) => sum + value, 0) / numbers.length : null
}

function interpolateNumber(a: number, b: number, ratio: number): number {
  return a + (b - a) * ratio
}

export function generateKilometreSplits(samples: TrackSample[]): RunSplit[] {
  if (samples.length < 2) return []
  const splits: RunSplit[] = []
  let cumulativeM = 0
  let splitStartTime = samples[0].recorded_at
  let splitStartElevation = samples[0].elevation_m ?? null
  let nextBoundaryM = 1000
  let splitHeartRates: number[] = []

  for (let index = 1; index < samples.length; index += 1) {
    const previous = samples[index - 1]
    const current = samples[index]
    const segmentM = geographicDistanceM(previous, current)
    if (segmentM <= 0) continue
    if (current.heart_rate_bpm != null) splitHeartRates.push(current.heart_rate_bpm)

    while (cumulativeM + segmentM >= nextBoundaryM) {
      const ratio = (nextBoundaryM - cumulativeM) / segmentM
      const boundaryTime = interpolateNumber(previous.recorded_at, current.recorded_at, ratio)
      const boundaryElevation = previous.elevation_m != null && current.elevation_m != null
        ? interpolateNumber(previous.elevation_m, current.elevation_m, ratio)
        : null
      const durationS = Math.max(1, (boundaryTime - splitStartTime) / 1000)
      splits.push({
        index: splits.length + 1,
        distance_m: 1000,
        duration_s: Math.round(durationS),
        pace_sec_km: Math.round(durationS),
        elevation_delta_m: boundaryElevation != null && splitStartElevation != null
          ? Math.round(boundaryElevation - splitStartElevation)
          : null,
        heart_rate_avg: average(splitHeartRates) == null ? null : Math.round(average(splitHeartRates)!),
      })
      splitStartTime = boundaryTime
      splitStartElevation = boundaryElevation
      splitHeartRates = []
      nextBoundaryM += 1000
    }
    cumulativeM += segmentM
  }

  const remainderM = cumulativeM - splits.length * 1000
  const last = samples.at(-1)
  if (last && remainderM >= 200) {
    const durationS = Math.max(1, (last.recorded_at - splitStartTime) / 1000)
    const endElevation = last.elevation_m ?? null
    splits.push({
      index: splits.length + 1,
      distance_m: Math.round(remainderM),
      duration_s: Math.round(durationS),
      pace_sec_km: Math.round(durationS / (remainderM / 1000)),
      elevation_delta_m: endElevation != null && splitStartElevation != null ? Math.round(endElevation - splitStartElevation) : null,
      heart_rate_avg: average(splitHeartRates) == null ? null : Math.round(average(splitHeartRates)!),
    })
  }
  return splits
}

export function calculateRunMetrics(
  rawSamples: TrackSample[],
  pauses: PauseInterval[],
  weightKg?: number | null,
): RunMetrics {
  const { accepted, rejected } = filterGpsSamples(rawSamples)
  const first = accepted[0]
  const last = accepted.at(-1)
  const distanceM = Math.round(polylineDistanceM(accepted))
  const elapsedS = first && last
    ? Math.max(0, Math.round((last.recorded_at - first.recorded_at) / 1000 - pauseDurationS(pauses, last.recorded_at)))
    : 0
  const movingS = Math.round(movingTimeS(accepted))
  const denominatorS = movingS > 0 ? movingS : elapsedS
  const avgPace = distanceM >= 100 && denominatorS > 0 ? Math.round(denominatorS / (distanceM / 1000)) : null
  const splits = generateKilometreSplits(accepted)
  const fullSplitPaces = splits.filter((split) => split.distance_m >= 900).map((split) => split.pace_sec_km)
  const bestPace = fullSplitPaces.length > 0 ? Math.min(...fullSplitPaces) : avgPace
  const averageAccuracy = average(accepted.map((sample) => sample.accuracy_m))
  const gpsConfidence = accepted.length < 3 || averageAccuracy == null || averageAccuracy > GPS_CONFIG.weakAccuracyM
    ? 'low'
    : rejected.length > accepted.length * 0.15 || averageAccuracy > 20
      ? 'moderate'
      : 'high'
  return {
    distance_m: distanceM,
    elapsed_s: elapsedS,
    moving_s: movingS,
    avg_pace_sec_km: avgPace,
    best_pace_sec_km: bestPace,
    elevation_gain_m: elevationGainM(accepted),
    heart_rate_avg: average(accepted.map((sample) => sample.heart_rate_bpm)) == null
      ? null
      : Math.round(average(accepted.map((sample) => sample.heart_rate_bpm))!),
    cadence_avg: average(accepted.map((sample) => sample.cadence_spm)) == null
      ? null
      : Math.round(average(accepted.map((sample) => sample.cadence_spm))!),
    calories_kcal: weightKg && distanceM > 0 ? Math.round(weightKg * distanceM / 1000) : null,
    splits,
    rejected_samples: rejected.length,
    gps_confidence: gpsConfidence,
  }
}

interface XYPoint { x: number; y: number }

function toLocal(point: GeoPoint, origin: GeoPoint): XYPoint {
  const latScale = Math.PI * EARTH_RADIUS_M / 180
  const lngScale = latScale * Math.cos(radians(origin.lat))
  return { x: (point.lng - origin.lng) * lngScale, y: (point.lat - origin.lat) * latScale }
}

function pointSegmentDistanceM(point: GeoPoint, start: GeoPoint, end: GeoPoint): number {
  const p = toLocal(point, start)
  const b = toLocal(end, start)
  const lengthSquared = b.x ** 2 + b.y ** 2
  if (lengthSquared === 0) return Math.hypot(p.x, p.y)
  const ratio = Math.max(0, Math.min(1, (p.x * b.x + p.y * b.y) / lengthSquared))
  return Math.hypot(p.x - b.x * ratio, p.y - b.y * ratio)
}

export function routeDeviationM(point: GeoPoint, route: GeoPoint[]): number | null {
  if (route.length < 2) return null
  let minimum = Number.POSITIVE_INFINITY
  for (let index = 1; index < route.length; index += 1) {
    minimum = Math.min(minimum, pointSegmentDistanceM(point, route[index - 1], route[index]))
  }
  return Number.isFinite(minimum) ? minimum : null
}

export interface RouteNavigationCue {
  instruction: string
  remaining_m: number
  route_index: number
}

export function routeNavigationCue(point: GeoPoint, route: GeoPoint[]): RouteNavigationCue | null {
  if (route.length < 2) return null
  let nearestIndex = 0
  let nearestDistance = Number.POSITIVE_INFINITY
  for (let index = 0; index < route.length; index += 1) {
    const distance = geographicDistanceM(point, route[index])
    if (distance < nearestDistance) {
      nearestDistance = distance
      nearestIndex = index
    }
  }
  const lookAhead = Math.min(route.length - 1, nearestIndex + Math.max(1, Math.floor(route.length / 40)))
  const target = route[lookAhead]
  const lat1 = radians(route[nearestIndex].lat)
  const lat2 = radians(target.lat)
  const deltaLng = radians(target.lng - route[nearestIndex].lng)
  const bearing = (Math.atan2(Math.sin(deltaLng) * Math.cos(lat2), Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(deltaLng)) * 180 / Math.PI + 360) % 360
  const directions = ['north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest']
  const direction = directions[Math.round(bearing / 45) % 8]
  const remainingM = Math.round(polylineDistanceM(route.slice(nearestIndex)))
  return { instruction: remainingM < 60 ? 'Approaching the planned finish.' : `Continue ${direction} on the planned route.`, remaining_m: remainingM, route_index: nearestIndex }
}

function perpendicularDistance(point: GeoPoint, start: GeoPoint, end: GeoPoint): number {
  return pointSegmentDistanceM(point, start, end)
}

export function simplifyTrack<T extends GeoPoint>(points: T[], toleranceM = 8): T[] {
  if (points.length <= 2) return [...points]
  let maxDistance = 0
  let maxIndex = 0
  for (let index = 1; index < points.length - 1; index += 1) {
    const distance = perpendicularDistance(points[index], points[0], points.at(-1)!)
    if (distance > maxDistance) {
      maxDistance = distance
      maxIndex = index
    }
  }
  if (maxDistance <= toleranceM) return [points[0], points.at(-1)!]
  const left = simplifyTrack(points.slice(0, maxIndex + 1), toleranceM)
  const right = simplifyTrack(points.slice(maxIndex), toleranceM)
  return [...left.slice(0, -1), ...right]
}

export function trimRoutePrivacy<T extends GeoPoint>(points: T[], trimM: number): T[] {
  if (trimM <= 0 || points.length < 3) return [...points]
  let fromStart = 0
  let startIndex = 0
  for (let index = 1; index < points.length; index += 1) {
    fromStart += geographicDistanceM(points[index - 1], points[index])
    if (fromStart >= trimM) {
      startIndex = index
      break
    }
  }
  let fromEnd = 0
  let endIndex = points.length - 1
  for (let index = points.length - 1; index > 0; index -= 1) {
    fromEnd += geographicDistanceM(points[index], points[index - 1])
    if (fromEnd >= trimM) {
      endIndex = index - 1
      break
    }
  }
  return startIndex < endIndex ? points.slice(startIndex, endIndex + 1) : []
}

export function pointAtDistance(points: TrackSample[], targetM: number): TrackSample | null {
  if (points.length === 0) return null
  if (targetM <= 0) return points[0]
  let cumulative = 0
  for (let index = 1; index < points.length; index += 1) {
    cumulative += geographicDistanceM(points[index - 1], points[index])
    if (cumulative >= targetM) return points[index]
  }
  return points.at(-1) ?? null
}
