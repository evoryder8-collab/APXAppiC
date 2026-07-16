type ReleasableTrack = Pick<MediaStreamTrack, 'enabled' | 'stop'>
type ReleasableStream = Pick<MediaStream, 'getTracks'>
type CaptureVideo = Pick<HTMLVideoElement, 'pause' | 'srcObject'>

function isReleasableStream(value: unknown): value is ReleasableStream {
  return Boolean(value && typeof value === 'object' && 'getTracks' in value && typeof value.getTracks === 'function')
}

/* Release both the stream retained by React and any stream still attached to
   the video element. iOS owns its privacy indicator; disabling and stopping
   every track, then clearing srcObject, is the strongest control available to
   a web app and prevents a capture session surviving into review/navigation. */
export function releaseProgressCamera(
  stream: ReleasableStream | null,
  video: CaptureVideo | null,
): number {
  const sources = new Set<ReleasableStream>()
  if (stream) sources.add(stream)
  if (isReleasableStream(video?.srcObject)) sources.add(video.srcObject)

  const tracks = new Set<ReleasableTrack>()
  for (const source of sources) {
    for (const track of source.getTracks()) tracks.add(track)
  }
  for (const track of tracks) {
    try { track.enabled = false } catch { /* Keep releasing the remaining tracks. */ }
    try { track.stop() } catch { /* A track may already have ended. */ }
  }

  if (video) {
    try { video.pause() } catch { /* The element may already be detached. */ }
    video.srcObject = null
  }
  return tracks.size
}
