import { useEffect, useRef } from 'react'
import * as L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import type { GeoPoint } from '../domain/types.ts'
import { useOrbitText } from '../ui/i18n.ts'

export function OrbitMap({
  planned = [],
  completed = [],
  current = null,
  editable = false,
  onAddPoint,
  className = '',
}: {
  planned?: GeoPoint[]
  completed?: GeoPoint[]
  current?: GeoPoint | null
  editable?: boolean
  onAddPoint?: (point: GeoPoint) => void
  className?: string
}) {
  const t = useOrbitText()
  const host = useRef<HTMLDivElement>(null)
  const mapRef = useRef<L.Map | null>(null)
  const layers = useRef<L.LayerGroup | null>(null)
  const onAddPointRef = useRef(onAddPoint)
  onAddPointRef.current = onAddPoint

  useEffect(() => {
    if (!host.current || mapRef.current) return
    const map = L.map(host.current, { zoomControl: false, attributionControl: true, preferCanvas: true }).setView([46.8, 8.2], 7)
    L.control.zoom({ position: 'bottomright' }).addTo(map)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '© OpenStreetMap contributors',
    }).addTo(map)
    layers.current = L.layerGroup().addTo(map)
    map.on('click', (event) => onAddPointRef.current?.({ lat: event.latlng.lat, lng: event.latlng.lng }))
    mapRef.current = map
    return () => {
      map.remove()
      mapRef.current = null
      layers.current = null
    }
  }, [])

  useEffect(() => {
    const map = mapRef.current
    const group = layers.current
    if (!map || !group) return
    group.clearLayers()
    const plannedLatLngs = planned.map((point) => [point.lat, point.lng] as L.LatLngTuple)
    const completedLatLngs = completed.map((point) => [point.lat, point.lng] as L.LatLngTuple)
    if (plannedLatLngs.length > 1) L.polyline(plannedLatLngs, { color: '#7dd3fc', weight: 5, opacity: 0.68, dashArray: '7 9' }).addTo(group)
    if (completedLatLngs.length > 1) L.polyline(completedLatLngs, { color: '#fbbf24', weight: 6, opacity: 0.94 }).addTo(group)
    if (plannedLatLngs.length > 0) {
      L.circleMarker(plannedLatLngs[0], { radius: 7, color: '#34d399', fillColor: '#34d399', fillOpacity: 1 }).addTo(group)
      L.circleMarker(plannedLatLngs.at(-1)!, { radius: 7, color: '#fbbf24', fillColor: '#fbbf24', fillOpacity: 1 }).addTo(group)
    }
    if (current) L.circleMarker([current.lat, current.lng], { radius: 8, color: '#fff', weight: 3, fillColor: '#38bdf8', fillOpacity: 1 }).addTo(group)
    const all = [...plannedLatLngs, ...completedLatLngs, ...(current ? [[current.lat, current.lng] as L.LatLngTuple] : [])]
    if (all.length > 1) map.fitBounds(L.latLngBounds(all), { padding: [28, 28], maxZoom: 16 })
    else if (all.length === 1) map.setView(all[0], 15)
    map.getContainer().style.cursor = editable ? 'crosshair' : ''
  }, [completed, current, editable, planned])

  return <div ref={host} className={`orbit-map h-72 w-full overflow-hidden rounded-[22px] bg-[#07111f] ${className}`} aria-label={t('Interactive run map')} />
}
