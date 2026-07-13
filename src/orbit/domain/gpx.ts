import type { GeoPoint } from './types.ts'

function escapeXml(value: string): string {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;')
}

function decodeXml(value: string): string {
  return value.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&apos;', "'").replaceAll('&amp;', '&')
}

export function exportGpx(name: string, points: GeoPoint[]): string {
  const track = points.map((point) => {
    const elevation = point.elevation_m == null ? '' : `<ele>${point.elevation_m.toFixed(1)}</ele>`
    return `<trkpt lat="${point.lat.toFixed(7)}" lon="${point.lng.toFixed(7)}">${elevation}</trkpt>`
  }).join('')
  return `<?xml version="1.0" encoding="UTF-8"?><gpx version="1.1" creator="APEX Orbit" xmlns="http://www.topografix.com/GPX/1/1"><trk><name>${escapeXml(name)}</name><trkseg>${track}</trkseg></trk></gpx>`
}

export function importGpx(xml: string): { name: string; points: GeoPoint[] } {
  const points: GeoPoint[] = []
  const pattern = /<(?:trkpt|rtept)\b[^>]*\blat=["']([^"']+)["'][^>]*\blon=["']([^"']+)["'][^>]*>([\s\S]*?)<\/(?:trkpt|rtept)>/gi
  let match: RegExpExecArray | null
  while ((match = pattern.exec(xml)) != null) {
    const lat = Number(match[1])
    const lng = Number(match[2])
    const elevationMatch = match[3].match(/<ele>([^<]+)<\/ele>/i)
    const elevation = elevationMatch ? Number(elevationMatch[1]) : null
    if (Number.isFinite(lat) && Number.isFinite(lng)) points.push({ lat, lng, elevation_m: Number.isFinite(elevation) ? elevation : null })
  }
  if (points.length < 2) throw new Error('No usable route points were found in this GPX file.')
  const nameMatch = xml.match(/<name>([^<]+)<\/name>/i)
  return { name: nameMatch?.[1] ? decodeXml(nameMatch[1].trim()) : 'Imported route', points }
}
