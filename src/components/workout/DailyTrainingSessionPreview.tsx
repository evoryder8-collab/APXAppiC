import { ExercisePreviewPhoto } from './ExercisePreviewPhoto'
import { useState } from 'react'
import { guidedSessionPreview, type DailyGuidedSession } from '../../lib/dailyGuidedSessions'
import type { PlannedDay } from '../../lib/plan'

interface Props {
  session: DailyGuidedSession
  lightPlan?: PlannedDay
  trainToday?: boolean
  completedLite?: boolean
  translate: (text: string) => string
  exerciseName: (name: string) => string
  onOpen: (lite: boolean) => void
}

export function DailyTrainingSessionPreview({ session, lightPlan, completedLite, trainToday, translate: t, exerciseName, onOpen }: Props) {
  const [selectedLite, setSelectedLite] = useState(false)
  const lite = session.status === 'Continue' ? session.resumeLite === true
    : session.status === 'Completed' ? completedLite === true : selectedLite
  const preview = guidedSessionPreview(lite && lightPlan ? lightPlan : session.plan, t)
  const title = t(session.plan.programDay!.name)
  const completed = session.status === 'Completed'
  const actionLabel = t(session.status) + (!completed && trainToday ? ' · ' + t('Today') : '')

  return (
    <section data-testid={`simple-training-session-${session.plan.programDay!.id}`}
      className="min-w-0 rounded-[22px] border border-violet-100 bg-gradient-to-br from-white via-white to-violet-50/70 p-3.5 shadow-sm">
      <div className="flex items-start gap-2.5">
        <span aria-hidden="true" className={`grid h-8 w-8 shrink-0 place-items-center rounded-xl text-base ${completed ? 'bg-emerald-100 text-emerald-700' : 'bg-violet-100 text-violet-700'}`}>
          {completed ? '✓' : session.status === 'Continue' ? '▶' : '○'}
        </span>
        <div className="min-w-0 flex-1">
          <h3 className="break-words font-display text-sm font-black leading-snug text-ink">{title}</h3>
          <p className="mt-1 flex flex-wrap gap-x-2 gap-y-0.5 text-[11px] font-semibold text-ink-soft">
            <span>{preview.exerciseCount} {t(preview.exerciseCount === 1 ? 'exercise' : 'exercises')}</span>
            <span aria-hidden="true">·</span><span>{t('sets')}: {preview.plannedSets}</span>
          </p>
        </div>
      </div>

      {session.status === 'Start' && lightPlan && lightPlan.exercises.length > 0 ? (
        <div className="mt-3 grid grid-cols-2 gap-1 rounded-xl bg-violet-50 p-1" role="group" aria-label={t('Workout version')}>
          {[false, true].map((mode) => (
            <button key={String(mode)} type="button" aria-pressed={lite === mode} onClick={() => setSelectedLite(mode)}
              className={`min-h-9 min-w-0 rounded-lg px-2 py-2 text-[11px] font-bold leading-snug ${lite === mode ? 'bg-white text-violet-800 shadow-sm' : 'text-ink-soft'}`}>
              {t(mode ? 'Minimum effective' : 'Full session')}
            </button>
          ))}
        </div>
      ) : <p className="mt-2 text-[10px] font-semibold text-ink-faint">{t(lite ? 'Minimum effective' : 'Full session')}</p>}

      <ol aria-label={t('Exercises')} className="mt-4 flex flex-col divide-y divide-violet-100">
        {preview.exercises.map((exercise, index) => (
          <li key={exercise.id} className="min-w-0 py-3">
            <div className="flex items-baseline gap-2.5">
              <span aria-hidden="true" className="font-mono text-xs font-bold text-violet-700">{String(index + 1).padStart(2, '0')}</span>
              <p className="break-words text-base font-bold leading-snug text-ink">{exerciseName(exercise.name)}</p>
            </div>
            <p className="mt-1 font-mono text-xs leading-relaxed text-ink-soft">{exercise.prescription}{exercise.optional ? ` · ${t('optional')}` : ''}</p>
            <ExercisePreviewPhoto exercise={exercise} className="mt-2 h-[150px] w-full" />
          </li>
        ))}
      </ol>
      <button type="button" onClick={() => onOpen(lite)}
        aria-label={`${completed ? t('View workout stats') : actionLabel}: ${title}`}
        className={`mt-3 min-h-11 w-full rounded-xl px-3 py-2.5 text-xs font-bold leading-snug ${completed ? 'bg-emerald-50 text-emerald-800' : 'bg-violet-600 text-white shadow-sm'}`}>
        {actionLabel} <span aria-hidden="true">{completed ? '✓' : '→'}</span>
      </button>
    </section>
  )
}
