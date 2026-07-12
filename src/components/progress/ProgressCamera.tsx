import { useCallback, useEffect, useRef, useState } from 'react'
import type { ProgressPose } from '../../lib/progressPhoto'

export function ProgressCamera({
  initialPose,
  referenceUrl,
  onSave,
  onClose,
}: {
  initialPose: ProgressPose
  referenceUrl?: string | null
  onSave: (blob: Blob, pose: ProgressPose) => Promise<void>
  onClose: () => void
}) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const [pose, setPose] = useState<ProgressPose>(initialPose)
  const [devices, setDevices] = useState<MediaDeviceInfo[]>([])
  const [deviceIndex, setDeviceIndex] = useState(0)
  const [timer, setTimer] = useState<3 | 5 | 10>(5)
  const [countdown, setCountdown] = useState<number | null>(null)
  const [captured, setCaptured] = useState<Blob | null>(null)
  const [preview, setPreview] = useState<string | null>(null)
  const [ghostOpacity, setGhostOpacity] = useState(referenceUrl ? 0.25 : 0)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const stop = useCallback(() => {
    for (const track of streamRef.current?.getTracks() ?? []) track.stop()
    streamRef.current = null
  }, [])

  useEffect(() => {
    let cancelled = false
    const start = async () => {
      stop()
      setError(null)
      try {
        const available = await navigator.mediaDevices.enumerateDevices().then((values) => values.filter((device) => device.kind === 'videoinput')).catch(() => [])
        if (!cancelled) setDevices(available)
        const selected = available[deviceIndex]?.deviceId
        const stream = await navigator.mediaDevices.getUserMedia({
          audio: false,
          video: selected
            ? { deviceId: { exact: selected }, width: { ideal: 1920 }, height: { ideal: 1080 } }
            : { facingMode: { ideal: 'environment' }, width: { ideal: 1920 }, height: { ideal: 1080 } },
        })
        if (cancelled) {
          stream.getTracks().forEach((track) => track.stop())
          return
        }
        streamRef.current = stream
        if (videoRef.current) {
          videoRef.current.srcObject = stream
          await videoRef.current.play()
        }
        const refreshed = await navigator.mediaDevices.enumerateDevices().then((values) => values.filter((device) => device.kind === 'videoinput'))
        if (!cancelled) setDevices(refreshed)
      } catch (cause) {
        const name = cause instanceof DOMException ? cause.name : ''
        setError(name === 'NotAllowedError'
          ? 'Camera access is blocked. Allow it in Safari settings, or use the photo-library fallback.'
          : 'The camera could not start. Use the photo-library fallback below.')
      }
    }
    void start()
    return () => { cancelled = true; stop() }
  }, [deviceIndex, stop])

  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview) }, [preview])

  const captureFrame = useCallback(async () => {
    const video = videoRef.current
    if (!video?.videoWidth || !video.videoHeight) return
    const canvas = document.createElement('canvas')
    canvas.width = video.videoWidth
    canvas.height = video.videoHeight
    const context = canvas.getContext('2d')
    if (!context) return
    context.drawImage(video, 0, 0)
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.94))
    if (!blob) return
    const url = URL.createObjectURL(blob)
    setCaptured(blob)
    setPreview(url)
    navigator.vibrate?.(40)
  }, [])

  const beginCountdown = () => {
    if (countdown != null) return
    setCountdown(timer)
    let current = timer
    const interval = window.setInterval(() => {
      current -= 1
      if (current <= 0) {
        window.clearInterval(interval)
        setCountdown(null)
        void captureFrame()
      } else setCountdown(current)
    }, 1000)
  }

  const acceptLibrary = (file: File | undefined) => {
    if (!file) return
    if (preview) URL.revokeObjectURL(preview)
    setCaptured(file)
    setPreview(URL.createObjectURL(file))
  }

  const retake = () => {
    if (preview) URL.revokeObjectURL(preview)
    setPreview(null)
    setCaptured(null)
  }

  const save = async () => {
    if (!captured) return
    setSaving(true)
    try { await onSave(captured, pose) } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 z-[95] bg-[#08090d] text-white" role="dialog" aria-modal="true" aria-label="Private progress camera">
      <video ref={videoRef} muted playsInline className="absolute inset-0 h-full w-full object-cover" />
      {preview && <img src={preview} alt="Captured progress review" className="absolute inset-0 h-full w-full object-cover" />}
      {!preview && referenceUrl && ghostOpacity > 0 && <img src={referenceUrl} alt="Previous pose alignment guide" className="pointer-events-none absolute inset-0 h-full w-full object-cover" style={{ opacity: ghostOpacity }} />}

      {!preview && (
        <div className="pointer-events-none absolute inset-x-[13%] top-[11%] bottom-[14%] rounded-[42%] border border-white/75" style={{ boxShadow: '0 0 40px rgba(255,255,255,0.14)' }}>
          <div className="absolute -right-[18%] bottom-[3%] -left-[18%] border-t border-dashed border-amber-300/85" />
          <p className="absolute -bottom-7 left-1/2 -translate-x-1/2 whitespace-nowrap font-mono text-[9px] font-bold tracking-[0.12em] text-amber-200 uppercase">Feet on the floor line</p>
        </div>
      )}

      <div className="absolute inset-x-0 top-0 flex items-center justify-between bg-gradient-to-b from-black/65 to-transparent px-4 pt-[calc(1rem+env(safe-area-inset-top))] pb-12">
        <button type="button" onClick={onClose} className="rounded-full bg-black/35 px-4 py-2 text-sm font-bold backdrop-blur">Close</button>
        <div className="flex rounded-full bg-black/35 p-1 backdrop-blur">
          {(['front', 'side', 'back'] as const).map((value) => <button key={value} type="button" onClick={() => setPose(value)} className={`rounded-full px-3 py-1.5 text-[10px] font-bold uppercase ${pose === value ? 'bg-white text-black' : 'text-white/70'}`}>{value}</button>)}
        </div>
      </div>

      {countdown != null && <div className="absolute inset-0 grid place-items-center bg-black/15 font-mono text-9xl font-bold drop-shadow-2xl">{countdown}</div>}
      {error && <p className="absolute top-28 right-4 left-4 rounded-2xl bg-red-600/75 px-4 py-3 text-xs font-semibold backdrop-blur">{error}</p>}

      <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/85 via-black/50 to-transparent px-4 pt-20 pb-[calc(1rem+env(safe-area-inset-bottom))]">
        {preview ? (
          <div className="mx-auto flex max-w-md gap-3"><button type="button" onClick={retake} className="flex-1 rounded-2xl bg-white/15 px-5 py-4 font-bold backdrop-blur">Retake</button><button type="button" disabled={saving} onClick={() => void save()} className="flex-[1.4] rounded-2xl bg-emerald-500 px-5 py-4 font-bold disabled:opacity-50">{saving ? 'Encrypting locally…' : 'Save privately'}</button></div>
        ) : (
          <div className="mx-auto max-w-md space-y-3">
            <div className="flex items-center justify-between gap-2">
              <div className="flex rounded-full bg-black/35 p-1 backdrop-blur">{([3, 5, 10] as const).map((value) => <button key={value} type="button" onClick={() => setTimer(value)} className={`rounded-full px-3 py-1.5 text-[10px] font-bold ${timer === value ? 'bg-white text-black' : 'text-white/70'}`}>{value}s</button>)}</div>
              {referenceUrl && <label className="flex items-center gap-2 rounded-full bg-black/35 px-3 py-2 text-[10px] font-bold backdrop-blur">Ghost <input type="range" min="0" max="0.55" step="0.05" value={ghostOpacity} onChange={(event) => setGhostOpacity(Number(event.target.value))} className="w-20" /></label>}
              {devices.length > 1 && <button type="button" onClick={() => setDeviceIndex((value) => (value + 1) % devices.length)} className="rounded-full bg-black/35 px-3 py-2 text-[10px] font-bold backdrop-blur">Flip</button>}
            </div>
            <div className="flex items-center justify-center gap-5">
              <label className="cursor-pointer rounded-full bg-white/15 px-3 py-2 text-[10px] font-bold backdrop-blur">Library<input type="file" accept="image/*" capture="environment" onChange={(event) => acceptLibrary(event.target.files?.[0])} className="sr-only" /></label>
              <button type="button" onClick={beginCountdown} className="h-20 w-20 rounded-full border-4 border-white bg-white/20 active:scale-95" style={{ boxShadow: '0 0 0 2px rgba(255,255,255,0.4)' }} aria-label={`Take photo in ${timer} seconds`} />
              <span className="w-16 text-center font-mono text-[10px] font-bold text-white/60">1×</span>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
