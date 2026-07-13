import { useMemo } from 'react'
import { addDays, format, isSameMonth, startOfMonth, startOfWeek } from 'date-fns'
import { useLocation, useNavigate } from 'react-router-dom'
import { GlassCard, GhostButton, GradientButton } from '../../components/ui.tsx'
import { ACCENTS } from '../../lib/theme.ts'
import { useStore } from '../../store/AppStore.tsx'
import { adaptAfterMissedSession, campaignFamilyLabel, campaignPhaseLabel, preserveUserOverride, readinessComponents } from '../domain/campaign.ts'
import { PHASE_ORDER } from '../domain/config.ts'
import type { CampaignPhase, CampaignSession, MarathonCampaign } from '../domain/types.ts'
import { missionLabel } from '../domain/analysis.ts'
import { OrbitFrame, OrbitPill } from '../components/OrbitFrame.tsx'
import { useOrbitStore } from '../store/OrbitStore.tsx'
import { useOrbitText } from '../ui/i18n.ts'

const DAY_MS = 86_400_000

function daysUntil(date: string): number {
  return Math.ceil((new Date(`${date}T12:00:00`).getTime() - new Date(new Date().toISOString().slice(0, 10) + 'T12:00:00').getTime()) / DAY_MS)
}

function stateTone(state: string): 'ice' | 'amber' | 'emerald' | 'violet' {
  if (state === 'strong' || state === 'on_track') return 'emerald'
  if (state === 'needs_attention') return 'amber'
  return 'ice'
}

function OrbitalJourney({ phase, sessions }: { phase: CampaignPhase; sessions: CampaignSession[] }) {
  const t = useOrbitText()
  const currentIndex = PHASE_ORDER.indexOf(phase)
  return <div className="relative overflow-hidden rounded-[28px] bg-[#050b16] p-5 text-white"><div className="orbit-stars absolute inset-0 opacity-60" aria-hidden /><div className="relative"><p className="font-mono text-[9px] tracking-[.22em] text-sky-300">{t('CAMPAIGN ORBIT')}</p><div className="mt-5 flex items-center overflow-x-auto pb-2">{PHASE_ORDER.map((item, index) => { const completed = index < currentIndex; const active = index === currentIndex; const completedSessions = sessions.filter((session) => session.phase === item && session.status === 'completed').length; return <div key={item} className="flex min-w-[108px] items-center"><div className="text-center"><div className={`orbit-phase-star mx-auto grid h-9 w-9 place-items-center rounded-full border ${active ? 'border-amber-300 bg-amber-300 text-slate-950 shadow-[0_0_24px_rgba(251,191,36,.75)]' : completed ? 'border-emerald-300/60 bg-emerald-300/20 text-emerald-100' : 'border-sky-200/20 bg-white/5 text-slate-500'}`}>{completedSessions > 0 ? completedSessions : '·'}</div><p className={`mt-2 text-[8px] font-bold uppercase ${active ? 'text-amber-200' : 'text-slate-500'}`}>{t(campaignPhaseLabel(item))}</p></div>{index < PHASE_ORDER.length - 1 && <div className={`mb-6 h-px w-9 ${index < currentIndex ? 'bg-emerald-300/50' : 'bg-white/10'}`} />}</div> })}</div><p className="mt-2 text-xs text-slate-400">{t('Missed sessions reorganise the path. They do not break it.')}</p></div></div>
}

function RaceWeek({ campaign }: { campaign: MarathonCampaign }) {
  const t = useOrbitText()
  return <GlassCard accent={ACCENTS.amber} className="p-5 sm:p-6"><p className="font-mono text-[10px] font-bold tracking-widest text-amber-700">{t('RACE WEEK COMMAND CENTRE')}</p><h3 className="mt-2 font-display text-2xl font-bold text-ink">{t('Calm, rehearsed, decisive.')}</h3><div className="mt-4 grid gap-2 sm:grid-cols-2">{[
    ['Taper status', 'Volume reduced while familiar rhythm remains.'], ['Primary pacing', 'Begin conservatively and settle into rehearsed marathon effort.'], ['Fallback strategy', 'Use controlled perceived effort if weather or course conditions differ.'], ['Fueling', 'Use only products and timing already tolerated in long-run rehearsals.'], ['Breakfast', 'Use a familiar saved breakfast. Do not introduce a new race-day product.'], ['Equipment', 'Shoes, clothing, timing chip, route, transport and start details checked.'], ['Weather decision', 'Current weather is not assumed. Review an authoritative forecast close to the race.'], ['After the finish', 'Begin the scheduled recovery phase instead of returning immediately to hard training.'],
  ].map(([title, body]) => <div key={title} className="rounded-2xl border border-white/80 bg-white/60 p-3"><p className="text-xs font-bold text-ink">{t(title)}</p><p className="mt-1 text-xs leading-relaxed text-ink-soft">{t(body)}</p></div>)}</div><p className="mt-4 text-xs text-ink-soft">{t('Orbit does not promise a finish time. The pacing strategy remains adjustable to conditions and how the body responds.')}</p><OrbitPill tone="amber">{campaign.race_name.toUpperCase()} · {campaign.race_date}</OrbitPill></GlassCard>
}

function CampaignCalendar({ sessions }: { sessions: CampaignSession[] }) {
  const t = useOrbitText()
  const month = startOfMonth(new Date())
  const start = startOfWeek(month, { weekStartsOn: 1 })
  const cells = Array.from({ length: 42 }, (_, index) => addDays(start, index))
  return <GlassCard className="p-5"><div className="flex items-center justify-between"><h3 className="font-display text-lg font-bold text-ink">{t('Campaign calendar')}</h3><span className="font-mono text-[10px] text-ink-faint">{t(format(month, 'MMMM yyyy')).toUpperCase()}</span></div><div className="mt-3 grid grid-cols-7 gap-1">{['MON SHORT', 'TUE SHORT', 'WED SHORT', 'THU SHORT', 'FRI SHORT', 'SAT SHORT', 'SUN SHORT'].map((day) => <div key={day} className="py-1 text-center text-[9px] font-bold text-ink-faint">{t(day)}</div>)}{cells.map((date) => { const iso = format(date, 'yyyy-MM-dd'); const item = sessions.find((session) => session.date === iso); return <div key={iso} className={`relative min-h-12 rounded-xl border p-1.5 ${!isSameMonth(date, month) ? 'border-transparent opacity-25' : item?.status === 'completed' ? 'border-emerald-200 bg-emerald-50/80' : item ? item.adapted.demanding ? 'border-amber-200 bg-amber-50/80' : 'border-sky-100 bg-sky-50/70' : 'border-white/70 bg-white/35'}`}><span className="font-mono text-[9px] font-bold text-ink-soft">{format(date, 'd')}</span>{item && <span className={`absolute right-1.5 bottom-1.5 h-2 w-2 rounded-full ${item.status === 'completed' ? 'bg-emerald-500' : item.adapted.demanding ? 'bg-amber-500' : 'bg-sky-500'}`} title={`${t(item.adapted.title)} · ${t(item.status)}`} />}</div> })}</div><p className="mt-3 text-[10px] text-ink-faint">{t('Sky: controlled · amber: demanding · green: completed. Prescribed and completed states remain separate.')}</p></GlassCard>
}

export function MarathonCampaignPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const t = useOrbitText()
  const app = useStore()
  const orbit = useOrbitStore()
  const campaign = [...orbit.state.campaigns].sort((a, b) => b.created_at.localeCompare(a.created_at))[0] ?? null
  const sessions = useMemo(() => campaign ? orbit.state.sessions.filter((session) => session.campaign_id === campaign.id).sort((a, b) => a.date.localeCompare(b.date)) : [], [campaign, orbit.state.sessions])
  const today = new Date().toISOString().slice(0, 10)
  const todaySession = sessions.find((session) => session.date === today && session.status === 'planned')
  const nextSession = todaySession ?? sessions.find((session) => session.date >= today && session.status === 'planned') ?? null
  const currentPhase = nextSession?.phase ?? campaign?.phase ?? 'foundation'
  const readiness = campaign ? readinessComponents(orbit.state.runs, sessions, { ...campaign, phase: currentPhase }) : []
  const currentWeek = sessions.filter((session) => {
    const delta = Math.abs(new Date(`${session.date}T12:00:00`).getTime() - Date.now()) / DAY_MS
    return delta <= 4
  })
  const justCompleted = Boolean((location.state as { justCompleted?: boolean } | null)?.justCompleted)

  if (!campaign) return <OrbitFrame title="Marathon Campaign" subtitle="An expert running journey without the planning burden." backTo="/orbit"><div className="space-y-4"><div className="relative overflow-hidden rounded-[32px] bg-[#050b16] p-7 text-white shadow-2xl sm:p-10"><div className="orbit-stars absolute inset-0 opacity-75" aria-hidden /><div className="relative max-w-xl"><OrbitPill tone="ice">{t('PERSONAL · PRIVATE · ADAPTIVE')}</OrbitPill><h2 className="mt-5 font-display text-3xl font-bold">{t('Build the credible path to 42.195 km.')}</h2><p className="mt-3 text-sm leading-relaxed text-slate-300">{t('Orbit reuses your APEX profile, strength week, activity history and calendar. It asks only what it does not already know, then assigns a readiness outcome before creating a campaign.')}</p><GradientButton accent={ACCENTS.ice} onClick={() => navigate('/orbit/induction')} className="mt-6 min-h-14">{t('Begin induction')}</GradientButton></div></div><GlassCard className="p-5"><p className="text-sm font-bold text-ink">{t('Not every runner receives a twelve-week plan.')}</p><p className="mt-1 text-xs leading-relaxed text-ink-soft">{t('A credible recent base may enter marathon-specific training. A newer or returning runner receives Foundation first. A timeline that is too close is explained instead of compressed.')}</p></GlassCard></div></OrbitFrame>

  if (campaign.status === 'review_required') return <OrbitFrame title="Marathon Campaign" subtitle="Professional review recommended before strenuous marathon preparation." backTo="/orbit"><GlassCard accent={ACCENTS.amber} className="p-6"><OrbitPill tone="amber">{t('FITNESS-READINESS OUTCOME')}</OrbitPill><h2 className="mt-4 font-display text-2xl font-bold text-ink">{t('Professional review recommended before strenuous marathon preparation')}</h2><p className="mt-3 text-sm leading-relaxed text-ink-soft">{t(campaign.assignment_reason)}</p><p className="mt-3 text-xs leading-relaxed text-ink-faint">{t('This is not a diagnosis and APEX has not medically cleared or rejected you. General Orbit route planning and easy free running remain available, subject to any existing professional restriction.')}</p><div className="mt-5 flex gap-2"><GradientButton accent={ACCENTS.ice} onClick={() => navigate('/orbit')}>{t('Use general Orbit')}</GradientButton><GhostButton onClick={() => navigate('/orbit/induction')}>{t('Review answers')}</GhostButton></div></GlassCard></OrbitFrame>

  if (campaign.status === 'paused') return <OrbitFrame title="Marathon Campaign" subtitle="More information needed" backTo="/orbit"><GlassCard accent={ACCENTS.amber} className="p-6"><OrbitPill tone="amber">{t('TIMELINE CHECK')}</OrbitPill><h2 className="mt-4 font-display text-2xl font-bold text-ink">{t('More information needed')}</h2><p className="mt-3 text-sm leading-relaxed text-ink-soft">{t(campaign.assignment_reason)}</p>{campaign.timeline_warning && <p className="mt-3 rounded-2xl bg-amber-50 p-3 text-sm font-semibold text-amber-900">{t(campaign.timeline_warning)}</p>}<GhostButton onClick={() => navigate('/orbit/induction')} className="mt-5">{t('Review induction')}</GhostButton></GlassCard></OrbitFrame>

  const markMissed = async (session: CampaignSession): Promise<void> => {
    if (!window.confirm(t('Mark this session missed? Orbit will reorganise forward without stacking catch-up work.'))) return
    const adapted = adaptAfterMissedSession(campaign, sessions, session.id)
    await orbit.saveCampaign(adapted.campaign, adapted.sessions)
    app.toast(t('The week was rebalanced without catch-up stacking.'), 'ok')
  }

  const chooseVersion = async (session: CampaignSession, original: boolean): Promise<void> => {
    const updatedSession = preserveUserOverride(session, original)
    const adaptations = campaign.adaptations.map((item) => item.session_id === session.id ? { ...item, accepted: !original } : item)
    await orbit.saveSession(updatedSession)
    await orbit.saveCampaign({ ...campaign, adaptations, updated_at: new Date().toISOString(), sync_state: 'local' }, [])
    app.toast(t(original ? 'Original prescription restored.' : 'Adapted prescription accepted.'), 'ok')
  }

  return (
    <OrbitFrame title="Marathon Campaign" subtitle={`${campaign.race_name} · ${Math.max(0, daysUntil(campaign.race_date))} days remaining`} backTo="/orbit" action={<OrbitPill tone={campaign.outcome === 'foundation' ? 'violet' : 'emerald'}>{t(campaign.outcome === 'foundation' ? 'FOUNDATION FIRST' : 'SPECIFIC CAMPAIGN')}</OrbitPill>}>
      <div className="space-y-4">
        {justCompleted && <GlassCard accent={campaign.outcome === 'foundation' ? ACCENTS.violet : ACCENTS.emerald} className="p-5"><p className="font-mono text-[10px] font-bold tracking-widest text-ink-faint">{t('INDUCTION OUTCOME')}</p><h2 className="mt-2 font-display text-xl font-bold text-ink">{campaign.outcome === 'foundation' ? t('Foundation Phase recommended first') : t('Ready for a marathon-specific campaign')}</h2><p className="mt-2 text-sm leading-relaxed text-ink-soft">{t(campaign.assignment_reason)}</p>{campaign.timeline_warning && <p className="mt-3 rounded-2xl bg-amber-50 p-3 text-sm font-semibold text-amber-900">{t(campaign.timeline_warning)}</p>}</GlassCard>}

        <OrbitalJourney phase={currentPhase} sessions={sessions} />

        {nextSession ? <GlassCard accent={ACCENTS.ice} breathe className="p-5 sm:p-6"><div className="flex flex-wrap items-center justify-between gap-2"><OrbitPill tone={todaySession ? 'amber' : 'ice'}>{t(todaySession ? 'TODAY' : format(new Date(`${nextSession.date}T12:00:00`), 'EEEE · d MMM'))}</OrbitPill><span className="font-mono text-[10px] text-ink-faint">{t(campaignPhaseLabel(nextSession.phase)).toUpperCase()}</span></div><h2 className="mt-4 font-display text-2xl font-bold text-ink">{t(nextSession.adapted.title)}</h2><p className="mt-1 text-sm font-bold text-sky-800">{t(`${nextSession.adapted.duration_min} minutes · ${nextSession.adapted.intensity}`)}</p><div className="mt-4 grid gap-3 sm:grid-cols-2"><div className="rounded-2xl bg-white/60 p-3"><p className="text-[10px] font-bold text-ink-faint">{t('PURPOSE')}</p><p className="mt-1 text-sm leading-relaxed text-ink">{t(nextSession.adapted.purpose)}</p></div><div className="rounded-2xl bg-white/60 p-3"><p className="text-[10px] font-bold text-ink-faint">{t('ROUTE')}</p><p className="mt-1 text-sm leading-relaxed text-ink">{t(nextSession.adapted.route_characteristics)}</p></div></div><details className="mt-3 rounded-2xl border border-white/80 bg-white/45 p-3"><summary className="cursor-pointer text-sm font-bold text-sky-800">{t('Why?')}</summary><p className="mt-2 text-sm leading-relaxed text-ink-soft">{t(nextSession.adapted.why)}</p><p className="mt-2 text-xs text-ink-soft"><strong>{t('Warm-up')}:</strong> {t(nextSession.adapted.warmup)}</p><p className="mt-2 text-xs text-ink-soft"><strong>{t('Main work')}:</strong> {t(nextSession.adapted.main_work)}</p><p className="mt-2 text-xs text-ink-soft"><strong>{t('Cooldown')}:</strong> {t(nextSession.adapted.cooldown)}</p><p className="mt-2 text-xs text-ink-soft"><strong>{t('Fueling')}:</strong> {t(nextSession.adapted.fueling_note)}</p></details>{nextSession.adaptation_reason && <div className="mt-3 rounded-2xl border border-violet-200 bg-violet-50/70 p-3"><p className="text-xs font-bold text-violet-900">{t('PLAN ADAPTATION')}</p><p className="mt-1 text-xs leading-relaxed text-violet-800">{t(nextSession.adaptation_reason)}</p><p className="mt-2 text-[10px] text-violet-700">{t('Original')}: {t(missionLabel(nextSession.original.mission))} · {nextSession.original.duration_min} min. {t('Adapted')}: {t(missionLabel(nextSession.adapted.mission))} · {nextSession.adapted.duration_min} min.</p><div className="mt-2 flex gap-2"><GhostButton onClick={() => void chooseVersion(nextSession, false)}>{t('Use adapted session')}</GhostButton><GhostButton onClick={() => void chooseVersion(nextSession, true)}>{t('Keep original')}</GhostButton></div></div>}<div className="mt-5 grid grid-cols-2 gap-2 sm:flex"><GradientButton accent={ACCENTS.ice} onClick={() => navigate('/orbit/plan', { state: { mission: nextSession.adapted.mission, campaignSessionId: nextSession.id } })}>{t('Choose route')}</GradientButton><GradientButton accent={ACCENTS.emerald} onClick={() => navigate('/orbit/run', { state: { mission: nextSession.adapted.mission, campaignSessionId: nextSession.id } })}>{t('Start session')}</GradientButton>{nextSession.adapted.minimum_version_min && <GhostButton onClick={() => navigate('/orbit/run', { state: { mission: nextSession.adapted.mission, campaignSessionId: nextSession.id, minimumMinutes: nextSession.adapted.minimum_version_min } })}>{t(`Short on time? ${nextSession.adapted.minimum_version_min} min`)}</GhostButton>}<GhostButton onClick={() => void markMissed(nextSession)}>{t('Mark missed')}</GhostButton></div></GlassCard> : <GlassCard accent={ACCENTS.emerald} className="p-6"><h2 className="font-display text-xl font-bold text-ink">{t('Post-marathon recovery')}</h2><p className="mt-2 text-sm text-ink-soft">{t('No demanding session is waiting. Orbit preserves a gradual return before another campaign.')}</p></GlassCard>}

        {currentPhase === 'race_week' && <RaceWeek campaign={campaign} />}

        <GlassCard accent={ACCENTS.violet} className="p-5"><div className="flex items-start justify-between gap-3"><div><p className="font-mono text-[10px] font-bold tracking-widest text-violet-700">{t('Current phase').toUpperCase()}</p><h3 className="mt-1 font-display text-xl font-bold text-ink">{t(campaignPhaseLabel(currentPhase))}</h3><p className="mt-1 text-sm text-ink-soft">{t(campaignFamilyLabel(campaign.family))}</p></div><OrbitPill tone="violet">{campaign.plan_version}</OrbitPill></div><p className="mt-3 text-sm leading-relaxed text-ink-soft">{t(campaign.assignment_reason)}</p></GlassCard>

        <GlassCard className="p-5"><h3 className="font-display text-lg font-bold text-ink">{t('Marathon readiness')}</h3><p className="mt-1 text-xs text-ink-soft">{t('No mysterious score. Every conclusion keeps its reason visible.')}</p><div className="mt-4 grid gap-2 sm:grid-cols-2">{readiness.map((component) => <div key={component.key} className="rounded-2xl border border-white/80 bg-white/55 p-3"><div className="flex items-center justify-between gap-2"><p className="text-sm font-bold text-ink">{t(component.label)}</p><OrbitPill tone={stateTone(component.state)}>{t(component.state.replaceAll('_', ' ')).toUpperCase()}</OrbitPill></div><p className="mt-2 text-xs leading-relaxed text-ink-soft">{t(component.reason)}</p></div>)}</div></GlassCard>

        <GlassCard className="p-5"><h3 className="font-display text-lg font-bold text-ink">{t('Full week')}</h3><div className="mt-3 space-y-2">{currentWeek.length === 0 ? <p className="text-sm text-ink-soft">{t('No prescribed run falls in the current calendar window.')}</p> : currentWeek.map((session) => <div key={session.id} className="flex items-center justify-between rounded-2xl border border-white/80 bg-white/55 px-3 py-3"><div><p className="text-sm font-bold text-ink">{t(format(new Date(`${session.date}T12:00:00`), 'EEE d'))} · {t(session.adapted.title)}</p><p className="text-xs text-ink-soft">{session.adapted.duration_min} min · {t(session.status)}</p></div>{session.status === 'completed' ? <OrbitPill tone="emerald">{t('DONE')}</OrbitPill> : session.adapted.demanding ? <OrbitPill tone="amber">{t('QUALITY')}</OrbitPill> : <OrbitPill tone="ice">{t('EASY')}</OrbitPill>}</div>)}</div><details className="mt-4"><summary className="cursor-pointer text-xs font-bold text-sky-700">{t('View remaining campaign')}</summary><div className="mt-3 max-h-96 space-y-1 overflow-y-auto pr-1">{sessions.filter((session) => session.date >= today).map((session) => <div key={session.id} className="flex justify-between rounded-xl bg-white/45 px-3 py-2 text-xs"><span>{session.date} · {t(session.adapted.title)}</span><span className="font-mono text-ink-faint">{session.adapted.duration_min}m</span></div>)}</div></details></GlassCard>

        <CampaignCalendar sessions={sessions} />

        {campaign.adaptations.length > 0 && <GlassCard accent={ACCENTS.ice} className="p-5"><h3 className="font-display text-lg font-bold text-ink">{t('Recent adaptations')}</h3><div className="mt-3 space-y-2">{campaign.adaptations.slice(-5).reverse().map((adaptation) => <div key={adaptation.id} className="rounded-2xl bg-white/55 p-3"><p className="text-xs font-bold text-ink">{t(missionLabel(adaptation.original_mission))} → {t(missionLabel(adaptation.adapted_mission))}</p><p className="mt-1 text-xs text-ink-soft">{t(adaptation.reason)}</p><p className="mt-1 font-mono text-[9px] text-ink-faint">{t(adaptation.accepted == null ? 'AWAITING YOUR CHOICE' : adaptation.accepted ? 'ADAPTED VERSION ACCEPTED' : 'ORIGINAL KEPT')}</p></div>)}</div></GlassCard>}

        <GlassCard className="p-5"><h3 className="font-display text-base font-bold text-ink">{t('Why this plan is built this way')}</h3><p className="mt-2 text-xs leading-relaxed text-ink-soft">{t('Predominantly controlled running, progressive exposure, purposeful quality, long-run development, recovery, strength coordination, fueling rehearsal and tapering. The rules are versioned and their limitations remain visible.')}</p><GhostButton onClick={() => navigate('/orbit/science')} className="mt-3">{t('Science ledger')}</GhostButton></GlassCard>

        <p className="px-3 text-center text-[10px] leading-relaxed text-ink-faint">{t('APEX Orbit Marathon Campaign provides personalized fitness training, educational guidance and performance tracking for adults preparing for endurance events. It does not diagnose, treat, monitor, predict or prevent disease or injury and does not determine medical fitness for exercise.')}</p>
      </div>
    </OrbitFrame>
  )
}
