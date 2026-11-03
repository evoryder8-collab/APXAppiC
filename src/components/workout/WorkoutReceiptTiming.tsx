import { useRef, useState } from 'react'
import type { WorkoutSession } from '../../lib/types'
import { useStore } from '../../store/AppStore'
import { useLanguage, translateInterfaceText } from '../../lib/i18n'
import { timeZoneFromSettings } from '../../lib/mealTiming'
import { isWorkoutDate } from '../../lib/workoutTimingMetadata'
import {
  shiftWorkoutTimingDraftDate, stageWorkoutTimingEdit, workoutLocalDateTime,
  workoutTimingDraft, WorkoutTimingValidationError,
} from '../../lib/workoutTiming'

export function WorkoutReceiptTiming({ session }: { session: WorkoutSession }) {
  const { data, commitOwnerBoundMutation, toast } = useStore()
  const { language } = useLanguage()
  const t = (text: string): string => translateInterfaceText(text, language)
  const timeZone = timeZoneFromSettings(data.settings)
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(() => workoutTimingDraft(session, timeZone))
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const savingRef = useRef(false)
  const fieldClass = 'mt-1 min-h-11 w-full min-w-0 rounded-xl border border-violet-100 bg-white px-3 py-2 font-mono text-sm text-ink'
  const dateTime = (value: string | null): string => workoutLocalDateTime(value, timeZone).replace('T', ' · ') || t('Not recorded')

  const save = async (): Promise<void> => {
    if (savingRef.current) return
    savingRef.current = true
    setSaving(true)
    setError(null)
    try {
      await commitOwnerBoundMutation(session.user_id, (current) => stageWorkoutTimingEdit(current, {
        ownerID: session.user_id, sessionID: session.id, draft, timeZone,
      }))
      setEditing(false)
      toast(t('Workout date and time saved.'), 'ok')
    } catch (reason) {
      setError(reason instanceof WorkoutTimingValidationError
        ? 'Choose a valid workout date and time.' : 'Could not save the workout time. Try again.')
    } finally {
      savingRef.current = false
      setSaving(false)
    }
  }

  return (
    <section className="mt-4 rounded-2xl border border-violet-100 bg-violet-50/60 p-3.5" data-testid="workout-receipt-timing">
      <div className="flex items-start justify-between gap-3">
        <h3 className="min-w-0 text-sm font-bold leading-snug text-ink">{t('Workout date and time')}</h3>
        {!editing && <button type="button" onClick={() => { setDraft(workoutTimingDraft(session, timeZone)); setError(null); setEditing(true) }}
          className="min-h-10 shrink-0 rounded-xl bg-white px-3 py-2 text-xs font-bold text-violet-700">{t('Edit')}</button>}
      </div>
      {!session.completed_at && <p className="mt-2 text-xs leading-relaxed text-ink-soft">{t('Finish time was not recorded. Enter it to correct this receipt.')}</p>}
      {editing ? (
        <form className="mt-3 space-y-3" onSubmit={(event) => { event.preventDefault(); void save() }}>
          <fieldset disabled={saving} className="min-w-0 space-y-3">
            <label className="block text-xs font-semibold text-ink-soft">{t('Workout date')}
              <input type="date" required value={draft.date} onChange={(event) => setDraft((value) => shiftWorkoutTimingDraftDate(value, event.target.value))} className={fieldClass} />
            </label>
            <label className="flex min-h-10 items-center gap-2 text-xs font-semibold text-ink">
              <input type="checkbox" checked={draft.includeStart} onChange={(event) => setDraft((value) => {
                const anchor = (event.target.checked ? value.startedLocal : value.finishedLocal).slice(0, 10)
                return { ...value, includeStart: event.target.checked, date: isWorkoutDate(anchor) ? anchor : value.date }
              })} className="h-4 w-4 accent-violet-600" />
              {t('Include start time')}
            </label>
            {draft.includeStart && <label className="block text-xs font-semibold text-ink-soft">{t('Started')}
              <input type="datetime-local" required value={draft.startedLocal} onChange={(event) => setDraft((value) => {
                const anchor = event.target.value.slice(0, 10)
                return { ...value, startedLocal: event.target.value, date: isWorkoutDate(anchor) ? anchor : value.date }
              })} className={fieldClass} />
            </label>}
            <label className="block text-xs font-semibold text-ink-soft">{t('Finished')}
              <input type="datetime-local" required value={draft.finishedLocal} onChange={(event) => setDraft((value) => {
                const anchor = event.target.value.slice(0, 10)
                return { ...value, finishedLocal: event.target.value, date: !value.includeStart && isWorkoutDate(anchor) ? anchor : value.date }
              })} className={fieldClass} />
            </label>
          </fieldset>
          {error && <p role="alert" className="text-xs font-semibold leading-relaxed text-rose-700">{t(error)}</p>}
          <div className="flex flex-wrap gap-2">
            <button type="button" disabled={saving} onClick={() => { setEditing(false); setError(null) }} className="min-h-11 flex-1 rounded-xl bg-white px-3 py-2 text-xs font-bold text-ink">{t('Cancel')}</button>
            <button type="submit" disabled={saving} className="min-h-11 flex-1 rounded-xl bg-violet-600 px-3 py-2 text-xs font-bold text-white disabled:opacity-60">{t(saving ? 'Saving…' : 'Save')}</button>
          </div>
        </form>
      ) : (
        <dl className="mt-2 space-y-2 text-xs">
          {[[t('Workout date'), session.date], [t('Started'), dateTime(session.started_at)], [t('Finished'), dateTime(session.completed_at)]].map(([label, value]) => (
            <div key={label} className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1"><dt className="text-ink-soft">{label}</dt><dd className="break-words font-mono font-semibold text-ink">{value}</dd></div>
          ))}
        </dl>
      )}
      <p className="mt-3 break-words text-[10px] leading-relaxed text-ink-faint">{t('Times use your Settings time zone.')} {timeZone}</p>
    </section>
  )
}
