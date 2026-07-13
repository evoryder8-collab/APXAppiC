import { useCallback, useEffect, useRef, useState } from 'react'
import * as L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import type { GeoPoint } from '../domain/types.ts'
import { useOrbitText } from '../ui/i18n.ts'

type MapStyle = 'night' | 'light' | 'satellite'

const TILE_STYLES: Record<MapStyle, { url: string; attribution: string; maxZoom: number }> = {
  night: {
    url: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    attribution: '&copy; OpenStreetMap contributors &copy; CARTO',
    maxZoom: 20,
  },
  light: {
    url: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    attribution: '&copy; OpenStreetMap contributors &copy; CARTO',
    maxZoom: 20,
  },
  satellite: {
    url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attribution: 'Tiles &copy; Esri',
    maxZoom: 19,
  },
}

function latLngs(points: GeoPoint[]): L.LatLngTuple[] {
  return points.map((point) => [point.lat, point.lng])
}

function routeSignature(points: GeoPoint[]): string {
  if (points.length === 0) return 'empty'
  const first = points[0]
  const last = points.at(-1)!
  return `${points.length}:${first.lat.toFixed(4)}:${first.lng.toFixed(4)}:${last.lat.toFixed(4)}:${last.lng.toFixed(4)}`
}

function MarkerIcon({ kind }: { kind: 'layers' | 'fit' | 'history' }) {
  if (kind === 'fit') return <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden><circle cx="12" cy="12" r="4" fill="none" stroke="currentColor" strokeWidth="2"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3" fill="none" stroke="currentColor" strokeLinecap="round" strokeWidth="2"/></svg>
  if (kind === 'history') return <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden><path d="M4 17c3-7 5 2 8-5s4 2 8-5" fill="none" stroke="currentColor" strokeLinecap="round" strokeWidth="2"/><path d="M4 21c4-5 7 0 10-5s4 0 6-3" fill="none" stroke="currentColor" strokeLinecap="round" strokeWidth="1.5" opacity=".55"/></svg>
  return <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden><path d="m12 3 8 4-8 4-8-4 8-4Z" fill="none" stroke="currentColor" strokeLinejoin="round" strokeWidth="1.8"/><path d="m4 12 8 4 8-4M4 17l8 4 8-4" fill="none" stroke="currentColor" strokeLinejoin="round" strokeWidth="1.8"/></svg>
}

export function OrbitMap({
  planned = [],
  completed = [],
  current = null,
  history = [],
  editable = false,
  followCurrent = false,
  onAddPoint,
  className = '',
}: {
  planned?: GeoPoint[]
  completed?: GeoPoint[]
  current?: GeoPoint | null
  history?: GeoPoint[][]
  editable?: boolean
  followCurrent?: boolean
  onAddPoint?: (point: GeoPoint) => void
  className?: string
}) {
  const t = useOrbitText()
  const host = useRef<HTMLDivElement>(null)
  const mapRef = useRef<L.Map | null>(null)
  const tileRef = useRef<L.TileLayer | null>(null)
  const layers = useRef<L.LayerGroup | null>(null)
  const viewPoints = useRef<L.LatLngTuple[]>([])
  const lastFitSignature = useRef('')
  const onAddPointRef = useRef(onAddPoint)
  const [style, setStyle] = useState<MapStyle>('night')
  const [historyVisible, setHistoryVisible] = useState(true)
  onAddPointRef.current = onAddPoint

  const fitMap = useCallback(() => {
    const map = mapRef.current
    const points = viewPoints.current
    if (!map || points.length === 0) return
    if (points.length === 1) map.flyTo(points[0], 15, { duration: 0.65 })
    else map.flyToBounds(L.latLngBounds(points), { paddingTopLeft: [34, 48], paddingBottomRight: [64, 92], maxZoom: 16, duration: 0.65 })
  }, [])

  useEffect(() => {
    if (!host.current || mapRef.current) return
    const map = L.map(host.current, {
      zoomControl: false,
      attributionControl: true,
      preferCanvas: true,
      worldCopyJump: true,
      zoomSnap: 0.5,
      zoomDelta: 0.5,
    }).setView([46.8, 8.2], 7)
    map.createPane('orbitHistory').style.zIndex = '410'
    map.createPane('orbitRoute').style.zIndex = '430'
    map.createPane('orbitProgress').style.zIndex = '440'
    map.createPane('orbitMarkers').style.zIndex = '450'
    layers.current = L.layerGroup().addTo(map)
    map.on('click', (event) => onAddPointRef.current?.({ lat: event.latlng.lat, lng: event.latlng.lng }))
    mapRef.current = map
    return () => {
      map.remove()
      mapRef.current = null
      tileRef.current = null
      layers.current = null
    }
  }, [])

  useEffect(() => {
    const map = mapRef.current
    if (!map) return
    tileRef.current?.remove()
    const config = TILE_STYLES[style]
    tileRef.current = L.tileLayer(config.url, {
      maxZoom: config.maxZoom,
      attribution: config.attribution,
      subdomains: style === 'satellite' ? undefined : 'abcd',
      className: `orbit-map-tiles orbit-map-tiles-${style}`,
    }).addTo(map)
    tileRef.current.setZIndex(0)
  }, [style])

  useEffect(() => {
    const map = mapRef.current
    const group = layers.current
    if (!map || !group) return
    group.clearLayers()

    const plannedLatLngs = latLngs(planned)
    const completedLatLngs = latLngs(completed)
    const usableHistory = historyVisible ? history.filter((points) => points.length > 1).slice(-60) : []
    const historyPalette = ['#4f46e5', '#7c3aed', '#2563eb', '#0891b2']

    usableHistory.forEach((points, index) => {
      const line = latLngs(points)
      const color = historyPalette[index % historyPalette.length]
      L.polyline(line, { pane: 'orbitHistory', color, weight: 8, opacity: 0.13, interactive: false, className: 'orbit-history-halo' }).addTo(group)
      L.polyline(line, { pane: 'orbitHistory', color, weight: 2.25, opacity: 0.58, interactive: false, className: 'orbit-history-line' }).addTo(group)
    })

    if (plannedLatLngs.length > 1) {
      L.polyline(plannedLatLngs, { pane: 'orbitRoute', color: '#020617', weight: 12, opacity: 0.92, interactive: false }).addTo(group)
      L.polyline(plannedLatLngs, { pane: 'orbitRoute', color: '#6366f1', weight: 10, opacity: 0.32, interactive: false, className: 'orbit-planned-halo' }).addTo(group)
      L.polyline(plannedLatLngs, { pane: 'orbitRoute', color: '#dbeafe', weight: 4.5, opacity: 0.98, interactive: false, lineCap: 'round', lineJoin: 'round', className: 'orbit-planned-line' }).addTo(group)
    }
    if (completedLatLngs.length > 1) {
      L.polyline(completedLatLngs, { pane: 'orbitProgress', color: '#020617', weight: 13, opacity: 0.94, interactive: false }).addTo(group)
      L.polyline(completedLatLngs, { pane: 'orbitProgress', color: '#f59e0b', weight: 11, opacity: 0.34, interactive: false, className: 'orbit-progress-halo' }).addTo(group)
      L.polyline(completedLatLngs, { pane: 'orbitProgress', color: '#fbbf24', weight: 5.5, opacity: 1, interactive: false, lineCap: 'round', lineJoin: 'round', className: 'orbit-progress-line' }).addTo(group)
    }

    if (plannedLatLngs.length > 0) {
      const start = plannedLatLngs[0]
      const finish = plannedLatLngs.at(-1)!
      L.marker(start, { pane: 'orbitMarkers', interactive: false, icon: L.divIcon({ className: 'orbit-map-pin-shell', html: '<span class="orbit-map-pin orbit-map-pin-start">S</span>', iconSize: [30, 30], iconAnchor: [15, 15] }) }).addTo(group)
      if (L.latLng(start).distanceTo(L.latLng(finish)) > 12) {
        L.marker(finish, { pane: 'orbitMarkers', interactive: false, icon: L.divIcon({ className: 'orbit-map-pin-shell', html: '<span class="orbit-map-pin orbit-map-pin-finish">F</span>', iconSize: [30, 30], iconAnchor: [15, 15] }) }).addTo(group)
      }
    }
    if (current) {
      const point: L.LatLngTuple = [current.lat, current.lng]
      const accuracy = 'accuracy_m' in current ? Number(current.accuracy_m) : null
      if (accuracy && Number.isFinite(accuracy)) L.circle(point, { pane: 'orbitMarkers', radius: Math.max(8, accuracy), stroke: false, fillColor: '#38bdf8', fillOpacity: 0.1, interactive: false }).addTo(group)
      L.circleMarker(point, { pane: 'orbitMarkers', radius: 17, stroke: false, fillColor: '#38bdf8', fillOpacity: 0.16, interactive: false, className: 'orbit-location-pulse' }).addTo(group)
      L.circleMarker(point, { pane: 'orbitMarkers', radius: 8, color: '#fff', weight: 3, fillColor: '#38bdf8', fillOpacity: 1, interactive: false }).addTo(group)
    }

    const primary = plannedLatLngs.length > 0
      ? plannedLatLngs
      : completedLatLngs.length > 0
        ? completedLatLngs
        : current
          ? [[current.lat, current.lng] as L.LatLngTuple]
          : usableHistory.flatMap(latLngs)
    viewPoints.current = primary
    const signature = `${routeSignature(planned)}|${routeSignature(completed)}|${current ? 'current' : 'none'}`
    if (signature !== lastFitSignature.current) {
      lastFitSignature.current = signature
      window.setTimeout(fitMap, 40)
    } else if (followCurrent && current) {
      map.panTo([current.lat, current.lng], { animate: true, duration: 0.45 })
    }
    map.getContainer().style.cursor = editable ? 'crosshair' : ''
  }, [completed, current, editable, fitMap, followCurrent, history, historyVisible, planned])

  const cycleStyle = (): void => setStyle((currentStyle) => currentStyle === 'night' ? 'light' : currentStyle === 'light' ? 'satellite' : 'night')

  return (
    <div className={`orbit-map relative h-72 w-full overflow-hidden rounded-[28px] bg-[#050b16] ${className}`} aria-label={t('Interactive run map')}>
      <div ref={host} className="absolute inset-0" />
      <div className="orbit-map-vignette pointer-events-none absolute inset-0 z-[450]" aria-hidden />
      <div className="pointer-events-none absolute top-3 left-3 z-[470] flex items-center gap-2 rounded-full border border-white/12 bg-[#050b16]/88 px-3 py-2 text-white shadow-xl">
        <span className="h-2 w-2 rounded-full bg-cyan-300 shadow-[0_0_12px_rgba(103,232,249,.9)]" />
        <span className="font-mono text-[9px] font-bold tracking-[.13em]">{t(history.length > 0 ? 'PRIVATE ROUTE NETWORK' : 'ORBIT MAP')}</span>
      </div>
      {editable && <div className="pointer-events-none absolute bottom-3 left-3 z-[470] rounded-full border border-amber-200/25 bg-[#120b02]/88 px-3 py-2 font-mono text-[9px] font-bold tracking-wide text-amber-100">{t('TAP TO DRAW')}</div>}
      <div className="absolute top-3 right-3 z-[480] flex flex-col gap-2">
        <button type="button" onClick={fitMap} aria-label={t('Fit route')} title={t('Fit route')} className="orbit-map-control"><MarkerIcon kind="fit" /></button>
        <button type="button" onClick={cycleStyle} aria-label={t('Change map style')} title={t('Change map style')} className="orbit-map-control"><MarkerIcon kind="layers" /><span className="sr-only">{t(style === 'night' ? 'Night map' : style === 'light' ? 'Light map' : 'Satellite map')}</span></button>
        {history.length > 0 && <button type="button" onClick={() => setHistoryVisible((visible) => !visible)} aria-pressed={historyVisible} aria-label={t(historyVisible ? 'Hide private routes' : 'Show private routes')} title={t(historyVisible ? 'Hide private routes' : 'Show private routes')} className={`orbit-map-control ${historyVisible ? 'orbit-map-control-active' : ''}`}><MarkerIcon kind="history" /></button>}
        <div className="overflow-hidden rounded-full border border-white/12 bg-[#050b16]/88 shadow-xl">
          <button type="button" onClick={() => mapRef.current?.zoomIn(0.5)} aria-label={t('Zoom in')} className="grid h-11 w-11 place-items-center border-b border-white/10 text-xl font-light text-white">+</button>
          <button type="button" onClick={() => mapRef.current?.zoomOut(0.5)} aria-label={t('Zoom out')} className="grid h-11 w-11 place-items-center text-xl font-light text-white">−</button>
        </div>
      </div>
    </div>
  )
}
