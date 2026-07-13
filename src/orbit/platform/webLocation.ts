import type { LocationSensor } from '../domain/ports.ts'
import type { TrackSample } from '../domain/types.ts'

function sampleFromPosition(position: GeolocationPosition): TrackSample {
  return {
    lat: position.coords.latitude,
    lng: position.coords.longitude,
    elevation_m: position.coords.altitude,
    recorded_at: position.timestamp || Date.now(),
    accuracy_m: position.coords.accuracy,
    heart_rate_bpm: null,
    cadence_spm: null,
  }
}

function positionError(error: GeolocationPositionError): Error {
  if (error.code === error.PERMISSION_DENIED) return new Error('Location permission was denied. You can still plan manually or import GPX.')
  if (error.code === error.POSITION_UNAVAILABLE) return new Error('Location is currently unavailable.')
  return new Error('Location timed out. Move to an open area and try again.')
}

export class WebLocationSensor implements LocationSensor {
  requestCurrent(): Promise<TrackSample> {
    if (!navigator.geolocation) return Promise.reject(new Error('Location is not supported by this browser.'))
    return new Promise((resolve, reject) => {
      navigator.geolocation.getCurrentPosition(
        (position) => resolve(sampleFromPosition(position)),
        (error) => reject(positionError(error)),
        { enableHighAccuracy: true, timeout: 15_000, maximumAge: 5_000 },
      )
    })
  }

  watch(onSample: (sample: TrackSample) => void, onError: (error: Error) => void): () => void {
    if (!navigator.geolocation) {
      onError(new Error('Location is not supported by this browser.'))
      return () => undefined
    }
    const id = navigator.geolocation.watchPosition(
      (position) => onSample(sampleFromPosition(position)),
      (error) => onError(positionError(error)),
      { enableHighAccuracy: true, timeout: 20_000, maximumAge: 1_000 },
    )
    return () => navigator.geolocation.clearWatch(id)
  }
}
