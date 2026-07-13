import { lazy, Suspense, useMemo, useRef, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { GlassCard, GhostButton, GradientButton } from '../../components/ui.tsx'
import { ACCENTS } from '../../lib/theme.ts'
import { useStore } from '../../store/AppStore.tsx'
import { missionLabel } from '../domain/analysis.ts'
import { polylineDistanceM, routeDeviationM } from '../domain/geo.ts'
import { exportGpx, importGpx } from '../domain/gpx.ts'
import { orbitUuid } from '../domain/ids.ts'
import { scoreRouteCandidate } from '../domain/missions.ts'
import type { GeoPoint, OrbitRoute, RouteCandidate, RouteFamiliarity, RouteShape, RouteSurface, RouteTerrain, RunMission } from '../domain/types.ts'
import { MissionPicker } from '../components/MissionPicker.tsx'
import { OrbitFrame, OrbitPill } from '../components/OrbitFrame.tsx'
import { OpenOrbitRouteProvider, OpenStreetMapGeocoder } from '../platform/providers.ts'
import { WebLocationSensor } from '../platform/webLocation.ts'
import { useOrbitStore } from '../store/OrbitStore.tsx'
import { formatDistance } from '../ui/format.ts'
import { useOrbitText } from '../ui/i18n.ts'

const OrbitMap = lazy(() => import('../components/OrbitMap.tsx').then((module) => ({ default: module.OrbitMap })))

type PlanningMeasure = 'distance' | 'duration'
type SearchRole = 'start' | 'destination' | 'waypoint'

function planningPaceMinKm(mission: RunMission): number {
  if (mission === 'recovery' || mission === 'run_walk') return 7.3
  if (mission === 'easy' || mission === 'aerobic_base' || mission === 'long_run' || mission === 'exploration') return 6.5
  if (mission === 'tempo' || mission === 'threshold' || mission === 'intervals' || mission === 'marathon_pace' || mission === 'performance_test') return 5.5
  return 6.1
}

function download(name: string, body: string, type: string): void {
  const url = URL.createObjectURL(new Blob([body], { type }))
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = name
  anchor.click()
  URL.revokeObjectURL(url)
}

function SelectRow<T extends string>({ label, value, values, onChange }: {
  label: string
  value: T
  values: Array<{ value: T; label: string }>
  onChange: (value: T) => void
}) {
  return (
    <label className="block">
      <span className="text-[11px] font-bold tracking-wide text-ink-faint uppercase">{label}</span>
      <select value={value} onChange={(event) => onChange(event.target.value as T)} className="mt-1.5 min-h-12 w-full rounded-2xl border border-white/80 bg-white/70 px-3 text-sm font-bold text-ink outline-none focus:ring-2 focus:ring-sky-300/50">
        {values.map((item) => <option key={item.value} value={item.value}>{item.label}</option>)}
      </select>
    </label>
  )
}

function routeFromPoints(userId: string, name: string, points: GeoPoint[], mission: RunMission): OrbitRoute {
  const now = new Date().toISOString()
  const key = `${name}:${now}:${points.length}`
  return {
    id: orbitUuid(userId, key), user_id: userId, client_idempotency_key: orbitUuid(userId, `client:${key}`),
    name, note: '', points, distance_m: Math.round(polylineDistanceM(points)), elevation_gain_m: null,
    surface: 'mixed', terrain: 'rolling', shape: 'loop', navigation_complexity: points.length < 8 ? 'low' : 'moderate',
    familiarity_pct: null, favourite: false, rating: null, mission_tags: [mission], preferred_sections: [], avoided_sections: [],
    provider: 'Manual or GPX', attribution: 'User supplied route', created_at: now, updated_at: now, sync_state: 'local',
  }
}

export function RoutePlanner() {
  const navigate = useNavigate()
  const location = useLocation()
  const t = useOrbitText()
  const { data, toast } = useStore()
  const orbit = useOrbitStore()
  const userId = data.profile?.user_id ?? ''
  const navigationContext = (location.state as { mission?: RunMission; campaignSessionId?: string } | null) ?? {}
  const initialMission = navigationContext.mission ?? 'easy'
  const activeCampaign = orbit.state.campaigns.find((campaign) => campaign.status === 'active')
  const campaignInduction = orbit.state.inductions.find((induction) => induction.id === activeCampaign?.induction_id)
  const [mission, setMission] = useState<RunMission>(initialMission)
  const [measure, setMeasure] = useState<PlanningMeasure>('distance')
  const [distance, setDistance] = useState(5)
  const [duration, setDuration] = useState(45)
  const [shape, setShape] = useState<RouteShape>('loop')
  const [terrain, setTerrain] = useState<RouteTerrain>(initialMission === 'marathon_pace' && campaignInduction?.answers.course_profile ? campaignInduction.answers.course_profile : 'flat')
  const [surface, setSurface] = useState<RouteSurface>(initialMission === 'marathon_pace' && campaignInduction?.answers.course_surface ? campaignInduction.answers.course_surface : 'mixed')
  const [familiarity, setFamiliarity] = useState<RouteFamiliarity>('balanced')
  const [simple, setSimple] = useState(true)
  const [start, setStart] = useState<GeoPoint | null>(null)
  const [destination, setDestination] = useState<GeoPoint | null>(null)
  const [waypoints, setWaypoints] = useState<GeoPoint[]>([])
  const [searchRole, setSearchRole] = useState<SearchRole>('start')
  const [avoidNotes, setAvoidNotes] = useState('')
  const [search, setSearch] = useState('')
  const [searchResults, setSearchResults] = useState<Array<{ label: string; point: GeoPoint }>>([])
  const [candidates, setCandidates] = useState<RouteCandidate[]>([])
  const [selected, setSelected] = useState<RouteCandidate | OrbitRoute | null>(null)
  const [manual, setManual] = useState(false)
  const [manualPoints, setManualPoints] = useState<GeoPoint[]>([])
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [searchOpen, setSearchOpen] = useState(false)
  const [attempted, setAttempted] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)
  const provider = useMemo(() => new OpenOrbitRouteProvider(), [])
  const geocoder = useMemo(() => new OpenStreetMapGeocoder(), [])
  const sensor = useMemo(() => new WebLocationSensor(), [])
  const requestedDistance = measure === 'distance' ? distance : Math.max(1, Math.round(duration / planningPaceMinKm(mission) * 10) / 10)

  const useCurrent = async (): Promise<void> => {
    setBusy(true)
    setMessage('')
    try {
      const point = await sensor.requestCurrent()
      setStart(point)
      setSearchOpen(false)
      setMessage('Starting point set from your current location.')
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Location is unavailable.')
    } finally { setBusy(false) }
  }

  const runSearch = async (): Promise<void> => {
    setBusy(true)
    setMessage('')
    try {
      const results = await geocoder.search(search)
      setSearchResults(results)
      if (results.length === 0) setMessage('No matching location was found.')
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Search is unavailable.')
    } finally { setBusy(false) }
  }

  const generate = async (): Promise<void> => {
    if (!start) return setMessage('Choose a starting point first.')
    setAttempted(true)
    setBusy(true)
    setMessage('Orbit is comparing genuinely different route shapes.')
    try {
      const request = {
        start,
        destination,
        waypoints,
        distance_km: requestedDistance,
        duration_min: measure === 'duration' ? duration : null,
        mission,
        shape,
        terrain,
        surface,
        familiarity,
        simple_navigation: simple,
        avoid_notes: [
          ...orbit.state.routes.flatMap((route) => route.avoided_sections),
          ...avoidNotes.split(',').map((note) => note.trim()).filter(Boolean),
        ],
      }
      const result = await provider.generate(request)
      const enriched = result.map((candidate) => {
        if (orbit.state.routes.length === 0) return { ...candidate, familiarity_pct: 0 }
        const sampled = candidate.points.filter((_, index) => index % Math.max(1, Math.floor(candidate.points.length / 40)) === 0)
        const familiar = sampled.filter((point) => orbit.state.routes.some((known) => (routeDeviationM(point, known.points) ?? Infinity) <= 50)).length
        const updated = { ...candidate, familiarity_pct: sampled.length > 0 ? Math.round(familiar / sampled.length * 100) : 0 }
        return { ...updated, score: scoreRouteCandidate(updated, request) }
      }).sort((a, b) => b.score - a.score)
      setCandidates(enriched)
      setSelected(enriched[0] ?? null)
      setManual(false)
      setMessage('')
    } catch (error) {
      setMessage(error instanceof Error ? error.message : t('Automatic routing unavailable'))
    } finally { setBusy(false) }
  }

  const save = async (route = selected): Promise<OrbitRoute | null> => {
    if (!route || !userId) return null
    const stamped: OrbitRoute = {
      ...route,
      user_id: userId,
      id: route.user_id === userId ? route.id : orbitUuid(userId, `${route.id}:${Date.now()}`),
      client_idempotency_key: route.user_id === userId ? route.client_idempotency_key : orbitUuid(userId, `route-client:${route.id}:${Date.now()}`),
      updated_at: new Date().toISOString(),
      sync_state: 'local',
    }
    await orbit.saveRoute(stamped)
    setSelected(stamped)
    toast(t('Orbit route saved privately.'), 'ok')
    return stamped
  }

  const startRoute = async (): Promise<void> => {
    const route = await save()
    if (route) navigate('/orbit/run', { state: { routeId: route.id, mission, campaignSessionId: navigationContext.campaignSessionId } })
  }

  const onFile = async (file: File | undefined): Promise<void> => {
    if (!file || !userId) return
    try {
      const imported = importGpx(await file.text())
      const route = routeFromPoints(userId, imported.name, imported.points, mission)
      setManualPoints(imported.points)
      setSelected(route)
      setCandidates([])
      setManual(false)
      setAttempted(true)
      setMessage('GPX imported locally. Review it before saving or starting.')
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'GPX import failed.')
    }
  }

  const commitManual = (): void => {
    if (!userId || manualPoints.length < 2) return setMessage('Tap at least two map points to draw a route.')
    const route = routeFromPoints(userId, `Drawn route · ${new Date().toLocaleDateString()}`, manualPoints, mission)
    setSelected(route)
    setCandidates([])
    setManual(false)
    setAttempted(true)
    setMessage('Manual route ready to review.')
  }

  return (
    <OrbitFrame title="Route planner" subtitle="Set the purpose and distance. Orbit handles the complexity." backTo="/orbit">
      <div className="space-y-4">
        <section className="overflow-hidden rounded-[32px] bg-[#050b16] text-white shadow-[0_30px_84px_-36px_rgba(37,99,235,.8)]">
          <div className="p-4 pb-3 sm:p-5 sm:pb-4">
            <details className="group rounded-2xl border border-white/10 bg-white/5 px-3.5 py-3">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-3"><div><p className="font-mono text-[8px] font-bold tracking-[.16em] text-sky-300/70">{t('RUN PURPOSE')}</p><p className="mt-0.5 text-sm font-bold text-white">{t(missionLabel(mission))}</p></div><span className="rounded-full border border-white/10 bg-white/5 px-3 py-1.5 text-[10px] font-bold text-sky-200">{t('Change')}</span></summary>
              <div className="mt-3 border-t border-white/10 pt-3"><MissionPicker value={mission} onChange={setMission} compact /></div>
            </details>
            <div className="mt-3 rounded-2xl border border-white/10 bg-white/5 p-3.5">
              <div className="flex items-center justify-between gap-3">
                <div className="flex gap-1 rounded-full bg-black/20 p-1" role="group" aria-label={t('Plan by distance or duration')}>
                  {(['distance', 'duration'] as PlanningMeasure[]).map((item) => <button key={item} type="button" onClick={() => setMeasure(item)} className={`rounded-full px-3 py-1.5 text-[10px] font-bold ${measure === item ? 'bg-sky-100 text-slate-950' : 'text-slate-400'}`}>{item === 'distance' ? t('Distance') : t('Duration')}</button>)}
                </div>
                <span className="font-mono text-xl font-bold text-white">{measure === 'distance' ? `${distance.toFixed(1)} km` : `${duration} ${t('MIN')}`}</span>
              </div>
              <input aria-label={t(measure === 'distance' ? 'Desired distance in kilometres' : 'Desired duration in minutes')} type="range" min={measure === 'distance' ? 1 : 15} max={measure === 'distance' ? 42.2 : 240} step={measure === 'distance' ? 0.5 : 5} value={measure === 'distance' ? distance : duration} onChange={(event) => measure === 'distance' ? setDistance(Number(event.target.value)) : setDuration(Number(event.target.value))} className="mt-3 w-full accent-cyan-300" />
              {measure === 'duration' && <p className="mt-1 text-[9px] text-slate-500">{t('Orbit will seek roughly')} {requestedDistance.toFixed(1)} km {t('for this mission, then show each option’s estimate.')}</p>}
            </div>
          </div>

          <div className="relative px-3 sm:px-4">
            <Suspense fallback={<div className="h-[48dvh] min-h-[380px] animate-pulse rounded-[28px] bg-slate-900" />}>
              <OrbitMap
                planned={manual ? manualPoints : selected?.points ?? [start, ...waypoints, destination].filter((point): point is GeoPoint => point != null)}
                history={orbit.state.routes.map((route) => route.points)}
                editable={manual}
                onAddPoint={(point) => setManualPoints((points) => [...points, point])}
                className="h-[48dvh] min-h-[380px] max-h-[620px]"
              />
            </Suspense>
            <div className="pointer-events-none absolute right-6 bottom-4 left-6 z-[490] flex justify-start">
              <div className="rounded-full border border-white/12 bg-[#050b16]/90 px-3 py-2 font-mono text-[9px] font-bold tracking-wide text-sky-100 shadow-xl">{start ? `${t('START READY')} · ${start.lat.toFixed(3)}, ${start.lng.toFixed(3)}` : t('SET A START POINT')}</div>
            </div>
          </div>

          <div className="p-4 sm:p-5">
            {message && <p role="status" className="mb-3 rounded-2xl border border-sky-200/10 bg-sky-300/8 px-3 py-2.5 text-xs font-semibold leading-relaxed text-sky-100">{t(message)}</p>}
            <GradientButton accent={ACCENTS.ice} onClick={() => void (start ? generate() : useCurrent())} disabled={busy} className="min-h-16 w-full text-base" breathe>{busy ? t('Working…') : t(start ? 'Generate routes' : 'Use current location')}</GradientButton>
            <div className="mt-2 grid grid-cols-2 gap-2">
              <button type="button" onClick={() => setSearchOpen((open) => !open)} className="min-h-12 rounded-2xl border border-white/12 bg-white/6 px-3 text-xs font-bold text-white active:scale-[.98]">{t(start ? 'Choose another start' : 'Search location')}</button>
              <button type="button" onClick={() => navigate('/orbit/run', { state: { mission, campaignSessionId: navigationContext.campaignSessionId } })} className="min-h-12 rounded-2xl border border-white/12 bg-white/6 px-3 text-xs font-bold text-white active:scale-[.98]">{t('Start free run')}</button>
            </div>
          </div>
        </section>

        {searchOpen && <GlassCard accent={ACCENTS.ice} className="p-4 sm:p-5">
          <div className="flex items-center justify-between gap-3"><div><p className="font-display text-base font-bold text-ink">{t('Choose a location')}</p><p className="mt-0.5 text-xs text-ink-soft">{t('Start, destination or waypoint')}</p></div><button type="button" onClick={() => setSearchOpen(false)} className="grid h-10 w-10 place-items-center rounded-full bg-white/70 text-lg text-ink">×</button></div>
          <div className="mt-3 flex gap-2 overflow-x-auto pb-1" aria-label={t('Search result purpose')}>
            {(['start', 'destination', 'waypoint'] as SearchRole[]).map((role) => <button key={role} type="button" onClick={() => setSearchRole(role)} className={`shrink-0 rounded-full px-3 py-2 text-[10px] font-bold uppercase ${searchRole === role ? 'bg-sky-950 text-sky-100' : 'bg-white/65 text-ink-soft'}`}>{t(role === 'start' ? 'Start' : role === 'destination' ? 'Destination' : 'Waypoint')}</button>)}
          </div>
          <div className="mt-2 flex gap-2">
            <input value={search} onChange={(event) => setSearch(event.target.value)} onKeyDown={(event) => { if (event.key === 'Enter') void runSearch() }} placeholder={t(searchRole === 'start' ? 'Search another start' : searchRole === 'destination' ? 'Search a destination' : 'Search a waypoint')} className="min-h-12 min-w-0 flex-1 rounded-2xl border border-white/80 bg-white/70 px-4 text-sm font-semibold text-ink outline-none" />
            <GradientButton accent={ACCENTS.ice} onClick={() => void runSearch()} disabled={busy || search.trim().length < 3}>{t('Search')}</GradientButton>
          </div>
          {searchResults.length > 0 && <div className="mt-2 space-y-1">{searchResults.map((result) => <button key={`${result.point.lat}:${result.point.lng}`} type="button" onClick={() => {
            if (searchRole === 'start') setStart(result.point)
            else if (searchRole === 'destination') setDestination(result.point)
            else setWaypoints((current) => [...current, result.point])
            setSearchResults([])
            setSearchOpen(false)
            setMessage(`${t(searchRole === 'start' ? 'Start' : searchRole === 'destination' ? 'Destination' : 'Waypoint')}: ${result.label}`)
          }} className="w-full rounded-xl bg-white/60 px-3 py-2.5 text-left text-xs font-semibold text-ink-soft">{result.label}</button>)}</div>}
        </GlassCard>}

        <details className="glass group rounded-[26px] border border-white/80 p-4">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-3"><div><p className="font-display text-base font-bold text-ink">{t('Route preferences')}</p><p className="mt-0.5 text-xs text-ink-soft">{t('Optional fine tuning')}</p></div><span className="grid h-9 w-9 place-items-center rounded-full bg-white/70 text-lg text-ink transition group-open:rotate-45">+</span></summary>
          <div className="mt-4 grid gap-4 border-t border-slate-200/70 pt-4 sm:grid-cols-2">
            <SelectRow label={t('Route shape')} value={shape} onChange={setShape} values={[{ value: 'loop', label: t('Loop') }, { value: 'out_back', label: t('Out and back') }, { value: 'point_to_point', label: t('Point to point') }]} />
            <SelectRow label={t('Terrain')} value={terrain} onChange={setTerrain} values={[{ value: 'flat', label: t('Flat') }, { value: 'rolling', label: t('Rolling') }, { value: 'hilly', label: t('Hilly') }]} />
            <SelectRow label={t('Surface')} value={surface} onChange={setSurface} values={[{ value: 'road', label: t('Road') }, { value: 'path', label: t('Path') }, { value: 'trail', label: t('Trail') }, { value: 'mixed', label: t('Mixed') }]} />
            <SelectRow label={t('Familiarity')} value={familiarity} onChange={setFamiliarity} values={[{ value: 'familiar', label: t('Familiar') }, { value: 'balanced', label: t('Balanced') }, { value: 'exploratory', label: t('Exploratory') }]} />
            <label className="flex min-h-12 items-center justify-between rounded-2xl border border-white/80 bg-white/70 px-3 text-sm font-bold text-ink">{t('Simple navigation')}<input type="checkbox" checked={simple} onChange={(event) => setSimple(event.target.checked)} className="h-5 w-5 accent-sky-500" /></label>
            <label className="block text-[10px] font-bold tracking-wide text-ink-faint uppercase">{t('Roads or areas to avoid')}<input value={avoidNotes} onChange={(event) => setAvoidNotes(event.target.value)} placeholder={t('Comma-separated notes')} className="mt-1.5 min-h-11 w-full rounded-2xl border border-white/80 bg-white/70 px-3 text-xs font-semibold normal-case tracking-normal text-ink" /></label>
            {(destination || waypoints.length > 0) && <div className="sm:col-span-2 flex flex-wrap gap-2 font-mono text-[10px] text-sky-700">{destination && <button type="button" onClick={() => setDestination(null)}>{t('Destination set').toUpperCase()} ×</button>}{waypoints.length > 0 && <button type="button" onClick={() => setWaypoints([])}>{waypoints.length} {t(waypoints.length === 1 ? 'Waypoint' : 'Waypoints').toUpperCase()} ×</button>}</div>}
          </div>
        </details>

        <details className="glass group rounded-[26px] border border-white/80 p-4">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-3"><div><p className="font-display text-base font-bold text-ink">{t('Route tools')}</p><p className="mt-0.5 text-xs text-ink-soft">{t('Draw manually or import GPX')}</p></div><span className="grid h-9 w-9 place-items-center rounded-full bg-white/70 text-lg text-ink transition group-open:rotate-45">+</span></summary>
          <div className="mt-4 flex flex-wrap gap-2 border-t border-slate-200/70 pt-4"><GhostButton onClick={() => { setManual(true); setManualPoints(start ? [start] : []); setSelected(null) }}>{t('Draw manually')}</GhostButton><GhostButton onClick={() => fileRef.current?.click()}>{t('Import GPX')}</GhostButton><input ref={fileRef} type="file" accept=".gpx,application/gpx+xml,text/xml" className="hidden" onChange={(event) => void onFile(event.target.files?.[0])} /></div>
        </details>

        {manual && <GlassCard accent={ACCENTS.amber} className="p-4"><p className="text-sm font-bold text-ink">{t('Tap the map to add route points.')}</p><p className="mt-1 text-xs text-ink-soft">{manualPoints.length} {t('points')} · {formatDistance(polylineDistanceM(manualPoints))}</p><div className="mt-3 flex gap-2"><GradientButton accent={ACCENTS.amber} onClick={commitManual}>{t('Use drawing')}</GradientButton><GhostButton onClick={() => setManualPoints(start ? [start] : [])}>{t('Clear')}</GhostButton></div></GlassCard>}

        {candidates.length > 0 && <section><div className="mb-2 flex items-end justify-between"><div><p className="font-display text-lg font-bold text-ink">{t('Route options')}</p><p className="text-xs text-ink-soft">{t('Different shapes, ranked for this mission')}</p></div><span className="font-mono text-[10px] font-bold text-sky-700">{candidates.length} {t('OPTIONS')}</span></div><div className="flex snap-x gap-3 overflow-x-auto pb-2 sm:grid sm:grid-cols-3 sm:overflow-visible">{candidates.map((candidate, index) => <button type="button" key={candidate.id} onClick={() => setSelected(candidate)} className={`min-w-[82%] snap-center rounded-3xl border p-4 text-left transition sm:min-w-0 ${selected?.id === candidate.id ? 'border-sky-400 bg-sky-950 text-white shadow-xl' : 'glass border-white/80 text-ink'}`}><OrbitPill tone={index === 0 ? 'amber' : 'ice'}>{index === 0 ? t('Best fit').toUpperCase() : `${t('Option').toUpperCase()} ${index + 1}`}</OrbitPill><p className="mt-3 font-display text-xl font-bold">{formatDistance(candidate.distance_m)}</p><p className="mt-1 font-mono text-[9px] opacity-70">{candidate.estimated_duration_min} {t('MIN')} · {candidate.elevation_gain_m == null ? t('Elevation unavailable').toUpperCase() : `${candidate.elevation_gain_m} ${t('m gain').toUpperCase()}`} · {t(candidate.navigation_complexity).toUpperCase()} {t('NAV')}</p><p className="mt-3 text-xs leading-relaxed opacity-80">{t(candidate.explanation)}</p></button>)}</div></section>}

        {selected && !manual && <GlassCard accent={ACCENTS.ice} className="p-5">
          <div className="flex items-start justify-between gap-3"><div><p className="font-display text-xl font-bold text-ink">{t(selected.name)}</p><p className="mt-1 text-xs font-medium text-ink-soft">{selected.provider} · {selected.attribution}</p></div><OrbitPill tone="emerald">{t('Private').toUpperCase()}</OrbitPill></div>
          {'explanation' in selected && <p className="mt-3 text-sm leading-relaxed text-ink-soft">{t(selected.explanation)}</p>}
          <p className="mt-3 text-xs leading-relaxed text-ink-faint">{t('Orbit describes map-supported characteristics, not guaranteed safety, lighting, access or traffic conditions. Verify the route before running.')}</p>
          <div className="mt-4 grid grid-cols-2 gap-2 sm:flex">
            <GradientButton accent={ACCENTS.ice} onClick={() => void startRoute()} className="col-span-2 min-h-14 sm:col-span-1 sm:min-w-44">{t('Start this route')}</GradientButton>
            <GhostButton onClick={() => void save()}>{t('Save route')}</GhostButton>
            <GhostButton onClick={() => download(`${selected.name.replaceAll(' ', '-').toLowerCase()}.gpx`, exportGpx(selected.name, selected.points), 'application/gpx+xml')}>{t('Export GPX')}</GhostButton>
          </div>
        </GlassCard>}

        {attempted && !selected && !manual && <GlassCard className="p-5 text-center"><p className="font-display text-base font-bold text-ink">{t('Automatic routing unavailable')}</p><p className="mt-1 text-sm text-ink-soft">{t('You can still draw a route, import GPX or begin a free run.')}</p><GradientButton accent={ACCENTS.ice} onClick={() => navigate('/orbit/run', { state: { mission, campaignSessionId: navigationContext.campaignSessionId } })} className="mt-4">{t('Start free run')}</GradientButton></GlassCard>}
      </div>
    </OrbitFrame>
  )
}
