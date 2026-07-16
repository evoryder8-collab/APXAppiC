import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react'
import {
  comparisonAspectRatio,
  daysBetweenPhotos,
  formatProgressPhotoMoment,
  normalizeComparisonView,
  progressFramingMode,
  updateComparisonViews,
  zoomComparisonView,
  type ComparisonSide,
  type ComparisonViews,
  type ProgressPhoto,
} from '../../lib/progressPhoto'
import { createProgressComparisonPoster, type ProgressExportMode, type ProgressStrengthComparison } from '../../lib/progressComparison'
import { useLanguage } from '../../lib/i18n'

const IDENTITY = { scale: 1, x: 0, y: 0 }

const COPY = {
  en: {
    dialog: 'Photo comparison', private: 'Private comparison', before: 'BEFORE', after: 'AFTER', close: 'Close',
    synced: 'Synced', unlocked: 'Unlocked', drag: 'Drag to inspect. Synced moves both photos together; Unlocked edits the side you touch.',
    share: 'Shareable progress card', preserve: 'Your current zoom and positioning are preserved in the high-resolution PNG.', creating: 'Creating PNG…', export: 'Export PNG',
    mismatch: 'Different poses are selected. Matching poses produce a fairer comparison.', zoomOut: 'Zoom out', zoomIn: 'Zoom in', movement: 'Comparison movement mode',
    framingMismatch: 'Different framing modes are selected. Matching Full body, Torso or Free photos gives the cleanest comparison.',
    days: (value: number) => `${value} days apart`, workouts: (value: number) => `${value} completed workouts between`,
    loading: 'Photos are still loading.', failure: 'The image could not be exported. Let both photos finish loading and try again.',
  },
  ro: {
    dialog: 'Comparație foto', private: 'Comparație privată', before: 'ÎNAINTE', after: 'DUPĂ', close: 'Închide',
    synced: 'Sincronizat', unlocked: 'Independent', drag: 'Trage pentru detalii. Sincronizat mută ambele fotografii; Independent controlează separat partea atinsă.',
    share: 'Card de progres pentru distribuire', preserve: 'Zoomul și poziționarea actuală sunt păstrate în imaginea PNG de înaltă rezoluție.', creating: 'Se creează imaginea PNG…', export: 'Exportă PNG',
    mismatch: 'Ai selectat poziții diferite. Pozițiile identice oferă o comparație mai corectă.', zoomOut: 'Micșorează', zoomIn: 'Mărește', movement: 'Mod de deplasare a comparației',
    framingMismatch: 'Ai selectat încadrări diferite. Pentru cea mai clară comparație, combină două fotografii Corp întreg, Trunchi sau Liber.',
    days: (value: number) => `${value} zile între fotografii`, workouts: (value: number) => `${value} antrenamente finalizate între date`,
    loading: 'Fotografiile încă se încarcă.', failure: 'Imaginea nu a putut fi exportată. Așteaptă încărcarea fotografiilor și încearcă din nou.',
  },
  th: {
    dialog: 'เปรียบเทียบภาพ', private: 'การเปรียบเทียบส่วนตัว', before: 'ก่อน', after: 'หลัง', close: 'ปิด',
    synced: 'ซิงก์', unlocked: 'แยกอิสระ', drag: 'ลากเพื่อดูรายละเอียด ซิงก์จะขยับทั้งสองภาพพร้อมกัน ส่วนแยกอิสระจะควบคุมเฉพาะด้านที่แตะ',
    share: 'การ์ดความก้าวหน้าสำหรับแชร์', preserve: 'ระดับซูมและตำแหน่งปัจจุบันจะถูกเก็บไว้ในไฟล์ PNG ความละเอียดสูง', creating: 'กำลังสร้าง PNG…', export: 'ส่งออก PNG',
    mismatch: 'เลือกท่าต่างกัน การใช้ท่าเดียวกันจะเปรียบเทียบได้แม่นยำกว่า', zoomOut: 'ซูมออก', zoomIn: 'ซูมเข้า', movement: 'โหมดเลื่อนภาพเปรียบเทียบ',
    framingMismatch: 'เลือกกรอบภาพต่างกัน ควรใช้ภาพเต็มตัว ช่วงลำตัว หรืออิสระแบบเดียวกันเพื่อการเปรียบเทียบที่ชัดที่สุด',
    days: (value: number) => `ห่างกัน ${value} วัน`, workouts: (value: number) => `ฝึกเสร็จแล้ว ${value} ครั้งในช่วงนี้`,
    loading: 'รูปภาพกำลังโหลดอยู่', failure: 'ไม่สามารถส่งออกภาพได้ โปรดรอให้รูปโหลดเสร็จแล้วลองอีกครั้ง',
  },
} as const

interface DragState {
  side: ComparisonSide
  pointerId: number
  startX: number
  startY: number
  width: number
  height: number
  origin: ComparisonViews
}

function ComparisonPane({
  side,
  photo,
  view,
  active,
  url,
  onPointerDown,
  onPointerMove,
  onPointerUp,
}: {
  side: ComparisonSide
  photo: ProgressPhoto
  view: ComparisonViews[ComparisonSide]
  active: boolean
  url: string | undefined
  onPointerDown: (side: ComparisonSide, event: ReactPointerEvent<HTMLDivElement>) => void
  onPointerMove: (event: ReactPointerEvent<HTMLDivElement>) => void
  onPointerUp: (event: ReactPointerEvent<HTMLDivElement>) => void
}) {
  const { language } = useLanguage()
  const copy = COPY[language]
  const poseLabel = ({
    en: { front: 'Front', side: 'Side', back: 'Back' },
    ro: { front: 'Față', side: 'Profil', back: 'Spate' },
    th: { front: 'ด้านหน้า', side: 'ด้านข้าง', back: 'ด้านหลัง' },
  })[language][photo.pose]
  return (
    <div
      className={`relative h-full min-w-0 overflow-hidden bg-[#11131a] transition-shadow ${active ? 'shadow-[inset_0_0_0_1px_rgba(196,181,253,.9)]' : ''}`}
      style={{ touchAction: 'none' }}
      onPointerDown={(event) => onPointerDown(side, event)}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
    >
      {url ? (
        <img
          src={url}
          alt={`${photo.pose} progress from ${photo.local_date}`}
          draggable={false}
          className="pointer-events-none h-full w-full select-none object-cover will-change-transform"
          style={{
            objectPosition: `${photo.crop_x * 100}% ${photo.crop_y * 100}%`,
            transform: `translate3d(${view.x}%, ${view.y}%, 0) scale(${view.scale * photo.crop_scale})`,
            transformOrigin: 'center',
          }}
        />
      ) : <div className="skeleton h-full w-full bg-white/10" />}
      <div className={`pointer-events-none absolute inset-x-0 top-0 flex items-center bg-gradient-to-b from-black/70 to-transparent px-2 py-3 ${side === 'right' ? 'justify-end text-right' : ''}`}>
        <div><p className="font-mono text-[9px] font-bold tracking-wide text-white">{side === 'left' ? copy.before : copy.after}</p><p className="mt-0.5 font-mono text-[8px] text-white/75">{formatProgressPhotoMoment(photo, language)} · {poseLabel}</p></div>
      </div>
    </div>
  )
}

export function PhotoComparison({
  left,
  right,
  workoutCount,
  strengthComparison,
  athleteName,
  exportMode,
  photoUrls,
  fullPhotoUrls,
  ensurePhotoUrl,
  onClose,
}: {
  left: ProgressPhoto
  right: ProgressPhoto
  workoutCount: number
  strengthComparison: ProgressStrengthComparison
  athleteName: string
  exportMode: ProgressExportMode
  photoUrls: Record<string, string>
  fullPhotoUrls: Record<string, string>
  ensurePhotoUrl: (photo: ProgressPhoto) => Promise<unknown>
  onClose: () => void
}) {
  const { language } = useLanguage()
  const copy = COPY[language]
  const [synced, setSynced] = useState(true)
  const [active, setActive] = useState<ComparisonSide>('left')
  const [views, setViews] = useState<ComparisonViews>({ left: IDENTITY, right: IDENTITY })
  const [exporting, setExporting] = useState(false)
  const [exportError, setExportError] = useState<string | null>(null)
  const dragRef = useRef<DragState | null>(null)
  useEffect(() => {
    if (!fullPhotoUrls[left.id]) void ensurePhotoUrl(left)
    if (!fullPhotoUrls[right.id]) void ensurePhotoUrl(right)
  }, [ensurePhotoUrl, fullPhotoUrls, left, right])

  const changeView = (side: ComparisonSide, view: ComparisonViews[ComparisonSide]) => {
    setViews((current) => updateComparisonViews(current, side, view, synced))
  }

  const zoom = (delta: number) => changeView(active, zoomComparisonView(views[active], delta))

  const reset = () => setViews({ left: IDENTITY, right: IDENTITY })

  const setLinkMode = (nextSynced: boolean) => {
    setSynced(nextSynced)
    if (nextSynced) {
      const source = normalizeComparisonView(views[active])
      setViews({ left: source, right: source })
    }
  }

  const pointerDown = (side: ComparisonSide, event: ReactPointerEvent<HTMLDivElement>) => {
    setActive(side)
    event.currentTarget.setPointerCapture(event.pointerId)
    const rect = event.currentTarget.getBoundingClientRect()
    dragRef.current = {
      side,
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      width: Math.max(1, rect.width),
      height: Math.max(1, rect.height),
      origin: views,
    }
  }

  const pointerMove = (event: ReactPointerEvent<HTMLDivElement>) => {
    const drag = dragRef.current
    if (!drag || drag.pointerId !== event.pointerId) return
    const origin = drag.origin[drag.side]
    const next = normalizeComparisonView({
      ...origin,
      x: origin.x + ((event.clientX - drag.startX) / drag.width) * 100,
      y: origin.y + ((event.clientY - drag.startY) / drag.height) * 100,
    })
    setViews(updateComparisonViews(drag.origin, drag.side, next, synced))
  }

  const pointerUp = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (dragRef.current?.pointerId === event.pointerId) dragRef.current = null
  }

  const baseCombinedRatio = Math.max(0.8, Math.min(1.55, comparisonAspectRatio(left, right) * 2))
  const leftFraming = progressFramingMode(left)
  const rightFraming = progressFramingMode(right)
  const torsoComparison = leftFraming === 'torso' && rightFraming === 'torso'
  const combinedRatio = torsoComparison ? Math.min(1.55, baseCombinedRatio * 1.18) : baseCombinedRatio
  const loadSignal = strengthComparison.averageLoadDeltaKg
  const loadSummary = loadSignal == null
    ? null
    : language === 'ro'
      ? `Greutatea medie pe set ${loadSignal >= 0 ? 'a crescut' : 'a scăzut'} cu ${Math.abs(loadSignal)} kg în ${strengthComparison.matchedExercises} exerciții comparate.`
      : language === 'th'
        ? `น้ำหนักเฉลี่ยต่อเซต${loadSignal >= 0 ? 'เพิ่มขึ้น' : 'ลดลง'} ${Math.abs(loadSignal)} กก. จาก ${strengthComparison.matchedExercises} ท่าที่เปรียบเทียบ`
        : `Average working-set load ${loadSignal >= 0 ? 'rose' : 'fell'} ${Math.abs(loadSignal)} kg across ${strengthComparison.matchedExercises} matched exercises.`

  const exportCard = async () => {
    setExporting(true)
    setExportError(null)
    try {
      const leftUrl = fullPhotoUrls[left.id]
      const rightUrl = fullPhotoUrls[right.id]
      if (!leftUrl || !rightUrl) throw new Error(copy.loading)
      const blob = await createProgressComparisonPoster({
        left,
        right,
        leftUrl,
        rightUrl,
        views,
        athleteName,
        language,
        mode: exportMode,
        stats: { days: daysBetweenPhotos(left, right), workouts: workoutCount, ...strengthComparison },
      })
      const url = URL.createObjectURL(blob)
      const anchor = document.createElement('a')
      anchor.href = url
      anchor.download = `apex-progress-${left.local_date}-${right.local_date}.png`
      anchor.click()
      window.setTimeout(() => URL.revokeObjectURL(url), 1000)
    } catch {
      setExportError(copy.failure)
    } finally {
      setExporting(false)
    }
  }

  return (
    <div data-no-translate className="fixed inset-0 z-[100] flex flex-col overflow-y-auto bg-[#07080d] text-white" role="dialog" aria-modal="true" aria-label={copy.dialog}>
      <header className="flex items-center justify-between gap-3 px-4 pt-[calc(1rem+env(safe-area-inset-top))] pb-3">
        <div>
          <p className="font-mono text-[9px] font-bold tracking-[0.18em] text-violet-200 uppercase">{copy.private}</p>
          <h2 className="mt-1 font-display text-lg font-bold">{copy.days(daysBetweenPhotos(left, right))}</h2>
          <p className="text-[10px] text-white/55">{copy.workouts(workoutCount)}</p>
          {loadSummary && <p className="mt-1 max-w-sm text-[9px] leading-relaxed font-semibold text-emerald-200/70">{loadSummary}</p>}
        </div>
        <button type="button" onClick={onClose} className="rounded-full bg-white/10 px-4 py-2 text-sm font-bold backdrop-blur">{copy.close}</button>
      </header>

      {left.pose !== right.pose && <p className="mx-4 mb-3 rounded-xl bg-amber-300/10 px-3 py-2 text-[10px] font-semibold text-amber-100">{copy.mismatch}</p>}
      {leftFraming !== rightFraming && <p className="mx-4 mb-3 rounded-xl bg-violet-300/10 px-3 py-2 text-[10px] font-semibold text-violet-100">{copy.framingMismatch}</p>}

      <div className="flex min-h-0 flex-1 items-center justify-center px-2 sm:px-4">
        <div className="relative w-full max-w-3xl overflow-hidden rounded-[1.75rem] border border-white/10 bg-[#11131a] shadow-2xl" style={{ aspectRatio: combinedRatio }}>
          <div className="grid h-full grid-cols-2 gap-px bg-violet-200/70">
            <ComparisonPane side="left" photo={left} url={photoUrls[left.id]} view={views.left} active={!synced && active === 'left'} onPointerDown={pointerDown} onPointerMove={pointerMove} onPointerUp={pointerUp} />
            <ComparisonPane side="right" photo={right} url={photoUrls[right.id]} view={views.right} active={!synced && active === 'right'} onPointerDown={pointerDown} onPointerMove={pointerMove} onPointerUp={pointerUp} />
          </div>
          <div className="pointer-events-none absolute inset-y-0 left-1/2 w-px -translate-x-1/2 bg-white/85 shadow-[0_0_10px_rgba(196,181,253,.85)]" />
        </div>
      </div>

      <div className="mx-auto w-full max-w-xl px-4 pt-4 pb-[calc(1rem+env(safe-area-inset-bottom))]">
        <div className="flex items-center justify-between gap-3 rounded-3xl border border-white/10 bg-white/[0.07] p-2 backdrop-blur-xl">
          <div className="flex items-center gap-1">
            <button type="button" onClick={() => zoom(-0.25)} disabled={views[active].scale <= 1} className="grid h-11 w-11 place-items-center rounded-2xl bg-white/10 text-2xl font-light disabled:opacity-30" aria-label={copy.zoomOut}>−</button>
            <button type="button" onClick={reset} className="min-w-16 rounded-2xl px-2 py-3 font-mono text-[10px] font-bold text-white/75">{Math.round(views[active].scale * 100)}%</button>
            <button type="button" onClick={() => zoom(0.25)} disabled={views[active].scale >= 4} className="grid h-11 w-11 place-items-center rounded-2xl bg-white/10 text-2xl font-light disabled:opacity-30" aria-label={copy.zoomIn}>+</button>
          </div>
          <div className="flex rounded-2xl bg-black/25 p-1" aria-label={copy.movement}>
            <button type="button" onClick={() => setLinkMode(true)} aria-pressed={synced} className={`rounded-xl px-3 py-2 text-[9px] font-bold uppercase ${synced ? 'bg-violet-500 text-white' : 'text-white/55'}`}>{copy.synced}</button>
            <button type="button" onClick={() => setLinkMode(false)} aria-pressed={!synced} className={`rounded-xl px-3 py-2 text-[9px] font-bold uppercase ${!synced ? 'bg-violet-500 text-white' : 'text-white/55'}`}>{copy.unlocked}</button>
          </div>
        </div>
        <p className="mt-2 text-center text-[9px] font-medium text-white/45">{copy.drag}</p>
        <div className="mt-3 flex items-center justify-between gap-3 rounded-3xl border border-violet-300/15 bg-[radial-gradient(circle_at_0%_0%,rgba(139,92,246,.28),transparent_48%),rgba(255,255,255,.07)] p-3 backdrop-blur-xl">
          <div className="min-w-0"><p className="font-mono text-[8px] font-black tracking-[0.16em] text-violet-200/70 uppercase">{copy.share}</p><p className="mt-1 text-[9px] leading-relaxed text-white/48">{copy.preserve}</p></div>
          <button type="button" disabled={exporting || !fullPhotoUrls[left.id] || !fullPhotoUrls[right.id]} onClick={() => void exportCard()} className="shrink-0 rounded-2xl bg-gradient-to-r from-violet-500 via-fuchsia-400 to-cyan-400 px-4 py-3 text-xs font-black text-[#07080d] shadow-[0_14px_32px_-18px_rgba(167,139,250,.95)] disabled:opacity-45">{exporting ? copy.creating : copy.export}</button>
        </div>
        {exportError && <p role="alert" className="mt-2 rounded-xl bg-red-400/10 px-3 py-2 text-center text-[9px] font-semibold text-red-100">{exportError}</p>}
      </div>
    </div>
  )
}
