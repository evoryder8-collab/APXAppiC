import type { GeoPoint, RouteCandidate, RouteRequest, TrackSample } from './types.ts'

export interface RouteProvider {
  readonly name: string
  generate(request: RouteRequest): Promise<RouteCandidate[]>
}

export interface GeocoderResult {
  label: string
  point: GeoPoint
}

export interface Geocoder {
  readonly name: string
  search(query: string): Promise<GeocoderResult[]>
}

export interface LocationSensor {
  requestCurrent(): Promise<TrackSample>
  watch(onSample: (sample: TrackSample) => void, onError: (error: Error) => void): () => void
}

export interface MapRendererPort {
  fit(points: GeoPoint[]): void
  setPlannedRoute(points: GeoPoint[]): void
  setCompletedTrack(points: GeoPoint[]): void
}

export interface RunRecorderPort {
  start(): Promise<void>
  pause(): void
  resume(): void
  stop(): void
}

export interface PosterRendererPort {
  saveSvg(svg: string, filename: string): void
  savePng(svg: string, filename: string): Promise<void>
}

export interface HeartRateCadenceSource {
  latest(): { heart_rate_bpm: number | null; cadence_spm: number | null }
}
