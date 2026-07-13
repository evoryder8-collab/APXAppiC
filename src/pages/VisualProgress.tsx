import { lazy, Suspense, useEffect, useMemo, useState } from 'react'
import { format } from 'date-fns'
import { useLocation } from 'react-router-dom'
import { ACCENTS } from '../lib/theme'
import { comparisonAspectRatio, daysBetweenPhotos, preferSamePose, snapshotForProgressDate, type ProgressPhoto, type ProgressPose } from '../lib/progressPhoto'
import { parseDecimalInput } from '../lib/food'
import { useProgressPhotoStore } from '../store/ProgressPhotoStore'
import { useStore } from '../store/AppStore'
import { AccentChip, GlassCard, GradientButton, SectionHeader } from '../components/ui'
import { CameraIcon } from '../components/Icons'
import type { RpgSnapshot } from '../lib/types'
import { useOrbitStore } from '../orbit/store/OrbitStore'
import { useOrbitText } from '../orbit/ui/i18n'

const ProgressCamera = lazy(() => import('../components/progress/ProgressCamera').then((module) => ({ default: module.ProgressCamera })))
const violet = ACCENTS.violet

function PhotoImage({ photo, thumbnail = false, className = '' }: { photo: ProgressPhoto; thumbnail?: boolean; className?: string }) {
  const store = useProgressPhotoStore()
  const url = thumbnail ? store.thumbnailUrls[photo.id] : store.fullUrls[photo.id]
  useEffect(() => { if (!url) void store.ensurePhotoUrl(photo, thumbnail) }, [photo, store, thumbnail, url])
  if (!url) return <div className={`${className} skeleton bg-white/60`} aria-label="Loading private photo" />
  return <img src={url} alt={`${photo.pose} progress from ${photo.local_date}`} className={className} style={{ objectPosition: `${photo.crop_x * 100}% ${photo.crop_y * 100}%`, transform: `scale(${photo.crop_scale})` }} />
}

const COMPARISON_STATS: Array<{
  key: keyof Pick<RpgSnapshot, 'overall' | 'health' | 'joint' | 'flexibility' | 'endurance' | 'strength'>
  label: string
  color: string
}> = [
  { key: 'overall', label: 'Overall', color: '#34d399' },
  { key: 'health', label: 'Health', color: '#fbbf24' },
  { key: 'joint', label: 'Joint Health', color: '#38bdf8' },
  { key: 'flexibility', label: 'Flexibility', color: '#2dd4bf' },
  { key: 'endurance', label: 'Endurance', color: '#a78bfa' },
  { key: 'strength', label: 'Strength', color: '#fb923c' },
]

function PhotoStatsCard({ snapshot, period }: { snapshot: RpgSnapshot | null; period: 'Before' | 'After' }) {
  return (
    <div className="min-w-0 rounded-xl border border-white/15 bg-[#080a12]/60 p-1.5 text-white shadow-lg backdrop-blur-md sm:p-2">
      <div className="mb-1 flex items-center justify-between gap-1">
        <span className="font-mono text-[7px] font-bold tracking-[0.13em] text-white/80 uppercase sm:text-[8px]">{period} · APEX</span>
        {snapshot && <span className="font-mono text-[7px] font-semibold text-white/55 sm:text-[8px]">{snapshot.date}</span>}
      </div>
      {snapshot ? (
        <div className="space-y-1">
          {COMPARISON_STATS.map((stat) => {
            const value = snapshot[stat.key]
            return (
              <div key={stat.key} className="grid grid-cols-[minmax(0,1fr)_1.35rem] items-center gap-1">
                <div className="min-w-0">
                  <div className="mb-0.5 flex items-center justify-between gap-1">
                    <span className="truncate text-[7px] leading-none font-semibold text-white/80 sm:text-[8px]">{stat.label}</span>
                  </div>
                  <div className="h-1 overflow-hidden rounded-full bg-white/15">
                    <div className="h-full rounded-full" style={{ width: `${Math.max(0, Math.min(100, value))}%`, background: stat.color, boxShadow: `0 0 5px ${stat.color}` }} />
                  </div>
                </div>
                <span className="text-right font-mono text-[8px] font-bold text-white sm:text-[9px]">{value.toFixed(0)}</span>
              </div>
            )
          })}
        </div>
      ) : (
        <p className="py-1 text-[8px] leading-tight font-medium text-white/60">No APEX stats for this date</p>
      )}
    </div>
  )
}

export function VisualProgress() {
  const { data, snapshots } = useStore()
  const store = useProgressPhotoStore()
  const orbit = useOrbitStore()
  const t = useOrbitText()
  const location = useLocation()
  const backTo = (location.state as { from?: string } | null)?.from === '/nutrition' ? '/nutrition' : '/avatar'
  const [guide, setGuide] = useState(false)
  const [camera, setCamera] = useState(false)
  const [pose, setPose] = useState<ProgressPose>('front')
  const [weight, setWeight] = useState(data.profile?.weight_kg ? String(data.profile.weight_kg) : '')
  const [note, setNote] = useState('')
  const [selected, setSelected] = useState<ProgressPhoto | null>(null)
  const [leftId, setLeftId] = useState<string | null>(null)
  const [rightId, setRightId] = useState<string | null>(null)
  const [slider, setSlider] = useState(50)
  const [compareMode, setCompareMode] = useState<'split' | 'slider'>('slider')
  const [includeStats, setIncludeStats] = useState(true)
  const [deleteConfirm, setDeleteConfirm] = useState<string | null>(null)

  const reference = useMemo(() => store.photos.find((photo) => photo.pose === pose) ?? store.photos[0] ?? null, [pose, store.photos])
  const left = store.photos.find((photo) => photo.id === leftId) ?? store.photos.at(-1) ?? null
  const right = store.photos.find((photo) => photo.id === rightId) ?? store.photos[0] ?? null
  const referenceUrl = reference ? store.fullUrls[reference.id] ?? store.thumbnailUrls[reference.id] : null
  const leftSnapshot = left ? snapshotForProgressDate(left.local_date, snapshots) : null
  const rightSnapshot = right ? snapshotForProgressDate(right.local_date, snapshots) : null
  useEffect(() => { if (reference && !referenceUrl) void store.ensurePhotoUrl(reference) }, [reference, referenceUrl, store])

  useEffect(() => {
    if (store.photos.length > 0 && !rightId) setRightId(store.photos[0].id)
    if (store.photos.length > 1 && !leftId) setLeftId(preferSamePose(store.photos[0], store.photos).find((photo) => photo.id !== store.photos[0].id)?.id ?? store.photos.at(-1)?.id ?? null)
  }, [leftId, rightId, store.photos])

  const workoutCount = useMemo(() => {
    if (!left || !right) return 0
    const from = left.local_date < right.local_date ? left.local_date : right.local_date
    const to = left.local_date > right.local_date ? left.local_date : right.local_date
    return data.workout_sessions.filter((session) => session.completed && session.date >= from && session.date <= to).length
  }, [data.workout_sessions, left, right])
  const orbitMilestones = useMemo(() => {
    const campaign = [...orbit.state.campaigns].sort((a, b) => b.created_at.localeCompare(a.created_at))[0]
    if (!campaign) return []
    const sessions = orbit.state.sessions.filter((session) => session.campaign_id === campaign.id)
    const peak = sessions.find((session) => session.phase === 'peak')
    const recovery = sessions.find((session) => session.phase === 'post_marathon')
    return [
      { label: 'Campaign induction', date: campaign.started_at.slice(0, 10) },
      ...(peak ? [{ label: 'Peak week', date: peak.date }] : []),
      { label: 'Marathon', date: campaign.race_date },
      ...(recovery ? [{ label: 'Post-marathon recovery', date: recovery.date }] : []),
    ]
  }, [orbit.state.campaigns, orbit.state.sessions])

  const begin = () => setGuide(true)
  const openCamera = () => { setGuide(false); setCamera(true) }
  const saveCapture = async (blob: Blob, capturedPose: ProgressPose) => {
    await store.savePhoto({ raw: blob, pose: capturedPose, weightKg: parseDecimalInput(weight), note, referencePhotoId: reference?.id ?? null })
    setCamera(false)
    setNote('')
  }

  return (
    <div className="mx-auto w-full max-w-4xl">
      <SectionHeader accent={violet} title="Visual Progress" subtitle="A private, consistent record of physical change" backTo={backTo} backLabel={backTo === '/nutrition' ? 'Nutrition' : 'Avatar'} right={<AccentChip accent={violet}>{store.syncing ? 'SYNCING' : store.photos.some((photo) => photo.sync_status === 'failed') ? 'RETRY PENDING' : store.photos.some((photo) => photo.sync_status === 'queued') ? 'QUEUED OFFLINE' : 'PRIVATE'}</AccentChip>} />

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

        {orbitMilestones.length > 0 && <GlassCard accent={ACCENTS.ice} className="p-4"><p className="font-display text-sm font-bold text-ink">{t('Optional Orbit comparison milestones')}</p><p className="mt-1 text-[11px] leading-relaxed text-ink-soft">{t('These private dates can anchor progress photos. APEX never requires a photo.')}</p><div className="mt-3 flex gap-2 overflow-x-auto pb-1">{orbitMilestones.map((milestone) => <button key={`${milestone.label}:${milestone.date}`} type="button" onClick={() => { setNote(`${t('Orbit milestone')}: ${t(milestone.label)}`); if (milestone.date <= new Date().toISOString().slice(0, 10)) setGuide(true) }} className="shrink-0 rounded-2xl border border-sky-100 bg-white/65 px-3 py-2 text-left"><span className="block text-[10px] font-bold text-sky-800">{t(milestone.label)}</span><span className="font-mono text-[9px] text-ink-faint">{milestone.date}</span></button>)}</div></GlassCard>}

        {store.photos.length === 0 ? (
          <GlassCard className="p-8 text-center">
            <div className="mx-auto grid h-20 w-20 place-items-center rounded-[2rem] bg-violet-500/10 text-violet-600"><CameraIcon className="h-9 w-9" /></div>
            <h2 className="mt-4 font-display text-lg font-bold text-ink">Your private timeline starts here</h2>
            <p className="mx-auto mt-2 max-w-md text-sm font-medium text-ink-soft">Take front, side and back photos under similar lighting. Every two to four weeks is enough to reveal trends without encouraging daily body checking.</p>
          </GlassCard>
        ) : (
          <>
            {left && right && left.id !== right.id && (
              <GlassCard accent={violet} className="p-4 sm:p-5">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div><h2 className="font-display text-lg font-bold text-ink">Compare</h2><p className="text-xs font-medium text-ink-soft">{daysBetweenPhotos(left, right)} days · {workoutCount} completed workouts between</p></div>
                  <div className="flex flex-wrap items-center justify-end gap-2">
                    <button
                      type="button"
                      role="switch"
                      aria-checked={includeStats}
                      aria-label="Include stats in comparison"
                      onClick={() => setIncludeStats((current) => !current)}
                      className="flex items-center gap-2 rounded-full border border-violet-500/15 bg-white/70 px-2.5 py-1.5 text-[10px] font-bold text-ink-soft shadow-sm"
                    >
                      <span>Include stats</span>
                      <span className={`relative h-5 w-9 shrink-0 rounded-full transition-colors ${includeStats ? 'bg-violet-500' : 'bg-ink/15'}`} aria-hidden>
                        <span className={`absolute top-0.5 left-0.5 h-4 w-4 rounded-full bg-white shadow-sm transition-transform ${includeStats ? 'translate-x-4' : 'translate-x-0'}`} />
                      </span>
                    </button>
                    <div className="flex rounded-full bg-white/70 p-1">{(['slider', 'split'] as const).map((mode) => <button key={mode} type="button" onClick={() => setCompareMode(mode)} className={`rounded-full px-3 py-1.5 text-[10px] font-bold uppercase ${compareMode === mode ? 'bg-violet-500 text-white' : 'text-ink-soft'}`}>{mode}</button>)}</div>
                  </div>
                </div>
                {left.pose !== right.pose && <p className="mt-3 rounded-xl bg-amber-500/10 px-3 py-2 text-xs font-semibold text-amber-800">These photos use different poses. Matching poses gives a fairer comparison.</p>}
                <div className="mt-4 grid grid-cols-2 gap-2">
                  <select value={left.id} onChange={(event) => setLeftId(event.target.value)} className="min-w-0 rounded-xl bg-white/75 px-2 py-2 text-xs font-bold">{preferSamePose(right, store.photos).map((photo) => <option key={photo.id} value={photo.id}>{photo.local_date} · {photo.pose}</option>)}</select>
                  <select value={right.id} onChange={(event) => setRightId(event.target.value)} className="min-w-0 rounded-xl bg-white/75 px-2 py-2 text-xs font-bold">{preferSamePose(left, store.photos).map((photo) => <option key={photo.id} value={photo.id}>{photo.local_date} · {photo.pose}</option>)}</select>
                </div>
                <div className="relative mt-3 overflow-hidden rounded-3xl bg-[#14151b]" style={{ aspectRatio: comparisonAspectRatio(left, right) }}>
                  {compareMode === 'split' ? (
                    <div className="grid h-full grid-cols-2 gap-px"><div className="overflow-hidden"><PhotoImage photo={left} className="h-full w-full object-cover" /></div><div className="overflow-hidden"><PhotoImage photo={right} className="h-full w-full object-cover" /></div></div>
                  ) : (
                    <>
                      <div className="absolute inset-0 overflow-hidden"><PhotoImage photo={right} className="h-full w-full object-cover" /></div>
                      <div className="absolute inset-0 overflow-hidden" style={{ clipPath: `inset(0 ${100 - slider}% 0 0)` }}><PhotoImage photo={left} className="h-full w-full object-cover" /></div>
                      <div className="pointer-events-none absolute inset-y-0 w-0.5 bg-white" style={{ left: `${slider}%`, boxShadow: '0 0 12px rgba(0,0,0,0.55)' }} />
                      <input aria-label="Comparison slider" type="range" min="0" max="100" value={slider} onChange={(event) => setSlider(Number(event.target.value))} className="absolute inset-x-4 bottom-4 z-10" />
                    </>
                  )}
                  {includeStats && (
                    <div className={`pointer-events-none absolute inset-x-2 z-20 grid grid-cols-2 gap-2 ${compareMode === 'slider' ? 'bottom-10' : 'bottom-2'}`}>
                      <PhotoStatsCard snapshot={leftSnapshot} period="Before" />
                      <PhotoStatsCard snapshot={rightSnapshot} period="After" />
                    </div>
                  )}
                  <span className="absolute top-3 left-3 rounded-full bg-black/45 px-2 py-1 font-mono text-[9px] font-bold text-white backdrop-blur">{left.local_date}</span><span className="absolute top-3 right-3 rounded-full bg-black/45 px-2 py-1 font-mono text-[9px] font-bold text-white backdrop-blur">{right.local_date}</span>
                </div>
              </GlassCard>
            )}

            <div>
              <div className="mb-3 flex items-end justify-between"><div><h2 className="font-display text-lg font-bold text-ink">Private timeline</h2><p className="text-xs font-medium text-ink-soft">{store.photos.length} photo{store.photos.length === 1 ? '' : 's'} · newest first</p></div></div>
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
                {store.photos.map((photo) => (
                  <button key={photo.id} type="button" onClick={() => setSelected(photo)} className="glass overflow-hidden rounded-3xl text-left">
                    <div className="relative aspect-[2/3] overflow-hidden bg-white/50"><PhotoImage photo={photo} thumbnail className="h-full w-full object-cover" /><span className="absolute right-2 bottom-2 rounded-full bg-black/45 px-2 py-1 text-[9px] font-bold text-white uppercase backdrop-blur">{photo.pose}</span></div>
                    <div className="p-3"><p className="font-mono text-[10px] font-bold text-ink">{format(new Date(`${photo.local_date}T12:00:00`), 'd MMM yyyy')}</p><p className="mt-1 truncate text-[10px] text-ink-faint">{photo.weight_kg ? `${photo.weight_kg} kg · ` : ''}{photo.sync_status}</p></div>
                  </button>
                ))}
              </div>
            </div>
          </>
        )}

        <GlassCard className="p-4">
          <p className="text-xs font-bold text-ink">Privacy design</p>
          <p className="mt-1 text-[11px] leading-relaxed font-medium text-ink-soft">The bucket is private, paths begin with your authenticated user ID, and row-level policies require the same ID. The app requests short-lived signed URLs only after you open this page. Deleting removes both image objects and metadata.</p>
        </GlassCard>
      </div>

      {guide && (
        <div className="fixed inset-0 z-[90] grid place-items-end bg-black/35 p-4 backdrop-blur-sm sm:place-items-center" role="dialog" aria-modal="true">
          <GlassCard accent={violet} className="w-full max-w-lg p-5 sm:p-6">
            <p className="font-mono text-[10px] font-bold tracking-[0.18em] text-violet-700 uppercase">Before the camera opens</p>
            <h2 className="mt-2 font-display text-xl font-bold text-ink">Build a repeatable image</h2>
            <div className="mt-4 grid grid-cols-2 gap-2 text-xs font-semibold text-ink-soft"><p className="rounded-2xl bg-white/65 p-3">1. Same room and similar light</p><p className="rounded-2xl bg-white/65 p-3">2. Camera around waist height</p><p className="rounded-2xl bg-white/65 p-3">3. Neutral stance, no forced flex</p><p className="rounded-2xl bg-white/65 p-3">4. Feet on the guide line</p></div>
            <div className="mt-4 flex gap-2">{(['front', 'side', 'back'] as const).map((value) => <button key={value} type="button" onClick={() => setPose(value)} className={`flex-1 rounded-xl px-3 py-2 text-xs font-bold uppercase ${pose === value ? 'bg-violet-500 text-white' : 'bg-white/70 text-ink-soft'}`}>{value}</button>)}</div>
            <div className="mt-3 grid grid-cols-2 gap-2"><input inputMode="decimal" value={weight} onChange={(event) => setWeight(event.target.value)} placeholder="Weight kg (optional)" className="rounded-xl bg-white/70 px-3 py-2 text-sm outline-none" /><input value={note} onChange={(event) => setNote(event.target.value)} placeholder="Short note (optional)" className="rounded-xl bg-white/70 px-3 py-2 text-sm outline-none" /></div>
            <p className="mt-3 text-[10px] font-medium text-ink-faint">Camera access begins only after you confirm below. Nothing is uploaded until you review and save.</p>
            <div className="mt-4 flex gap-2"><button type="button" onClick={() => setGuide(false)} className="rounded-2xl bg-white/75 px-4 py-3 text-sm font-bold text-ink">Cancel</button><GradientButton accent={violet} onClick={openCamera} className="flex-1">Got it, open camera</GradientButton></div>
          </GlassCard>
        </div>
      )}

      {camera && <Suspense fallback={null}><ProgressCamera initialPose={pose} referenceUrl={referenceUrl} onSave={saveCapture} onClose={() => setCamera(false)} /></Suspense>}

      {selected && (
        <div className="fixed inset-0 z-[85] flex flex-col bg-[#090a0f] text-white" role="dialog" aria-modal="true">
          <div className="flex items-center justify-between px-4 pt-[calc(1rem+env(safe-area-inset-top))] pb-3"><div><p className="font-mono text-xs font-bold">{selected.local_date} · {selected.pose}</p><p className="text-[10px] text-white/55">{selected.weight_kg ? `${selected.weight_kg} kg · ` : ''}{selected.sync_status}</p></div><button type="button" onClick={() => setSelected(null)} className="rounded-full bg-white/12 px-4 py-2 text-sm font-bold">Close</button></div>
          <div className="min-h-0 flex-1 overflow-hidden"><PhotoImage photo={selected} className="h-full w-full object-contain" /></div>
          <div className="px-4 pt-3 pb-[calc(1rem+env(safe-area-inset-bottom))]"><p className="text-xs text-white/70">{selected.note || 'No note'}</p>{deleteConfirm === selected.id ? <div className="mt-3 flex gap-2"><button type="button" onClick={() => { void store.deletePhoto(selected.id); setSelected(null); setDeleteConfirm(null) }} className="rounded-xl bg-red-600 px-4 py-2 text-xs font-bold">Delete forever</button><button type="button" onClick={() => setDeleteConfirm(null)} className="rounded-xl bg-white/12 px-4 py-2 text-xs font-bold">Cancel</button></div> : <button type="button" onClick={() => setDeleteConfirm(selected.id)} className="mt-3 text-xs font-bold text-red-300">Delete private photo</button>}</div>
        </div>
      )}
    </div>
  )
}
