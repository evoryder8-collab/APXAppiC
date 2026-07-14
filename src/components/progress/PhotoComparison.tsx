import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react'
import {
  comparisonAspectRatio,
  daysBetweenPhotos,
  normalizeComparisonView,
  updateComparisonViews,
  zoomComparisonView,
  type ComparisonSide,
  type ComparisonViews,
  type ProgressPhoto,
} from '../../lib/progressPhoto'

const IDENTITY = { scale: 1, x: 0, y: 0 }

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
      <div className={`pointer-events-none absolute inset-x-0 top-0 flex items-center bg-gradient-to-b from-black/65 to-transparent px-2 py-3 ${side === 'right' ? 'justify-end text-right' : ''}`}>
        <div><p className="font-mono text-[9px] font-bold tracking-wide text-white">{side === 'left' ? 'BEFORE' : 'AFTER'}</p><p className="mt-0.5 font-mono text-[8px] text-white/70">{photo.local_date} · {photo.pose}</p></div>
      </div>
    </div>
  )
}

export function PhotoComparison({
  left,
  right,
  workoutCount,
  photoUrls,
  ensurePhotoUrl,
  onClose,
}: {
  left: ProgressPhoto
  right: ProgressPhoto
  workoutCount: number
  photoUrls: Record<string, string>
  ensurePhotoUrl: (photo: ProgressPhoto) => Promise<unknown>
  onClose: () => void
}) {
  const [synced, setSynced] = useState(true)
  const [active, setActive] = useState<ComparisonSide>('left')
  const [views, setViews] = useState<ComparisonViews>({ left: IDENTITY, right: IDENTITY })
  const dragRef = useRef<DragState | null>(null)
  useEffect(() => {
    if (!photoUrls[left.id]) void ensurePhotoUrl(left)
    if (!photoUrls[right.id]) void ensurePhotoUrl(right)
  }, [ensurePhotoUrl, left, photoUrls, right])

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

  const combinedRatio = Math.max(0.8, Math.min(1.55, comparisonAspectRatio(left, right) * 2))

  return (
    <div className="fixed inset-0 z-[100] flex flex-col overflow-y-auto bg-[#07080d] text-white" role="dialog" aria-modal="true" aria-label="Photo comparison">
      <header className="flex items-center justify-between gap-3 px-4 pt-[calc(1rem+env(safe-area-inset-top))] pb-3">
        <div>
          <p className="font-mono text-[9px] font-bold tracking-[0.18em] text-violet-200 uppercase">Private comparison</p>
          <h2 className="mt-1 font-display text-lg font-bold">{daysBetweenPhotos(left, right)} days apart</h2>
          <p className="text-[10px] text-white/55">{workoutCount} completed workouts between</p>
        </div>
        <button type="button" onClick={onClose} className="rounded-full bg-white/10 px-4 py-2 text-sm font-bold backdrop-blur">Close</button>
      </header>

      {left.pose !== right.pose && <p className="mx-4 mb-3 rounded-xl bg-amber-300/10 px-3 py-2 text-[10px] font-semibold text-amber-100">Different poses are selected. Matching poses produce a fairer comparison.</p>}

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
            <button type="button" onClick={() => zoom(-0.25)} disabled={views[active].scale <= 1} className="grid h-11 w-11 place-items-center rounded-2xl bg-white/10 text-2xl font-light disabled:opacity-30" aria-label="Zoom out">−</button>
            <button type="button" onClick={reset} className="min-w-16 rounded-2xl px-2 py-3 font-mono text-[10px] font-bold text-white/75">{Math.round(views[active].scale * 100)}%</button>
            <button type="button" onClick={() => zoom(0.25)} disabled={views[active].scale >= 4} className="grid h-11 w-11 place-items-center rounded-2xl bg-white/10 text-2xl font-light disabled:opacity-30" aria-label="Zoom in">+</button>
          </div>
          <div className="flex rounded-2xl bg-black/25 p-1" aria-label="Comparison movement mode">
            <button type="button" onClick={() => setLinkMode(true)} aria-pressed={synced} className={`rounded-xl px-3 py-2 text-[9px] font-bold uppercase ${synced ? 'bg-violet-500 text-white' : 'text-white/55'}`}>Synced</button>
            <button type="button" onClick={() => setLinkMode(false)} aria-pressed={!synced} className={`rounded-xl px-3 py-2 text-[9px] font-bold uppercase ${!synced ? 'bg-violet-500 text-white' : 'text-white/55'}`}>Unlocked</button>
          </div>
        </div>
        <p className="mt-2 text-center text-[9px] font-medium text-white/45">Drag to inspect. Synced moves both photos together; Unlocked edits the side you touch.</p>
      </div>
    </div>
  )
}
