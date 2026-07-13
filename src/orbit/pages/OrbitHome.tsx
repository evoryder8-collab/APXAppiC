import { lazy, Suspense, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { addDays, differenceInCalendarDays, format, parseISO, subDays } from 'date-fns'
import { motion } from 'framer-motion'
import { GlassCard, GhostButton, GradientButton } from '../../components/ui.tsx'
import { ACCENTS } from '../../lib/theme.ts'
import { todayIso } from '../../lib/plan.ts'
import { useStore } from '../../store/AppStore.tsx'
import { missionLabel } from '../domain/analysis.ts'
import { campaignFamilyLabel, campaignPhaseLabel } from '../domain/campaign.ts'
import { recommendMission } from '../domain/missions.ts'
import type { RunMission } from '../domain/types.ts'
import { OrbitFrame, OrbitPill } from '../components/OrbitFrame.tsx'
import { MissionPicker } from '../components/MissionPicker.tsx'
import { useOrbitStore } from '../store/OrbitStore.tsx'
import { formatDistance, formatDuration } from '../ui/format.ts'
import { useOrbitText } from '../ui/i18n.ts'

const OrbitMap = lazy(() => import('../components/OrbitMap.tsx').then((module) => ({ default: module.OrbitMap })))

export function OrbitHome() {
  const navigate = useNavigate()
  const t = useOrbitText()
  const { data, snapshots, toast } = useStore()
  const { state, syncState, exportPrivateData, deleteAllPrivateData } = useOrbitStore()
  const today = todayIso()
  const activeCampaign = state.campaigns.find((campaign) => campaign.status === 'active') ?? null
  const todaySession = activeCampaign
    ? state.sessions.find((session) => session.campaign_id === activeCampaign.id && session.date === today && session.status === 'planned') ?? null
    : null
  const dayType = new Map(data.program_days.map((day) => [day.id, day.day_type]))
  const lowerDates = new Set(data.workout_sessions.filter((session) => ['legs_a', 'legs_b'].includes(dayType.get(session.program_day_id) ?? '')).map((session) => session.date))
  const todayEvent = data.events.find((event) => event.start_date <= today && event.end_date >= today) ?? null
  const todayNutrition = data.daily_logs.find((log) => log.date === today)
  const latestSnapshot = snapshots.at(-1)
  const previousSnapshot = snapshots.length > 7 ? snapshots.at(-8) : null
  const [missionOverride, setMissionOverride] = useState<RunMission | null>(null)
  const [choosingMission, setChoosingMission] = useState(false)
  const recommendation = useMemo(() => recommendMission({
    campaignMission: todaySession?.adapted.mission,
    campaignTitle: todaySession?.adapted.title,
    campaignDurationMin: todaySession?.adapted.duration_min,
    lowerBodyYesterday: lowerDates.has(format(subDays(parseISO(today), 1), 'yyyy-MM-dd')),
    lowerBodyToday: lowerDates.has(today),
    lowerBodyTomorrow: lowerDates.has(format(addDays(parseISO(today), 1), 'yyyy-MM-dd')),
    recoveryStable: (latestSnapshot?.health ?? 60) >= 50,
    enduranceTrend: latestSnapshot && previousSnapshot
      ? latestSnapshot.endurance < previousSnapshot.endurance - 0.5 ? 'declining' : latestSnapshot.endurance > previousSnapshot.endurance + 0.5 ? 'rising' : 'stable'
      : 'unknown',
    availableMinutes: todayEvent?.type === 'filming_championship' ? 30 : 60,
    recentRuns: state.runs,
  }), [latestSnapshot, lowerDates, previousSnapshot, state.runs, today, todayEvent?.type, todaySession])
  const effectiveMission = todaySession?.adapted.mission ?? missionOverride ?? recommendation.mission
  const primaryTitle = state.active_run
    ? t('Continue run')
    : todaySession
      ? todaySession.adapted.title
      : missionOverride
        ? missionLabel(missionOverride)
        : recommendation.title
  const primaryDuration = todaySession?.adapted.duration_min ?? recommendation.duration_min
  const recentRuns = [...state.runs].sort((a, b) => b.started_at.localeCompare(a.started_at)).slice(0, 2)
  const latestRun = recentRuns[0] ?? null
  const weekStart = format(subDays(new Date(), 6), 'yyyy-MM-dd')
  const weeklyKm = state.runs.filter((run) => run.local_date >= weekStart).reduce((sum, run) => sum + run.metrics.distance_m, 0)
  const lastLong = [...state.runs].filter((run) => run.mission === 'long_run').sort((a, b) => b.started_at.localeCompare(a.started_at))[0]
  const comparable = [...state.runs].filter((run) => run.mission === effectiveMission).sort((a, b) => b.started_at.localeCompare(a.started_at))[0]
  const routeCompletions = state.runs.reduce((counts, run) => {
    if (run.route_id) counts.set(run.route_id, (counts.get(run.route_id) ?? 0) + 1)
    return counts
  }, new Map<string, number>())
  const familiarRoute = [...state.routes].sort((a, b) => {
    const aPriority = (a.favourite ? 1000 : 0) + (routeCompletions.get(a.id) ?? 0)
    const bPriority = (b.favourite ? 1000 : 0) + (routeCompletions.get(b.id) ?? 0)
    return bPriority - aPriority || b.updated_at.localeCompare(a.updated_at)
  })[0] ?? null
  const raceDaysRemaining = activeCampaign ? Math.max(0, differenceInCalendarDays(parseISO(activeCampaign.race_date), parseISO(today))) : null
  const routeHistory = state.routes.map((route) => route.points)

  const start = () => navigate('/orbit/run', { state: {
    mission: state.active_run?.mission ?? effectiveMission,
    campaignSessionId: todaySession?.id ?? null,
    routeId: state.active_run?.route_id ?? null,
  } })

  return (
    <OrbitFrame
      title="Run Intelligence"
      subtitle="One useful decision now. Everything deeper stays one tap away."
      action={<OrbitPill tone={syncState === 'queued' ? 'amber' : 'ice'}>{syncState.toUpperCase()}</OrbitPill>}
    >
      <div className="space-y-4">
        <motion.section initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }}>
          <div className="orbit-command relative overflow-hidden rounded-[32px] bg-[#050b16] text-white shadow-[0_30px_84px_-34px_rgba(56,189,248,.8)]">
            <div className="orbit-stars pointer-events-none absolute inset-0 opacity-55" aria-hidden />
            <div className="relative p-5 pb-4 sm:p-7 sm:pb-5">
              <div className="flex items-center justify-between gap-3">
                <OrbitPill tone={todaySession ? 'amber' : 'ice'}>{t(missionLabel(effectiveMission)).toUpperCase()}</OrbitPill>
                <span className="font-mono text-[9px] font-bold tracking-wide text-slate-400">{format(new Date(), 'EEE · d MMM').toUpperCase()}</span>
              </div>
              <div className="mt-4 flex items-end justify-between gap-4">
                <div className="min-w-0">
                  <p className="font-mono text-[9px] font-bold tracking-[.18em] text-cyan-300/70">{t(state.active_run ? 'READY TO CONTINUE' : 'TODAY’S BEST NEXT MOVE')}</p>
                  <h2 className="mt-1 max-w-xl font-display text-[30px] leading-[1.05] font-bold sm:text-4xl">{t(primaryTitle)}</h2>
                  <p className="mt-2 text-sm font-semibold text-sky-100/75">{state.active_run ? t('Your run is safely stored on this device.') : `${primaryDuration} ${t('MIN')} · ${t(missionLabel(effectiveMission))}`}</p>
                </div>
                {!state.active_run && <div className="shrink-0 text-right"><p className="font-mono text-3xl font-bold text-white">{primaryDuration}</p><p className="text-[9px] font-bold tracking-widest text-slate-500">{t('MIN')}</p></div>}
              </div>
              <button type="button" onClick={() => setChoosingMission((open) => !open)} className="mt-4 min-h-10 rounded-full border border-white/10 bg-white/6 px-3 text-[11px] font-bold text-sky-200 active:scale-95">{t(choosingMission ? 'Keep this mission' : 'Change mission')}</button>
              {choosingMission && !todaySession && !state.active_run && <div className="mt-3 rounded-2xl border border-white/10 bg-white/5 p-3"><MissionPicker value={effectiveMission} onChange={(next) => { setMissionOverride(next); setChoosingMission(false) }} compact /></div>}
            </div>

            <div className="relative px-3 sm:px-5">
              <Suspense fallback={<div className="h-56 animate-pulse rounded-[26px] bg-slate-900" />}>
                <OrbitMap
                  planned={familiarRoute?.points ?? []}
                  completed={familiarRoute ? [] : latestRun?.samples ?? []}
                  history={routeHistory}
                  className="h-56 sm:h-64"
                />
              </Suspense>
            </div>

            <div className="relative p-4 sm:p-5">
              <details className="mb-4 rounded-2xl border border-white/10 bg-white/5 px-4 py-3">
                <summary className="cursor-pointer text-xs font-bold text-sky-200">{t('Why this run?')}</summary>
                <p className="mt-2 text-xs leading-relaxed text-slate-300">{t(todaySession?.adapted.why ?? recommendation.reason)}{todayEvent ? ` ${t('Calendar context')}: ${todayEvent.name} ${t('is scheduled today')}.` : ''}{comparable ? ` ${t('Last comparable run')}: ${comparable.local_date} · ${formatDistance(comparable.metrics.distance_m)}.` : ''}</p>
              </details>
              <GradientButton accent={ACCENTS.ice} onClick={start} className="min-h-16 w-full text-base" breathe>{state.active_run ? t('CONTINUE RUN') : t('START RUN')}</GradientButton>
              <div className="mt-2 grid grid-cols-2 gap-2">
                <button onClick={() => navigate('/orbit/plan', { state: { mission: effectiveMission, campaignSessionId: todaySession?.id ?? null } })} className="min-h-12 rounded-2xl border border-white/12 bg-white/7 px-3 text-xs font-bold text-white active:scale-95">{t('Choose route')}</button>
                <button onClick={() => navigate('/orbit/run', { state: { mission: 'free_run' } })} className="min-h-12 rounded-2xl border border-white/12 bg-white/7 px-3 text-xs font-bold text-white active:scale-95">{t('Start free run')}</button>
              </div>
              {familiarRoute && <button type="button" onClick={() => navigate('/orbit/run', { state: { routeId: familiarRoute.id, mission: familiarRoute.mission_tags[0] ?? 'easy' } })} className="mt-2 flex min-h-12 w-full items-center justify-between rounded-2xl bg-white/5 px-4 text-left text-xs font-bold text-sky-100"><span>{t('Repeat familiar route')}</span><span className="font-mono text-[10px] text-sky-300">{familiarRoute.name} · {formatDistance(familiarRoute.distance_m)}</span></button>}
            </div>
          </div>
        </motion.section>

        <div className="grid grid-cols-3 gap-2.5">
          <GlassCard accent={ACCENTS.ice} className="p-3.5"><p className="text-[9px] font-bold text-ink-faint">{t('THIS WEEK')}</p><p className="mt-1 font-mono text-lg font-bold text-ink">{(weeklyKm / 1000).toFixed(1)} <span className="text-[10px] text-ink-faint">KM</span></p></GlassCard>
          <GlassCard accent={ACCENTS.violet} className="p-3.5"><p className="text-[9px] font-bold text-ink-faint">{t('LONG RUN')}</p><p className="mt-1 font-mono text-lg font-bold text-ink">{lastLong ? formatDistance(lastLong.metrics.distance_m) : '0 km'}</p></GlassCard>
          <GlassCard accent={ACCENTS.emerald} className="p-3.5"><p className="text-[9px] font-bold text-ink-faint">{t('RECOVERY')}</p><p className="mt-1 font-mono text-lg font-bold text-ink">{latestSnapshot ? Math.round(latestSnapshot.health) : '·'}</p></GlassCard>
        </div>

        <details className="glass group rounded-[26px] border border-white/80 p-4">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-3"><div><p className="font-display text-base font-bold text-ink">{t('Today’s context')}</p><p className="mt-0.5 text-xs text-ink-soft">{t('Calendar, strength and nutrition signals')}</p></div><span className="grid h-9 w-9 place-items-center rounded-full bg-white/70 text-lg text-ink transition group-open:rotate-45">+</span></summary>
          <div className="mt-4 grid gap-3 border-t border-slate-200/70 pt-4 text-xs text-ink-soft sm:grid-cols-3"><p><strong className="text-ink">{t('Calendar:')}</strong> {todayEvent ? `${todayEvent.name} · ${todayEvent.type.replaceAll('_', ' ')}` : t('No demanding event recorded')}</p><p><strong className="text-ink">{t('Strength')}:</strong> {t(lowerDates.has(today) ? 'Lower-body work is scheduled' : 'No lower-body session recorded today')}</p><p><strong className="text-ink">{t('Nutrition:')}</strong> {t(todayNutrition?.kcal == null ? 'No intake logged yet' : `${todayNutrition.kcal} kcal logged so far`)}</p></div>
        </details>

        {activeCampaign && (
          <GlassCard accent={ACCENTS.violet} className="p-5">
            <div className="flex items-center justify-between gap-3"><div className="min-w-0"><p className="font-mono text-[9px] font-bold tracking-widest text-violet uppercase">{t('Marathon Campaign')}</p><h3 className="mt-1 truncate font-display text-lg font-bold text-ink">{t(campaignFamilyLabel(activeCampaign.family))}</h3><p className="mt-1 text-xs font-medium text-ink-soft">{t(campaignPhaseLabel(activeCampaign.phase))} · {activeCampaign.race_name}{raceDaysRemaining != null ? ` · ${raceDaysRemaining} ${t('days remaining')}` : ''}</p></div><GhostButton onClick={() => navigate('/orbit/campaign')}>{t('Open')}</GhostButton></div>
          </GlassCard>
        )}

        <GlassCard className="p-5">
          <div className="flex items-center justify-between"><div><h3 className="font-display text-lg font-bold text-ink">{t('Recent performance')}</h3><p className="mt-0.5 text-xs text-ink-soft">{t('Your private running history')}</p></div>{recentRuns.length > 0 && <button onClick={() => navigate('/orbit/library?view=runs')} className="min-h-10 px-2 text-[10px] font-bold text-sky-700">{t('VIEW ALL')}</button>}</div>
          {recentRuns.length === 0 ? <div className="py-5 text-center"><p className="font-bold text-ink">{t('No run history yet')}</p><p className="mx-auto mt-1 max-w-sm text-xs text-ink-soft">{t('Your first completed run will become a private performance baseline.')}</p></div> : (
            <div className="mt-3 space-y-2">{recentRuns.map((run) => <button key={run.id} onClick={() => navigate(`/orbit/debrief/${run.id}`)} className="flex w-full items-center justify-between rounded-2xl border border-white/80 bg-white/55 px-3.5 py-3 text-left"><div><p className="text-sm font-bold text-ink">{t(missionLabel(run.mission))}</p><p className="text-[11px] text-ink-soft">{run.local_date} · {formatDuration(run.metrics.moving_s)}</p></div><span className="font-mono text-sm font-bold text-sky-700">{formatDistance(run.metrics.distance_m)}</span></button>)}</div>
          )}
        </GlassCard>

        <details className="glass group rounded-[26px] border border-white/80 p-4">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-3"><div><p className="font-display text-base font-bold text-ink">{t('More from Orbit')}</p><p className="mt-0.5 text-xs text-ink-soft">{t('Routes, segments, shoes, science and privacy')}</p></div><span className="grid h-9 w-9 place-items-center rounded-full bg-white/70 text-lg text-ink transition group-open:rotate-45">+</span></summary>
          <div className="mt-4 grid grid-cols-2 gap-2 border-t border-slate-200/70 pt-4">
            {[
              ['/orbit/library?view=routes', 'Saved routes'],
              ['/orbit/library?view=segments', 'Personal segments'],
              ['/orbit/library?view=shoes', 'Running shoes'],
              ['/orbit/science', 'Science ledger'],
            ].map(([to, label]) => <button key={to} type="button" onClick={() => navigate(to)} className="min-h-12 rounded-2xl border border-white/80 bg-white/60 px-3 text-left text-xs font-bold text-ink active:scale-[.98]">{t(label)}</button>)}
          </div>
          <div className="mt-3 rounded-2xl bg-slate-50/70 p-3"><p className="text-xs font-bold text-ink">{t('Private by design')}</p><p className="mt-1 text-[11px] leading-relaxed text-ink-soft">{t('Routes, tracks, readiness answers and campaign notes remain user-scoped. There is no public feed, leaderboard or follower graph.')}</p><div className="mt-3 flex flex-wrap gap-2"><GhostButton onClick={exportPrivateData}>{t('Export Orbit data')}</GhostButton><GhostButton onClick={() => {
            if (!window.confirm(t('Permanently delete all Orbit routes, runs, campaign answers and shoe records for this profile?'))) return
            void deleteAllPrivateData().then(() => toast(t('Orbit data deleted'), 'ok'))
          }}>{t('Delete Orbit data')}</GhostButton></div></div>
        </details>
      </div>
    </OrbitFrame>
  )
}
