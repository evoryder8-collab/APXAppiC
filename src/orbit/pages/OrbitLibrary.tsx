import { useRef, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { GlassCard, GhostButton, GradientButton } from '../../components/ui.tsx'
import { ACCENTS } from '../../lib/theme.ts'
import { useStore } from '../../store/AppStore.tsx'
import { buildRouteDna, missionLabel, segmentEffort } from '../domain/analysis.ts'
import { exportGpx, importGpx } from '../domain/gpx.ts'
import { polylineDistanceM } from '../domain/geo.ts'
import { orbitUuid } from '../domain/ids.ts'
import { RUN_MISSIONS, type OrbitRoute, type OrbitRun, type PersonalSegment, type RouteSurface, type RunningShoe, type RunMission } from '../domain/types.ts'
import { OrbitFrame, OrbitPill } from '../components/OrbitFrame.tsx'
import { RoutePreview } from '../components/RoutePreview.tsx'
import { inferNavigationComplexity, inferRouteShape } from '../domain/routePresentation.ts'
import { useOrbitStore } from '../store/OrbitStore.tsx'
import { formatDistance, formatDuration, formatPace } from '../ui/format.ts'
import { useOrbitText } from '../ui/i18n.ts'

type View = 'runs' | 'routes' | 'segments' | 'shoes'

function downloadGpx(route: OrbitRoute): void {
  const url = URL.createObjectURL(new Blob([exportGpx(route.name, route.points)], { type: 'application/gpx+xml' }))
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = `${route.name.replaceAll(' ', '-').toLowerCase()}.gpx`
  anchor.click()
  URL.revokeObjectURL(url)
}

function routeShapeLabel(shape: ReturnType<typeof inferRouteShape>): string {
  if (shape === 'out_back') return 'Out & back'
  if (shape === 'point_to_point') return 'Point to point'
  return 'Loop'
}

function routeSourceLabel(route: OrbitRoute): string {
  if (route.provider.toLowerCase().includes('manual') || route.name.startsWith('Drawn route')) return 'Map drawing'
  if (route.provider.toLowerCase().includes('gpx')) return 'GPX import'
  return route.provider
}

function RouteAction({ children, onClick, danger = false }: { children: string; onClick: () => void; danger?: boolean }) {
  return <button type="button" onClick={onClick} className={`min-h-10 rounded-xl border px-3 py-2 text-left text-[11px] font-bold transition active:scale-[.98] ${danger ? 'border-rose-200/80 bg-rose-50/80 text-rose-700' : 'border-slate-200/80 bg-white/75 text-slate-700'}`}>{children}</button>
}

function SavedRouteCard({
  route,
  runs,
  onStart,
  onEdit,
  onAddSegment,
  onRemove,
}: {
  route: OrbitRoute
  runs: OrbitRun[]
  onStart: () => void
  onEdit: (action: 'rename' | 'note' | 'prefer' | 'avoid' | 'reverse' | 'duplicate' | 'favourite' | 'rate' | 'tag') => void
  onAddSegment: () => void
  onRemove: () => void
}) {
  const t = useOrbitText()
  const dna = buildRouteDna(route, runs)
  const completions = runs.filter((run) => run.route_id === route.id && run.status === 'completed').length
  const shape = inferRouteShape(route.points)
  const navigation = inferNavigationComplexity(route.points)
  const created = new Date(route.created_at)
  const createdLabel = Number.isNaN(created.getTime()) ? '' : new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short', year: 'numeric' }).format(created)

  return (
    <GlassCard accent={route.favourite ? ACCENTS.amber : ACCENTS.ice} className="p-3 sm:p-4">
      <RoutePreview points={route.points} name={route.name} />
      <div className="px-1 pt-4 sm:px-2">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="truncate font-display text-xl font-bold text-ink">{route.name}</p>
            <p className="mt-1 text-[11px] font-semibold text-ink-soft">{t(routeSourceLabel(route))}{createdLabel ? ` · ${createdLabel}` : ''}</p>
          </div>
          <button type="button" onClick={() => onEdit('favourite')} aria-label={t(route.favourite ? 'Unfavourite' : 'Favourite')} aria-pressed={route.favourite} className={`grid h-11 w-11 shrink-0 place-items-center rounded-full border text-xl transition active:scale-95 ${route.favourite ? 'border-amber-200 bg-amber-100 text-amber-600' : 'border-slate-200 bg-white/75 text-slate-400'}`}>{route.favourite ? '★' : '☆'}</button>
        </div>

        <div className="mt-3 grid grid-cols-4 gap-1.5">
          <div className="rounded-xl bg-slate-950 px-2 py-2.5 text-white"><p className="font-mono text-[11px] font-bold">{formatDistance(route.distance_m)}</p><p className="mt-0.5 text-[8px] font-bold tracking-wide text-slate-400">{t('DISTANCE')}</p></div>
          <div className="rounded-xl bg-white/65 px-2 py-2.5"><p className="truncate text-[10px] font-bold text-ink">{t(route.terrain)}</p><p className="mt-0.5 text-[8px] font-bold tracking-wide text-ink-faint">{t('TERRAIN')}</p></div>
          <div className="rounded-xl bg-white/65 px-2 py-2.5"><p className="truncate text-[10px] font-bold text-ink">{t(routeShapeLabel(shape))}</p><p className="mt-0.5 text-[8px] font-bold tracking-wide text-ink-faint">{t('SHAPE')}</p></div>
          <div className="rounded-xl bg-white/65 px-2 py-2.5"><p className="truncate text-[10px] font-bold text-ink">{t(navigation)}</p><p className="mt-0.5 text-[8px] font-bold tracking-wide text-ink-faint">{t('NAV')}</p></div>
        </div>

        {route.note && <p className="mt-3 rounded-2xl bg-white/60 px-3 py-2.5 text-sm leading-relaxed text-ink-soft">{route.note}</p>}
        {route.mission_tags.length > 0 && <div className="mt-3 flex flex-wrap gap-1.5">{route.mission_tags.map((mission) => <span key={mission} className="rounded-full border border-sky-200/80 bg-sky-50 px-2.5 py-1 text-[10px] font-bold text-sky-800">{t(missionLabel(mission))}</span>)}</div>}

        <div className="mt-4 grid grid-cols-[1fr_auto] gap-2">
          <GradientButton accent={ACCENTS.ice} onClick={onStart} className="min-h-14 w-full text-sm">{t('Start run')}</GradientButton>
          <div className="grid min-w-20 place-items-center rounded-2xl border border-white/80 bg-white/60 px-3 text-center"><p className="font-mono text-sm font-bold text-sky-800">{completions}</p><p className="text-[8px] font-bold tracking-wide text-ink-faint">{t(completions === 1 ? 'RUN' : 'RUNS')}</p></div>
        </div>

        {dna && (
          <details className="group mt-3 rounded-2xl border border-sky-100 bg-sky-50/65 px-3.5 py-3">
            <summary className="flex cursor-pointer list-none items-center justify-between gap-3 text-xs font-bold text-sky-900"><span>{t('Route insights')}</span><span className="text-[10px] text-sky-700">{formatPace(dna.typical_pace_sec_km)} · {formatDuration(dna.typical_duration_s)} <span className="ml-1 inline-block transition group-open:rotate-180">⌄</span></span></summary>
            <div className="mt-3 grid grid-cols-2 gap-2 border-t border-sky-100 pt-3 text-[10px] text-sky-900"><span>{t('Typical')} {formatDistance(dna.typical_distance_m)}</span><span>{dna.typical_heart_rate == null ? t('Heart rate unavailable') : `${dna.typical_heart_rate} bpm`}</span><span>{dna.typical_elevation_gain_m == null ? t('Elevation unavailable') : `${dna.typical_elevation_gain_m} m ${t('gain')}`}</span><span>{dna.pace_consistency_pct == null ? t('Pacing baseline developing') : `${dna.pace_consistency_pct.toFixed(1)}% ${t('pace variation')}`}</span></div>
            <p className="mt-2 text-xs text-sky-800">{t(dna.interpretation)}</p>
            <p className="mt-1 text-[10px] text-sky-700">{t(dna.recent_trend)}</p>
          </details>
        )}

        <details className="group mt-3 rounded-2xl border border-slate-200/80 bg-white/50 px-3.5 py-3">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-3 text-xs font-bold text-ink"><span>{t('Manage route')}</span><span className="text-[10px] text-ink-soft">{t('Edit, personalise or export')} <span className="ml-1 inline-block transition group-open:rotate-180">⌄</span></span></summary>
          <div className="mt-3 space-y-3 border-t border-slate-200/70 pt-3">
            <div><p className="mb-1.5 text-[9px] font-bold tracking-widest text-ink-faint">{t('PERSONALISE')}</p><div className="grid grid-cols-2 gap-1.5"><RouteAction onClick={() => onEdit('rate')}>{t('Rate')}</RouteAction><RouteAction onClick={() => onEdit('tag')}>{t('Tag mission')}</RouteAction><RouteAction onClick={() => onEdit('prefer')}>{t('Prefer section')}</RouteAction><RouteAction onClick={() => onEdit('avoid')}>{t('Avoid section')}</RouteAction></div></div>
            <div><p className="mb-1.5 text-[9px] font-bold tracking-widest text-ink-faint">{t('EDIT & SHARE')}</p><div className="grid grid-cols-2 gap-1.5"><RouteAction onClick={() => onEdit('rename')}>{t('Rename')}</RouteAction><RouteAction onClick={() => onEdit('note')}>{t('Note')}</RouteAction><RouteAction onClick={() => onEdit('reverse')}>{t('Reverse')}</RouteAction><RouteAction onClick={() => onEdit('duplicate')}>{t('Duplicate')}</RouteAction><RouteAction onClick={() => downloadGpx(route)}>{t('Export GPX')}</RouteAction><RouteAction onClick={onAddSegment}>{t('Add segment')}</RouteAction><RouteAction danger onClick={onRemove}>{t('Delete route')}</RouteAction></div></div>
          </div>
        </details>
      </div>
    </GlassCard>
  )
}

export function OrbitLibrary() {
  const navigate = useNavigate()
  const [params, setParams] = useSearchParams()
  const t = useOrbitText()
  const { data, toast } = useStore()
  const orbit = useOrbitStore()
  const userId = data.profile?.user_id ?? ''
  const view = (['runs', 'routes', 'segments', 'shoes'].includes(params.get('view') ?? '') ? params.get('view') : 'runs') as View
  const [shoeName, setShoeName] = useState('')
  const [shoeBrand, setShoeBrand] = useState('')
  const [shoeFirstUse, setShoeFirstUse] = useState(() => new Date().toISOString().slice(0, 10))
  const [shoeSurfaces, setShoeSurfaces] = useState<RouteSurface[]>([])
  const [shoeNotes, setShoeNotes] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)

  const saveImported = async (file: File | undefined): Promise<void> => {
    if (!file || !userId) return
    try {
      const imported = importGpx(await file.text())
      const now = new Date().toISOString()
      const route: OrbitRoute = {
        id: orbitUuid(userId, `gpx:${file.name}:${now}`), user_id: userId, client_idempotency_key: orbitUuid(userId, `gpx-client:${file.name}:${now}`),
        name: imported.name, note: '', points: imported.points, distance_m: Math.round(polylineDistanceM(imported.points)), elevation_gain_m: null,
        surface: 'mixed', terrain: 'rolling', shape: 'loop', navigation_complexity: 'moderate', familiarity_pct: null, favourite: false, rating: null,
        mission_tags: [], preferred_sections: [], avoided_sections: [], provider: 'GPX import', attribution: 'User supplied route', created_at: now, updated_at: now, sync_state: 'local',
      }
      await orbit.saveRoute(route)
      toast(t('GPX route imported privately.'), 'ok')
    } catch (error) { toast(t(error instanceof Error ? error.message : 'GPX import failed.')) }
  }

  const editRoute = async (route: OrbitRoute, action: 'rename' | 'note' | 'prefer' | 'avoid' | 'reverse' | 'duplicate' | 'favourite' | 'rate' | 'tag'): Promise<void> => {
    const now = new Date().toISOString()
    if (action === 'duplicate') {
      const copy = { ...route, id: orbitUuid(route.user_id, `duplicate:${route.id}:${now}`), client_idempotency_key: orbitUuid(route.user_id, `duplicate-client:${route.id}:${now}`), name: `${route.name} ${t('copy')}`, favourite: false, created_at: now, updated_at: now, sync_state: 'local' as const }
      return orbit.saveRoute(copy)
    }
    let patch: Partial<OrbitRoute> = {}
    if (action === 'rename') {
      const name = window.prompt(t('Route name'), route.name)?.trim()
      if (!name) return
      patch = { name }
    }
    if (action === 'note') {
      const note = window.prompt(t('Private route note'), route.note) ?? route.note
      patch = { note }
    }
    if (action === 'prefer' || action === 'avoid') {
      const note = window.prompt(t(action === 'prefer' ? 'Describe the preferred road or section' : 'Describe the road or section to avoid'))?.trim()
      if (!note) return
      patch = action === 'prefer' ? { preferred_sections: [...route.preferred_sections, note] } : { avoided_sections: [...route.avoided_sections, note] }
    }
    if (action === 'reverse') patch = { points: [...route.points].reverse(), name: `${route.name} ${t('reversed')}` }
    if (action === 'favourite') patch = { favourite: !route.favourite }
    if (action === 'rate') {
      const rating = Number(window.prompt(t('Private route rating from 1 to 5'), String(route.rating ?? 5)))
      if (!Number.isInteger(rating) || rating < 1 || rating > 5) return toast(t('Choose a whole number from 1 to 5.'))
      patch = { rating }
    }
    if (action === 'tag') {
      const mission = window.prompt(`${t('Useful mission')} (${RUN_MISSIONS.join(', ')})`, route.mission_tags[0] ?? 'easy')?.trim() as RunMission | undefined
      if (!mission || !RUN_MISSIONS.includes(mission)) return toast(t('Choose a valid run mission.'))
      patch = { mission_tags: route.mission_tags.includes(mission) ? route.mission_tags : [...route.mission_tags, mission] }
    }
    await orbit.saveRoute({ ...route, ...patch, updated_at: now, sync_state: 'local' })
  }

  const addSegment = async (route: OrbitRoute): Promise<void> => {
    const name = window.prompt(t('Private segment name'), `${route.name} ${t('section')}`)?.trim()
    if (!name) return
    const startKm = Number(window.prompt(t('Start distance in km'), '0'))
    const endKm = Number(window.prompt(t('End distance in km'), Math.min(1, route.distance_m / 1000).toString()))
    if (!Number.isFinite(startKm) || !Number.isFinite(endKm) || startKm < 0 || endKm <= startKm || endKm * 1000 > route.distance_m) return toast(t('Segment distances are outside this route.'))
    const now = new Date().toISOString()
    const segment: PersonalSegment = { id: orbitUuid(route.user_id, `segment:${route.id}:${name}:${now}`), user_id: route.user_id, route_id: route.id, name, start_distance_m: Math.round(startKm * 1000), end_distance_m: Math.round(endKm * 1000), created_at: now, updated_at: now, sync_state: 'local' }
    await orbit.saveSegment(segment)
    toast(t('Private segment created.'), 'ok')
  }

  const addShoe = async (): Promise<void> => {
    if (!userId || !shoeName.trim()) return
    const now = new Date().toISOString()
    const shoe: RunningShoe = { id: orbitUuid(userId, `shoe:${shoeName}:${now}`), user_id: userId, name: shoeName.trim(), brand: shoeBrand.trim(), first_use_date: shoeFirstUse, preferred_surfaces: shoeSurfaces, notes: shoeNotes.trim(), archived: false, created_at: now, updated_at: now, sync_state: 'local' }
    await orbit.saveShoe(shoe)
    setShoeName(''); setShoeBrand(''); setShoeSurfaces([]); setShoeNotes('')
    toast(t('Running shoes added.'), 'ok')
  }

  const removeRoute = async (route: OrbitRoute): Promise<void> => {
    if (!window.confirm(t(`Delete “${route.name}” and its private segments? This cannot be undone.`))) return
    const segments = orbit.state.segments.filter((segment) => segment.route_id === route.id)
    for (const segment of segments) await orbit.removeEntity('segments', segment.id)
    await orbit.removeEntity('routes', route.id)
    toast(t('Route deleted.'), 'ok')
  }

  const tabs: Array<[View, string]> = [['runs', t('Runs')], ['routes', t('Routes')], ['segments', t('Segments')], ['shoes', t('Shoes')]]
  return (
    <OrbitFrame title={view === 'runs' ? 'Recent runs' : view === 'routes' ? 'Saved routes' : view === 'segments' ? 'Personal segments' : 'Running shoes'} subtitle="Private history that becomes more useful with repetition." backTo="/orbit">
      <div className="space-y-4">
        <div className="glass grid grid-cols-4 gap-1 rounded-[20px] border border-white/80 p-1.5">{tabs.map(([key, label]) => <button key={key} onClick={() => setParams({ view: key })} aria-current={view === key ? 'page' : undefined} className={`min-h-10 rounded-[14px] px-1 text-[10px] font-bold transition active:scale-[.97] ${view === key ? 'bg-[#07111f] text-sky-100 shadow-lg' : 'text-ink-soft'}`}>{label}</button>)}</div>

        {view === 'runs' && <div className="space-y-3">{orbit.state.runs.length === 0 ? <GlassCard className="p-7 text-center"><p className="font-display text-lg font-bold text-ink">{t('No run history yet')}</p><p className="mt-1 text-sm text-ink-soft">{t('Your first completed run will become a private performance baseline.')}</p><GradientButton accent={ACCENTS.ice} onClick={() => navigate('/orbit/run')} className="mt-4">{t('Start free run')}</GradientButton></GlassCard> : [...orbit.state.runs].sort((a, b) => b.started_at.localeCompare(a.started_at)).map((run) => <button key={run.id} onClick={() => navigate(`/orbit/debrief/${run.id}`)} className="glass flex w-full items-center justify-between rounded-3xl p-4 text-left active:scale-[.985]"><div><p className="font-display text-base font-bold text-ink">{t(missionLabel(run.mission))}</p><p className="mt-1 text-xs text-ink-soft">{run.local_date} · {formatDuration(run.metrics.moving_s)} · {formatPace(run.metrics.avg_pace_sec_km)}</p></div><span className="font-mono text-base font-bold text-sky-700">{formatDistance(run.metrics.distance_m)}</span></button>)}</div>}

        {view === 'routes' && <div className="space-y-3">
          <div className="grid grid-cols-2 gap-2"><GradientButton accent={ACCENTS.ice} onClick={() => navigate('/orbit/plan')} className="min-h-12 w-full">{t('Plan new route')}</GradientButton><GhostButton onClick={() => fileRef.current?.click()} className="min-h-12 w-full">{t('Import GPX')}</GhostButton><input ref={fileRef} type="file" accept=".gpx,application/gpx+xml,text/xml" className="hidden" onChange={(event) => void saveImported(event.target.files?.[0])} /></div>
          {orbit.state.routes.length > 0 && <div className="flex items-center justify-between rounded-2xl bg-white/55 px-3.5 py-2.5 text-[11px] font-semibold text-ink-soft"><span>{orbit.state.routes.length} {t(orbit.state.routes.length === 1 ? 'private route' : 'private routes')}</span><span className="font-mono font-bold text-sky-800">{formatDistance(orbit.state.routes.reduce((total, route) => total + route.distance_m, 0))}</span></div>}
          {orbit.state.routes.length === 0 ? <GlassCard className="p-7 text-center"><p className="font-bold text-ink">{t('No saved routes yet.')}</p><p className="mt-1 text-sm text-ink-soft">{t('Generate several options, draw manually or import GPX.')}</p></GlassCard> : [...orbit.state.routes].sort((a, b) => Number(b.favourite) - Number(a.favourite) || b.updated_at.localeCompare(a.updated_at)).map((route) => <SavedRouteCard key={route.id} route={route} runs={orbit.state.runs} onStart={() => navigate('/orbit/run', { state: { routeId: route.id, mission: route.mission_tags[0] ?? 'easy' } })} onEdit={(action) => void editRoute(route, action)} onAddSegment={() => void addSegment(route)} onRemove={() => void removeRoute(route)} />)}
        </div>}

        {view === 'segments' && <div className="space-y-3">{orbit.state.segments.length === 0 ? <GlassCard className="p-7 text-center"><p className="font-bold text-ink">{t('No personal segments yet.')}</p><p className="mt-1 text-sm text-ink-soft">{t('Create a private climb, flat kilometre or finishing stretch from a saved route.')}</p></GlassCard> : orbit.state.segments.map((segment) => {
          const route = orbit.state.routes.find((item) => item.id === segment.route_id)
          const efforts = orbit.state.runs.map((run) => segmentEffort(run, segment)).filter((effort) => effort != null).sort((a, b) => a.duration_s - b.duration_s)
          const latest = [...efforts].sort((a, b) => orbit.state.runs.find((run) => run.id === b.run_id)!.started_at.localeCompare(orbit.state.runs.find((run) => run.id === a.run_id)!.started_at))[0]
          const typical = efforts.length > 0 ? Math.round(efforts.reduce((sum, effort) => sum + effort.duration_s, 0) / efforts.length) : null
          return <GlassCard key={segment.id} accent={ACCENTS.violet} className="p-5"><p className="font-display text-lg font-bold text-ink">{segment.name}</p><p className="mt-1 text-xs text-ink-soft">{route?.name ?? t('Route unavailable')} · {formatDistance(segment.end_distance_m - segment.start_distance_m)}</p><div className="mt-3 grid grid-cols-3 gap-2"><div><p className="text-[10px] text-ink-faint">{t('BEST')}</p><p className="font-mono font-bold">{efforts[0] ? formatDuration(efforts[0].duration_s) : t('No effort')}</p></div><div><p className="text-[10px] text-ink-faint">{t('RECENT')}</p><p className="font-mono font-bold">{latest ? formatDuration(latest.duration_s) : t('No effort')}</p></div><div><p className="text-[10px] text-ink-faint">{t('TYPICAL')}</p><p className="font-mono font-bold">{typical == null ? t('No effort') : formatDuration(typical)}</p></div></div>{latest && <div className="mt-3 grid grid-cols-2 gap-2 rounded-2xl bg-violet-50/70 p-3 text-[10px] text-violet-900"><span>{t('Pace')} {formatPace(latest.pace_sec_km)}</span><span>{latest.heart_rate_avg == null ? t('Heart rate unavailable') : `${latest.heart_rate_avg} bpm`}</span><span>{latest.cadence_avg == null ? t('Cadence unavailable') : `${latest.cadence_avg} spm`}</span><span>{latest.elevation_delta_m == null ? t('Elevation unavailable') : `${latest.elevation_delta_m >= 0 ? '+' : ''}${latest.elevation_delta_m} m`}</span></div>}<p className="mt-3 text-[10px] font-bold text-violet-800">{t('PRIVATE · NO LEADERBOARD')}</p></GlassCard>
        })}</div>}

        {view === 'shoes' && <div className="space-y-3">
          <GlassCard accent={ACCENTS.ice} className="p-5"><h3 className="font-display text-lg font-bold text-ink">{t('Add shoes')}</h3><div className="mt-3 grid gap-2 sm:grid-cols-2"><input value={shoeBrand} onChange={(event) => setShoeBrand(event.target.value)} placeholder={t('Brand')} className="min-h-12 rounded-2xl border border-white/80 bg-white/70 px-3 text-sm" /><input value={shoeName} onChange={(event) => setShoeName(event.target.value)} placeholder={t('Model or nickname')} className="min-h-12 rounded-2xl border border-white/80 bg-white/70 px-3 text-sm" /><label className="text-[10px] font-bold text-ink-faint">{t('FIRST USE')}<input type="date" value={shoeFirstUse} onChange={(event) => setShoeFirstUse(event.target.value)} className="mt-1 min-h-12 w-full rounded-2xl border border-white/80 bg-white/70 px-3 text-sm text-ink" /></label><input value={shoeNotes} onChange={(event) => setShoeNotes(event.target.value)} placeholder={t('Comfort or wear notes')} className="min-h-12 self-end rounded-2xl border border-white/80 bg-white/70 px-3 text-sm" /></div><div className="mt-3 flex flex-wrap gap-2">{(['road', 'path', 'trail', 'mixed'] as RouteSurface[]).map((surface) => <button key={surface} type="button" onClick={() => setShoeSurfaces((current) => current.includes(surface) ? current.filter((item) => item !== surface) : [...current, surface])} className={`rounded-full px-3 py-2 text-xs font-bold ${shoeSurfaces.includes(surface) ? 'bg-sky-950 text-sky-100' : 'bg-white/70 text-ink-soft'}`}>{t(surface)}</button>)}</div><GradientButton accent={ACCENTS.ice} onClick={() => void addShoe()} disabled={!shoeName.trim() || !shoeFirstUse} className="mt-3">{t('Add privately')}</GradientButton></GlassCard>
          {orbit.state.shoes.map((shoe) => {
            const distanceM = orbit.state.runs.filter((run) => run.shoe_id === shoe.id).reduce((sum, run) => sum + run.metrics.distance_m, 0)
            return <GlassCard key={shoe.id} className={`p-5 ${shoe.archived ? 'opacity-60' : ''}`}><div className="flex items-start justify-between"><div><p className="font-display text-lg font-bold text-ink">{shoe.brand} {shoe.name}</p><p className="mt-1 text-xs text-ink-soft">{t('First used')} {shoe.first_use_date}{shoe.preferred_surfaces.length > 0 ? ` · ${shoe.preferred_surfaces.map((surface) => t(surface)).join(', ')}` : ''}</p></div>{shoe.archived && <OrbitPill tone="ice">{t('ARCHIVED')}</OrbitPill>}</div><p className="mt-4 text-[10px] font-bold text-ink-faint">{t('Total distance').toUpperCase()}</p><p className="font-mono text-2xl font-bold text-sky-700">{formatDistance(distanceM)}</p>{shoe.notes && <p className="mt-2 text-xs font-semibold text-ink">{shoe.notes}</p>}<p className="mt-2 text-xs text-ink-soft">{t('Mileage is factual. Orbit does not declare footwear unsafe from a generic threshold.')}</p><div className="mt-3 flex gap-2"><GhostButton onClick={() => { const notes = window.prompt(t('Comfort or wear notes'), shoe.notes); if (notes != null) void orbit.saveShoe({ ...shoe, notes, updated_at: new Date().toISOString(), sync_state: 'local' }) }}>{t('Notes')}</GhostButton><GhostButton onClick={() => void orbit.saveShoe({ ...shoe, archived: !shoe.archived, updated_at: new Date().toISOString(), sync_state: 'local' })}>{t(shoe.archived ? 'Restore' : 'Archive')}</GhostButton></div></GlassCard>
          })}
        </div>}
      </div>
    </OrbitFrame>
  )
}
