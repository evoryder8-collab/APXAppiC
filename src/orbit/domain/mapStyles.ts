export const MAP_STYLE_ORDER = ['night', 'light', 'satellite'] as const

export type MapStyle = (typeof MAP_STYLE_ORDER)[number]

export interface MapTileStyle {
  url: string
  attribution: string
  maxZoom: number
  subdomains?: string
}

export const MAP_TILE_STYLES: Record<MapStyle, MapTileStyle> = {
  night: {
    url: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    attribution: '&copy; OpenStreetMap contributors &copy; CARTO',
    maxZoom: 20,
    subdomains: 'abcd',
  },
  light: {
    url: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    attribution: '&copy; OpenStreetMap contributors &copy; CARTO',
    maxZoom: 20,
    subdomains: 'abcd',
  },
  satellite: {
    url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attribution: 'Tiles &copy; Esri',
    maxZoom: 19,
  },
}

export function nextMapStyle(style: MapStyle): MapStyle {
  const index = MAP_STYLE_ORDER.indexOf(style)
  return MAP_STYLE_ORDER[(index + 1) % MAP_STYLE_ORDER.length]
}

/** Leaflet treats an explicitly supplied undefined `subdomains` as a value and
 * later reads `.length` from it. Omit the key entirely for single-host tile
 * providers such as Esri to keep style changes safe on every browser. */
export function mapTileOptions(style: MapStyle): {
  maxZoom: number
  attribution: string
  className: string
  crossOrigin: true
  subdomains?: string
} {
  const config = MAP_TILE_STYLES[style]
  return {
    maxZoom: config.maxZoom,
    attribution: config.attribution,
    className: `orbit-map-tiles orbit-map-tiles-${style}`,
    crossOrigin: true,
    ...(config.subdomains ? { subdomains: config.subdomains } : {}),
  }
}
