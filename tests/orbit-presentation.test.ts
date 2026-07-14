import assert from 'node:assert/strict'
import test from 'node:test'
import { MAP_STYLE_ORDER, mapTileOptions, nextMapStyle } from '../src/orbit/domain/mapStyles.ts'
import { inferNavigationComplexity, inferRouteShape, routeGeometryKey, routePreviewGeometry } from '../src/orbit/domain/routePresentation.ts'

test('map styles cycle safely without explicit undefined tile options', () => {
  assert.deepEqual(MAP_STYLE_ORDER.map(nextMapStyle), ['light', 'satellite', 'night'])
  const satellite = mapTileOptions('satellite')
  assert.equal(Object.hasOwn(satellite, 'subdomains'), false)
  assert.equal(mapTileOptions('night').subdomains, 'abcd')
})

test('route presentation distinguishes open and closed geometry', () => {
  const open = [{ lat: 47.37, lng: 8.52 }, { lat: 47.38, lng: 8.54 }, { lat: 47.39, lng: 8.55 }]
  const loop = [...open, { lat: 47.3701, lng: 8.5201 }]
  assert.equal(inferRouteShape(open), 'point_to_point')
  assert.equal(inferRouteShape(loop), 'loop')
  assert.ok(routePreviewGeometry(open)?.path.startsWith('M '))
  assert.notEqual(routeGeometryKey(open), routeGeometryKey(loop))
})

test('route presentation rejects invalid points and keeps simple paths low complexity', () => {
  const points = [
    { lat: Number.NaN, lng: 8.5 },
    { lat: 47.37, lng: 8.52 },
    { lat: 47.371, lng: 8.521 },
    { lat: 47.372, lng: 8.522 },
  ]
  assert.equal(routePreviewGeometry(points)?.pointCount, 3)
  assert.equal(inferNavigationComplexity(points), 'low')
})
