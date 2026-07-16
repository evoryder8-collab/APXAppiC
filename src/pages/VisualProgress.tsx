import { lazy, Suspense, useEffect, useMemo, useState } from 'react'
import { useLocation } from 'react-router-dom'
import { ACCENTS } from '../lib/theme'
import { formatProgressPhotoMoment, type ProcessedProgressPhoto, type ProgressPhoto, type ProgressPose } from '../lib/progressPhoto'
import { parseDecimalInput } from '../lib/food'
import { useProgressPhotoStore } from '../store/ProgressPhotoStore'
import { useStore } from '../store/AppStore'
import { AccentChip, GlassCard, GradientButton, SectionHeader } from '../components/ui'
import { CameraIcon } from '../components/Icons'
import { PhotoComparison } from '../components/progress/PhotoComparison'
import { useOrbitText } from '../orbit/ui/i18n'
import { useLanguage } from '../lib/i18n'
import { progressStrengthComparison, resolveProgressExportMode } from '../lib/progressComparison'

const ProgressCamera = lazy(() => import('../components/progress/ProgressCamera').then((module) => ({ default: module.ProgressCamera })))
const violet = ACCENTS.violet

function PhotoImage({ photo, thumbnail = false, className = '' }: { photo: ProgressPhoto; thumbnail?: boolean; className?: string }) {
  const store = useProgressPhotoStore()
  const url = thumbnail ? store.thumbnailUrls[photo.id] : store.fullUrls[photo.id]
  useEffect(() => { if (!url) void store.ensurePhotoUrl(photo, thumbnail) }, [photo, store, thumbnail, url])
  if (!url) return <div className={`${className} skeleton bg-white/60`} aria-label="Loading private photo" />
  return <img src={url} alt={`${photo.pose} progress from ${photo.local_date}`} className={className} style={{ objectPosition: `${photo.crop_x * 100}% ${photo.crop_y * 100}%`, transform: `scale(${photo.crop_scale})` }} />
}

export function VisualProgress() {
  const { data } = useStore()
  const store = useProgressPhotoStore()
  const t = useOrbitText()
  const { language } = useLanguage()
  const location = useLocation()
  const backTo = (location.state as { from?: string } | null)?.from === '/nutrition' ? '/nutrition' : '/avatar'
  const [guide, setGuide] = useState(false)
  const [camera, setCamera] = useState(false)
  const [pose, setPose] = useState<ProgressPose>('front')
  const [weight, setWeight] = useState(data.profile?.weight_kg ? String(data.profile.weight_kg) : '')
  const [note, setNote] = useState('')
  const [selected, setSelected] = useState<ProgressPhoto | null>(null)
  const [selecting, setSelecting] = useState(false)
  const [compareIds, setCompareIds] = useState<string[]>([])
  const [compareOpen, setCompareOpen] = useState(false)
  const [deleteConfirm, setDeleteConfirm] = useState<string | null>(null)
  const poseLabel = (value: ProgressPose): string => ({
    en: { front: 'Front', side: 'Side', back: 'Back' },
    ro: { front: 'Față', side: 'Profil', back: 'Spate' },
    th: { front: 'ด้านหน้า', side: 'ด้านข้าง', back: 'ด้านหลัง' },
  })[language][value]

  const reference = useMemo(() => store.photos.find((photo) => photo.pose === pose) ?? store.photos[0] ?? null, [pose, store.photos])
  const comparisonPhotos = compareIds
    .map((id) => store.photos.find((photo) => photo.id === id))
    .filter((photo): photo is ProgressPhoto => photo != null)
    .sort((a, b) => a.captured_at.localeCompare(b.captured_at))
  const left = comparisonPhotos[0] ?? null
  const right = comparisonPhotos[1] ?? null
  const referenceUrl = reference ? store.fullUrls[reference.id] ?? store.thumbnailUrls[reference.id] : null
  useEffect(() => { if (reference && !referenceUrl) void store.ensurePhotoUrl(reference) }, [reference, referenceUrl, store])

  useEffect(() => {
    setCompareIds((current) => current.filter((id) => store.photos.some((photo) => photo.id === id)).slice(0, 2))
  }, [store.photos])

  const workoutCount = useMemo(() => {
    if (!left || !right) return 0
    const from = left.local_date < right.local_date ? left.local_date : right.local_date
    const to = left.local_date > right.local_date ? left.local_date : right.local_date
    return data.workout_sessions.filter((session) => session.completed && session.date >= from && session.date <= to).length
  }, [data.workout_sessions, left, right])
  const strengthComparison = useMemo(() => left && right
    ? progressStrengthComparison(data, left.local_date, right.local_date)
    : { averageLoadDeltaKg: null, matchedExercises: 0, loadedSets: 0 }, [data, left, right])

  const begin = () => setGuide(true)
  const openCamera = () => { setGuide(false); setCamera(true) }
  const toggleComparePhoto = (photoId: string) => {
    setCompareIds((current) => current.includes(photoId)
      ? current.filter((id) => id !== photoId)
      : current.length < 2 ? [...current, photoId] : current)
  }
  const cancelCompareSelection = () => {
    setSelecting(false)
    setCompareIds([])
  }
  const openComparison = () => {
    if (comparisonPhotos.length !== 2) return
    setCompareOpen(true)
  }
  const saveCapture = async (blob: Blob, capturedPose: ProgressPose, processed?: ProcessedProgressPhoto) => {
    await store.savePhoto({
      raw: blob,
      processed,
      pose: capturedPose,
      weightKg: parseDecimalInput(weight),
      note,
      // The alignment guide can remain local, but server metadata may only
      // reference a row that has already crossed the sync boundary.
      referencePhotoId: reference?.sync_status === 'synced' ? reference.id : null,
    })
    setCamera(false)
    setNote('')
  }

  return (
    <div className="mx-auto w-full max-w-4xl">
      <SectionHeader accent={violet} title="Visual Progress" subtitle="A private, consistent record of physical change" backTo={backTo} backLabel={backTo === '/nutrition' ? 'Nutrition' : 'Avatar'} right={store.photos.some((photo) => photo.sync_status === 'failed') && !store.syncing
        ? <button type="button" onClick={() => { void store.retrySync() }} aria-label="Retry private photo sync"><AccentChip accent={violet}>RETRY SYNC</AccentChip></button>
        : <AccentChip accent={violet}>{store.syncing ? 'SYNCING' : store.photos.some((photo) => photo.sync_status === 'queued') ? 'QUEUED OFFLINE' : 'PRIVATE'}</AccentChip>} />

      <div className="space-y-5">
        <GlassCard accent={violet} className="overflow-hidden p-5 sm:p-7">
          <div className="grid items-center gap-5 sm:grid-cols-[1fr_auto]">
            <div>
              <p className="font-mono text-[10px] font-bold tracking-[0.18em] text-violet-700 uppercase">Evidence, not judgement</p>
              <h2 className="mt-2 font-display text-2xl font-bold text-ink">Make subtle progress visible.</h2>
              <p className="mt-2 max-w-xl text-sm leading-relaxed font-medium text-ink-soft">APEX guides pose, distance and framing so comparisons become meaningful. Photos are re-encoded on your device to strip EXIF and GPS data, then stored in your private Supabase folder.</p>
              <div className="mt-4 flex flex-wrap gap-2 text-[10px] font-bold text-ink-soft"><span className="rounded-full bg-white/70 px-3 py-1.5">🔒 Per-user storage</span><span className="rounded-full bg-white/70 px-3 py-1.5">⌖ GPS stripped</span><span className="rounded-full bg-white/70 px-3 py-1.5">↔ Pose matching</span></div>
            </div>
            <GradientButton accent={violet} breathe onClick={begin} className="sm:min-w-44">Take progress photo</GradientButton>
          </div>
        </GlassCard>

        {store.photos.length === 0 ? (
          <GlassCard className="p-8 text-center">
            <div className="mx-auto grid h-20 w-20 place-items-center rounded-[2rem] bg-violet-500/10 text-violet-600"><CameraIcon className="h-9 w-9" /></div>
            <h2 className="mt-4 font-display text-lg font-bold text-ink">Your private timeline starts here</h2>
            <p className="mx-auto mt-2 max-w-md text-sm font-medium text-ink-soft">Take front, side and back photos under similar lighting. Every two to four weeks is enough to reveal trends without encouraging daily body checking.</p>
          </GlassCard>
        ) : (
          <>
            <div>
              <div className="mb-3 flex items-end justify-between gap-3">
                <div><h2 className="font-display text-lg font-bold text-ink">Private timeline</h2><p className="text-xs font-medium text-ink-soft">{store.photos.length} photo{store.photos.length === 1 ? '' : 's'} · newest first</p></div>
                {store.photos.length > 1 && (
                  <button type="button" onClick={() => selecting ? cancelCompareSelection() : setSelecting(true)} className={`shrink-0 rounded-full px-3 py-2 text-[10px] font-bold ${selecting ? 'bg-ink/8 text-ink-soft' : 'bg-violet-500 text-white shadow-sm'}`}>
                    {selecting ? 'Cancel' : 'Select 2 · Compare'}
                  </button>
                )}
              </div>
              {selecting && (
                <GlassCard accent={violet} className="mb-3 flex items-center justify-between gap-3 p-3">
                  <div><p className="text-xs font-bold text-ink">Choose any two photos</p><p className="mt-0.5 text-[10px] font-medium text-ink-soft">{compareIds.length}/2 selected · matching poses work best</p></div>
                  <button type="button" disabled={comparisonPhotos.length !== 2} onClick={openComparison} className="rounded-xl bg-violet-500 px-4 py-2.5 text-xs font-bold text-white shadow-sm disabled:opacity-35">Compare</button>
                </GlassCard>
              )}
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
                {store.photos.map((photo) => {
                  const compareIndex = compareIds.indexOf(photo.id)
                  const chosen = compareIndex >= 0
                  return (
                  <button key={photo.id} type="button" aria-pressed={selecting ? chosen : undefined} onClick={() => selecting ? toggleComparePhoto(photo.id) : setSelected(photo)} className={`glass overflow-hidden rounded-3xl text-left transition ${chosen ? 'ring-2 ring-violet-500 ring-offset-2 ring-offset-transparent' : ''}`}>
                    <div className="relative aspect-[2/3] overflow-hidden bg-white/50"><PhotoImage photo={photo} thumbnail className="h-full w-full object-cover" />{selecting && <span className={`absolute top-2 left-2 grid h-7 w-7 place-items-center rounded-full border text-[10px] font-bold backdrop-blur ${chosen ? 'border-violet-300 bg-violet-500 text-white' : 'border-white/70 bg-black/25 text-white'}`}>{chosen ? compareIndex + 1 : ''}</span>}<span className="absolute right-2 bottom-2 rounded-full bg-black/45 px-2 py-1 text-[9px] font-bold text-white uppercase backdrop-blur">{poseLabel(photo.pose)}</span></div>
                    <div className="p-3"><p className="font-mono text-[10px] font-bold text-ink">{formatProgressPhotoMoment(photo, language)}</p><p className="mt-1 truncate text-[10px] text-ink-faint">{photo.weight_kg ? `${photo.weight_kg} kg · ` : ''}{photo.sync_status}</p></div>
                  </button>
                )})}
              </div>
            </div>
          </>
        )}

        <details className="group glass overflow-hidden rounded-2xl border border-white/80 shadow-[0_12px_30px_-26px_rgba(24,24,32,.55)]">
          <summary className="flex min-h-12 cursor-pointer list-none items-center justify-between gap-3 px-4 text-xs font-bold text-ink marker:content-none">
            <span className="flex items-center gap-2"><span className="grid h-6 w-6 place-items-center rounded-full bg-emerald-500/10 text-[10px] text-emerald-700">⌁</span>{t('Privacy design')}</span>
            <span className="grid h-7 w-7 place-items-center rounded-full bg-ink/5 font-mono text-base text-ink-soft transition-transform group-open:rotate-45">+</span>
          </summary>
          <p className="border-t border-white/70 px-4 pt-3 pb-4 text-[11px] leading-relaxed font-medium text-ink-soft">{t('The bucket is private, paths begin with your authenticated user ID, and row-level policies require the same ID. The app requests short-lived signed URLs only after you open this page. Deleting removes both image objects and metadata.')}</p>
        </details>
      </div>

      {guide && (
        <div className="fixed inset-0 z-[90] grid place-items-end bg-black/45 px-3 pt-10 pb-[max(.75rem,env(safe-area-inset-bottom))] sm:place-items-center sm:p-4" style={{ WebkitBackdropFilter: 'blur(12px)', backdropFilter: 'blur(12px)' }} role="dialog" aria-modal="true">
          <GlassCard accent={violet} className="flex min-h-[78dvh] max-h-[94dvh] w-full max-w-lg flex-col overflow-y-auto p-5 sm:min-h-0 sm:p-6" style={{ background: 'linear-gradient(155deg, rgba(253,253,255,.985), rgba(246,245,252,.97))', WebkitBackdropFilter: 'blur(30px) saturate(120%)', backdropFilter: 'blur(30px) saturate(120%)' }}>
            <p className="font-mono text-[10px] font-bold tracking-[0.18em] text-violet-700 uppercase">{t('Before the camera opens')}</p>
            <h2 className="mt-2 font-display text-2xl font-bold text-ink">{t('Build a repeatable image')}</h2>
            <p className="mt-2 text-xs leading-relaxed font-medium text-ink-soft">{t('Four calm checks make every future comparison more meaningful.')}</p>
            <ol className="mt-6 space-y-4 text-sm font-semibold text-ink-soft">
              {[
                'Same room and similar light',
                'Camera around waist height',
                'Neutral stance, no forced flex',
                'Feet on the guide line',
              ].map((step, index) => (
                <li key={step} className="flex min-h-11 items-center gap-4 px-1">
                  <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-violet-500/12 font-mono text-xs font-black text-violet-700">{index + 1}</span>
                  <span className="leading-snug">{t(step)}</span>
                </li>
              ))}
            </ol>
            <div className="mt-6 flex gap-2">{(['front', 'side', 'back'] as const).map((value) => <button key={value} type="button" onClick={() => setPose(value)} className={`flex-1 rounded-xl px-3 py-2.5 text-xs font-bold uppercase ${pose === value ? 'bg-violet-500 text-white' : 'bg-white/70 text-ink-soft'}`}>{poseLabel(value)}</button>)}</div>
            <div className="mt-3 grid gap-2 sm:grid-cols-2"><input inputMode="decimal" value={weight} onChange={(event) => setWeight(event.target.value)} placeholder={t('Weight kg (optional)')} className="rounded-xl bg-white/70 px-3 py-2.5 text-sm outline-none" /><input value={note} onChange={(event) => setNote(event.target.value)} placeholder={t('Short note (optional)')} className="rounded-xl bg-white/70 px-3 py-2.5 text-sm outline-none" /></div>
            <p className="mt-4 text-[10px] leading-relaxed font-medium text-ink-faint">{t('Camera access begins only after you confirm below. Nothing is uploaded until you review and save.')}</p>
            <div className="mt-auto flex gap-2 pt-5"><button type="button" onClick={() => setGuide(false)} className="rounded-2xl bg-white/75 px-4 py-3 text-sm font-bold text-ink">{t('Cancel')}</button><GradientButton accent={violet} onClick={openCamera} className="flex-1">{t('Got it, open camera')}</GradientButton></div>
          </GlassCard>
        </div>
      )}

      {camera && <Suspense fallback={null}><ProgressCamera initialPose={pose} referenceUrl={referenceUrl} onSave={saveCapture} onClose={() => setCamera(false)} /></Suspense>}

      {compareOpen && left && right && (
        <PhotoComparison
          left={left}
          right={right}
          workoutCount={workoutCount}
          strengthComparison={strengthComparison}
          athleteName={data.profile?.display_name ?? 'APEX athlete'}
          exportMode={resolveProgressExportMode(data.settings?.addons.comparison_export_mode)}
          photoUrls={{ ...store.thumbnailUrls, ...store.fullUrls }}
          fullPhotoUrls={store.fullUrls}
          ensurePhotoUrl={store.ensurePhotoUrl}
          onClose={() => setCompareOpen(false)}
        />
      )}

      {selected && (
        <div className="fixed inset-0 z-[85] flex flex-col bg-[#090a0f] text-white" role="dialog" aria-modal="true">
          <div className="flex items-center justify-between px-4 pt-[calc(1rem+env(safe-area-inset-top))] pb-3"><div><p className="font-mono text-xs font-bold">{formatProgressPhotoMoment(selected, language)} · {poseLabel(selected.pose)}</p><p className="text-[10px] text-white/55">{selected.weight_kg ? `${selected.weight_kg} kg · ` : ''}{selected.sync_status}</p></div><button type="button" onClick={() => setSelected(null)} className="rounded-full bg-white/12 px-4 py-2 text-sm font-bold">Close</button></div>
          <div className="min-h-0 flex-1 overflow-hidden"><PhotoImage photo={selected} className="h-full w-full object-contain" /></div>
          <div className="px-4 pt-3 pb-[calc(1rem+env(safe-area-inset-bottom))]"><p className="text-xs text-white/70">{selected.note || 'No note'}</p>{deleteConfirm === selected.id ? <div className="mt-3 flex gap-2"><button type="button" onClick={() => { void store.deletePhoto(selected.id); setSelected(null); setDeleteConfirm(null) }} className="rounded-xl bg-red-600 px-4 py-2 text-xs font-bold">Delete forever</button><button type="button" onClick={() => setDeleteConfirm(null)} className="rounded-xl bg-white/12 px-4 py-2 text-xs font-bold">Cancel</button></div> : <button type="button" onClick={() => setDeleteConfirm(selected.id)} className="mt-3 text-xs font-bold text-red-300">Delete private photo</button>}</div>
        </div>
      )}
    </div>
  )
}
