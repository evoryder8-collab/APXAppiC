import { useCallback, useEffect, useRef, useState } from 'react'
import { coverCrop, type ProgressPose } from '../../lib/progressPhoto'
import { useLanguage } from '../../lib/i18n'

type CameraFacing = 'user' | 'environment'

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
  const { language } = useLanguage()
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const countdownRef = useRef<number | null>(null)
  const [pose, setPose] = useState<ProgressPose>(initialPose)
  const [facing, setFacing] = useState<CameraFacing>('user')
  const [restartKey, setRestartKey] = useState(0)
  const [ready, setReady] = useState(false)
  const [timer, setTimer] = useState<3 | 5 | 10>(5)
  const [countdown, setCountdown] = useState<number | null>(null)
  const [captured, setCaptured] = useState<Blob | null>(null)
  const [preview, setPreview] = useState<string | null>(null)
  const [ghostOpacity, setGhostOpacity] = useState(referenceUrl ? 0.25 : 0)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const poseLabel = (value: ProgressPose): string => ({
    en: { front: 'Front', side: 'Profile', back: 'Back' },
    ro: { front: 'Față', side: 'Profil', back: 'Spate' },
    th: { front: 'ด้านหน้า', side: 'ด้านข้าง', back: 'ด้านหลัง' },
  })[language][value]

  const stop = useCallback(() => {
    if (countdownRef.current != null) window.clearInterval(countdownRef.current)
    countdownRef.current = null
    for (const track of streamRef.current?.getTracks() ?? []) track.stop()
    streamRef.current = null
  }, [])

  useEffect(() => {
    let cancelled = false
    const connect = async () => {
      stop()
      setReady(false)
      setError(null)
      if (!navigator.mediaDevices?.getUserMedia) {
        setError('Live camera is unavailable in this browser. Choose a photo from your library instead.')
        return
      }
      try {
        let stream: MediaStream
        try {
          stream = await navigator.mediaDevices.getUserMedia({
            audio: false,
            video: {
              facingMode: { ideal: facing },
              width: { ideal: 1440 },
              height: { ideal: 2160 },
            },
          })
        } catch (firstError) {
          const name = firstError instanceof DOMException ? firstError.name : ''
          if (name === 'NotAllowedError' || name === 'SecurityError') throw firstError
          stream = await navigator.mediaDevices.getUserMedia({ audio: false, video: true })
        }
        if (cancelled) {
          stream.getTracks().forEach((track) => track.stop())
          return
        }
        streamRef.current = stream
        const video = videoRef.current
        if (!video) return
        video.srcObject = stream
        video.muted = true
        if (video.readyState < 1) {
          await new Promise<void>((resolve) => video.addEventListener('loadedmetadata', () => resolve(), { once: true }))
        }
        await video.play()
        if (cancelled) return
        setReady(true)
      } catch (cause) {
        if (cancelled) return
        const name = cause instanceof DOMException ? cause.name : ''
        setError(name === 'NotAllowedError' || name === 'SecurityError'
          ? 'Camera access is blocked. Allow camera access in Safari settings, then tap Retry—or choose a photo from your library.'
          : 'The camera could not start. Tap Retry or choose a photo from your library.')
      }
    }
    void connect()
    return () => { cancelled = true; stop() }
  }, [facing, restartKey, stop])

  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview) }, [preview])

  const captureFrame = useCallback(async () => {
    const video = videoRef.current
    if (!video?.videoWidth || !video.videoHeight) {
      setError('The camera is still focusing. Try the shutter again in a moment.')
      return
    }
    const previewRatio = video.clientWidth > 0 && video.clientHeight > 0
      ? video.clientWidth / video.clientHeight
      : 2 / 3
    const crop = coverCrop(video.videoWidth, video.videoHeight, previewRatio)
    const canvas = document.createElement('canvas')
    canvas.width = Math.max(1, Math.min(1440, Math.round(crop.width)))
    canvas.height = Math.max(1, Math.round(canvas.width / previewRatio))
    const context = canvas.getContext('2d', { alpha: false })
    if (!context) return
    if (facing === 'user') {
      context.translate(canvas.width, 0)
      context.scale(-1, 1)
    }
    context.drawImage(video, crop.sx, crop.sy, crop.width, crop.height, 0, 0, canvas.width, canvas.height)
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.94))
    if (!blob) return
    if (preview) URL.revokeObjectURL(preview)
    const url = URL.createObjectURL(blob)
    setCaptured(blob)
    setPreview(url)
    navigator.vibrate?.(40)
  }, [facing, preview])

  const beginCountdown = () => {
    if (countdown != null || !ready) return
    setCountdown(timer)
    let current = timer
    countdownRef.current = window.setInterval(() => {
      current -= 1
      if (current <= 0) {
        if (countdownRef.current != null) window.clearInterval(countdownRef.current)
        countdownRef.current = null
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
    setError(null)
  }

  const retake = () => {
    if (preview) URL.revokeObjectURL(preview)
    setPreview(null)
    setCaptured(null)
  }

  const save = async () => {
    if (!captured) return
    setSaving(true)
    setError(null)
    try {
      await onSave(captured, pose)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'The photo could not be saved. It remains on this review screen so you can retry.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 z-[95] overflow-hidden bg-[#08090d] text-white" role="dialog" aria-modal="true" aria-label="Private progress camera">
      <video
        ref={videoRef}
        autoPlay
        muted
        playsInline
        className={`absolute inset-0 h-full w-full object-cover ${facing === 'user' ? '-scale-x-100' : ''}`}
      />
      {preview && <img src={preview} alt="Captured progress review" className="absolute inset-0 h-full w-full object-cover" />}
      {!preview && referenceUrl && ghostOpacity > 0 && <img src={referenceUrl} alt="Previous pose alignment guide" className="pointer-events-none absolute inset-0 h-full w-full object-cover" style={{ opacity: ghostOpacity }} />}

      {!preview && (
        <div className="pointer-events-none absolute inset-x-0 top-[calc(max(0.75rem,env(safe-area-inset-top))+4.25rem)] bottom-[calc(max(0.75rem,env(safe-area-inset-bottom))+9.25rem)] flex items-center justify-center" aria-hidden>
          <svg viewBox="0 0 240 560" fill="none" className="h-full max-h-[68dvh] w-auto max-w-[70vw] overflow-visible drop-shadow-[0_0_16px_rgba(0,0,0,0.45)]">
            <circle cx="120" cy="48" r="28" stroke="rgba(255,255,255,.9)" strokeWidth="2" />
            <path d="M91 92c-27 8-44 26-47 57l-8 109M149 92c27 8 44 26 47 57l8 109M91 92c5 38 2 94-11 151l-10 71M149 92c-5 38-2 94 11 151l10 71M80 243c10 10 25 15 40 15s30-5 40-15M80 314l-16 187M160 314l16 187M64 501l-18 24M176 501l18 24" stroke="rgba(255,255,255,.88)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            <path d="M120 84v423" stroke="rgba(196,181,253,.42)" strokeWidth="1" strokeDasharray="5 8" />
            <path d="M28 525h184" stroke="rgba(253,230,138,.95)" strokeWidth="2" strokeDasharray="7 7" />
          </svg>
          <p className="absolute bottom-0 left-1/2 -translate-x-1/2 whitespace-nowrap rounded-full bg-black/35 px-3 py-1.5 font-mono text-[8px] font-bold tracking-[0.12em] text-amber-100 uppercase backdrop-blur">Head and feet inside the guide</p>
        </div>
      )}

      <div className="absolute inset-x-0 top-0 flex items-center justify-between bg-gradient-to-b from-black/70 to-transparent px-4 pt-[calc(1rem+env(safe-area-inset-top))] pb-12">
        <button type="button" onClick={onClose} className="rounded-full bg-black/40 px-4 py-2 text-sm font-bold backdrop-blur">Close</button>
        <div className="flex rounded-full bg-black/40 p-1 backdrop-blur">
          {(['front', 'side', 'back'] as const).map((value) => <button key={value} type="button" onClick={() => setPose(value)} className={`rounded-full px-3 py-1.5 text-[10px] font-bold uppercase ${pose === value ? 'bg-white text-black' : 'text-white/70'}`}>{poseLabel(value)}</button>)}
        </div>
      </div>

      {!preview && !ready && !error && <div className="pointer-events-none absolute inset-0 grid place-items-center bg-black/30"><span className="rounded-full bg-black/45 px-4 py-2 text-xs font-bold backdrop-blur">Starting camera…</span></div>}
      {countdown != null && <div className="absolute inset-0 grid place-items-center bg-black/15 font-mono text-9xl font-bold drop-shadow-2xl">{countdown}</div>}
      {error && (
        <div className="absolute top-28 right-4 left-4 z-10 rounded-2xl bg-red-700/80 px-4 py-3 text-xs font-semibold backdrop-blur">
          <p>{error}</p>
          <button type="button" onClick={() => setRestartKey((value) => value + 1)} className="mt-2 rounded-lg bg-white/18 px-3 py-1.5 text-[10px] font-bold">Retry camera</button>
        </div>
      )}

      <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/90 via-black/55 to-transparent px-4 pt-20 pb-[calc(1rem+env(safe-area-inset-bottom))]">
        {preview ? (
          <div className="mx-auto flex max-w-md gap-3"><button type="button" onClick={retake} className="flex-1 rounded-2xl bg-white/15 px-5 py-4 font-bold backdrop-blur">Retake</button><button type="button" disabled={saving} onClick={() => void save()} className="flex-[1.4] rounded-2xl bg-emerald-500 px-5 py-4 font-bold disabled:opacity-50">{saving ? 'Saving privately…' : 'Save privately'}</button></div>
        ) : (
          <div className="mx-auto max-w-md space-y-3">
            <div className="flex items-center justify-between gap-2">
              <div className="flex rounded-full bg-black/40 p-1 backdrop-blur">{([3, 5, 10] as const).map((value) => <button key={value} type="button" onClick={() => setTimer(value)} className={`rounded-full px-3 py-1.5 text-[10px] font-bold ${timer === value ? 'bg-white text-black' : 'text-white/70'}`}>{value}s</button>)}</div>
              {referenceUrl && <label className="flex items-center gap-2 rounded-full bg-black/40 px-3 py-2 text-[10px] font-bold backdrop-blur">Ghost <input type="range" min="0" max="0.55" step="0.05" value={ghostOpacity} onChange={(event) => setGhostOpacity(Number(event.target.value))} className="w-16" /></label>}
              <button type="button" onClick={() => setFacing((value) => value === 'user' ? 'environment' : 'user')} className="rounded-full bg-black/40 px-3 py-2 text-[10px] font-bold backdrop-blur">Flip camera</button>
            </div>
            <div className="grid grid-cols-[4rem_1fr_4rem] items-center">
              <label className="cursor-pointer rounded-full bg-white/15 px-3 py-2 text-center text-[10px] font-bold backdrop-blur">Library<input type="file" accept="image/*" onChange={(event) => acceptLibrary(event.target.files?.[0])} className="sr-only" /></label>
              <button type="button" disabled={!ready} onClick={beginCountdown} className="mx-auto h-20 w-20 rounded-full border-4 border-white bg-white/20 active:scale-95 disabled:opacity-35" style={{ boxShadow: '0 0 0 2px rgba(255,255,255,0.4)' }} aria-label={`Take photo in ${timer} seconds`} />
              <span className="text-center font-mono text-[9px] font-bold text-white/65">{facing === 'user' ? 'FRONT' : 'REAR'}</span>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
