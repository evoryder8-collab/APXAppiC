import { geographicDistanceM, polylineDistanceM, routeDeviationM } from './geo.ts'
import type { GeoPoint, RouteShape } from './types.ts'

export interface RoutePreviewGeometry {
  path: string
  start: { x: number; y: number }
  finish: { x: number; y: number }
  closed: boolean
  pointCount: number
}

export function cleanRoutePoints(points: GeoPoint[]): GeoPoint[] {
  const clean: GeoPoint[] = []
  for (const point of points) {
    if (!Number.isFinite(point.lat) || !Number.isFinite(point.lng)) continue
    if (point.lat < -90 || point.lat > 90 || point.lng < -180 || point.lng > 180) continue
    const previous = clean.at(-1)
    if (previous && geographicDistanceM(previous, point) < 1) continue
    clean.push(point)
  }
  return clean
}

export function routeGeometryKey(points: GeoPoint[]): string {
  const clean = cleanRoutePoints(points)
  if (clean.length === 0) return 'empty'
  const stride = Math.max(1, Math.floor(clean.length / 8))
  const sampled = clean.filter((_, index) => index % stride === 0)
  if (sampled.at(-1) !== clean.at(-1)) sampled.push(clean.at(-1)!)
  return `${clean.length}:${sampled.map((point) => `${point.lat.toFixed(4)},${point.lng.toFixed(4)}`).join('|')}`
}

export function inferRouteShape(points: GeoPoint[]): RouteShape {
  const clean = cleanRoutePoints(points)
  if (clean.length < 2) return 'point_to_point'
  const totalM = polylineDistanceM(clean)
  const closureM = geographicDistanceM(clean[0], clean.at(-1)!)
  const closureThresholdM = Math.min(120, Math.max(35, totalM * 0.06))
  if (closureM > closureThresholdM) return 'point_to_point'

  if (clean.length >= 6) {
    const midpoint = Math.ceil(clean.length / 2)
    const outbound = clean.slice(0, midpoint)
    const returning = clean.slice(midpoint)
    const overlap = returning.filter((point) => (routeDeviationM(point, outbound) ?? Infinity) <= 35).length
    if (returning.length > 0 && overlap / returning.length >= 0.6) return 'out_back'
  }
  return 'loop'
}

export function inferNavigationComplexity(points: GeoPoint[]): 'low' | 'moderate' | 'high' {
  const clean = cleanRoutePoints(points)
  if (clean.length < 4) return 'low'
  let significantTurns = 0
  for (let index = 1; index < clean.length - 1; index += 1) {
    const before = Math.atan2(clean[index].lat - clean[index - 1].lat, clean[index].lng - clean[index - 1].lng)
    const after = Math.atan2(clean[index + 1].lat - clean[index].lat, clean[index + 1].lng - clean[index].lng)
    const delta = Math.abs(Math.atan2(Math.sin(after - before), Math.cos(after - before))) * 180 / Math.PI
    if (delta >= 35) significantTurns += 1
  }
  const distanceKm = Math.max(0.5, polylineDistanceM(clean) / 1000)
  const turnsPerKm = significantTurns / distanceKm
  if (significantTurns <= 2 || turnsPerKm < 1.4) return 'low'
  if (significantTurns <= 7 && turnsPerKm < 4.5) return 'moderate'
  return 'high'
}

export function routePreviewGeometry(
  points: GeoPoint[],
  width = 320,
  height = 150,
  padding = 18,
): RoutePreviewGeometry | null {
  const clean = cleanRoutePoints(points)
  if (clean.length < 2) return null
  const averageLat = clean.reduce((sum, point) => sum + point.lat, 0) / clean.length
  const longitudeScale = Math.max(0.15, Math.cos(averageLat * Math.PI / 180))
  const projected = clean.map((point) => ({ x: point.lng * longitudeScale, y: -point.lat }))
  const xs = projected.map((point) => point.x)
  const ys = projected.map((point) => point.y)
  const minX = Math.min(...xs)
  const maxX = Math.max(...xs)
  const minY = Math.min(...ys)
  const maxY = Math.max(...ys)
  const spanX = Math.max(maxX - minX, 1e-8)
  const spanY = Math.max(maxY - minY, 1e-8)
  const scale = Math.min((width - padding * 2) / spanX, (height - padding * 2) / spanY)
  const drawingWidth = spanX * scale
  const drawingHeight = spanY * scale
  const offsetX = (width - drawingWidth) / 2
  const offsetY = (height - drawingHeight) / 2
  const fitted = projected.map((point) => ({
    x: offsetX + (point.x - minX) * scale,
    y: offsetY + (point.y - minY) * scale,
  }))
  const path = fitted.map((point, index) => `${index === 0 ? 'M' : 'L'} ${point.x.toFixed(2)} ${point.y.toFixed(2)}`).join(' ')
  return {
    path,
    start: fitted[0],
    finish: fitted.at(-1)!,
    closed: inferRouteShape(clean) !== 'point_to_point',
    pointCount: clean.length,
  }
}
