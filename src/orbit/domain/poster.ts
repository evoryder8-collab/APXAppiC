import { simplifyTrack, trimRoutePrivacy } from './geo.ts'
import type { OrbitRun, PosterStyle, TrackSample } from './types.ts'

export interface PosterMetadata {
  run_id: string
  style: PosterStyle
  mission: string
  distance_km: number
  moving_time_s: number
  pace_sec_km: number | null
  elevation_gain_m: number | null
  heart_rate_avg: number | null
  date: string
  persona_name: string
  privacy_trim_m: number
  visible_points: TrackSample[]
}

export function posterMetadata(
  run: OrbitRun,
  style: PosterStyle,
  personaName: string,
  privacyTrimM: number,
  includeHeartRate: boolean,
): PosterMetadata {
  return {
    run_id: run.id,
    style,
    mission: run.mission,
    distance_km: Math.round(run.metrics.distance_m / 10) / 100,
    moving_time_s: run.metrics.moving_s,
    pace_sec_km: run.metrics.avg_pace_sec_km,
    elevation_gain_m: run.metrics.elevation_gain_m,
    heart_rate_avg: includeHeartRate ? run.metrics.heart_rate_avg : null,
    date: run.local_date,
    persona_name: personaName,
    privacy_trim_m: privacyTrimM,
    visible_points: simplifyTrack(trimRoutePrivacy(run.samples, privacyTrimM), 10),
  }
}

function routeCoordinates(points: TrackSample[], width: number, height: number, padding: number): Array<{ x: number; y: number }> {
  if (points.length < 2) return []
  const minLat = Math.min(...points.map((point) => point.lat))
  const maxLat = Math.max(...points.map((point) => point.lat))
  const minLng = Math.min(...points.map((point) => point.lng))
  const maxLng = Math.max(...points.map((point) => point.lng))
  const latRange = maxLat - minLat || 0.001
  const lngRange = maxLng - minLng || 0.001
  return points.map((point) => {
    const x = padding + ((point.lng - minLng) / lngRange) * (width - padding * 2)
    const y = height - padding - ((point.lat - minLat) / latRange) * (height - padding * 2)
    return { x, y }
  })
}

function pathFor(points: TrackSample[], width: number, height: number, padding: number): string {
  return routeCoordinates(points, width, height, padding).map((point, index) => `${index === 0 ? 'M' : 'L'}${point.x.toFixed(1)} ${point.y.toFixed(1)}`).join(' ')
}

function elevationCoordinates(points: TrackSample[], width: number, height: number, padding: number): Array<{ x: number; y: number }> {
  const elevations = points.map((point) => point.elevation_m).filter((value): value is number => value != null && Number.isFinite(value))
  if (elevations.length < 2) return []
  const low = Math.min(...elevations)
  const range = Math.max(1, Math.max(...elevations) - low)
  return elevations.map((elevation, index) => {
    const x = padding + index / Math.max(1, elevations.length - 1) * (width - padding * 2)
    const y = height - padding - (elevation - low) / range * (height - padding * 2)
    return { x, y }
  })
}

function elevationPath(points: TrackSample[], width: number, height: number, padding: number): string {
  return elevationCoordinates(points, width, height, padding).map((point, index) => `${index === 0 ? 'M' : 'L'}${point.x.toFixed(1)} ${point.y.toFixed(1)}`).join(' ')
}

function paceLabel(seconds: number | null): string {
  if (seconds == null) return 'Not recorded'
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')} /km`
}

function escapeSvgText(value: string): string {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;')
}

export function posterSvg(metadata: PosterMetadata, note = ''): string {
  const width = 1080
  const height = 1350
  const routePath = pathFor(metadata.visible_points, 880, 640, 55)
  const displayPath = metadata.style === 'elevation' ? elevationPath(metadata.visible_points, 880, 640, 55) || routePath : routePath
  const routeMarkers = metadata.style === 'elevation'
    ? elevationCoordinates(metadata.visible_points, 880, 640, 55)
    : routeCoordinates(metadata.visible_points, 880, 640, 55)
  const start = routeMarkers[0] ?? { x: 55, y: 585 }
  const finish = routeMarkers.at(-1) ?? { x: 825, y: 55 }
  const styleTone = metadata.style === 'constellation' ? '#7dd3fc' : metadata.style === 'elevation' ? '#fbbf24' : '#e0f2fe'
  const stars = metadata.style === 'constellation'
    ? metadata.visible_points.filter((_, index) => index % Math.max(1, Math.floor(metadata.visible_points.length / 18)) === 0).map((_, index) => `<circle cx="${120 + (index * 47) % 820}" cy="${235 + (index * 83) % 550}" r="${index % 3 === 0 ? 4 : 2}" fill="#fff" opacity="0.72"/>`).join('')
    : ''
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#050a16"/><stop offset="0.52" stop-color="#10152d"/><stop offset="1" stop-color="#071827"/></linearGradient><filter id="glow"><feGaussianBlur stdDeviation="8" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
  <rect width="1080" height="1350" fill="url(#bg)"/><circle cx="160" cy="120" r="210" fill="#38bdf8" opacity="0.08"/><circle cx="940" cy="1210" r="330" fill="#8b5cf6" opacity="0.09"/>${stars}
  <text x="80" y="105" fill="#7dd3fc" font-family="monospace" font-size="24" letter-spacing="7">APEX ORBIT</text>
  <text x="80" y="168" fill="#fff" font-family="system-ui,sans-serif" font-size="56" font-weight="700">${escapeSvgText(metadata.mission.replaceAll('_', ' ').toUpperCase())}</text>
  <g transform="translate(100 230)"><path d="${displayPath}" fill="none" stroke="${styleTone}" stroke-width="${metadata.style === 'minimal' ? 6 : 9}" stroke-linecap="round" stroke-linejoin="round" filter="url(#glow)"/><circle cx="${start.x.toFixed(1)}" cy="${start.y.toFixed(1)}" r="11" fill="#34d399"/><circle cx="${finish.x.toFixed(1)}" cy="${finish.y.toFixed(1)}" r="11" fill="#fbbf24"/></g>
  <line x1="80" x2="1000" y1="930" y2="930" stroke="#fff" opacity="0.14"/>
  <text x="80" y="1005" fill="#fff" font-family="system-ui,sans-serif" font-size="68" font-weight="700">${metadata.distance_km.toFixed(2)} km</text>
  <text x="80" y="1060" fill="#9fb6c8" font-family="monospace" font-size="26">PACE ${paceLabel(metadata.pace_sec_km)} · ${metadata.date}</text>
  <text x="80" y="1100" fill="#668096" font-family="monospace" font-size="20">${metadata.elevation_gain_m == null ? 'ELEVATION NOT RECORDED' : `ELEVATION ${metadata.elevation_gain_m} M`}${metadata.heart_rate_avg == null ? '' : ` · HEART RATE ${metadata.heart_rate_avg} BPM`}</text>
  <text x="80" y="1160" fill="#dbeafe" font-family="system-ui,sans-serif" font-size="30">${escapeSvgText(metadata.persona_name)}</text>
  <text x="80" y="1215" fill="#9fb6c8" font-family="system-ui,sans-serif" font-size="25">${escapeSvgText(note.slice(0, 90))}</text>
  <text x="80" y="1285" fill="#668096" font-family="monospace" font-size="18">START AND FINISH TRIMMED ${metadata.privacy_trim_m} M · PRIVATE BY DEFAULT</text>
  </svg>`
}
