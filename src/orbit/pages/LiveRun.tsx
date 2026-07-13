import { lazy, Suspense, useEffect, useMemo, useRef, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { GlassCard, GhostButton, GradientButton } from '../../components/ui.tsx'
import { ACCENTS } from '../../lib/theme.ts'
import { useStore } from '../../store/AppStore.tsx'
import { activityCatalogMap, blockFromActivityLog, estimateActivityDay } from '../../lib/activity.ts'
import { dailyLogId } from '../../lib/ids.ts'
import { authoritativeActivityLogs, importedActivityForRun } from '../domain/integrations.ts'
import { calculateRunMetrics, geographicDistanceM, pauseDurationS, routeDeviationM, routeNavigationCue } from '../domain/geo.ts'
import { orbitUuid } from '../domain/ids.ts'
import type { ActiveRun, GeoPoint, OrbitRun, RunMission, TrackSample } from '../domain/types.ts'
import { missionLabel } from '../domain/analysis.ts'
import { OrbitFrame, OrbitPill } from '../components/OrbitFrame.tsx'
import { WebLocationSensor } from '../platform/webLocation.ts'
import { useOrbitStore } from '../store/OrbitStore.tsx'
import { formatDistance, formatDuration, formatPace } from '../ui/format.ts'
import { useOrbitText } from '../ui/i18n.ts'

const OrbitMap = lazy(() => import('../components/OrbitMap.tsx').then((module) => ({ default: module.OrbitMap })))

type WakeLockSentinelLike = { release: () => Promise<void> }

function currentPace(samples: TrackSample[]): number | null {
  if (samples.length < 2) return null
  const recent = samples.slice(-5)
  const first = recent[0]
  const last = recent.at(-1)!
  const seconds = (last.recorded_at - first.recorded_at) / 1000
  const metres = recent.slice(1).reduce((sum, point, index) => sum + geographicDistanceM(recent[index], point), 0)
  return seconds >= 8 && metres >= 10 ? Math.round(seconds / (metres / 1000)) : null
}

function guidanceFor(mission: RunMission, metricsDistance: number, pace: number | null, deviation: number | null): string {
  if (deviation != null && deviation > 100) return `You are ${Math.round(deviation)} m from the planned route. Slow down and use the map to return.`
  if (metricsDistance < 300) return mission === 'recovery' ? 'Begin deliberately easy. Today’s value comes from restraint.' : 'Settle in gradually. There is no need to win the first kilometre.'
  if (mission === 'recovery') return 'Keep the effort conversational. Protect the next demanding session.'
  if (mission === 'marathon_pace') return 'Settle into the intended range rather than accelerating immediately.'
  if (mission === 'intervals') return 'Keep the work repetitions controlled and make recovery sections genuinely easy.'
  if (mission === 'hills') return 'Let pace change with the gradient while effort remains controlled.'
  if (pace == null) return 'GPS is still stabilising. Run by effort until pace becomes reliable.'
  return 'Stay with the mission. Faster is only useful when the session calls for it.'
}

export function LiveRun() {
  const navigate = useNavigate()
  const location = useLocation()
  const t = useOrbitText()
  const app = useStore()
  const orbit = useOrbitStore()
  const profile = app.data.profile
  const requested = (location.state as { routeId?: string; mission?: RunMission; campaignSessionId?: string; minimumMinutes?: number } | null) ?? {}
  const restored = orbit.state.active_run
  const availableShoes = orbit.state.shoes.filter((shoe) => !shoe.archived)
  const [selectedShoeId, setSelectedShoeId] = useState(restored?.shoe_id ?? availableShoes[0]?.id ?? '')
  const [active, setActive] = useState<ActiveRun | null>(restored)
  const activeRef = useRef(active)
  activeRef.current = active
  const [countdown, setCountdown] = useState<number | null>(null)
  const [now, setNow] = useState(Date.now())
  const [gpsMessage, setGpsMessage] = useState('')
  const [watching, setWatching] = useState(false)
  const [returnPath, setReturnPath] = useState<GeoPoint[] | null>(null)
  const stopWatchRef = useRef<(() => void) | null>(null)
  const wakeRef = useRef<WakeLockSentinelLike | null>(null)
  const lastPersist = useRef(0)
  const sensor = useMemo(() => new WebLocationSensor(), [])
  const routeId = active?.route_id ?? requested.routeId ?? null
  const route = orbit.state.routes.find((item) => item.id === routeId) ?? null
  const campaignSession = orbit.state.sessions.find((item) => item.id === (active?.campaign_session_id ?? requested.campaignSessionId)) ?? null
  const targetMinutes = active?.target_duration_min ?? requested.minimumMinutes ?? campaignSession?.adapted.duration_min ?? null
  const plannedPoints = returnPath ?? route?.points ?? []
  const mission = active?.mission ?? requested.mission ?? 'free_run'
  const metrics = useMemo(() => calculateRunMetrics(active?.samples ?? [], active?.pauses ?? [], profile?.weight_kg), [active?.pauses, active?.samples, profile?.weight_kg])
  const current = active?.samples.at(-1) ?? null
  const pace = currentPace(active?.samples ?? [])
  const deviation = current && plannedPoints.length > 1 ? routeDeviationM(current, plannedPoints) : null
  const navigationCue = current && plannedPoints.length > 1 ? routeNavigationCue(current, plannedPoints) : null
  const pausedSeconds = active ? pauseDurationS(active.pauses, now) : 0
  const elapsed = active ? Math.max(0, Math.round((now - active.started_at) / 1000 - pausedSeconds)) : 0
  const guidance = targetMinutes != null && elapsed >= targetMinutes * 60
    ? 'You have completed the useful planned stimulus. There is no need to extend today’s session.'
    : guidanceFor(mission, metrics.distance_m, pace, deviation)

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1000)
    return () => window.clearInterval(timer)
  }, [])

  useEffect(() => {
    if (!selectedShoeId && availableShoes[0]) setSelectedShoeId(availableShoes[0].id)
  }, [availableShoes, selectedShoeId])

  const persist = (next: ActiveRun, immediate = false): void => {
    setActive(next)
    activeRef.current = next
    if (immediate || Date.now() - lastPersist.current >= 4_000) {
      lastPersist.current = Date.now()
      void orbit.setActiveRun(next)
    }
  }

  const speakSplitIfNeeded = (next: ActiveRun): ActiveRun => {
    const nextSplit = Math.floor(calculateRunMetrics(next.samples, next.pauses).distance_m / 1000)
    if (nextSplit <= next.last_spoken_split) return next
    if ('speechSynthesis' in window) {
      const split = calculateRunMetrics(next.samples, next.pauses).splits[nextSplit - 1]
      const words = t(split ? `Kilometre ${nextSplit}. ${formatPace(split.pace_sec_km)}.` : `Kilometre ${nextSplit}.`)
      window.speechSynthesis.speak(new SpeechSynthesisUtterance(words))
    }
    return { ...next, last_spoken_split: nextSplit }
  }

  const beginWatch = (): void => {
    if (stopWatchRef.current) return
    setWatching(true)
    setGpsMessage('Waiting for a precise GPS sample.')
    stopWatchRef.current = sensor.watch((sample) => {
      const currentRun = activeRef.current
      if (!currentRun || currentRun.paused) return
      const next = speakSplitIfNeeded({ ...currentRun, samples: [...currentRun.samples, sample], updated_at: Date.now() })
      persist(next)
      setGpsMessage(sample.accuracy_m > 25 ? 'Weak GPS. Move into a clearer area if possible.' : '')
    }, (error) => setGpsMessage(error.message))
  }

  useEffect(() => {
    if (restored) beginWatch()
    return () => {
      stopWatchRef.current?.()
      stopWatchRef.current = null
      void wakeRef.current?.release()
    }
    // Run only on mount. The watcher reads the latest active run through a ref.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    const loaded = orbit.state.active_run
    if (!loaded || activeRef.current) return
    setActive(loaded)
    activeRef.current = loaded
    beginWatch()
    // The watcher is guarded by stopWatchRef and reads current state via a ref.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [orbit.state.active_run])

  const requestWakeLock = async (): Promise<void> => {
    try {
      const navigatorWithWakeLock = navigator as Navigator & { wakeLock?: { request: (type: 'screen') => Promise<WakeLockSentinelLike> } }
      wakeRef.current = await navigatorWithWakeLock.wakeLock?.request('screen') ?? null
    } catch {
      // Wake lock is an enhancement. Recording remains available without it.
    }
  }

  const startAfterCountdown = (): void => {
    if (!profile) return
    setCountdown(3)
    let value = 3
    const timer = window.setInterval(() => {
      value -= 1
      if (value > 0) return setCountdown(value)
      window.clearInterval(timer)
      const started = Date.now()
      const id = orbitUuid(profile.user_id, `active:${started}`)
      const next: ActiveRun = {
        id, user_id: profile.user_id, mission, route_id: route?.id ?? null,
        campaign_session_id: requested.campaignSessionId ?? null, shoe_id: selectedShoeId || null,
        target_duration_min: targetMinutes,
        started_at: started, paused: false, samples: [], pauses: [], manual_laps_m: [], last_spoken_split: 0, updated_at: started,
      }
      setCountdown(null)
      persist(next, true)
      void requestWakeLock()
      beginWatch()
    }, 1000)
  }

  const pauseOrResume = (): void => {
    const run = activeRef.current
    if (!run) return
    const timestamp = Date.now()
    const pauses = run.paused
      ? run.pauses.map((interval, index) => index === run.pauses.length - 1 ? { ...interval, ended_at: timestamp } : interval)
      : [...run.pauses, { started_at: timestamp, ended_at: null }]
    persist({ ...run, paused: !run.paused, pauses, updated_at: timestamp }, true)
  }

  const addLap = (): void => {
    const run = activeRef.current
    if (!run) return
    persist({ ...run, manual_laps_m: [...run.manual_laps_m, metrics.distance_m], updated_at: Date.now() }, true)
    app.toast(t('Manual lap marked.'), 'ok')
  }

  const finish = async (): Promise<void> => {
    const run = activeRef.current
    if (!run || !profile) return
    if (run.samples.length < 2 && !window.confirm(t('Very little GPS data was recorded. Finish this run anyway?'))) return
    const ended = Date.now()
    const pauses = run.paused ? run.pauses.map((interval, index) => index === run.pauses.length - 1 ? { ...interval, ended_at: ended } : interval) : run.pauses
    const finalMetrics = calculateRunMetrics(run.samples, pauses, profile.weight_kg)
    const completed: OrbitRun = {
      id: run.id, user_id: run.user_id, client_idempotency_key: orbitUuid(run.user_id, `run:${run.id}`),
      local_date: new Date(run.started_at).toLocaleDateString('en-CA'), started_at: new Date(run.started_at).toISOString(), ended_at: new Date(ended).toISOString(),
      mission: run.mission, route_id: run.route_id, campaign_session_id: run.campaign_session_id, shoe_id: run.shoe_id,
      samples: run.samples, pauses, manual_laps_m: run.manual_laps_m, metrics: finalMetrics,
      check_in: { perceived_effort: null, legs: null, discomfort: null, note: '' }, status: 'completed', sync_state: 'local',
      nutrition_adjustment_applied_at: null,
      created_at: new Date(run.started_at).toISOString(), updated_at: new Date(ended).toISOString(),
    }
    stopWatchRef.current?.()
    stopWatchRef.current = null
    await orbit.saveRun(completed)
    const authoritative = authoritativeActivityLogs(app.data.activity_logs, completed, profile)
    authoritative.removeIds.forEach((id) => app.remove('activity_logs', id))
    app.upsert('activity_logs', authoritative.orbitLog)
    app.upsert('imported_activities', importedActivityForRun(completed))
    const dayActivityLogs = [...app.data.activity_logs.filter((log) => log.date === completed.local_date && !authoritative.removeIds.includes(log.id) && log.id !== authoritative.orbitLog.id), authoritative.orbitLog]
    const catalog = activityCatalogMap(app.data.activity_types)
    const estimate = estimateActivityDay(profile, dayActivityLogs.map((log) => blockFromActivityLog(log, catalog)), catalog)
    const existingDaily = app.data.daily_logs.find((log) => log.date === completed.local_date)
    app.upsert('daily_logs', {
      id: existingDaily?.id ?? dailyLogId(completed.local_date, profile.user_id), user_id: profile.user_id, date: completed.local_date,
      kcal: existingDaily?.kcal ?? null, protein_g: existingDaily?.protein_g ?? null, fat_g: existingDaily?.fat_g ?? null, carbs_g: existingDaily?.carbs_g ?? null,
      water_l: existingDaily?.water_l ?? 0, estimated_tdee: estimate.tdee, computed_pal: estimate.pal, activity_mode: 'precise' as const,
      weight_kg: existingDaily?.weight_kg ?? profile.weight_kg, nutrition_source: existingDaily?.nutrition_source ?? 'manual',
      manual_kcal: existingDaily?.manual_kcal ?? null, manual_protein_g: existingDaily?.manual_protein_g ?? null,
      manual_fat_g: existingDaily?.manual_fat_g ?? null, manual_carbs_g: existingDaily?.manual_carbs_g ?? null,
    })
    if (completed.campaign_session_id) {
      const session = orbit.state.sessions.find((item) => item.id === completed.campaign_session_id)
      if (session) await orbit.saveSession({ ...session, status: 'completed', completion_run_id: completed.id, updated_at: new Date().toISOString(), sync_state: 'local' })
    }
    void wakeRef.current?.release()
    navigate(`/orbit/debrief/${completed.id}`, { replace: true })
  }

  const cancel = async (): Promise<void> => {
    if (!window.confirm(t('Cancel this run and permanently discard its recorded track?'))) return
    stopWatchRef.current?.()
    stopWatchRef.current = null
    await orbit.setActiveRun(null)
    void wakeRef.current?.release()
    navigate('/orbit', { replace: true })
  }

  if (!active) {
    return (
      <OrbitFrame title="Live run" subtitle="One purpose, one clear action." backTo="/orbit">
        <div className="space-y-4">
          <div className="relative overflow-hidden rounded-[32px] border border-sky-100/20 bg-[#050b16] p-7 text-center text-white shadow-2xl sm:p-10">
            <div className="orbit-stars absolute inset-0 opacity-70" aria-hidden />
            <div className="relative">
              <OrbitPill tone="amber">{t(missionLabel(mission)).toUpperCase()}</OrbitPill>
              <p className="mt-5 font-display text-3xl font-bold">{route?.name ?? t('Free run')}</p>
              {targetMinutes != null && <p className="mt-2 font-mono text-xs font-bold tracking-wide text-sky-200">{t('TARGET')} · {targetMinutes} {t('MINUTES')}{requested.minimumMinutes ? ` · ${t('MINIMUM-EFFECTIVE VERSION')}` : ''}</p>}
              <p className="mx-auto mt-2 max-w-md text-sm leading-relaxed text-slate-300">{t('GPS permission is requested only when you start. The active run is kept in private offline storage so an interrupted screen can recover it.')}</p>
              {availableShoes.length > 0 && <label className="mx-auto mt-5 block max-w-xs text-left text-[10px] font-bold tracking-widest text-slate-400">{t('RUNNING SHOES')}
                <select value={selectedShoeId} onChange={(event) => setSelectedShoeId(event.target.value)} className="mt-1.5 min-h-12 w-full rounded-2xl border border-white/15 bg-slate-900 px-3 text-sm font-bold text-white">
                  <option value="">{t('No shoes assigned')}</option>
                  {availableShoes.map((shoe) => <option key={shoe.id} value={shoe.id}>{shoe.brand} {shoe.name}</option>)}
                </select>
              </label>}
              {countdown == null ? <GradientButton accent={ACCENTS.ice} onClick={startAfterCountdown} className="mt-7 min-h-16 min-w-52 text-lg" breathe>{t('START RUN')}</GradientButton> : <div className="mt-7 font-mono text-7xl font-bold text-sky-200" aria-live="assertive">{countdown}</div>}
            </div>
          </div>
          <GlassCard className="p-4"><p className="text-sm font-bold text-ink">{t('Foreground recording')}</p><p className="mt-1 text-xs leading-relaxed text-ink-soft">{t('The web prototype cannot guarantee GPS while the phone is locked. Keep APEX visible during the run.')}</p></GlassCard>
        </div>
      </OrbitFrame>
    )
  }

  return (
    <OrbitFrame title="Live run" subtitle={missionLabel(active.mission)} backTo="/orbit" action={<OrbitPill tone={active.paused ? 'amber' : 'emerald'}>{t(active.paused ? 'PAUSED' : watching ? 'RECORDING' : 'GPS WAIT')}</OrbitPill>}>
      <div className="space-y-4">
        <div className="overflow-hidden rounded-[30px] bg-[#050b16] p-4 text-white shadow-2xl sm:p-5">
          <Suspense fallback={<div className="h-72 animate-pulse rounded-[22px] bg-slate-900" />}><OrbitMap planned={plannedPoints} completed={active.samples} current={current} className="h-[42dvh] min-h-72 max-h-[520px]" /></Suspense>
          {deviation != null && deviation > 100 && <div className="mt-3 rounded-2xl border border-amber-300/30 bg-amber-300/10 px-4 py-3 text-sm font-bold text-amber-100">{t('OFF ROUTE')} · {Math.round(deviation)} {t('M')} · {t('Return to route')}</div>}
          {navigationCue && <div className="mt-3 flex items-center justify-between rounded-2xl border border-sky-200/15 bg-sky-300/8 px-4 py-3"><p className="text-sm font-bold text-sky-100">{t(navigationCue.instruction)}</p><span className="font-mono text-xs text-sky-300">{formatDistance(navigationCue.remaining_m)}</span></div>}
          <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div><p className="text-[10px] font-bold text-slate-500">{t('Distance')}</p><p className="mt-1 font-mono text-2xl font-bold">{formatDistance(metrics.distance_m)}</p></div>
            <div><p className="text-[10px] font-bold text-slate-500">{t('Elapsed')}</p><p className="mt-1 font-mono text-2xl font-bold">{formatDuration(elapsed)}</p></div>
            <div><p className="text-[10px] font-bold text-slate-500">{t('Current pace')}</p><p className="mt-1 font-mono text-2xl font-bold">{formatPace(pace)}</p></div>
            <div><p className="text-[10px] font-bold text-slate-500">{t('Average pace')}</p><p className="mt-1 font-mono text-2xl font-bold">{formatPace(metrics.avg_pace_sec_km)}</p></div>
          </div>
          <div className="mt-3 flex flex-wrap gap-2 text-[10px] font-bold text-slate-400"><span className="rounded-full bg-white/5 px-3 py-1.5">{t('CURRENT SPLIT')} {metrics.splits.at(-1) ? `${metrics.splits.at(-1)!.index} · ${formatPace(metrics.splits.at(-1)!.pace_sec_km)}` : t('WAITING')}</span><span className="rounded-full bg-white/5 px-3 py-1.5">{t('TARGET')} · {t(['recovery', 'easy', 'aerobic_base', 'run_walk'].includes(active.mission) ? 'CONVERSATIONAL EFFORT' : 'MISSION-CONTROLLED EFFORT')}</span>{targetMinutes != null && <span className="rounded-full bg-white/5 px-3 py-1.5">{t('PLANNED')} · {targetMinutes} {t('MIN')}</span>}</div>
        </div>

        {(gpsMessage || guidance) && <GlassCard accent={gpsMessage ? ACCENTS.amber : ACCENTS.ice} className="p-4"><p className="text-[10px] font-bold tracking-widest text-ink-faint uppercase">{t('ORBIT COACH')}</p><p className="mt-1 text-sm font-semibold leading-relaxed text-ink">{t(gpsMessage || guidance)}</p></GlassCard>}

        <div className="grid grid-cols-3 gap-2">
          <GradientButton accent={active.paused ? ACCENTS.emerald : ACCENTS.amber} onClick={pauseOrResume} className="min-h-16">{active.paused ? t('Resume') : t('Pause')}</GradientButton>
          <GhostButton onClick={addLap} className="min-h-16">{t('Add lap')}</GhostButton>
          <GradientButton accent={ACCENTS.ice} onClick={() => void finish()} className="min-h-16">{t('Finish')}</GradientButton>
        </div>
        <div className="grid grid-cols-2 gap-2"><GhostButton onClick={() => { if (window.confirm(t('Finish at the current distance? Orbit will analyse the useful work completed.'))) void finish() }}>{t('Shorten run')}</GhostButton><GhostButton onClick={() => { const points = [...active.samples].reverse(); if (points.length < 2) return setGpsMessage('A return path becomes available after enough movement is recorded.'); setReturnPath(points); setGpsMessage('Return-to-start guidance now follows your recorded path in reverse.') }}>{t('Return to start')}</GhostButton></div>
        <div className="flex justify-center"><button type="button" onClick={() => void cancel()} className="min-h-11 px-4 text-xs font-bold text-red-700">{t('Cancel run')}</button></div>
      </div>
    </OrbitFrame>
  )
}
