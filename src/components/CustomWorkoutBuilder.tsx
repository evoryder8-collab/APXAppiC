import { lazy, Suspense, useEffect, useMemo, useRef, useState } from 'react'
import { getISODay } from 'date-fns'
import type { IntroLanguage } from '../lib/introLanguage'
import { useLanguage } from '../lib/i18n'
import type { Accent } from '../lib/theme'
import { ACCENTS } from '../lib/theme'
import type { Exercise, Program, ProgramDay, SessionMode } from '../lib/types'
import { useOrbitText } from '../orbit/ui/i18n'
import { useStore } from '../store/AppStore'
import {
  EXERCISE_CATEGORIES,
  EXERCISE_CATALOG,
  displayExerciseName,
  searchExerciseCatalog,
  type ExerciseCatalogItem,
  type ExerciseCategory,
} from '../data/exerciseCatalog'
import { GhostButton, GradientButton, Sheet } from './ui'
import { followAlongFields, suggestedRestSeconds } from '../lib/sessionShape'
import {
  activeCustomWorkoutDays,
  CustomWorkoutReplacementRequiredError,
  customWorkoutDraftForDay,
  customWorkoutGroupAssignments,
  customWorkoutReplacementDecision,
  customWorkoutSaveDayID,
  stageCustomWorkoutSave,
  customWorkoutTargetLabel,
  moveCustomWorkoutSelection,
  removeCustomWorkoutSelection,
  type CustomWorkoutSelection,
} from '../lib/customWorkout'
import { clientPolicyForAccount } from '../lib/coachAccess'

const HologramStage = lazy(() =>
  import('./hologram/HologramStage').then((module) => ({ default: module.HologramStage })),
)

const WEEKDAYS = [
  { id: 1, label: 'Monday' },
  { id: 2, label: 'Tuesday' },
  { id: 3, label: 'Wednesday' },
  { id: 4, label: 'Thursday' },
  { id: 5, label: 'Friday' },
  { id: 6, label: 'Saturday' },
  { id: 7, label: 'Sunday' },
]

const WEEKDAY_SHORT: Record<IntroLanguage, string[]> = {
  en: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  ro: ['Lun', 'Mar', 'Mie', 'Joi', 'Vin', 'Sâm', 'Dum'],
  th: ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'],
}

function clamp(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min
  return Math.max(min, Math.min(max, Math.round(value)))
}

function estimatedMinutes(selected: CustomWorkoutSelection[], byId: Map<string, ExerciseCatalogItem>): number {
  const seconds = selected.reduce((total, selection) => {
    const exercise = byId.get(selection.id)
    if (!exercise) return total
    const workSeconds = exercise.unit === 'minutes'
      ? selection.target * 60
      : exercise.unit === 'seconds'
        ? selection.target
        : Math.max(20, selection.target * 3)
    return total + selection.sets * (workSeconds + selection.rest)
  }, 0)
  return Math.max(8, Math.round(seconds / 60))
}

export function CustomWorkoutBuilder({
  open,
  onClose,
  onSaved,
  editingDayId = null,
  accent = ACCENTS.violet,
}: {
  open: boolean
  onClose: () => void
  onSaved: () => void
  editingDayId?: string | null
  accent?: Accent
}) {
  const { appAccess, coachContext, commitOwnerBoundMutation, data, toast } = useStore()
  const t = useOrbitText()
  const { language } = useLanguage()
  const policy = clientPolicyForAccount(appAccess, coachContext)
  const [name, setName] = useState('')
  /* A trainer building a plan for somebody else knows which of the two this
   * is meant to be. Guided paces the session and counts the reps aloud;
   * tracked shows the list and lets the lifter record what they actually did. */
  const [sessionMode, setSessionMode] = useState<SessionMode>('guided')
  const [weekday, setWeekday] = useState(() => getISODay(new Date()))
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState<'all' | ExerciseCategory>('all')
  const [selected, setSelected] = useState<CustomWorkoutSelection[]>([])
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [replacementDayIds, setReplacementDayIds] = useState<string[]>([])
  const [unavailableSavedMovements, setUnavailableSavedMovements] = useState(0)
  const loadedDraftKey = useRef<string | null>(null)
  const savingInFlight = useRef(false)

  const byId = useMemo(() => new Map(EXERCISE_CATALOG.map((item) => [item.id, item])), [])
  const results = useMemo(
    () => searchExerciseCatalog(query, category, language),
    [category, language, query],
  )
  const selectedNames = useMemo(
    () => selected.map((selection) => byId.get(selection.id)?.name).filter((value): value is string => !!value),
    [byId, selected],
  )
  const selectedIds = useMemo(() => new Set(selected.map((item) => item.id)), [selected])
  const previewWorkGroups = useMemo(
    () => customWorkoutGroupAssignments(selected, () => 'preview'),
    [selected],
  )
  const replacementConflictDays = useMemo(() => {
    const profile = data.profile
    const program = profile
      ? data.programs.find((candidate) => candidate.slug === 'custom' && candidate.user_id === profile.user_id)
      : null
    if (!profile || !program) return []
    const conflicts = new Set(replacementDayIds)
    return activeCustomWorkoutDays(data.program_days, profile.user_id, program.id)
      .filter((day) => conflicts.has(day.id))
      .sort((left, right) => left.id.localeCompare(right.id))
  }, [data.profile, data.program_days, data.programs, replacementDayIds])

  const addExercise = (item: ExerciseCatalogItem): void => {
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur()
    setSelected((current) => current.some((entry) => entry.id === item.id)
      ? removeCustomWorkoutSelection(current, item.id)
      : [...current, {
          id: item.id,
          sets: item.sets,
          target: item.reps,
          // The picker starts on what the movement actually warrants -- a cuff
          // drill and a heavy hinge do not want the same interval -- and the
          // trainer can still change it to anything they like.
          rest: suggestedRestSeconds(item.name, 'hypertrophy') ?? item.rest,
          linkedToNext: false,
        }])
  }

  const updateExercise = (id: string, patch: Partial<Omit<CustomWorkoutSelection, 'id'>>): void => {
    setSelected((current) => current.map((entry) => entry.id === id ? { ...entry, ...patch } : entry))
  }

  const reset = (): void => {
    setName('')
    setSessionMode('guided')
    setWeekday(getISODay(new Date()))
    setQuery('')
    setCategory('all')
    setSelected([])
    setSaving(false)
    setMessage(null)
    setReplacementDayIds([])
    setUnavailableSavedMovements(0)
  }

  useEffect(() => {
    if (!open) {
      loadedDraftKey.current = null
      return
    }
    const draftKey = `${data.profile?.user_id ?? 'signed-out'}:${editingDayId ?? 'new'}`
    if (loadedDraftKey.current === draftKey) return
    loadedDraftKey.current = draftKey
    reset()
    if (!editingDayId) return
    const profile = data.profile
    const customProgram = profile
      ? data.programs.find((program) => program.slug === 'custom' && program.user_id === profile.user_id)
      : null
    const editingDay = customProgram && profile
      ? activeCustomWorkoutDays(data.program_days, profile.user_id, customProgram.id)
          .find((day) => day.id === editingDayId)
      : null
    if (!editingDay) {
      setMessage(t('This workout is no longer available.'))
      return
    }
    const draft = customWorkoutDraftForDay(editingDay, data.exercises)
    setName(draft.name)
    setSessionMode(draft.sessionMode)
    setWeekday(draft.weekday)
    setSelected(draft.selected)
    setUnavailableSavedMovements(draft.omittedExerciseCount)
    if (draft.omittedExerciseCount > 0) {
      setMessage(t('Some saved movements are no longer available in the exercise library.'))
    }
  }, [data.exercises, data.profile, data.program_days, data.programs, editingDayId, open, t])

  const persistWorkout = async (confirmedReplacementDayIds: readonly string[] = []): Promise<void> => {
    if (savingInFlight.current) return
    const profile = data.profile
    if (unavailableSavedMovements > 0) {
      setMessage(t('Some saved movements are no longer available in the exercise library.'))
      return
    }
    if (!policy.can_create_custom_workouts) {
      toast(t('Your coach manages this plan. Custom workout creation is unavailable.'), 'error')
      return
    }
    if (!profile || !name.trim() || selected.length === 0) {
      toast(t('Add at least one exercise and give the workout a name.'))
      return
    }

    const existingProgram = data.programs.find((program) => program.slug === 'custom' && program.user_id === profile.user_id)
    const program: Program = existingProgram ?? {
      id: crypto.randomUUID(),
      user_id: profile.user_id,
      slug: 'custom',
      name: 'Custom workouts',
      description: 'Your searchable exercise studio, saved privately.',
    }
    const activeDays = activeCustomWorkoutDays(data.program_days, profile.user_id, program.id)
    const editingDay = editingDayId
      ? activeDays.find((day) => day.id === editingDayId)
      : null
    if (editingDayId && !editingDay) {
      setMessage(t('This workout is no longer available.'))
      return
    }
    const replacement = customWorkoutReplacementDecision(data.program_days, {
      ownerID: profile.user_id,
      programID: program.id,
      weekday,
      editingDayID: editingDay?.id ?? null,
      confirmedReplacementDayIDs: confirmedReplacementDayIds,
    })
    if (replacement.kind === 'confirmation-required') {
      setReplacementDayIds(replacement.replacingDayIDs)
      return
    }
  /* A custom workout was writing 2-0-1 onto everything the user picked, which
   * is the blanket cadence the movement library exists to replace. Where the
   * chosen exercise maps onto a known movement, its own timing is used; where
   * it does not, the previous defaults stand rather than guessing. */
  const followAlongFor = (item: ExerciseCatalogItem, rest: number) => ({
    ...followAlongFields(item.name, 'hypertrophy', {
      rest_sec: rest, per_side: item.perSide, increment_kg: item.incrementKG,
    }, { keepAuthoredRest: true }),
    // Cardio modalities deliberately are not fused into MOVEMENTS, so name
    // resolution alone cannot carry their canonical identity into the row.
    movement_id: item.movementID,
  })

    const day: ProgramDay = {
      id: customWorkoutSaveDayID(editingDay?.id ?? null),
      user_id: profile.user_id,
      program_id: program.id,
      weekday,
      name: name.trim(),
      day_type: 'custom',
      session_mode: sessionMode,
      est_minutes: estimatedMinutes(selected, byId),
      warmup_note: 'Five minutes of pain-free joint preparation',
      sort_order: weekday,
      is_active: true,
    }

    savingInFlight.current = true
    const operationDraftKey = loadedDraftKey.current
    setSaving(true)
    setMessage(null)
    setReplacementDayIds([])
    try {
      const workGroups = customWorkoutGroupAssignments(selected)
      const exercises: Exercise[] = selected.map((selection, index) => {
        const item = byId.get(selection.id)!
        const workGroup = workGroups[index]
        return {
          id: crypto.randomUUID(),
          user_id: profile.user_id,
          program_day_id: day.id,
          name: item.name,
          sets: clamp(selection.sets, 1, 12),
          rep_min: clamp(selection.target, 1, 600),
          rep_max: clamp(selection.target, 1, 600),
          rep_unit: item.unit,
          work_group_id: workGroup.workGroupId,
          work_group_position: workGroup.workGroupPosition,
          ...(({ movement_id, tempo_up_s, tempo_down_s, tempo_pause_s, tempo_note, per_side, rest_sec }) => ({
            movement_id, tempo_up_s, tempo_down_s, tempo_pause_s, tempo_note, per_side, rest_sec,
          }))(followAlongFor(item, clamp(selection.rest, 0, 600))),
          notes: `${item.equipment} · ${item.muscles.join(', ')}`,
          increment_kg: item.incrementKG,
          is_lite: false,
          optional: false,
          sort_order: index,
        }
      })
      await commitOwnerBoundMutation(profile.user_id, (current) => stageCustomWorkoutSave(current, {
        program, day, exercises,
        editingDayID: editingDay?.id ?? null,
        confirmedReplacementDayIDs: confirmedReplacementDayIds,
      }))
      if (loadedDraftKey.current !== operationDraftKey) return
      toast(t(editingDay ? 'Custom workout updated' : 'Custom workout saved'), 'ok')
      reset()
      onClose()
      onSaved()
    } catch (error) {
      if (loadedDraftKey.current !== operationDraftKey) return
      if (error instanceof CustomWorkoutReplacementRequiredError) {
        setReplacementDayIds(error.replacingDayIDs)
      } else {
        setMessage(t('Custom workout could not be saved.'))
      }
    } finally {
      savingInFlight.current = false
      if (loadedDraftKey.current === operationDraftKey) setSaving(false)
    }
  }

  const inputClass = 'w-full rounded-2xl border border-white/90 bg-white/72 px-4 py-3 text-sm font-bold text-ink shadow-[inset_0_1px_0_rgba(255,255,255,.9)] outline-none placeholder:text-ink-faint focus:border-violet-300 focus:ring-4 focus:ring-violet-200/25'

  return (
    <Sheet open={open} onClose={onClose} wide>
      <div className="relative overflow-hidden rounded-[26px] bg-[#07111f] p-5 text-white">
        <div className="orbit-stars pointer-events-none absolute inset-0 opacity-55" aria-hidden />
        <div className="pointer-events-none absolute -top-16 right-0 h-44 w-44 rounded-full bg-violet-500/25 blur-3xl" aria-hidden />
        <div className="relative flex items-start justify-between gap-3">
          <div>
            <p className="font-mono text-[9px] font-black tracking-[.2em] text-cyan-200 uppercase">{t('APEX WORKOUT STUDIO')}</p>
            <h2 className="mt-1 font-display text-2xl font-bold">{t('Build a workout')}</h2>
            <p className="mt-1 max-w-md text-xs leading-relaxed text-slate-300">{t('Search, choose and tune. The hologram updates every time you add a movement.')}</p>
          </div>
          <button type="button" onClick={onClose} aria-label={t('Close')} className="grid h-10 w-10 shrink-0 place-items-center rounded-full border border-white/10 bg-white/8 text-lg font-bold text-white active:scale-95">×</button>
        </div>
      </div>

      <div className="mt-4 grid gap-4 sm:grid-cols-[minmax(0,1fr)_220px]">
        <div className="space-y-3">
          <label className="block">
            <span className="mb-1.5 block text-xs font-bold text-ink-soft">{t('Workout name')}</span>
            <input value={name} onChange={(event) => setName(event.target.value)} className={inputClass} placeholder={t('e.g. Full-body power')} maxLength={56} />
          </label>
          <div>
            <span className="mb-1.5 block text-xs font-bold text-ink-soft">{t('How it is trained')}</span>
            <div className="flex gap-1.5">
              {([
                ['guided', t('Follow along'), t('Paced, counts the reps')],
                ['tracked', t('Track it'), t('A list you fill in')],
              ] as Array<[SessionMode, string, string]>).map(([mode, label, hint]) => (
                <button
                  key={mode}
                  type="button"
                  onClick={() => setSessionMode(mode)}
                  className={`flex-1 rounded-2xl border px-3 py-2.5 text-left transition ${
                    sessionMode === mode
                      ? 'border-violet-300 bg-violet-50'
                      : 'border-slate-100 bg-slate-50'
                  }`}
                >
                  <span className="block text-xs font-black text-ink">{label}</span>
                  <span className="mt-0.5 block text-[10px] font-semibold text-ink-soft">{hint}</span>
                </button>
              ))}
            </div>
          </div>
          <div>
            <span className="mb-1.5 block text-xs font-bold text-ink-soft">{t('Training day')}</span>
            <div className="flex gap-1.5 overflow-x-auto pb-1">
              {WEEKDAYS.map((day) => (
                <button key={day.id} type="button" onClick={() => setWeekday(day.id)} className={`min-h-10 shrink-0 rounded-full px-3 text-[11px] font-black transition ${weekday === day.id ? 'bg-[#111827] text-white shadow-lg' : 'border border-white/90 bg-white/65 text-ink-soft'}`}>
                  {WEEKDAY_SHORT[language][day.id - 1]}
                </button>
              ))}
            </div>
            <p className="mt-1 text-[10px] leading-relaxed text-ink-faint">{t('If that day already has a workout, APEX will ask before replacing it.')}</p>
          </div>
        </div>
        <Suspense fallback={<div className="h-[188px] animate-pulse rounded-3xl bg-slate-900" />}>
          <HologramStage dayType="custom" accent={accent} height={188} exerciseNames={selectedNames} />
        </Suspense>
      </div>

      <div className="mt-5">
        <label className="relative block">
          <span className="pointer-events-none absolute top-1/2 left-4 -translate-y-1/2 text-ink-faint">⌕</span>
          <input value={query} onChange={(event) => setQuery(event.target.value)} className={`${inputClass} pl-10`} placeholder={t('Search by movement, muscle or equipment')} aria-label={t('Search by movement, muscle or equipment')} autoComplete="off" />
        </label>
        <div className="mt-2 flex gap-2 overflow-x-auto pb-2">
          {EXERCISE_CATEGORIES.map((item) => (
            <button key={item.id} type="button" onClick={() => setCategory(item.id)} className={`min-h-9 shrink-0 rounded-full px-3 text-[10px] font-black transition ${category === item.id ? 'bg-violet-600 text-white shadow-[0_8px_20px_-10px_rgba(109,40,217,.9)]' : 'border border-white bg-white/65 text-ink-soft'}`}>
              {t(item.label)}
            </button>
          ))}
        </div>
        <p className="mb-2 font-mono text-[9px] font-black text-ink-faint">
          {results.length} {t('movements')}
        </p>
        <div className="grid max-h-[270px] gap-2 overflow-y-auto pr-1 sm:grid-cols-2">
          {results.map((item) => {
            const active = selectedIds.has(item.id)
            return (
              <button key={item.id} type="button" onClick={() => addExercise(item)} className={`flex min-h-[68px] items-center justify-between gap-3 rounded-2xl border p-3 text-left transition active:scale-[.985] ${active ? 'border-violet-300 bg-violet-50/90 shadow-[0_10px_28px_-20px_rgba(109,40,217,.8)]' : 'border-white/95 bg-white/60'}`}>
                <span className="min-w-0">
                  <span className="block truncate text-sm font-bold text-ink">{displayExerciseName(item, language)}</span>
                  <span className="mt-0.5 block truncate text-[10px] font-semibold text-ink-soft">{t(item.equipment)} · {t(item.category)}</span>
                </span>
                <span className={`grid h-8 w-8 shrink-0 place-items-center rounded-full text-lg font-black ${active ? 'bg-violet-600 text-white' : 'bg-slate-100 text-ink-soft'}`}>{active ? '✓' : '+'}</span>
              </button>
            )
          })}
        </div>
      </div>

      <div className="mt-5 rounded-[26px] border border-white/90 bg-white/58 p-3 shadow-[0_18px_50px_-34px_rgba(15,23,42,.55)]">
        <div className="flex items-center justify-between gap-3 px-1">
          <div>
            <h3 className="font-display text-base font-bold text-ink">{t('Selected exercises')}</h3>
            <p className="text-[10px] font-semibold text-ink-faint">{selected.length} · ~{estimatedMinutes(selected, byId)} {t('min')}</p>
          </div>
          {selected.length > 0 && <GhostButton onClick={() => setSelected([])}>{t('Clear')}</GhostButton>}
        </div>
        {selected.length === 0 ? (
          <p className="px-1 py-5 text-center text-sm font-semibold text-ink-faint">{t('No exercises selected yet')}</p>
        ) : (
          <div className="mt-2 space-y-2">
            {selected.map((selection, index) => {
              const item = byId.get(selection.id)!
              const workGroup = previewWorkGroups[index]
              return (
                <div key={selection.id} className="rounded-2xl border border-white bg-white/72 p-3">
                  <div className="flex items-center justify-between gap-3">
                    <p className="min-w-0 truncate text-sm font-bold text-ink">
                      <span className="mr-2 font-mono text-[9px] text-violet-600">{workGroup.label ?? String(index + 1).padStart(2, '0')}</span>
                      {displayExerciseName(item, language)}
                    </p>
                    <div className="flex shrink-0 items-center gap-1">
                      <button type="button" onClick={() => setSelected((current) => moveCustomWorkoutSelection(current, index, -1))} disabled={index === 0} className="grid h-11 w-11 place-items-center rounded-full bg-slate-50 font-bold text-ink-soft disabled:opacity-25" aria-label={`${t('Move up')} ${displayExerciseName(item, language)}`}>↑</button>
                      <button type="button" onClick={() => setSelected((current) => moveCustomWorkoutSelection(current, index, 1))} disabled={index === selected.length - 1} className="grid h-11 w-11 place-items-center rounded-full bg-slate-50 font-bold text-ink-soft disabled:opacity-25" aria-label={`${t('Move down')} ${displayExerciseName(item, language)}`}>↓</button>
                      <button type="button" onClick={() => addExercise(item)} className="grid h-11 w-11 place-items-center rounded-full bg-rose-50 font-bold text-rose-600" aria-label={`${t('Remove')} ${displayExerciseName(item, language)}`}>×</button>
                    </div>
                  </div>
                  <div className="mt-2 grid grid-cols-3 gap-2">
                    {([
                      ['Sets', 'sets', selection.sets, 1, 12],
                      [customWorkoutTargetLabel(item.unit), 'target', selection.target, 1, 600],
                      ['Rest seconds', 'rest', selection.rest, 0, 600],
                    ] as const).map(([label, key, value, min, max]) => (
                      <label key={key} className="min-w-0">
                        <span className="mb-1 block truncate text-[8px] font-black tracking-wide text-ink-faint uppercase">{t(label)}</span>
                        <input type="number" inputMode="numeric" min={min} max={max} value={value} onChange={(event) => updateExercise(selection.id, { [key]: clamp(Number(event.target.value), min, max) })} className="w-full rounded-xl border border-slate-100 bg-slate-50 px-2 py-2 text-center font-mono text-xs font-black text-ink outline-none focus:border-violet-300" />
                      </label>
                    ))}
                  </div>
                  {index < selected.length - 1 && (
                    <button
                      type="button"
                      onClick={() => updateExercise(selection.id, { linkedToNext: !selection.linkedToNext })}
                      className={`mt-2 inline-flex min-h-11 items-center gap-2 rounded-full px-3 text-[10px] font-black ${selection.linkedToNext ? 'bg-violet-600 text-white' : 'bg-violet-50 text-violet-700'}`}
                      aria-pressed={selection.linkedToNext}
                    >
                      <span aria-hidden>{selection.linkedToNext ? '⛓' : '＋'}</span>
                      {t(selection.linkedToNext ? 'Linked into the same round' : 'Link with next movement')}
                    </button>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </div>

      {message && <p className="mt-4 rounded-2xl bg-rose-50 px-4 py-3 text-xs font-bold text-rose-800" role="alert">{message}</p>}

      {replacementDayIds.length > 0 && (
        <div className="mt-4 rounded-2xl border border-amber-200 bg-amber-50 p-4" role="alertdialog" aria-labelledby="replace-workout-title">
          <h3 id="replace-workout-title" className="font-display text-lg font-bold text-ink">{t(replacementConflictDays.length > 1 ? 'Replace these workouts?' : 'Replace this workout?')}</h3>
          <p className="mt-1 text-xs font-semibold leading-relaxed text-ink-soft">{t(replacementConflictDays.length > 1 ? 'These workouts already use this training day. Replace them only if that is what you intend.' : 'This training day already has a custom workout. Replace it only if that is what you intend.')}</p>
          <ul className="mt-3 space-y-1" aria-label={t('Saved custom workouts')}>
            {replacementConflictDays.map((day) => (
              <li key={day.id} className="rounded-xl bg-white/75 px-3 py-2 text-xs font-black text-ink">{day.name}</li>
            ))}
          </ul>
          <div className="mt-3 flex gap-2">
            <button type="button" onClick={() => setReplacementDayIds([])} className="min-h-11 flex-1 rounded-xl bg-white px-3 text-xs font-black text-ink-soft">{t('Keep editing')}</button>
            <button type="button" onClick={() => void persistWorkout(replacementDayIds)} className="min-h-11 flex-1 rounded-xl bg-amber-500 px-3 text-xs font-black text-white">{t('Save as replacement')}</button>
          </div>
        </div>
      )}

      <GradientButton accent={accent} className="mt-5 w-full py-4" disabled={saving || replacementDayIds.length > 0} onClick={() => void persistWorkout()}>
        {t(saving ? 'Saving workout…' : editingDayId ? 'Save workout changes' : 'Save custom workout')}
      </GradientButton>
    </Sheet>
  )
}
