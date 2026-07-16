import { useCallback, useEffect, useRef, useState } from 'react'
import { releaseProgressCamera } from '../../lib/mediaCapture'
import {
  coverCrop,
  isProgressCameraShutterKey,
  processProgressPhoto,
  progressCaptureAspectRatio,
  progressPhotoSaveError,
  type ProcessedProgressPhoto,
  type ProgressFramingMode,
  type ProgressPose,
} from '../../lib/progressPhoto'
import { useLanguage } from '../../lib/i18n'

type CameraFacing = 'user' | 'environment'
type CameraPrivacyState = 'released' | 'requesting' | 'live'

function capturePageIsHidden(): boolean {
  return document.visibilityState === 'hidden'
}

export function ProgressCamera({
  initialPose,
  initialFramingMode,
  referenceUrl,
  onSave,
  onClose,
}: {
  initialPose: ProgressPose
  initialFramingMode: ProgressFramingMode
  referenceUrl?: string | null
  onSave: (blob: Blob, pose: ProgressPose, framingMode: ProgressFramingMode, processed?: ProcessedProgressPhoto) => Promise<void>
  onClose: () => void
}) {
  const { language } = useLanguage()
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const streamRequestRef = useRef(0)
  const countdownRef = useRef<number | null>(null)
  const libraryInputRef = useRef<HTMLInputElement>(null)
  const libraryRequestRef = useRef(0)
  const processedCaptureRef = useRef<ProcessedProgressPhoto | null>(null)
  const previewRef = useRef<string | null>(null)
  const importingRef = useRef(false)
  const suspendedRef = useRef(false)
  const [pose, setPose] = useState<ProgressPose>(initialPose)
  const [framingMode, setFramingMode] = useState<ProgressFramingMode>(initialFramingMode)
  const [facing, setFacing] = useState<CameraFacing>('user')
  const [restartKey, setRestartKey] = useState(0)
  const [ready, setReady] = useState(false)
  const [cameraPrivacyState, setCameraPrivacyState] = useState<CameraPrivacyState>('released')
  const [timer, setTimer] = useState<3 | 5 | 10>(5)
  const [countdown, setCountdown] = useState<number | null>(null)
  const [captured, setCaptured] = useState<Blob | null>(null)
  const [preview, setPreview] = useState<string | null>(null)
  const [ghostOpacity, setGhostOpacity] = useState(referenceUrl ? 0.25 : 0)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [importing, setImporting] = useState(false)
  previewRef.current = preview
  importingRef.current = importing
  const poseLabel = (value: ProgressPose): string => ({
    en: { front: 'Front', side: 'Side', back: 'Back' },
    ro: { front: 'Față', side: 'Profil', back: 'Spate' },
    th: { front: 'ด้านหน้า', side: 'ด้านข้าง', back: 'ด้านหลัง' },
  })[language][value]
  const framingLabel = (value: ProgressFramingMode): string => ({
    en: { full: 'Full body', torso: 'Torso', free: 'Free' },
    ro: { full: 'Corp întreg', torso: 'Trunchi', free: 'Liber' },
    th: { full: 'เต็มตัว', torso: 'ช่วงลำตัว', free: 'อิสระ' },
  })[language][value]
  const privacyCopy = ({
    en: { requesting: 'STARTING CAMERA · MICROPHONE OFF', live: 'CAMERA ONLY · MICROPHONE OFF', released: 'CAMERA RELEASED' },
    ro: { requesting: 'SE PORNEȘTE CAMERA · MICROFON OPRIT', live: 'DOAR CAMERA · MICROFON OPRIT', released: 'CAMERA OPRITĂ' },
    th: { requesting: 'กำลังเปิดกล้อง · ปิดไมโครโฟน', live: 'กล้องเท่านั้น · ปิดไมโครโฟน', released: 'ปิดกล้องแล้ว' },
  })[language]

  const stop = useCallback(() => {
    streamRequestRef.current += 1
    if (countdownRef.current != null) window.clearInterval(countdownRef.current)
    countdownRef.current = null
    releaseProgressCamera(streamRef.current, videoRef.current)
    streamRef.current = null
    setCameraPrivacyState('released')
  }, [])

  useEffect(() => {
    let cancelled = false
    const connect = async () => {
      stop()
      const requestId = streamRequestRef.current
      setReady(false)
      setError(null)
      if (capturePageIsHidden()) return
      if (!navigator.mediaDevices?.getUserMedia) {
        setError('Live camera is unavailable in this browser. Choose a photo from your library instead.')
        return
      }
      setCameraPrivacyState('requesting')
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
          if (cancelled || requestId !== streamRequestRef.current || capturePageIsHidden()) return
          stream = await navigator.mediaDevices.getUserMedia({ audio: false, video: true })
        }
        if (cancelled || requestId !== streamRequestRef.current || capturePageIsHidden()) {
          releaseProgressCamera(stream, null)
          return
        }
        streamRef.current = stream
        const video = videoRef.current
        if (!video) {
          releaseProgressCamera(stream, null)
          streamRef.current = null
          return
        }
        video.srcObject = stream
        video.muted = true
        if (video.readyState < 1) {
          await new Promise<void>((resolve) => video.addEventListener('loadedmetadata', () => resolve(), { once: true }))
        }
        await video.play()
        if (cancelled || requestId !== streamRequestRef.current || capturePageIsHidden()) {
          stop()
          return
        }
        setReady(true)
        setCameraPrivacyState('live')
      } catch (cause) {
        if (cancelled) return
        const stale = requestId !== streamRequestRef.current || capturePageIsHidden()
        stop()
        if (stale) return
        const name = cause instanceof DOMException ? cause.name : ''
        setError(name === 'NotAllowedError' || name === 'SecurityError'
          ? 'Camera access is blocked. Allow camera access in Safari settings, then tap Retry, or choose a photo from your library.'
          : 'The camera could not start. Tap Retry or choose a photo from your library.')
      }
    }
    void connect()
    return () => { cancelled = true; stop() }
  }, [facing, restartKey, stop])

  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview) }, [preview])
  useEffect(() => () => { libraryRequestRef.current += 1 }, [])

  useEffect(() => {
    const suspend = () => {
      suspendedRef.current = true
      stop()
      setReady(false)
      setCountdown(null)
    }
    const resume = () => {
      if (!suspendedRef.current || document.visibilityState === 'hidden') return
      suspendedRef.current = false
      if (!previewRef.current && !importingRef.current) {
        setRestartKey((value) => value + 1)
      }
    }
    const visibility = () => {
      if (document.visibilityState === 'hidden') suspend()
      else resume()
    }
    window.addEventListener('pagehide', suspend)
    window.addEventListener('pageshow', resume)
    document.addEventListener('visibilitychange', visibility)
    return () => {
      window.removeEventListener('pagehide', suspend)
      window.removeEventListener('pageshow', resume)
      document.removeEventListener('visibilitychange', visibility)
      stop()
    }
  }, [stop])

  const captureFrame = useCallback(async () => {
    const video = videoRef.current
    if (!video?.videoWidth || !video.videoHeight) {
      setError('The camera is still focusing. Try the shutter again in a moment.')
      return
    }
    const previewRatio = video.clientWidth > 0 && video.clientHeight > 0
      ? video.clientWidth / video.clientHeight
      : 2 / 3
    const captureRatio = progressCaptureAspectRatio(framingMode, previewRatio)
    const crop = coverCrop(video.videoWidth, video.videoHeight, captureRatio)
    const canvas = document.createElement('canvas')
    canvas.width = Math.max(1, Math.min(1440, Math.round(crop.width)))
    canvas.height = Math.max(1, Math.round(canvas.width / captureRatio))
    const context = canvas.getContext('2d', { alpha: false })
    if (!context) {
      stop()
      setReady(false)
      setError('The photo could not be captured. Tap Retry camera and try again.')
      return
    }
    let blob: Blob | null = null
    try {
      if (facing === 'user') {
        context.translate(canvas.width, 0)
        context.scale(-1, 1)
      }
      context.drawImage(video, crop.sx, crop.sy, crop.width, crop.height, 0, 0, canvas.width, canvas.height)
      const encoded = new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.94))
      // drawImage has copied the frame synchronously, so the physical camera
      // is no longer needed while JPEG encoding finishes.
      stop()
      setReady(false)
      blob = await encoded
    } catch {
      stop()
      setReady(false)
    }
    if (!blob) {
      setError('The photo could not be captured. Tap Retry camera and try again.')
      return
    }
    if (preview) URL.revokeObjectURL(preview)
    const url = URL.createObjectURL(blob)
    processedCaptureRef.current = null
    setCaptured(blob)
    setPreview(url)
    navigator.vibrate?.(40)
  }, [facing, framingMode, preview, stop])

  const beginCountdown = useCallback(() => {
    if (countdown != null || !ready || importing) return
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
  }, [captureFrame, countdown, importing, ready, timer])

  useEffect(() => {
    const volumeShutter = (event: KeyboardEvent) => {
      if (preview || !isProgressCameraShutterKey(event.key, event.code)) return
      event.preventDefault()
      beginCountdown()
    }
    window.addEventListener('keydown', volumeShutter)
    return () => window.removeEventListener('keydown', volumeShutter)
  }, [beginCountdown, preview])

  const acceptLibrary = async (file: File | undefined) => {
    if (!file) return
    if (countdownRef.current != null) window.clearInterval(countdownRef.current)
    countdownRef.current = null
    setCountdown(null)
    const requestId = ++libraryRequestRef.current
    setImporting(true)
    setError(null)
    stop()
    setReady(false)
    try {
      // Decode and re-encode gallery photos before review. This applies EXIF
      // orientation, strips GPS metadata, handles iPhone image dimensions and
      // guarantees the same upload formats used by live camera captures.
      const processed = await processProgressPhoto(file)
      if (requestId !== libraryRequestRef.current) return
      if (preview) URL.revokeObjectURL(preview)
      processedCaptureRef.current = processed
      setCaptured(processed.full)
      setPreview(URL.createObjectURL(processed.full))
    } catch (cause) {
      if (requestId !== libraryRequestRef.current) return
      processedCaptureRef.current = null
      setCaptured(null)
      setPreview(null)
      setError(progressPhotoSaveError(cause).message)
    } finally {
      if (requestId === libraryRequestRef.current) setImporting(false)
      if (libraryInputRef.current) libraryInputRef.current.value = ''
    }
  }

  const retake = () => {
    const hadPreview = Boolean(preview)
    if (preview) URL.revokeObjectURL(preview)
    setPreview(null)
    setCaptured(null)
    processedCaptureRef.current = null
    setError(null)
    if (hadPreview) setRestartKey((value) => value + 1)
  }

  const closeCamera = () => {
    stop()
    setReady(false)
    onClose()
  }

  const save = async () => {
    if (!captured) return
    setSaving(true)
    setError(null)
    try {
      await onSave(captured, pose, framingMode, processedCaptureRef.current ?? undefined)
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

      {!preview && framingMode === 'full' && (
        <div className="pointer-events-none absolute inset-x-0 top-[calc(max(0.75rem,env(safe-area-inset-top))+6.75rem)] bottom-[calc(max(0.75rem,env(safe-area-inset-bottom))+9.25rem)] flex items-center justify-center" aria-hidden>
          <svg viewBox="0 0 240 560" fill="none" className="h-full max-h-[64dvh] w-auto max-w-[70vw] overflow-visible drop-shadow-[0_0_16px_rgba(0,0,0,0.45)]">
            <circle cx="120" cy="48" r="28" stroke="rgba(255,255,255,.9)" strokeWidth="2" />
            <path d="M91 92c-27 8-44 26-47 57l-8 109M149 92c27 8 44 26 47 57l8 109M91 92c5 38 2 94-11 151l-10 71M149 92c-5 38-2 94 11 151l10 71M80 243c10 10 25 15 40 15s30-5 40-15M80 314l-16 187M160 314l16 187M64 501l-18 24M176 501l18 24" stroke="rgba(255,255,255,.88)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            <path d="M120 84v423" stroke="rgba(196,181,253,.42)" strokeWidth="1" strokeDasharray="5 8" />
            <path d="M28 525h184" stroke="rgba(253,230,138,.95)" strokeWidth="2" strokeDasharray="7 7" />
          </svg>
          <p className="absolute bottom-0 left-1/2 -translate-x-1/2 whitespace-nowrap rounded-full bg-black/35 px-3 py-1.5 font-mono text-[8px] font-bold tracking-[0.12em] text-amber-100 uppercase backdrop-blur">Head and feet inside the guide</p>
        </div>
      )}

      {!preview && framingMode === 'torso' && (
        <div className="pointer-events-none absolute inset-x-0 top-[calc(max(0.75rem,env(safe-area-inset-top))+8rem)] bottom-[calc(max(0.75rem,env(safe-area-inset-bottom))+10rem)] flex items-center justify-center" aria-hidden>
          <svg viewBox="0 0 340 430" fill="none" className="h-auto max-h-[56dvh] w-[82vw] max-w-[390px] overflow-visible drop-shadow-[0_0_18px_rgba(0,0,0,0.5)]">
            <circle cx="170" cy="58" r="42" stroke="rgba(255,255,255,.92)" strokeWidth="2.5" />
            <path d="M122 126c-45 9-76 34-89 75L18 292M218 126c45 9 76 34 89 75l15 91M122 126c7 52 2 116-18 188M218 126c-7 52-2 116 18 188M104 314c21 14 43 20 66 20s45-6 66-20" stroke="rgba(255,255,255,.9)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
            <path d="M170 102v244" stroke="rgba(196,181,253,.48)" strokeWidth="1.5" strokeDasharray="6 9" />
            <rect x="20" y="12" width="300" height="370" rx="54" stroke="rgba(253,230,138,.78)" strokeWidth="1.5" strokeDasharray="8 10" />
          </svg>
          <p className="absolute bottom-0 left-1/2 -translate-x-1/2 whitespace-nowrap rounded-full bg-black/35 px-3 py-1.5 font-mono text-[8px] font-bold tracking-[0.12em] text-amber-100 uppercase backdrop-blur">Head, shoulders and waist inside the guide</p>
        </div>
      )}

      <div className="absolute inset-x-0 top-0 flex items-center justify-between bg-gradient-to-b from-black/70 to-transparent px-4 pt-[calc(1rem+env(safe-area-inset-top))] pb-12">
        <button type="button" onClick={closeCamera} className="rounded-full bg-black/40 px-4 py-2 text-sm font-bold backdrop-blur">Close</button>
        <div className="flex rounded-full bg-black/40 p-1 backdrop-blur">
          {(['front', 'side', 'back'] as const).map((value) => <button key={value} type="button" onClick={() => setPose(value)} className={`rounded-full px-3 py-1.5 text-[10px] font-bold uppercase ${pose === value ? 'bg-white text-black' : 'text-white/70'}`}>{poseLabel(value)}</button>)}
        </div>
      </div>
      {!preview && (
        <div className="absolute inset-x-0 top-[calc(4.25rem+env(safe-area-inset-top))] flex justify-center px-4">
          <div className="flex rounded-full bg-black/45 p-1 backdrop-blur-xl" aria-label="Progress photo framing">
            {(['full', 'torso', 'free'] as const).map((value) => <button key={value} type="button" onClick={() => setFramingMode(value)} aria-pressed={framingMode === value} className={`rounded-full px-3 py-1.5 text-[9px] font-bold uppercase ${framingMode === value ? 'bg-violet-200 text-[#11121a]' : 'text-white/70'}`}>{framingLabel(value)}</button>)}
          </div>
        </div>
      )}

      {!preview && !ready && !error && <div className="pointer-events-none absolute inset-0 grid place-items-center bg-black/30"><span className="rounded-full bg-black/45 px-4 py-2 text-xs font-bold backdrop-blur">Starting camera…</span></div>}
      {countdown != null && <div className="absolute inset-0 grid place-items-center bg-black/15 font-mono text-9xl font-bold drop-shadow-2xl">{countdown}</div>}
      {error && (
        <div className="absolute top-28 right-4 left-4 z-10 rounded-2xl bg-red-700/80 px-4 py-3 text-xs font-semibold backdrop-blur">
          <p>{error}</p>
          {!preview && !ready && <button type="button" onClick={() => setRestartKey((value) => value + 1)} className="mt-2 rounded-lg bg-white/18 px-3 py-1.5 text-[10px] font-bold">Retry camera</button>}
        </div>
      )}

      <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/90 via-black/55 to-transparent px-4 pt-20 pb-[calc(1rem+env(safe-area-inset-bottom))]">
        {preview ? (
          <div className="mx-auto max-w-md"><div className="flex gap-3"><button type="button" onClick={retake} className="flex-1 rounded-2xl bg-white/15 px-5 py-4 font-bold backdrop-blur">Retake</button><button type="button" disabled={saving} onClick={() => void save()} className="flex-[1.4] rounded-2xl bg-emerald-500 px-5 py-4 font-bold disabled:opacity-50">{saving ? 'Saving privately…' : 'Save privately'}</button></div><p className="mt-2 text-center font-mono text-[8px] font-bold tracking-[0.1em] text-white/60" aria-live="polite">{privacyCopy.released}</p></div>
        ) : (
          <div className="mx-auto max-w-md space-y-3">
            <div className="flex items-center justify-between gap-2">
              <div className="flex rounded-full bg-black/40 p-1 backdrop-blur">{([3, 5, 10] as const).map((value) => <button key={value} type="button" onClick={() => setTimer(value)} className={`rounded-full px-3 py-1.5 text-[10px] font-bold ${timer === value ? 'bg-white text-black' : 'text-white/70'}`}>{value}s</button>)}</div>
              {referenceUrl && <label className="flex items-center gap-2 rounded-full bg-black/40 px-3 py-2 text-[10px] font-bold backdrop-blur">Ghost <input type="range" min="0" max="0.55" step="0.05" value={ghostOpacity} onChange={(event) => setGhostOpacity(Number(event.target.value))} className="w-16" /></label>}
              <button type="button" onClick={() => setFacing((value) => value === 'user' ? 'environment' : 'user')} className="rounded-full bg-black/40 px-3 py-2 text-[10px] font-bold backdrop-blur">Flip camera</button>
            </div>
            <p className="text-center font-mono text-[8px] font-bold tracking-[0.1em] text-emerald-100/80" aria-live="polite">{privacyCopy[cameraPrivacyState]}</p>
            <div className="grid grid-cols-[4rem_1fr_4rem] items-center">
              <label className={`rounded-full bg-white/15 px-3 py-2 text-center text-[10px] font-bold backdrop-blur ${importing ? 'cursor-wait opacity-60' : 'cursor-pointer'}`}>{importing ? 'Preparing…' : 'Library'}<input ref={libraryInputRef} type="file" accept="image/jpeg,image/png,image/webp,image/heic,image/heif" disabled={importing} onChange={(event) => { void acceptLibrary(event.target.files?.[0]) }} className="sr-only" /></label>
              <button type="button" disabled={!ready || importing} onClick={beginCountdown} className="mx-auto h-20 w-20 rounded-full border-4 border-white bg-white/20 active:scale-95 disabled:opacity-35" style={{ boxShadow: '0 0 0 2px rgba(255,255,255,0.4)' }} aria-label={`Take photo in ${timer} seconds`} />
              <span className="text-center font-mono text-[9px] font-bold text-white/65">{facing === 'user' ? 'FRONT' : 'REAR'}</span>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
