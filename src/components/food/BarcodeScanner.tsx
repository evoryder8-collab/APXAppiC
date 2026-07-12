import { useEffect, useRef, useState } from 'react'
import type { IScannerControls } from '@zxing/browser'
import { normalizeBarcode } from '../../../shared/openFoodFacts'

export function BarcodeScanner({
  onDetected,
  onClose,
}: {
  onDetected: (barcode: string) => void
  onClose: () => void
}) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const controlsRef = useRef<IScannerControls | null>(null)
  const lastCode = useRef<{ value: string; at: number } | null>(null)
  const [devices, setDevices] = useState<MediaDeviceInfo[]>([])
  const [deviceIndex, setDeviceIndex] = useState(0)
  const [error, setError] = useState<string | null>(null)
  const [manual, setManual] = useState('')
  const [starting, setStarting] = useState(true)

  useEffect(() => {
    let cancelled = false
    const start = async () => {
      controlsRef.current?.stop()
      setStarting(true)
      setError(null)
      try {
        const { BrowserMultiFormatReader, BrowserCodeReader } = await import('@zxing/browser')
        const available = await BrowserCodeReader.listVideoInputDevices().catch(() => [])
        if (!cancelled) setDevices(available)
        const selected = available[deviceIndex]?.deviceId
        const reader = new BrowserMultiFormatReader()
        const constraints: MediaStreamConstraints = {
          audio: false,
          video: selected
            ? { deviceId: { exact: selected }, width: { ideal: 1280 }, height: { ideal: 720 } }
            : { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } },
        }
        const controls = await reader.decodeFromConstraints(constraints, videoRef.current!, (result) => {
          if (!result || cancelled) return
          const normalized = normalizeBarcode(result.getText())
          const now = Date.now()
          if (!normalized || (lastCode.current?.value === normalized && now - lastCode.current.at < 1800)) return
          lastCode.current = { value: normalized, at: now }
          navigator.vibrate?.(35)
          onDetected(normalized)
        })
        if (cancelled) controls.stop()
        else controlsRef.current = controls
      } catch (cause) {
        if (!cancelled) {
          const name = cause instanceof DOMException ? cause.name : ''
          setError(name === 'NotAllowedError'
            ? 'Camera access is blocked. Allow camera access in Safari settings, or enter the barcode below.'
            : 'The scanner could not start. You can still enter the barcode manually.')
        }
      } finally {
        if (!cancelled) setStarting(false)
      }
    }
    void start()
    return () => {
      cancelled = true
      controlsRef.current?.stop()
      controlsRef.current = null
    }
  }, [deviceIndex, onDetected])

  const submitManual = () => {
    const barcode = normalizeBarcode(manual)
    if (!barcode) {
      setError('Enter a valid EAN-8, UPC-A, or EAN-13 barcode.')
      return
    }
    onDetected(barcode)
  }

  return (
    <div className="fixed inset-0 z-[90] flex flex-col bg-[#101016] text-white" role="dialog" aria-modal="true" aria-label="Barcode scanner">
      <div className="flex items-center justify-between px-5 pt-[calc(1rem+env(safe-area-inset-top))] pb-3">
        <div>
          <p className="font-mono text-[10px] tracking-[0.2em] text-white/55 uppercase">Food lookup</p>
          <h2 className="font-display text-xl font-bold">Scan barcode</h2>
        </div>
        <button type="button" onClick={onClose} className="rounded-full bg-white/12 px-4 py-2 text-sm font-bold">Close</button>
      </div>

      <div className="relative mx-4 min-h-0 flex-1 overflow-hidden rounded-3xl bg-black">
        <video ref={videoRef} className="h-full w-full object-cover" muted playsInline />
        <div className="pointer-events-none absolute inset-x-[9%] inset-y-[14%] rounded-3xl border-2 border-amber-300/90" style={{ boxShadow: '0 0 0 999px rgba(0,0,0,0.26), 0 0 40px rgba(245,158,11,0.25)' }}>
          <span className="absolute top-1/2 right-5 left-5 h-px bg-amber-300/80" style={{ boxShadow: '0 0 12px #fbbf24' }} />
        </div>
        {starting && <div className="absolute inset-0 grid place-items-center bg-black/45 text-sm font-bold">Starting rear camera…</div>}
      </div>

      <div className="space-y-3 px-5 pt-4 pb-[calc(1rem+env(safe-area-inset-bottom))]">
        <p className="text-center text-xs text-white/65">Hold the barcode inside the amber frame. APEX only sends the number, never your camera image.</p>
        {devices.length > 1 && (
          <button type="button" onClick={() => setDeviceIndex((value) => (value + 1) % devices.length)} className="mx-auto block rounded-full bg-white/10 px-4 py-2 text-xs font-bold">
            Switch camera
          </button>
        )}
        {error && <p className="rounded-xl bg-red-500/15 px-3 py-2 text-xs font-semibold text-red-100">{error}</p>}
        <div className="flex gap-2">
          <input
            inputMode="numeric"
            value={manual}
            onChange={(event) => setManual(event.target.value)}
            onKeyDown={(event) => event.key === 'Enter' && submitManual()}
            placeholder="Enter barcode manually"
            className="min-w-0 flex-1 rounded-2xl border border-white/15 bg-white/10 px-4 py-3 font-mono text-sm outline-none placeholder:text-white/35"
          />
          <button type="button" onClick={submitManual} className="rounded-2xl bg-amber-500 px-4 py-3 text-sm font-bold text-white">Look up</button>
        </div>
      </div>
    </div>
  )
}
