import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { CoachScopePicker } from '../components/coach/CoachScopePicker'
import { coachAPI } from '../lib/coachApi'
import { coachText } from '../lib/coachCopy'
import type { CoachConsentScope } from '../lib/coachPlatform'
import { useLanguage } from '../lib/i18n'
import { useStore } from '../store/AppStore'

const WEEKDAYS: Record<'en' | 'ro' | 'th', string[]> = {
  en: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
  ro: ['Luni', 'Marți', 'Miercuri', 'Joi', 'Vineri', 'Sâmbătă', 'Duminică'],
  th: ['วันจันทร์', 'วันอังคาร', 'วันพุธ', 'วันพฤหัสบดี', 'วันศุกร์', 'วันเสาร์', 'วันอาทิตย์'],
}

export function CoachPlan() {
  const { coachContext, refresh, refreshCoachContext, toast } = useStore()
  const { language } = useLanguage()
  const navigate = useNavigate()
  const t = (value: string) => coachText(value, language)
  const sponsorship = coachContext.sponsorship
  const plan = coachContext.current_plan
  const [scopes, setScopes] = useState<CoachConsentScope[]>(sponsorship?.consented_scopes.filter((scope) => scope !== 'visual_progress') ?? [])
  const [visualProgress, setVisualProgress] = useState(sponsorship?.consented_scopes.includes('visual_progress') ?? false)
  const [busy, setBusy] = useState<string | null>(null)

  useEffect(() => {
    setScopes(sponsorship?.consented_scopes.filter((scope) => scope !== 'visual_progress') ?? [])
    setVisualProgress(sponsorship?.consented_scopes.includes('visual_progress') ?? false)
  }, [sponsorship])

  const run = async (name: string, operation: () => Promise<unknown>, success: string) => {
    setBusy(name)
    try {
      await operation()
      await refreshCoachContext()
      toast(t(success), 'ok')
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Could not update your coach plan.', 'error')
    } finally {
      setBusy(null)
    }
  }

  if (!sponsorship || !coachContext.capabilities.sponsored_client) {
    return <div className="mx-auto max-w-xl pt-12 text-center"><h1 className="font-display text-3xl font-black text-ink">{t('Your coach plan')}</h1><p className="mt-3 text-sm font-semibold text-ink-soft">No active coach relationship.</p><Link to="/" className="mt-6 inline-flex rounded-full bg-emerald-600 px-5 py-3 text-sm font-black text-white">{t('Return home')}</Link></div>
  }

  const grace = sponsorship.relationship_status === 'grace' || sponsorship.seat_state === 'grace'
  const offeredScopes = sponsorship.offered_scopes ?? sponsorship.consented_scopes

  return (
    <div className="mx-auto w-full max-w-3xl space-y-5">
      <header className="rounded-[2rem] bg-gradient-to-br from-violet-600 via-fuchsia-500 to-amber-300 p-6 text-white shadow-[0_28px_70px_-30px_rgba(126,34,206,.75)] sm:p-8">
        <p className="font-mono text-[10px] font-black tracking-[0.2em] uppercase opacity-80">{t('Provided by')} {sponsorship.coach_display_name}</p>
        <h1 className="mt-2 font-display text-4xl font-black tracking-tight sm:text-5xl">{t('Your coach plan')}</h1>
        {grace && <div className="mt-5 rounded-2xl border border-white/30 bg-white/17 p-4 backdrop-blur"><p className="text-sm font-black">{t('Read-only grace period')}</p><p className="mt-1 text-xs font-semibold text-white/85">{t('Your last valid plan stays visible, but it cannot be changed or activated.')}</p></div>}
      </header>

      <section className="rounded-[1.75rem] border border-white/85 bg-white/76 p-5 shadow-[0_24px_60px_-36px_rgba(72,49,128,.45)] backdrop-blur-xl sm:p-7">
        {!plan ? <p className="py-12 text-center text-sm font-bold text-ink-soft">{t('Nothing has been published yet.')}</p> : (
          <>
            <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="font-mono text-[9px] font-black tracking-[0.16em] text-violet-700 uppercase">Version {plan.version}</p><h2 className="mt-1 font-display text-3xl font-black text-ink">{plan.title}</h2><p className="mt-2 text-sm font-semibold leading-relaxed text-ink-soft">{plan.objective}</p></div>{plan.review_date && <span className="rounded-full bg-violet-100 px-3 py-2 text-[10px] font-black text-violet-800">{t('Review date')} · {plan.review_date}</span>}</div>
            {plan.coach_note && <div className="mt-5 rounded-2xl bg-amber-50 p-4 text-sm font-semibold leading-relaxed text-amber-950">{plan.coach_note}</div>}
            <div className="mt-5 space-y-3">
              {plan.plan.sessions.map((session) => (
                <article key={session.id} className="rounded-2xl border border-violet-100 bg-violet-50/55 p-4">
                  <div className="flex items-start justify-between gap-3"><div><p className="font-mono text-[9px] font-black tracking-[0.13em] text-violet-700 uppercase">{WEEKDAYS[language][session.weekday - 1]}</p><h3 className="mt-1 text-lg font-black text-ink">{session.name}</h3></div><span className="rounded-full bg-white px-3 py-1.5 text-[9px] font-black text-ink-soft">{session.estimated_minutes} {t('minutes')}</span></div>
                  {session.warmup_note && <p className="mt-3 text-xs font-semibold text-ink-soft">{session.warmup_note}</p>}
                  <ol className="mt-3 space-y-2">{session.exercises.map((exercise) => <li key={exercise.id} className="flex items-start justify-between gap-3 rounded-xl bg-white/85 px-3 py-2.5"><div className="min-w-0"><p className="break-words text-sm font-black text-ink">{exercise.name}</p>{exercise.notes && <p className="mt-0.5 text-[10px] font-semibold text-ink-soft">{exercise.notes}</p>}</div><span className="shrink-0 font-mono text-[10px] font-black text-violet-700">{exercise.sets} × {exercise.target_min === exercise.target_max ? exercise.target_min : `${exercise.target_min}–${exercise.target_max}`} {exercise.unit}</span></li>)}</ol>
                </article>
              ))}
            </div>
            {!grace && <div className="mt-5 grid gap-3 sm:grid-cols-2"><button type="button" disabled={busy != null || plan.acknowledged_at != null} onClick={() => void run('ack', () => coachAPI.acknowledgePlan(plan.id), 'Acknowledge plan')} className="rounded-2xl border border-violet-200 bg-white px-4 py-3 text-sm font-black text-violet-800 disabled:opacity-45">{plan.acknowledged_at ? '✓ ' : ''}{t('Acknowledge plan')}</button><button type="button" disabled={busy != null || !plan.acknowledged_at || plan.activated_at != null} onClick={() => void run('activate', async () => { await coachAPI.activatePlan(plan.id); await refresh() }, 'Plan active')} className="rounded-2xl bg-gradient-to-r from-violet-600 to-fuchsia-500 px-4 py-3 text-sm font-black text-white shadow-lg disabled:opacity-40">{plan.activated_at ? '✓ ' : ''}{t('Activate plan')}</button></div>}
          </>
        )}
      </section>

      <section className="rounded-[1.75rem] border border-white/85 bg-white/76 p-5 shadow-[0_24px_60px_-36px_rgba(72,49,128,.45)] backdrop-blur-xl sm:p-7">
        <h2 className="font-display text-2xl font-black text-ink">{t('Privacy controls')}</h2><p className="mt-1 text-xs font-semibold text-ink-soft">{t('You decide what your coach can see.')}</p>
        <div className="mt-5"><CoachScopePicker language={language} scopes={scopes} onChange={setScopes} allowedScopes={offeredScopes} visualProgressOffered={offeredScopes.includes('visual_progress')} visualProgressConsent={visualProgress} onVisualProgressConsent={setVisualProgress} disabled={grace} /></div>
        <button type="button" disabled={busy != null || grace} onClick={() => void run('scopes', () => coachAPI.updateScopes(sponsorship.relationship_id, scopes, visualProgress), 'Privacy controls')} className="mt-5 w-full rounded-2xl bg-emerald-600 px-4 py-3 text-sm font-black text-white disabled:opacity-45">{t('Save sharing choices')}</button>
        <button type="button" disabled={busy != null} onClick={() => { if (window.confirm(t('End coach access'))) void run('end', () => coachAPI.endRelationship(sponsorship.relationship_id), 'Coach access ended').then(() => navigate('/', { replace: true })) }} className="mt-3 w-full rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm font-black text-rose-700 disabled:opacity-45">{t('End coach access')}</button>
      </section>
    </div>
  )
}
