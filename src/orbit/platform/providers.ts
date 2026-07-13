import { geographicDistanceM, polylineDistanceM, simplifyTrack } from '../domain/geo.ts'
import { explainRoute, scoreRouteCandidate } from '../domain/missions.ts'
import type { Geocoder, GeocoderResult, RouteProvider } from '../domain/ports.ts'
import type { GeoPoint, RouteCandidate, RouteRequest, RouteTerrain } from '../domain/types.ts'
import { supabase } from '../../lib/supabase.ts'

const BROUTER_URL = 'https://brouter.de/brouter'
const NOMINATIM_URL = 'https://nominatim.openstreetmap.org/search'

function destinationPoint(start: GeoPoint, distanceM: number, bearingDegrees: number): GeoPoint {
  const earth = 6_371_000
  const angular = distanceM / earth
  const bearing = bearingDegrees * Math.PI / 180
  const lat1 = start.lat * Math.PI / 180
  const lng1 = start.lng * Math.PI / 180
  const lat2 = Math.asin(Math.sin(lat1) * Math.cos(angular) + Math.cos(lat1) * Math.sin(angular) * Math.cos(bearing))
  const lng2 = lng1 + Math.atan2(Math.sin(bearing) * Math.sin(angular) * Math.cos(lat1), Math.cos(angular) - Math.sin(lat1) * Math.sin(lat2))
  return { lat: lat2 * 180 / Math.PI, lng: lng2 * 180 / Math.PI }
}

function waypointSets(request: RouteRequest): GeoPoint[][] {
  if (request.waypoints && request.waypoints.length > 0) {
    return [[request.start, ...request.waypoints, ...(request.destination ? [request.destination] : []), ...(request.shape === 'loop' ? [request.start] : [])]]
  }
  if (request.destination) return request.shape === 'out_back'
    ? [[request.start, request.destination, request.start]]
    : [[request.start, request.destination]]
  const targetM = request.distance_km * 1000
  const terrainBias = request.terrain === 'hilly' ? 1.08 : request.terrain === 'flat' ? 0.96 : 1
  if (request.shape === 'point_to_point') {
    return [25, 145, 265].map((bearing) => [request.start, destinationPoint(request.start, targetM * terrainBias * 0.72, bearing)])
  }
  if (request.shape === 'out_back') {
    return [20, 140, 260].map((bearing) => {
      const far = destinationPoint(request.start, targetM * 0.5, bearing)
      return [request.start, far, request.start]
    })
  }
  return [15, 135, 255].map((bearing) => {
    const radius = targetM / 3.7
    const a = destinationPoint(request.start, radius, bearing)
    const b = destinationPoint(request.start, radius, bearing + 105)
    return [request.start, a, b, request.start]
  })
}

function navigationComplexity(points: GeoPoint[]): 'low' | 'moderate' | 'high' {
  if (points.length < 15) return 'low'
  let turns = 0
  for (let index = 2; index < points.length; index += 1) {
    const a = points[index - 2]
    const b = points[index - 1]
    const c = points[index]
    const ab = Math.atan2(b.lat - a.lat, b.lng - a.lng)
    const bc = Math.atan2(c.lat - b.lat, c.lng - b.lng)
    let delta = Math.abs(ab - bc)
    if (delta > Math.PI) delta = Math.PI * 2 - delta
    if (delta > 0.55 && geographicDistanceM(a, b) > 15) turns += 1
  }
  return turns <= 6 ? 'low' : turns <= 14 ? 'moderate' : 'high'
}

function inferredTerrain(elevationGainM: number | null, distanceM: number): RouteTerrain {
  if (elevationGainM == null || distanceM <= 0) return 'rolling'
  const gainPerKm = elevationGainM / (distanceM / 1000)
  return gainPerKm < 10 ? 'flat' : gainPerKm < 24 ? 'rolling' : 'hilly'
}

interface BRouterGeoJson {
  features?: Array<{
    geometry?: { coordinates?: number[][] }
    properties?: Record<string, unknown>
  }>
}

async function directBrouter(points: GeoPoint[], _surface: RouteRequest['surface']): Promise<{ points: GeoPoint[]; elevationGainM: number | null }> {
  // BRouter's public instance does not expose a dedicated running profile.
  // `trekking` is the defensible pedestrian-compatible fallback. A bicycle
  // profile could silently route runners onto inappropriate roads.
  const profile = 'trekking'
  const params = new URLSearchParams({
    lonlats: points.map((point) => `${point.lng.toFixed(6)},${point.lat.toFixed(6)}`).join('|'),
    profile,
    alternativeidx: '0',
    format: 'geojson',
  })
  const response = await fetch(`${BROUTER_URL}?${params.toString()}`, { headers: { Accept: 'application/geo+json' } })
  if (!response.ok) throw new Error(`Routing unavailable (${response.status})`)
  const data = await response.json() as BRouterGeoJson
  const feature = data.features?.[0]
  const coordinates = feature?.geometry?.coordinates ?? []
  const routePoints = coordinates
    .map((coordinate) => ({ lng: Number(coordinate[0]), lat: Number(coordinate[1]), elevation_m: coordinate[2] == null ? null : Number(coordinate[2]) }))
    .filter((point) => Number.isFinite(point.lat) && Number.isFinite(point.lng))
  if (routePoints.length < 2) throw new Error('Routing provider returned no usable path.')
  const ascend = Number(feature?.properties?.['filtered ascend'] ?? feature?.properties?.ascend)
  return { points: simplifyTrack(routePoints, 5), elevationGainM: Number.isFinite(ascend) ? Math.round(ascend) : null }
}

async function edgeRequest(operation: 'route' | 'geocode', payload: unknown): Promise<unknown> {
  if (!supabase) throw new Error('Edge Function is unavailable in local mode.')
  const { data, error } = await supabase.functions.invoke('orbit-geo', { body: { operation, payload } })
  if (error) throw error
  return data
}

export class OpenOrbitRouteProvider implements RouteProvider {
  readonly name = 'BRouter and OpenStreetMap'

  async generate(request: RouteRequest): Promise<RouteCandidate[]> {
    const sets = waypointSets(request)
    const candidates = await Promise.allSettled(sets.map(async (waypoints, index) => {
      const result = supabase
        ? await edgeRequest('route', { waypoints, surface: request.surface }) as { points: GeoPoint[]; elevationGainM: number | null }
        : await directBrouter(waypoints, request.surface)
      const distanceM = Math.round(polylineDistanceM(result.points))
      const terrain = inferredTerrain(result.elevationGainM, distanceM)
      const now = new Date().toISOString()
      const candidate: RouteCandidate = {
        id: crypto.randomUUID(), user_id: '', client_idempotency_key: crypto.randomUUID(),
        name: `Orbit option ${index + 1}`, note: '', points: result.points, distance_m: distanceM,
        elevation_gain_m: result.elevationGainM, surface: request.surface, terrain, shape: request.shape,
        navigation_complexity: navigationComplexity(result.points), familiarity_pct: request.familiarity === 'exploratory' ? 20 : request.familiarity === 'familiar' ? 80 : 50,
        favourite: false, rating: null, mission_tags: [request.mission], preferred_sections: [], avoided_sections: request.avoid_notes,
        provider: this.name, attribution: 'Route data © OpenStreetMap contributors · routing by BRouter',
        created_at: now, updated_at: now, sync_state: 'local', score: 0, explanation: '',
        estimated_duration_min: Math.max(1, Math.round(distanceM / 1000 * 6.4)),
      }
      candidate.score = scoreRouteCandidate(candidate, request)
      candidate.explanation = explainRoute(candidate, request.mission)
      return candidate
    }))
    const successful = candidates
      .filter((result): result is PromiseFulfilledResult<RouteCandidate> => result.status === 'fulfilled')
      .map((result) => result.value)
      .sort((a, b) => b.score - a.score)
    if (successful.length === 0) throw new Error('Automatic routing is unavailable. Draw a route manually, import GPX or begin a free run.')
    return successful
  }
}

export class OpenStreetMapGeocoder implements Geocoder {
  readonly name = 'Nominatim and OpenStreetMap'

  async search(query: string): Promise<GeocoderResult[]> {
    if (query.trim().length < 3) return []
    if (supabase) {
      const data = await edgeRequest('geocode', { query }) as Array<{ display_name: string; lat: string; lon: string }>
      return data.slice(0, 5).map((item) => ({ label: item.display_name, point: { lat: Number(item.lat), lng: Number(item.lon) } }))
    }
    const params = new URLSearchParams({ q: query, format: 'jsonv2', limit: '5' })
    const response = await fetch(`${NOMINATIM_URL}?${params.toString()}`, { headers: { Accept: 'application/json' } })
    if (!response.ok) throw new Error('Geocoding is unavailable. Use current location or draw directly on the map.')
    const data = await response.json() as Array<{ display_name: string; lat: string; lon: string }>
    return data.map((item) => ({ label: item.display_name, point: { lat: Number(item.lat), lng: Number(item.lon) } }))
  }
}
