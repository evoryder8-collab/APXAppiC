import { useEffect, useMemo, useRef, useState } from 'react'
import type { PointerEvent as ReactPointerEvent } from 'react'
import { format, getISODay, parseISO } from 'date-fns'
import { Reorder, motion, useDragControls } from 'framer-motion'
import {
  EXERCISE_CATALOG,
  catalogExerciseByName,
  displayExerciseName,
  isTreadmillExercise,
  searchExerciseCatalog,
  type ExerciseCatalogItem,
} from '../../data/exerciseCatalog'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import {
  baseExerciseName,
  encodeTreadmillLog,
  manualExerciseTimelineForDate,
  manualWorkoutEditorDraft,
  manualWorkoutNotes,
  rankManualWorkoutPresets,
  reconcileManualWorkoutLogs,
  resequenceManualWorkoutLogs,
  type ManualExerciseDraft,
  type ManualExerciseTimelineEntry,
  type ManualSetDraft,
} from '../../lib/manualWorkout'
import { ACCENTS, type Accent } from '../../lib/theme'
import type { Program, ProgramDay, WorkoutLog, WorkoutSession } from '../../lib/types'
import { useStore } from '../../store/AppStore'
import { GhostButton, GradientButton, Sheet } from '../ui'

function uid(prefix: string): string {
  return `${prefix}-${crypto.randomUUID()}`
}

function numberValue(value: string, max = 999): number {
  const parsed = Number(value.replace(',', '.'))
  if (!Number.isFinite(parsed)) return 0
  return Math.min(max, Math.max(0, parsed))
}

function starterSets(item: ExerciseCatalogItem): ManualSetDraft[] {
  return [{
    id: uid('set-0'),
    reps: item.unit === 'reps' ? item.reps : 0,
    weightKg: 0,
  }]
}

function draftFromCatalog(item: ExerciseCatalogItem): ManualExerciseDraft {
  return {
    id: uid('exercise'),
    catalogId: item.id,
    canonicalName: item.name,
    sets: isTreadmillExercise(item) ? [] : starterSets(item),
    treadmill: isTreadmillExercise(item) ? { distanceKm: 0, inclineDeg: 0, durationMin: 25 } : null,
  }
}

function clonePreset(exercises: ManualExerciseDraft[]): ManualExerciseDraft[] {
  return exercises.map((exercise) => ({
    ...exercise,
    id: uid('exercise'),
    sets: exercise.sets.map((set) => ({ ...set, id: uid('set') })),
    treadmill: exercise.treadmill ? { ...exercise.treadmill } : null,
  }))
}

function localizedDraftName(exercise: ManualExerciseDraft, language: 'en' | 'ro' | 'th'): string {
  const catalog = exercise.catalogId
    ? EXERCISE_CATALOG.find((item) => item.id === exercise.catalogId)
    : catalogExerciseByName(exercise.canonicalName)
  return catalog ? displayExerciseName(catalog, language) : exercise.canonicalName
}

function automaticWorkoutTitle(exercises: ManualExerciseDraft[], language: 'en' | 'ro' | 'th'): string {
  return exercises.slice(0, 2).map((exercise) => localizedDraftName(exercise, language)).join(' + ')
}

export function ManualWorkoutLogger({
  open,
  onClose,
  onSaved,
  date,
  editSessionId = null,
  focusExerciseName = null,
  accent = ACCENTS.teal,
}: {
  open: boolean
  onClose: () => void
  onSaved?: () => void
  date: string
  editSessionId?: string | null
  focusExerciseName?: string | null
  accent?: Accent
}) {
  const { data, upsert, bulkUpsert, remove, toast } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const searchRef = useRef<HTMLInputElement>(null)
  const exerciseEditorRefs = useRef(new Map<string, HTMLDivElement>())
  const [title, setTitle] = useState('')
  const [query, setQuery] = useState('')
  const [exercises, setExercises] = useState<ManualExerciseDraft[]>([])
  const [focusedExercise, setFocusedExercise] = useState<string | null>(null)
  const loadedEditorRef = useRef<string | null | undefined>(undefined)
  const presets = useMemo(() => rankManualWorkoutPresets(data, date), [data, date])
  const editorDraft = useMemo(() => editSessionId ? manualWorkoutEditorDraft(data, editSessionId) : null, [data, editSessionId])
  const results = useMemo(() => {
    const matches = searchExerciseCatalog(query, 'all', language)
    const predicted = new Map<string, number>()
    for (const preset of presets) {
      for (const exercise of preset.exercises) {
        if (exercise.catalogId && !predicted.has(exercise.catalogId)) predicted.set(exercise.catalogId, predicted.size)
      }
    }
    return matches
      .map((item, searchIndex) => ({ item, searchIndex, predictedIndex: predicted.get(item.id) }))
      .sort((left, right) => {
        const leftPrediction = left.predictedIndex == null ? Number.MAX_SAFE_INTEGER : left.predictedIndex
        const rightPrediction = right.predictedIndex == null ? Number.MAX_SAFE_INTEGER : right.predictedIndex
        return leftPrediction - rightPrediction || left.searchIndex - right.searchIndex
      })
      .slice(0, query.trim() ? 10 : 8)
      .map(({ item }) => item)
  }, [language, presets, query])

  useEffect(() => {
    if (!open) {
      loadedEditorRef.current = undefined
      return
    }
    if (loadedEditorRef.current === editSessionId) return
    loadedEditorRef.current = editSessionId
    setQuery('')
    setTitle(editorDraft?.title ?? '')
    setExercises(editorDraft ? clonePreset(editorDraft.exercises) : [])
  }, [editSessionId, editorDraft, open])

  useEffect(() => {
    if (!open || !editSessionId || !focusExerciseName) {
      setFocusedExercise(null)
      return
    }
    setFocusedExercise(focusExerciseName)
    const scrollTimer = window.setTimeout(() => {
      exerciseEditorRefs.current.get(focusExerciseName)?.scrollIntoView({ behavior: 'smooth', block: 'center' })
    }, 220)
    const clearTimer = window.setTimeout(() => setFocusedExercise(null), 1_800)
    return () => {
      window.clearTimeout(scrollTimer)
      window.clearTimeout(clearTimer)
    }
  }, [editSessionId, focusExerciseName, open])

  const addExercise = (item: ExerciseCatalogItem): void => {
    setExercises((current) => [...current, draftFromCatalog(item)])
    setQuery('')
    window.setTimeout(() => searchRef.current?.focus(), 50)
  }

  const updateExercise = (id: string, patch: Partial<ManualExerciseDraft>): void => {
    setExercises((current) => current.map((exercise) => exercise.id === id ? { ...exercise, ...patch } : exercise))
  }

  const updateSet = (exerciseId: string, setId: string, patch: Partial<ManualSetDraft>): void => {
    setExercises((current) => current.map((exercise) => exercise.id === exerciseId
      ? { ...exercise, sets: exercise.sets.map((set) => set.id === setId ? { ...set, ...patch } : set) }
      : exercise))
  }

  const reset = (): void => {
    setTitle('')
    setQuery('')
    setExercises([])
  }

  const save = (): void => {
    const profile = data.profile
    if (!profile || exercises.length === 0) {
      toast(t('Add at least one exercise.'))
      return
    }
    const usable = exercises.filter((exercise) => exercise.treadmill
      ? exercise.treadmill.durationMin > 0
      : exercise.sets.some((set) => set.reps > 0))
    if (usable.length === 0) {
      toast(t('Add reps or cardio time before saving.'))
      return
    }

    const existingProgram = data.programs.find((program) => program.slug === 'custom')
    const program: Program = existingProgram ?? {
      id: crypto.randomUUID(),
      user_id: profile.user_id,
      slug: 'custom',
      name: 'Custom workouts',
      description: 'Your searchable exercise studio, saved privately.',
    }
    const weekday = getISODay(parseISO(date))
    const existingDay = data.program_days.find((day) => day.program_id === program.id && day.weekday === weekday)
    const day: ProgramDay = existingDay ?? {
      id: crypto.randomUUID(),
      user_id: profile.user_id,
      program_id: program.id,
      weekday,
      name: 'Manual workout',
      day_type: 'custom',
      est_minutes: 45,
      warmup_note: 'Five minutes of pain-free joint preparation',
      sort_order: weekday,
    }
    const now = new Date().toISOString()
    const existingSession = editSessionId ? data.workout_sessions.find((candidate) => candidate.id === editSessionId) : null
    if (editSessionId && !existingSession) {
      toast(t('This workout could not be reopened.'))
      return
    }
    const session: WorkoutSession = {
      id: existingSession?.id ?? crypto.randomUUID(),
      user_id: profile.user_id,
      date,
      program_day_id: existingSession?.program_day_id ?? day.id,
      is_lite: existingSession?.is_lite ?? false,
      is_deload: existingSession?.is_deload ?? false,
      is_event_recovery: existingSession?.is_event_recovery ?? false,
      completed: true,
      quality_score: 1,
      started_at: existingSession?.started_at ?? now,
      completed_at: now,
      notes: manualWorkoutNotes(title),
    }
    const existingLogs = existingSession
      ? data.workout_logs.filter((candidate) => candidate.session_id === existingSession.id)
      : []
    const existingExerciseTimes = new Map<string, number>()
    for (const log of existingLogs) {
      const key = baseExerciseName(log.exercise_name)
      const timestamp = Date.parse(log.created_at)
      if (!Number.isFinite(timestamp)) continue
      existingExerciseTimes.set(key, Math.min(existingExerciseTimes.get(key) ?? timestamp, timestamp))
    }
    const newExerciseBaseTime = Date.now()
    const proposedLogs = usable.flatMap<WorkoutLog>((exercise, exerciseIndex) => {
      const exerciseTime = existingExerciseTimes.get(exercise.canonicalName)
        ?? newExerciseBaseTime + exerciseIndex * 60_000
      if (exercise.treadmill) {
        return [{
          id: crypto.randomUUID(), user_id: profile.user_id, session_id: session.id, exercise_id: null,
          exercise_name: encodeTreadmillLog(exercise.canonicalName, exercise.treadmill), set_no: 1,
          weight_kg: null, reps: null, rir: null, skipped: false, override_flag: false,
          created_at: new Date(exerciseTime).toISOString(),
        }]
      }
      return exercise.sets.filter((set) => set.reps > 0).map((set, setIndex) => ({
        id: crypto.randomUUID(), user_id: profile.user_id, session_id: session.id, exercise_id: null,
        exercise_name: exercise.canonicalName, set_no: setIndex + 1,
        weight_kg: set.weightKg > 0 ? set.weightKg : null, reps: Math.round(set.reps), rir: null,
        skipped: false, override_flag: false,
        created_at: new Date(exerciseTime + setIndex * 100).toISOString(),
      }))
    })

    const reconciled = reconcileManualWorkoutLogs(existingLogs, proposedLogs)
    if (!existingSession && !existingProgram) upsert('programs', program)
    if (!existingSession && !existingDay) upsert('program_days', day)
    /* Parents and replacements reach Supabase before stale rows are removed.
       Stable ids make retries idempotent and avoid an empty-workout window. */
    upsert('workout_sessions', session)
    bulkUpsert('workout_logs', reconciled.logs)
    for (const staleId of reconciled.staleIds) remove('workout_logs', staleId)
    toast(t(existingSession ? 'Workout updated' : 'Workout saved for reuse'), 'ok')
    reset()
    onClose()
    onSaved?.()
  }

  const inputClass = 'w-full rounded-2xl border border-white/90 bg-white/80 px-4 py-3 text-sm font-bold text-ink outline-none placeholder:text-ink-faint focus:border-cyan-300 focus:ring-4 focus:ring-cyan-200/25'

  return (
    <Sheet open={open} onClose={onClose} wide>
      <div className="relative overflow-hidden rounded-[28px] bg-[#071624] p-5 text-white">
        <div className="orbit-stars pointer-events-none absolute inset-0 opacity-45" aria-hidden />
        <div className="pointer-events-none absolute -top-20 right-0 h-48 w-48 rounded-full bg-cyan-400/25 blur-3xl" aria-hidden />
        <div className="relative flex items-start justify-between gap-3">
          <div><p className="font-mono text-[9px] font-black tracking-[.2em] text-cyan-200 uppercase">{t('QUICK LOG')}</p><h2 className="mt-1 font-display text-2xl font-bold">{t(editSessionId ? 'Edit Workout' : 'Add Workout')}</h2><p className="mt-1 text-xs leading-relaxed text-slate-300">{t('Log what you actually did. Every saved workout becomes a reusable smart preset.')}</p></div>
          <button type="button" onClick={onClose} aria-label={t('Close')} className="grid h-10 w-10 shrink-0 place-items-center rounded-full border border-white/10 bg-white/8 text-xl font-bold">×</button>
        </div>
      </div>

      {exercises.length === 0 && presets.length > 0 && (
        <div className="mt-4">
          <div className="flex items-end justify-between gap-2"><div><p className="font-display text-base font-bold text-ink">{t('Ready when you are')}</p><p className="text-[10px] font-semibold text-ink-faint">{t('Ranked from your weekday rhythm and previous workout')}</p></div><span className="font-mono text-[9px] font-black text-cyan-700">{t('SMART PRESETS')}</span></div>
          <div className="mt-2 flex gap-2 overflow-x-auto pb-2">
            {presets.map((preset, index) => (
              <button key={preset.signature} type="button" onClick={() => { setTitle(preset.automaticTitle ? '' : preset.title); setExercises(clonePreset(preset.exercises)) }} className="min-w-[190px] rounded-2xl border border-cyan-100 bg-white/72 p-3 text-left shadow-[0_12px_34px_-28px_rgba(14,116,144,.8)] active:scale-[.985]">
                <span className="font-mono text-[8px] font-black tracking-wide text-cyan-700 uppercase">{index === 0 ? t('Best match today') : preset.reason === 'sequence' ? t('Follows your last workout') : t('Recently used')}</span>
                <span className="mt-1 block truncate text-sm font-black text-ink">{preset.automaticTitle ? automaticWorkoutTitle(preset.exercises, language) : preset.title}</span>
                <span className="mt-1 block text-[10px] font-semibold text-ink-soft">{preset.exercises.length} {t('exercises')} · {t('last')} {preset.lastUsedDate}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="mt-4 space-y-3">
        <input value={title} onChange={(event) => setTitle(event.target.value)} className={inputClass} placeholder={t('Workout name (optional)')} maxLength={64} />
        <label className="relative block">
          <span className="pointer-events-none absolute top-1/2 left-4 -translate-y-1/2 text-ink-faint">⌕</span>
          <input ref={searchRef} value={query} onChange={(event) => setQuery(event.target.value)} className={`${inputClass} pl-10`} placeholder={t('Type an exercise, e.g. row, pull-up or treadmill')} autoComplete="off" />
        </label>
        {(query.trim() || exercises.length === 0) && (
          <div className="grid max-h-52 gap-2 overflow-y-auto sm:grid-cols-2">
            {results.map((item) => (
              <button key={item.id} type="button" onClick={() => addExercise(item)} className="flex min-h-14 items-center justify-between rounded-2xl border border-white bg-white/66 px-3 py-2 text-left active:scale-[.985]">
                <span className="min-w-0"><span className="block truncate text-sm font-bold text-ink">{displayExerciseName(item, language)}</span><span className="block truncate text-[9px] font-semibold text-ink-faint">{t(item.category)} · {t(item.equipment)}</span></span><span className="ml-2 grid h-8 w-8 shrink-0 place-items-center rounded-full bg-cyan-50 text-lg font-black text-cyan-700">+</span>
              </button>
            ))}
          </div>
        )}
      </div>

      {exercises.length > 0 && (
        <div className="mt-5 space-y-3">
          {exercises.map((exercise, exerciseIndex) => (
            <div
              key={exercise.id}
              ref={(node) => {
                if (node) exerciseEditorRefs.current.set(exercise.canonicalName, node)
                else exerciseEditorRefs.current.delete(exercise.canonicalName)
              }}
              className={`rounded-[24px] border bg-white/72 p-3 shadow-[0_18px_40px_-34px_rgba(15,23,42,.7)] transition-[border-color,box-shadow] duration-500 ${focusedExercise === exercise.canonicalName ? 'border-cyan-300 ring-4 ring-cyan-200/35 shadow-[0_20px_54px_-28px_rgba(6,182,212,.9)]' : 'border-white'}`}
            >
              <div className="flex items-center justify-between gap-3"><p className="min-w-0 truncate text-sm font-black text-ink"><span className="mr-2 font-mono text-[9px] text-cyan-700">{String(exerciseIndex + 1).padStart(2, '0')}</span>{localizedDraftName(exercise, language)}</p><button type="button" onClick={() => setExercises((current) => current.filter((item) => item.id !== exercise.id))} className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-rose-50 font-black text-rose-600" aria-label={t('Remove exercise')}>×</button></div>
              {exercise.treadmill ? (
                <div className="mt-3 grid grid-cols-3 gap-2">
                  {([
                    ['KM', 'distanceKm', exercise.treadmill.distanceKm, 100],
                    ['Incline °', 'inclineDeg', exercise.treadmill.inclineDeg, 45],
                    ['Time min', 'durationMin', exercise.treadmill.durationMin, 600],
                  ] as const).map(([label, key, value, max]) => (
                    <label key={key} className="min-w-0"><span className="mb-1 block truncate text-center font-mono text-[8px] font-black text-ink-faint uppercase">{t(label)}</span><input type="text" inputMode="decimal" value={value || ''} onChange={(event) => updateExercise(exercise.id, { treadmill: { ...exercise.treadmill!, [key]: numberValue(event.target.value, max) } })} className="w-full rounded-xl bg-slate-50 px-2 py-2.5 text-center font-mono text-sm font-black text-ink outline-none focus:ring-2 focus:ring-cyan-200" placeholder="0" /></label>
                  ))}
                </div>
              ) : (
                <div className="mt-2 space-y-1.5">
                  <div className="grid grid-cols-[1.5rem_1fr_1fr_2rem] gap-2 px-1 font-mono text-[8px] font-black tracking-wide text-ink-faint uppercase"><span>#</span><span>{t('Reps')}</span><span>{t('KG')}</span><span /></div>
                  {exercise.sets.map((set, setIndex) => (
                    <div key={set.id} className="grid grid-cols-[1.5rem_1fr_1fr_2rem] items-center gap-2"><span className="text-center font-mono text-[10px] font-black text-cyan-700">{setIndex + 1}</span><input aria-label={`${t('Reps')} ${setIndex + 1}`} type="number" inputMode="numeric" min="0" value={set.reps || ''} onChange={(event) => updateSet(exercise.id, set.id, { reps: numberValue(event.target.value, 999) })} className="min-w-0 rounded-xl bg-slate-50 px-2 py-2 text-center font-mono text-sm font-black text-ink outline-none focus:ring-2 focus:ring-cyan-200" placeholder="0" /><input aria-label={`${t('KG')} ${setIndex + 1}`} type="text" inputMode="decimal" value={set.weightKg || ''} onChange={(event) => updateSet(exercise.id, set.id, { weightKg: numberValue(event.target.value, 9999) })} className="min-w-0 rounded-xl bg-slate-50 px-2 py-2 text-center font-mono text-sm font-black text-ink outline-none focus:ring-2 focus:ring-cyan-200" placeholder="0" /><button type="button" onClick={() => updateExercise(exercise.id, { sets: exercise.sets.filter((item) => item.id !== set.id) })} className="grid h-8 w-8 place-items-center rounded-full text-ink-faint" aria-label={t('Remove set')}>×</button></div>
                  ))}
                  <button type="button" onClick={() => updateExercise(exercise.id, { sets: [...exercise.sets, { id: uid('set'), reps: exercise.sets.at(-1)?.reps ?? 10, weightKg: exercise.sets.at(-1)?.weightKg ?? 0 }] })} className="mt-1 w-full rounded-xl border border-dashed border-cyan-200 py-2 text-[10px] font-black text-cyan-800">+ {t('Add set')}</button>
                </div>
              )}
            </div>
          ))}
          <button type="button" onClick={() => { setQuery(''); searchRef.current?.focus(); searchRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' }) }} className="w-full rounded-2xl border border-dashed border-cyan-300 bg-cyan-50/55 py-3 text-sm font-black text-cyan-900">+ {t('Add next exercise')}</button>
        </div>
      )}

      <div className="mt-5 grid grid-cols-[auto_minmax(0,1fr)] gap-2">
        <GhostButton onClick={reset}>{t('Clear')}</GhostButton>
        <GradientButton accent={accent} className="py-4" onClick={save}>{t(editSessionId ? 'Update workout' : 'Save workout')}</GradientButton>
      </div>
    </Sheet>
  )
}

function ManualWorkoutTimelineItem({
  item,
  position,
  language,
  onEdit,
  onRequestDelete,
  onReorderCommit,
}: {
  item: ManualExerciseTimelineEntry
  position: number
  language: 'en' | 'ro' | 'th'
  onEdit: () => void
  onRequestDelete: () => void
  onReorderCommit: () => void
}) {
  const t = (value: string): string => translateInterfaceText(value, language)
  const reorderControls = useDragControls()
  const holdTimer = useRef<number | null>(null)
  const pointerStart = useRef<{ x: number; y: number } | null>(null)
  const longPressed = useRef(false)
  const swipeStarted = useRef(false)
  const [dragging, setDragging] = useState(false)
  const [revealed, setRevealed] = useState(false)
  const name = localizedDraftName(item.exercise, language)

  const clearHold = (): void => {
    if (holdTimer.current != null) window.clearTimeout(holdTimer.current)
    holdTimer.current = null
  }

  useEffect(() => () => clearHold(), [])

  const beginHold = (event: ReactPointerEvent<HTMLDivElement>): void => {
    if (event.pointerType === 'mouse' && event.button !== 0) return
    clearHold()
    pointerStart.current = { x: event.clientX, y: event.clientY }
    longPressed.current = false
    swipeStarted.current = false
    const startEvent = event.nativeEvent
    holdTimer.current = window.setTimeout(() => {
      longPressed.current = true
      setDragging(true)
      setRevealed(false)
      reorderControls.start(startEvent)
    }, 1_000)
  }

  const trackPointer = (event: ReactPointerEvent<HTMLDivElement>): void => {
    if (!pointerStart.current || longPressed.current) return
    const dx = event.clientX - pointerStart.current.x
    const dy = event.clientY - pointerStart.current.y
    if (Math.hypot(dx, dy) > 10) clearHold()
  }

  const finishPointer = (): void => {
    clearHold()
    pointerStart.current = null
    if (longPressed.current) window.setTimeout(() => { longPressed.current = false }, 0)
  }

  return (
    <Reorder.Item
      as="div"
      value={item.key}
      dragListener={false}
      dragControls={reorderControls}
      layout
      onDragStart={() => {
        setDragging(true)
        setRevealed(false)
      }}
      onDragEnd={() => {
        setDragging(false)
        onReorderCommit()
      }}
      className="relative overflow-hidden rounded-2xl"
      style={{ zIndex: dragging ? 20 : 0 }}
    >
      <button
        type="button"
        onClick={onRequestDelete}
        tabIndex={revealed ? 0 : -1}
        aria-hidden={!revealed}
        aria-label={`${t('Delete exercise')}: ${name}`}
        className="absolute inset-y-0 right-0 flex w-[82px] flex-col items-center justify-center bg-rose-600 text-white"
      >
        <span className="grid h-7 w-7 place-items-center rounded-full bg-white/18 text-lg font-black">×</span>
        <span className="mt-1 text-[9px] font-black uppercase">{t('Delete')}</span>
      </button>
      <motion.div
        drag={dragging ? false : 'x'}
        dragConstraints={{ left: -82, right: 0 }}
        dragElastic={0.04}
        dragMomentum={false}
        animate={{ x: revealed ? -82 : 0, scale: dragging ? 1.015 : 1 }}
        transition={{ type: 'spring', stiffness: 520, damping: 40 }}
        role="button"
        tabIndex={0}
        aria-label={`${name}. ${t('Tap to edit')}`}
        onPointerDown={beginHold}
        onPointerMove={trackPointer}
        onPointerUp={finishPointer}
        onPointerCancel={finishPointer}
        onContextMenu={(event) => event.preventDefault()}
        onDragStart={() => {
          swipeStarted.current = true
        }}
        onDragEnd={(_event, info) => {
          const shouldReveal = info.offset.x < -42 || info.velocity.x < -350
          setRevealed(shouldReveal)
          window.setTimeout(() => { swipeStarted.current = false }, 0)
        }}
        onClick={() => {
          if (longPressed.current || swipeStarted.current) return
          if (revealed) {
            setRevealed(false)
            return
          }
          onEdit()
        }}
        onKeyDown={(event) => {
          if (event.key !== 'Enter' && event.key !== ' ') return
          event.preventDefault()
          onEdit()
        }}
        className={`relative min-h-[94px] cursor-pointer select-none border bg-white px-3 py-3 transition-[border-color,box-shadow] ${dragging ? 'border-cyan-300 shadow-[0_24px_54px_-24px_rgba(6,182,212,.75)]' : 'border-white/95 shadow-[0_12px_30px_-28px_rgba(15,23,42,.65)]'}`}
        style={{ touchAction: dragging ? 'none' : 'pan-y' }}
      >
        <div className="flex items-start gap-3">
          <span className="mt-0.5 grid h-7 w-7 shrink-0 place-items-center rounded-full bg-cyan-50 font-mono text-[9px] font-black text-cyan-800">{String(position).padStart(2, '0')}</span>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-black text-ink">{name}</p>
            {item.exercise.treadmill ? (
              <p className="mt-1 font-mono text-[11px] font-semibold text-ink-soft">{item.exercise.treadmill.distanceKm} km · {item.exercise.treadmill.inclineDeg}° · {item.exercise.treadmill.durationMin} {t('min')}</p>
            ) : (
              <div className="mt-1 space-y-0.5">
                {item.exercise.sets.map((set, index) => (
                  <p key={set.id} className="font-mono text-[11px] font-semibold text-ink-soft">{index + 1}. {set.reps} {t('reps')}{set.weightKg > 0 ? ` × ${set.weightKg} kg` : ''}</p>
                ))}
              </div>
            )}
          </div>
          <span aria-hidden className="mt-1 shrink-0 font-mono text-sm tracking-[-.25em] text-ink-faint">⠿</span>
        </div>
      </motion.div>
    </Reorder.Item>
  )
}

export function TodayManualWorkoutCard({
  date,
  onAdd,
  onEdit,
  accent = ACCENTS.teal,
  compact = false,
}: {
  date: string
  onAdd: () => void
  onEdit?: (sessionId: string, canonicalName: string) => void
  accent?: Accent
  compact?: boolean
}) {
  const { data, bulkUpsert, remove, toast } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const timeline = useMemo(() => manualExerciseTimelineForDate(data, date), [data, date])
  const [orderKeys, setOrderKeys] = useState<string[]>([])
  const orderRef = useRef<string[]>([])
  const [confirmDelete, setConfirmDelete] = useState<ManualExerciseTimelineEntry | null>(null)

  useEffect(() => {
    const available = timeline.map((item) => item.key)
    const availableSet = new Set(available)
    setOrderKeys((current) => {
      const merged = [...current.filter((key) => availableSet.has(key)), ...available.filter((key) => !current.includes(key))]
      orderRef.current = merged
      return merged
    })
  }, [timeline])

  const timelineByKey = new Map(timeline.map((item) => [item.key, item]))
  const activeOrder = orderKeys.length > 0 ? orderKeys : timeline.map((item) => item.key)
  const orderedTimeline = activeOrder.map((key) => timelineByKey.get(key)).filter((item): item is ManualExerciseTimelineEntry => Boolean(item))

  const commitOrder = (): void => {
    const ordered = orderRef.current.map((key) => timelineByKey.get(key)).filter((item): item is ManualExerciseTimelineEntry => Boolean(item))
    if (ordered.length !== timeline.length) return
    const sessionIds = new Set(timeline.map((item) => item.sessionId))
    const relevantLogs = data.workout_logs.filter((log) => sessionIds.has(log.session_id))
    const resequenced = resequenceManualWorkoutLogs(relevantLogs, ordered)
    bulkUpsert('workout_logs', resequenced)
  }

  const deleteExercise = (): void => {
    if (!confirmDelete) return
    const sessionLogs = data.workout_logs.filter((log) => log.session_id === confirmDelete.sessionId)
    const exerciseLogs = sessionLogs.filter((log) => baseExerciseName(log.exercise_name) === confirmDelete.canonicalName)
    for (const log of exerciseLogs) remove('workout_logs', log.id)
    if (exerciseLogs.length === sessionLogs.length) remove('workout_sessions', confirmDelete.sessionId)
    setConfirmDelete(null)
    toast(t('Exercise removed'), 'ok')
  }

  if (timeline.length === 0) {
    if (compact) {
      return (
        <button type="button" onClick={onAdd} className="flex w-full items-center justify-between gap-3 rounded-2xl border border-cyan-100/90 bg-white/68 px-4 py-3 text-left shadow-[0_16px_38px_-34px_rgba(8,145,178,.8)] active:scale-[.99]">
          <span className="min-w-0"><span className="block font-mono text-[8px] font-black tracking-[.16em] text-cyan-700 uppercase">{t('WORKOUT')}</span><span className="mt-0.5 block truncate text-sm font-black text-ink">{t('Add Workout')}</span></span>
          <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-cyan-50 text-xl font-black text-cyan-800">+</span>
        </button>
      )
    }
    return (
      <button type="button" onClick={onAdd} className="group relative w-full overflow-hidden rounded-[26px] bg-[#071624] p-5 text-left text-white active:scale-[.99]" style={{ boxShadow: `0 24px 55px -34px ${accent.glowStrong}` }}>
        <div className="orbit-stars pointer-events-none absolute inset-0 opacity-40" aria-hidden /><div className="pointer-events-none absolute -right-16 -bottom-24 h-52 w-52 rounded-full bg-cyan-400/25 blur-3xl" aria-hidden />
        <div className="relative flex items-center justify-between gap-4"><div><p className="font-mono text-[9px] font-black tracking-[.18em] text-cyan-200 uppercase">{t('TRAIN YOUR WAY')}</p><h2 className="mt-1 font-display text-xl font-bold">{t('Add Workout')}</h2><p className="mt-1 text-xs text-slate-300">{t('Log exercises, sets, reps and weight after training.')}</p></div><span className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl bg-cyan-400 text-2xl font-black text-slate-950 transition group-active:scale-90">+</span></div>
      </button>
    )
  }

  return (
    <div className="rounded-[26px] border border-cyan-100 bg-white/68 p-4" style={{ boxShadow: `0 20px 48px -36px ${accent.glowStrong}` }}>
      <div className="flex items-center justify-between gap-3"><p className="font-mono text-[9px] font-black tracking-[.16em] text-cyan-700 uppercase">{t('WORKOUT LOGGED')}</p><button type="button" onClick={onAdd} className="rounded-xl bg-cyan-50 px-3 py-2 text-[10px] font-black text-cyan-800">+ {t('Add another')}</button></div>
      <Reorder.Group
        as="div"
        axis="y"
        data-simple-local-gesture
        values={activeOrder}
        onReorder={(next) => {
          orderRef.current = next
          setOrderKeys(next)
        }}
        className="mt-3 space-y-2"
      >
        {orderedTimeline.map((item, index) => (
          <ManualWorkoutTimelineItem
            key={item.key}
            item={item}
            position={index + 1}
            language={language}
            onEdit={() => onEdit?.(item.sessionId, item.canonicalName)}
            onRequestDelete={() => setConfirmDelete(item)}
            onReorderCommit={commitOrder}
          />
        ))}
      </Reorder.Group>
      <p className="mt-3 text-center text-[9px] font-semibold text-ink-faint">{t('Tap to edit · Hold for 1 second to reorder · Swipe left to remove')}</p>
      <p className="mt-2 font-mono text-[8px] font-black tracking-wide text-ink-faint uppercase">{t('Saved as a smart preset')} · {format(parseISO(date), 'dd MMM')}</p>

      <Sheet open={Boolean(confirmDelete)} onClose={() => setConfirmDelete(null)}>
        <div role="alertdialog" aria-modal="true" aria-labelledby="delete-workout-exercise-title">
          <div className="mx-auto grid h-12 w-12 place-items-center rounded-full bg-rose-100 text-2xl font-black text-rose-600">×</div>
          <h2 id="delete-workout-exercise-title" className="mt-3 text-center font-display text-xl font-bold text-ink">{t('Delete exercise?')}</h2>
          <p className="mt-2 text-center text-sm font-medium leading-relaxed text-ink-soft">{confirmDelete ? localizedDraftName(confirmDelete.exercise, language) : ''}</p>
          <p className="mt-1 text-center text-xs leading-relaxed text-ink-faint">{t('Remove this exercise and all of its sets from this workout?')}</p>
          <div className="mt-5 grid grid-cols-2 gap-2">
            <button type="button" onClick={() => setConfirmDelete(null)} className="rounded-2xl bg-slate-100 px-4 py-3 text-sm font-black text-ink">{t('Keep exercise')}</button>
            <button type="button" onClick={deleteExercise} className="rounded-2xl bg-rose-600 px-4 py-3 text-sm font-black text-white shadow-lg shadow-rose-600/20">{t('Delete')}</button>
          </div>
        </div>
      </Sheet>
    </div>
  )
}
