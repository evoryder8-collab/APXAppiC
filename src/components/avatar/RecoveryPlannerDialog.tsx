import { useEffect, useMemo, useRef, useState } from 'react'

import { clientPolicyForAccount } from '../../lib/coachAccess.ts'
import {
  buildRecoveryPlan,
  futureRecoveryRowsToDeactivate,
  type RecoveryPlanSource,
  type RecoveryPlanTarget,
} from '../../lib/recoveryPlanner.ts'
import { translateInterfaceText, useLanguage } from '../../lib/i18n.tsx'
import { useStore } from '../../store/AppStore.tsx'

function tomorrowIso(): string {
  const date = new Date()
  date.setDate(date.getDate() + 1)
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

export function RecoveryPlannerDialog({
  target,
  onClose,
}: {
  target: RecoveryPlanTarget
  onClose: () => void
}) {
  const { data, coachContext, bulkUpsert, toast } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const [source, setSource] = useState<RecoveryPlanSource>('guided')
  const closeButton = useRef<HTMLButtonElement>(null)
  const ownerId = data.profile?.user_id ?? data.settings?.user_id ?? null
  const startDate = useMemo(tomorrowIso, [])
  const policy = clientPolicyForAccount(data.profile, coachContext)
  const proposal = useMemo(() => ownerId ? buildRecoveryPlan({
    ownerId,
    startDate,
    target,
    source,
    programs: data.programs,
    settings: data.settings,
    existingDays: data.program_days,
  }) : null, [data.program_days, data.programs, data.settings, ownerId, source, startDate, target])

  useEffect(() => {
    closeButton.current?.focus()
    const escape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', escape)
    return () => window.removeEventListener('keydown', escape)
  }, [onClose])

  const install = () => {
    if (!ownerId || !proposal || proposal.days.length === 0) {
      toast(t('Build or restore a current Fitness Plan before adding recovery sessions.'), 'error')
      return
    }
    if (!policy.can_create_custom_workouts) {
      toast(t('Ask your coach to add recovery sessions to your plan.'), 'error')
      return
    }
    const usedDayIds = new Set(data.workout_sessions.map((session) => session.program_day_id))
    const replacementRows = futureRecoveryRowsToDeactivate(data.program_days, ownerId, target, startDate, usedDayIds)
    bulkUpsert('program_days', [...replacementRows, ...proposal.days])
    bulkUpsert('exercises', proposal.exercises)
    toast(t('Recovery sessions added to your calendar.'), 'ok')
    onClose()
  }

  const dateFormatter = new Intl.DateTimeFormat(language, { weekday: 'short', day: 'numeric', month: 'short' })

  return (
    <div className="fixed inset-0 z-[120] grid place-items-center overflow-y-auto bg-slate-950/55 px-4 py-[max(1rem,env(safe-area-inset-top))] backdrop-blur-md" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose() }}>
      <section role="dialog" aria-modal="true" aria-labelledby="recovery-planner-title" className="w-full max-w-xl rounded-[2rem] border border-white/85 bg-canvas/98 p-5 shadow-[0_38px_110px_-34px_rgba(15,23,42,.72)] sm:p-6">
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <p className="font-mono text-[10px] font-black tracking-[0.18em] text-emerald uppercase">{t('RECOVERY RHYTHM')}</p>
            <h2 id="recovery-planner-title" className="mt-1 font-display text-3xl leading-tight font-bold text-ink">{t(target === 'joint' ? 'Plan joint care' : 'Plan flexibility')}</h2>
            <p className="mt-2 text-sm leading-relaxed font-medium text-ink-soft">{t('Four weeks, two short sessions each week. APEX favours lower-load days and never replaces your current programme.')}</p>
          </div>
          <button ref={closeButton} type="button" onClick={onClose} className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-white/80 text-xl font-bold text-ink-soft" aria-label={t('Close')}>×</button>
        </div>

        <div className="mt-5 grid gap-3 sm:grid-cols-2" role="radiogroup" aria-label={t('Session style')}>
          {([
            ['guided', 'APEX guided', 'A short follow-along routine using reviewed movements.'],
            ['external', 'My own session', 'Follow a mobility or recovery video or routine you trust, then log it honestly.'],
          ] as const).map(([value, title, detail]) => {
            const active = source === value
            return (
              <button key={value} type="button" role="radio" aria-checked={active} onClick={() => setSource(value)} className={`rounded-2xl border p-4 text-left transition-colors ${active ? 'border-emerald-400 bg-emerald-500/10' : 'border-white/90 bg-white/70'}`}>
                <span className="block font-display text-lg font-bold text-ink">{t(title)}</span>
                <span className="mt-1 block text-xs leading-relaxed font-medium text-ink-soft">{t(detail)}</span>
              </button>
            )
          })}
        </div>

        <div className="mt-5 rounded-2xl border border-white/90 bg-white/72 p-4">
          <div className="flex items-center justify-between gap-3">
            <h3 className="font-display text-lg font-bold text-ink">{t('Your proposed dates')}</h3>
            <span className="rounded-full bg-violet-500/10 px-3 py-1 font-mono text-[10px] font-bold text-violet-700">{proposal?.days.length ?? 0} {t('sessions')}</span>
          </div>
          <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-4">
            {(proposal?.days ?? []).map((day) => (
              <div key={day.id} className="rounded-xl bg-canvas px-2 py-2 text-center font-mono text-[10px] font-bold text-ink-soft">
                {dateFormatter.format(new Date(`${day.scheduled_date}T12:00:00Z`))}
              </div>
            ))}
          </div>
        </div>

        <div className="mt-4 rounded-2xl bg-amber-500/9 p-3 text-xs leading-relaxed font-medium text-ink-soft">
          {t('General movement support, not diagnosis or injury treatment. Use a comfortable range, stop if pain worsens, and seek qualified care for persistent or new symptoms.')}
        </div>

        {!policy.can_create_custom_workouts && (
          <p className="mt-3 text-sm font-bold text-amber-800">{t('Your coach manages this plan. Ask them to add the recovery rhythm for you.')}</p>
        )}

        <div className="mt-5 flex gap-3">
          <button type="button" onClick={onClose} className="min-h-12 flex-1 rounded-2xl bg-white/80 px-4 font-bold text-ink-soft">{t('Cancel')}</button>
          <button type="button" onClick={install} disabled={!proposal?.days.length || !policy.can_create_custom_workouts} className="min-h-12 flex-[1.5] rounded-2xl bg-gradient-to-r from-emerald-500 to-cyan-400 px-4 font-bold text-white shadow-lg disabled:opacity-45">{t('Add sessions')}</button>
        </div>
      </section>
    </div>
  )
}
