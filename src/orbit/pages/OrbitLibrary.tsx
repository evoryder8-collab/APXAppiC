import { useRef, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { GlassCard, GhostButton, GradientButton } from '../../components/ui.tsx'
import { ACCENTS } from '../../lib/theme.ts'
import { useStore } from '../../store/AppStore.tsx'
import { buildRouteDna, missionLabel, segmentEffort } from '../domain/analysis.ts'
import { exportGpx, importGpx } from '../domain/gpx.ts'
import { polylineDistanceM } from '../domain/geo.ts'
import { orbitUuid } from '../domain/ids.ts'
import { RUN_MISSIONS, type OrbitRoute, type PersonalSegment, type RouteSurface, type RunningShoe, type RunMission } from '../domain/types.ts'
import { OrbitFrame, OrbitPill } from '../components/OrbitFrame.tsx'
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

  const tabs: Array<[View, string]> = [['runs', t('Recent runs')], ['routes', t('Saved routes')], ['segments', t('Personal segments')], ['shoes', t('Running shoes')]]
  return (
    <OrbitFrame title={view === 'runs' ? 'Recent runs' : view === 'routes' ? 'Saved routes' : view === 'segments' ? 'Personal segments' : 'Running shoes'} subtitle="Private history that becomes more useful with repetition." backTo="/orbit">
      <div className="space-y-4">
        <div className="flex gap-2 overflow-x-auto pb-1">{tabs.map(([key, label]) => <button key={key} onClick={() => setParams({ view: key })} className={`shrink-0 rounded-full px-4 py-2 text-xs font-bold ${view === key ? 'bg-[#07111f] text-sky-100 shadow-lg' : 'glass text-ink-soft'}`}>{label}</button>)}</div>

        {view === 'runs' && <div className="space-y-3">{orbit.state.runs.length === 0 ? <GlassCard className="p-7 text-center"><p className="font-display text-lg font-bold text-ink">{t('No run history yet')}</p><p className="mt-1 text-sm text-ink-soft">{t('Your first completed run will become a private performance baseline.')}</p><GradientButton accent={ACCENTS.ice} onClick={() => navigate('/orbit/run')} className="mt-4">{t('Start free run')}</GradientButton></GlassCard> : [...orbit.state.runs].sort((a, b) => b.started_at.localeCompare(a.started_at)).map((run) => <button key={run.id} onClick={() => navigate(`/orbit/debrief/${run.id}`)} className="glass flex w-full items-center justify-between rounded-3xl p-4 text-left active:scale-[.985]"><div><p className="font-display text-base font-bold text-ink">{t(missionLabel(run.mission))}</p><p className="mt-1 text-xs text-ink-soft">{run.local_date} · {formatDuration(run.metrics.moving_s)} · {formatPace(run.metrics.avg_pace_sec_km)}</p></div><span className="font-mono text-base font-bold text-sky-700">{formatDistance(run.metrics.distance_m)}</span></button>)}</div>}

        {view === 'routes' && <div className="space-y-3">
          <div className="flex gap-2"><GradientButton accent={ACCENTS.ice} onClick={() => navigate('/orbit/plan')}>{t('Plan new route')}</GradientButton><GhostButton onClick={() => fileRef.current?.click()}>{t('Import GPX')}</GhostButton><input ref={fileRef} type="file" accept=".gpx,application/gpx+xml,text/xml" className="hidden" onChange={(event) => void saveImported(event.target.files?.[0])} /></div>
          {orbit.state.routes.length === 0 ? <GlassCard className="p-7 text-center"><p className="font-bold text-ink">{t('No saved routes yet.')}</p><p className="mt-1 text-sm text-ink-soft">{t('Generate several options, draw manually or import GPX.')}</p></GlassCard> : orbit.state.routes.map((route) => {
            const dna = buildRouteDna(route, orbit.state.runs)
            return <GlassCard key={route.id} accent={route.favourite ? ACCENTS.amber : ACCENTS.ice} className="p-5"><div className="flex items-start justify-between gap-3"><div><p className="font-display text-lg font-bold text-ink">{route.name}</p><p className="mt-1 font-mono text-[10px] text-ink-faint">{formatDistance(route.distance_m)} · {t(route.terrain).toUpperCase()} · {t(route.navigation_complexity).toUpperCase()} {t('NAV')}</p></div>{route.favourite && <OrbitPill tone="amber">{t('FAVOURITE')}</OrbitPill>}</div>{route.rating != null && <p className="mt-2 text-sm tracking-[.18em] text-amber-500" aria-label={`${route.rating} ${t('out of 5 stars')}`}>{'★'.repeat(route.rating)}<span className="text-slate-300">{'★'.repeat(5 - route.rating)}</span></p>}{route.note && <p className="mt-3 text-sm text-ink-soft">{route.note}</p>}{route.mission_tags.length > 0 && <div className="mt-2 flex flex-wrap gap-1">{route.mission_tags.map((mission) => <OrbitPill key={mission} tone="ice">{t(missionLabel(mission))}</OrbitPill>)}</div>}{dna && <div className="mt-3 rounded-2xl bg-sky-50/60 p-3"><p className="text-xs font-bold text-sky-900">{t('Route DNA')} · {dna.completions} {t('completions')}</p><div className="mt-2 grid grid-cols-2 gap-2 text-[10px] text-sky-900"><span>{t('Typical')} {formatDistance(dna.typical_distance_m)}</span><span>{formatDuration(dna.typical_duration_s)}</span><span>{formatPace(dna.typical_pace_sec_km)}</span><span>{dna.typical_heart_rate == null ? t('Heart rate unavailable') : `${dna.typical_heart_rate} bpm`}</span><span>{dna.typical_elevation_gain_m == null ? t('Elevation unavailable') : `${dna.typical_elevation_gain_m} m ${t('gain')}`}</span><span>{dna.pace_consistency_pct == null ? t('Pacing baseline developing') : `${dna.pace_consistency_pct.toFixed(1)}% ${t('pace variation')}`}</span></div><p className="mt-2 text-xs text-sky-800">{t(dna.interpretation)}</p><p className="mt-1 text-[10px] text-sky-700">{t(dna.recent_trend)}</p></div>}<div className="mt-4 flex flex-wrap gap-2"><GradientButton accent={ACCENTS.ice} onClick={() => navigate('/orbit/run', { state: { routeId: route.id, mission: route.mission_tags[0] ?? 'easy' } })}>{t('Start run')}</GradientButton><GhostButton onClick={() => void editRoute(route, 'favourite')}>{t(route.favourite ? 'Unfavourite' : 'Favourite')}</GhostButton><GhostButton onClick={() => void editRoute(route, 'rate')}>{t('Rate')}</GhostButton><GhostButton onClick={() => void editRoute(route, 'rename')}>{t('Rename')}</GhostButton><GhostButton onClick={() => void editRoute(route, 'note')}>{t('Note')}</GhostButton><GhostButton onClick={() => void editRoute(route, 'reverse')}>{t('Reverse')}</GhostButton><GhostButton onClick={() => void editRoute(route, 'duplicate')}>{t('Duplicate')}</GhostButton><GhostButton onClick={() => downloadGpx(route)}>{t('Export GPX')}</GhostButton><GhostButton onClick={() => void addSegment(route)}>{t('Add segment')}</GhostButton><GhostButton onClick={() => void editRoute(route, 'tag')}>{t('Tag mission')}</GhostButton><GhostButton onClick={() => void editRoute(route, 'prefer')}>{t('Prefer section')}</GhostButton><GhostButton onClick={() => void editRoute(route, 'avoid')}>{t('Avoid section')}</GhostButton></div></GlassCard>
          })}
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
