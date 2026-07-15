import { lazy, Suspense, useMemo, useState } from 'react'
import { getISODay } from 'date-fns'
import type { IntroLanguage } from '../lib/introLanguage'
import { useLanguage } from '../lib/i18n'
import type { Accent } from '../lib/theme'
import { ACCENTS } from '../lib/theme'
import type { Exercise, Program, ProgramDay } from '../lib/types'
import { useOrbitText } from '../orbit/ui/i18n'
import { useStore } from '../store/AppStore'
import {
  EXERCISE_CATEGORIES,
  EXERCISE_CATALOG,
  searchExerciseCatalog,
  type ExerciseCatalogItem,
  type ExerciseCategory,
} from '../data/exerciseCatalog'
import { GhostButton, GradientButton, Sheet } from './ui'

const HologramStage = lazy(() =>
  import('./hologram/HologramStage').then((module) => ({ default: module.HologramStage })),
)

interface SelectedExercise {
  id: string
  sets: number
  reps: number
  rest: number
}

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

function estimatedMinutes(selected: SelectedExercise[], byId: Map<string, ExerciseCatalogItem>): number {
  const seconds = selected.reduce((total, selection) => {
    const exercise = byId.get(selection.id)
    if (!exercise) return total
    const workSeconds = exercise.unit === 'minutes'
      ? selection.reps * 60
      : exercise.unit === 'seconds'
        ? selection.reps
        : Math.max(20, selection.reps * 3)
    return total + selection.sets * (workSeconds + selection.rest)
  }, 0)
  return Math.max(8, Math.round(seconds / 60))
}

export function CustomWorkoutBuilder({
  open,
  onClose,
  onSaved,
  accent = ACCENTS.violet,
}: {
  open: boolean
  onClose: () => void
  onSaved: () => void
  accent?: Accent
}) {
  const { data, upsert, bulkUpsert, remove, toast } = useStore()
  const t = useOrbitText()
  const { language } = useLanguage()
  const [name, setName] = useState('')
  const [weekday, setWeekday] = useState(() => getISODay(new Date()))
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState<'all' | ExerciseCategory>('all')
  const [selected, setSelected] = useState<SelectedExercise[]>([])

  const byId = useMemo(() => new Map(EXERCISE_CATALOG.map((item) => [item.id, item])), [])
  const results = useMemo(
    () => searchExerciseCatalog(query, category).slice(0, query.trim() ? 24 : 14),
    [category, query],
  )
  const selectedNames = useMemo(
    () => selected.map((selection) => byId.get(selection.id)?.name).filter((value): value is string => !!value),
    [byId, selected],
  )
  const selectedIds = useMemo(() => new Set(selected.map((item) => item.id)), [selected])

  const addExercise = (item: ExerciseCatalogItem): void => {
    setSelected((current) => current.some((entry) => entry.id === item.id)
      ? current.filter((entry) => entry.id !== item.id)
      : [...current, { id: item.id, sets: item.sets, reps: item.reps, rest: item.rest }])
  }

  const updateExercise = (id: string, patch: Partial<Omit<SelectedExercise, 'id'>>): void => {
    setSelected((current) => current.map((entry) => entry.id === id ? { ...entry, ...patch } : entry))
  }

  const reset = (): void => {
    setName('')
    setQuery('')
    setCategory('all')
    setSelected([])
  }

  const save = (): void => {
    const profile = data.profile
    if (!profile || !name.trim() || selected.length === 0) {
      toast(t('Add at least one exercise and give the workout a name.'))
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
    const existingDay = data.program_days.find((day) => day.program_id === program.id && day.weekday === weekday)
    const day: ProgramDay = {
      id: existingDay?.id ?? crypto.randomUUID(),
      user_id: profile.user_id,
      program_id: program.id,
      weekday,
      name: name.trim(),
      day_type: 'custom',
      est_minutes: estimatedMinutes(selected, byId),
      warmup_note: 'Five minutes of pain-free joint preparation',
      sort_order: weekday,
    }

    for (const exercise of data.exercises.filter((item) => item.program_day_id === day.id)) {
      remove('exercises', exercise.id)
    }
    upsert('programs', program)
    upsert('program_days', day)
    bulkUpsert<Exercise>('exercises', selected.map((selection, index) => {
      const item = byId.get(selection.id)!
      const weighted = item.category === 'weights' || item.category === 'machine'
      return {
        id: crypto.randomUUID(),
        user_id: profile.user_id,
        program_day_id: day.id,
        name: item.name,
        sets: clamp(selection.sets, 1, 12),
        rep_min: clamp(selection.reps, 1, 600),
        rep_max: clamp(selection.reps, 1, 600),
        rep_unit: item.unit,
        per_side: item.perSide,
        rest_sec: clamp(selection.rest, 0, 600),
        tempo_up_s: 1,
        tempo_down_s: 2,
        tempo_pause_s: 0,
        tempo_note: '',
        notes: `${item.equipment} · ${item.muscles.join(', ')}`,
        increment_kg: weighted ? 2.5 : 0,
        is_lite: false,
        optional: false,
        sort_order: index,
      }
    }))
    toast(t('Custom workout saved'), 'ok')
    reset()
    onClose()
    onSaved()
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
            <span className="mb-1.5 block text-xs font-bold text-ink-soft">{t('Training day')}</span>
            <div className="flex gap-1.5 overflow-x-auto pb-1">
              {WEEKDAYS.map((day) => (
                <button key={day.id} type="button" onClick={() => setWeekday(day.id)} className={`min-h-10 shrink-0 rounded-full px-3 text-[11px] font-black transition ${weekday === day.id ? 'bg-[#111827] text-white shadow-lg' : 'border border-white/90 bg-white/65 text-ink-soft'}`}>
                  {WEEKDAY_SHORT[language][day.id - 1]}
                </button>
              ))}
            </div>
            <p className="mt-1 text-[10px] leading-relaxed text-ink-faint">{t('Saving another workout on the same day replaces that day’s custom plan.')}</p>
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
        <div className="grid max-h-[270px] gap-2 overflow-y-auto pr-1 sm:grid-cols-2">
          {results.map((item) => {
            const active = selectedIds.has(item.id)
            return (
              <button key={item.id} type="button" onClick={() => addExercise(item)} className={`flex min-h-[68px] items-center justify-between gap-3 rounded-2xl border p-3 text-left transition active:scale-[.985] ${active ? 'border-violet-300 bg-violet-50/90 shadow-[0_10px_28px_-20px_rgba(109,40,217,.8)]' : 'border-white/95 bg-white/60'}`}>
                <span className="min-w-0">
                  <span className="block truncate text-sm font-bold text-ink">{t(item.name)}</span>
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
              return (
                <div key={selection.id} className="rounded-2xl border border-white bg-white/72 p-3">
                  <div className="flex items-center justify-between gap-3">
                    <p className="min-w-0 truncate text-sm font-bold text-ink"><span className="mr-2 font-mono text-[9px] text-violet-600">{String(index + 1).padStart(2, '0')}</span>{t(item.name)}</p>
                    <button type="button" onClick={() => addExercise(item)} className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-rose-50 font-bold text-rose-600" aria-label={`${t('Remove')} ${t(item.name)}`}>×</button>
                  </div>
                  <div className="mt-2 grid grid-cols-3 gap-2">
                    {([
                      ['Sets', 'sets', selection.sets, 1, 12],
                      [item.unit === 'reps' ? 'Repetitions' : item.unit, 'reps', selection.reps, 1, 600],
                      ['Rest seconds', 'rest', selection.rest, 0, 600],
                    ] as const).map(([label, key, value, min, max]) => (
                      <label key={key} className="min-w-0">
                        <span className="mb-1 block truncate text-[8px] font-black tracking-wide text-ink-faint uppercase">{t(label)}</span>
                        <input type="number" inputMode="numeric" min={min} max={max} value={value} onChange={(event) => updateExercise(selection.id, { [key]: clamp(Number(event.target.value), min, max) })} className="w-full rounded-xl border border-slate-100 bg-slate-50 px-2 py-2 text-center font-mono text-xs font-black text-ink outline-none focus:border-violet-300" />
                      </label>
                    ))}
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </div>

      <GradientButton accent={accent} className="mt-5 w-full py-4" onClick={save}>
        {t('Save custom workout')}
      </GradientButton>
    </Sheet>
  )
}
