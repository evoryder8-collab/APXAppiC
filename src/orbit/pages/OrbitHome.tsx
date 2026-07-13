import { useMemo, useState } from 'react'
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
  const [mission, setMission] = useState<RunMission>(todaySession?.adapted.mission ?? 'aerobic_base')
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
  }), [latestSnapshot, lowerDates, previousSnapshot, state.runs, today, todaySession])
  const effectiveMission = todaySession ? todaySession.adapted.mission : mission
  const primaryTitle = state.active_run ? t('Continue run') : todaySession ? todaySession.adapted.title : recommendation.title
  const recentRuns = [...state.runs].sort((a, b) => b.started_at.localeCompare(a.started_at)).slice(0, 3)
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

  const start = () => navigate('/orbit/run', { state: {
    mission: state.active_run?.mission ?? effectiveMission,
    campaignSessionId: todaySession?.id ?? null,
    routeId: state.active_run?.route_id ?? null,
  } })

  return (
    <OrbitFrame
      title="Run Intelligence"
      subtitle="Your next run, already reasoned through."
      action={<OrbitPill tone={syncState === 'queued' ? 'amber' : 'ice'}>{syncState.toUpperCase()}</OrbitPill>}
    >
      <div className="space-y-5">
        <motion.section initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }}>
          <div className="orbit-command relative overflow-hidden rounded-[30px] bg-[#07111f] p-5 text-white shadow-[0_28px_80px_-32px_rgba(56,189,248,.78)] sm:p-7">
            <div className="orbit-stars pointer-events-none absolute inset-0 opacity-60" aria-hidden />
            <div className="relative">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <OrbitPill tone={todaySession ? 'amber' : 'ice'}>{todaySession ? campaignPhaseLabel(todaySession.phase).toUpperCase() : missionLabel(recommendation.mission).toUpperCase()}</OrbitPill>
                <span className="font-mono text-[10px] text-slate-400">{t(format(new Date(), 'EEEE · d MMMM'))}</span>
              </div>
              <h2 className="mt-5 max-w-xl font-display text-[29px] leading-tight font-bold">{t(primaryTitle)}</h2>
              <p className="mt-2 text-sm font-semibold text-sky-100/80">
                {t(state.active_run ? 'An interrupted run is stored privately on this device and is ready to continue.' : `${todaySession?.adapted.duration_min ?? recommendation.duration_min} minutes · ${missionLabel(effectiveMission)}`)}
              </p>
              {!todaySession && !state.active_run && <div className="mt-4"><MissionPicker value={mission} onChange={setMission} compact /></div>}
              <details className="mt-5 rounded-2xl border border-white/10 bg-white/5 px-4 py-3">
                <summary className="cursor-pointer text-sm font-bold text-sky-200">{t('Why?')}</summary>
                <p className="mt-2 text-sm leading-relaxed text-slate-300">{t(todaySession?.adapted.why ?? recommendation.reason)}{todayEvent ? ` ${t('Calendar context')}: ${todayEvent.name} ${t('is scheduled today')}.` : ''}{comparable ? ` ${t('Last comparable run')}: ${comparable.local_date} · ${formatDistance(comparable.metrics.distance_m)}.` : ''}</p>
              </details>
              <div className="mt-5 grid grid-cols-2 gap-3 sm:flex">
                <GradientButton accent={ACCENTS.ice} onClick={start} className="min-h-14 sm:min-w-44" breathe>{state.active_run ? t('Continue run') : t('Start session')}</GradientButton>
                <button onClick={() => navigate('/orbit/plan', { state: { mission: effectiveMission, campaignSessionId: todaySession?.id ?? null } })} className="min-h-14 rounded-2xl border border-white/15 bg-white/8 px-5 text-sm font-bold text-white active:scale-95">{t('Choose route')}</button>
              </div>
            </div>
          </div>
        </motion.section>

        <div className="grid grid-cols-3 gap-3">
          <GlassCard accent={ACCENTS.ice} className="p-3.5 sm:p-4"><p className="text-[10px] font-bold text-ink-faint">{t('This week')}</p><p className="mt-1 font-mono text-lg font-bold text-ink">{(weeklyKm / 1000).toFixed(1)} km</p></GlassCard>
          <GlassCard accent={ACCENTS.violet} className="p-3.5 sm:p-4"><p className="text-[10px] font-bold text-ink-faint">{t('Last long run')}</p><p className="mt-1 font-mono text-lg font-bold text-ink">{lastLong ? formatDistance(lastLong.metrics.distance_m) : t('No data')}</p></GlassCard>
          <GlassCard accent={ACCENTS.emerald} className="p-3.5 sm:p-4"><p className="text-[10px] font-bold text-ink-faint">{t('Recovery context')}</p><p className="mt-1 font-mono text-lg font-bold text-ink">{latestSnapshot ? Math.round(latestSnapshot.health) : t('No data')}</p></GlassCard>
        </div>

        <GlassCard className="p-4"><p className="text-[10px] font-bold tracking-widest text-ink-faint">{t('Today in APEX')}</p><div className="mt-2 grid gap-2 text-xs text-ink-soft sm:grid-cols-3"><p><strong className="text-ink">{t('Calendar:')}</strong> {todayEvent ? `${todayEvent.name} · ${todayEvent.type.replaceAll('_', ' ')}` : t('No demanding event recorded')}</p><p><strong className="text-ink">{t('Strength')}:</strong> {t(lowerDates.has(today) ? 'Lower-body work is scheduled' : 'No lower-body session recorded today')}</p><p><strong className="text-ink">{t('Nutrition:')}</strong> {t(todayNutrition?.kcal == null ? 'No intake logged yet' : `${todayNutrition.kcal} kcal logged so far`)}</p></div></GlassCard>

        {activeCampaign && (
          <GlassCard accent={ACCENTS.violet} breathe className="p-5">
            <div className="flex items-start justify-between gap-3">
              <div><p className="font-mono text-[10px] font-bold tracking-widest text-violet uppercase">{t('Marathon Campaign')}</p><h3 className="mt-1 font-display text-xl font-bold text-ink">{t(campaignFamilyLabel(activeCampaign.family))}</h3><p className="mt-1 text-sm font-medium text-ink-soft">{t(campaignPhaseLabel(activeCampaign.phase))} · {activeCampaign.race_name}</p>{raceDaysRemaining != null && <p className="mt-1 font-mono text-[10px] font-bold text-violet">{raceDaysRemaining} {t('days remaining')}</p>}</div>
              <GhostButton onClick={() => navigate('/orbit/campaign')}>{t('Open')}</GhostButton>
            </div>
          </GlassCard>
        )}

        <div className="grid gap-3 sm:grid-cols-2">
          {familiarRoute && <button type="button" onClick={() => navigate('/orbit/run', { state: { routeId: familiarRoute.id, mission: familiarRoute.mission_tags[0] ?? 'easy' } })} className="glass rounded-3xl p-4 text-left active:scale-[.985]"><p className="font-display text-base font-bold text-ink">{t('Repeat familiar route')}</p><p className="mt-1 text-xs font-medium text-ink-soft">{familiarRoute.name} · {formatDistance(familiarRoute.distance_m)}</p></button>}
          {[
            ['/orbit/plan', 'Plan a run', 'Route mission, distance and terrain'],
            ['/orbit/campaign', 'Marathon Campaign', activeCampaign ? 'Today, phase and readiness' : 'Induction and campaign assignment'],
            ['/orbit/library?view=routes', 'Saved routes', 'Route DNA, GPX and favourites'],
            ['/orbit/library?view=segments', 'Personal segments', 'Private efforts without leaderboards'],
            ['/orbit/library?view=shoes', 'Running shoes', 'Distance, surfaces and notes'],
          ].map(([to, title, body]) => (
            <button key={to} type="button" onClick={() => navigate(to)} className="glass rounded-3xl p-4 text-left active:scale-[.985]">
              <p className="font-display text-base font-bold text-ink">{t(title)}</p><p className="mt-1 text-xs font-medium text-ink-soft">{t(body)}</p>
            </button>
          ))}
        </div>

        <GlassCard className="p-5">
          <div className="flex items-center justify-between"><h3 className="font-display text-lg font-bold text-ink">{t('Recent runs')}</h3>{recentRuns.length > 0 && <button onClick={() => navigate('/orbit/library?view=runs')} className="text-xs font-bold text-sky-700">{t('VIEW ALL')}</button>}</div>
          {recentRuns.length === 0 ? <div className="py-6 text-center"><p className="font-bold text-ink">{t('No run history yet')}</p><p className="mx-auto mt-1 max-w-sm text-sm text-ink-soft">{t('Your first completed run will become a private performance baseline.')}</p></div> : (
            <div className="mt-3 space-y-2">{recentRuns.map((run) => <button key={run.id} onClick={() => navigate(`/orbit/debrief/${run.id}`)} className="flex w-full items-center justify-between rounded-2xl border border-white/80 bg-white/55 px-3.5 py-3 text-left"><div><p className="text-sm font-bold text-ink">{missionLabel(run.mission)}</p><p className="text-xs text-ink-soft">{run.local_date} · {formatDuration(run.metrics.moving_s)}</p></div><span className="font-mono text-sm font-bold text-sky-700">{formatDistance(run.metrics.distance_m)}</span></button>)}</div>
          )}
        </GlassCard>

        <GlassCard className="p-5">
          <p className="font-display text-base font-bold text-ink">{t('Private by design')}</p>
          <p className="mt-1 text-xs leading-relaxed text-ink-soft">{t('Routes, tracks, readiness answers and campaign notes remain user-scoped. There is no public feed, leaderboard or follower graph.')}</p>
          <div className="mt-3 flex flex-wrap gap-2"><GhostButton onClick={exportPrivateData}>{t('Export Orbit data')}</GhostButton><GhostButton onClick={() => {
            if (!window.confirm(t('Permanently delete all Orbit routes, runs, campaign answers and shoe records for this profile?'))) return
            void deleteAllPrivateData().then(() => toast(t('Orbit data deleted'), 'ok'))
          }}>{t('Delete Orbit data')}</GhostButton></div>
        </GlassCard>
      </div>
    </OrbitFrame>
  )
}
