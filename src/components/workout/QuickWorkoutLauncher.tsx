import { useMemo, useState } from 'react'
import { EXERCISE_CATALOG, catalogExerciseByName, displayExerciseName } from '../../data/exerciseCatalog'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import {
  QUICK_WORKOUT_PRESET_LIMIT,
  rankManualWorkoutPresets,
  type ManualExerciseDraft,
  type ManualWorkoutPreset,
} from '../../lib/manualWorkout'
import { ACCENTS, type Accent } from '../../lib/theme'
import { useStore } from '../../store/AppStore'
import { Sheet } from '../ui'
import { ManualWorkoutLogger } from './ManualWorkoutLogger'

export interface QuickWorkoutLauncherProps {
  date: string
  accent?: Accent
  className?: string
  onSaved?: () => void
}

function DumbbellIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" className={className} aria-hidden>
      <path d="M7 8v8M4.5 9.5v5M17 8v8M19.5 9.5v5M7 12h10" />
    </svg>
  )
}

function localizedExerciseName(exercise: ManualExerciseDraft, language: 'en' | 'ro' | 'th'): string {
  const catalog = exercise.catalogId
    ? EXERCISE_CATALOG.find((item) => item.id === exercise.catalogId)
    : catalogExerciseByName(exercise.canonicalName)
  return catalog ? displayExerciseName(catalog, language) : exercise.canonicalName
}

function presetTitle(preset: ManualWorkoutPreset, language: 'en' | 'ro' | 'th', fallback: string): string {
  if (!preset.automaticTitle) return preset.title
  return preset.exercises
    .slice(0, 2)
    .map((exercise) => localizedExerciseName(exercise, language))
    .filter(Boolean)
    .join(' + ') || fallback
}

/**
 * A compact, mode-agnostic entry point for manual training. It intentionally
 * learns from persisted workout sessions and logs instead of keeping a second
 * preset store, so normal and ADHD Simple Mode always see the same data.
 */
export function QuickWorkoutLauncher({
  date,
  accent = ACCENTS.teal,
  className = '',
  onSaved,
}: QuickWorkoutLauncherProps) {
  const { data } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const [pickerOpen, setPickerOpen] = useState(false)
  const [loggerOpen, setLoggerOpen] = useState(false)
  const [initialPresetSignature, setInitialPresetSignature] = useState<string | null>(null)
  const presets = useMemo(
    () => rankManualWorkoutPresets(data, date).slice(0, QUICK_WORKOUT_PRESET_LIMIT),
    [data, date],
  )

  const openLogger = (signature: string | null): void => {
    setInitialPresetSignature(signature)
    setPickerOpen(false)
    setLoggerOpen(true)
  }

  const closeLogger = (): void => {
    setLoggerOpen(false)
    setInitialPresetSignature(null)
  }

  return (
    <div data-simple-local-gesture className={`inline-flex ${className}`}>
      <button
        type="button"
        onClick={() => setPickerOpen(true)}
        aria-label={t('Quick add workout')}
        className="relative grid h-11 w-11 shrink-0 place-items-center rounded-2xl border border-cyan-100/90 bg-white/78 text-cyan-800 shadow-[0_14px_34px_-24px_rgba(8,145,178,.9)] transition active:scale-90"
      >
        <DumbbellIcon className="h-5 w-5" />
        <span aria-hidden className="absolute -top-1 -right-1 grid h-4 w-4 place-items-center rounded-full bg-cyan-600 text-[10px] font-black leading-none text-white ring-2 ring-white">+</span>
      </button>

      <Sheet open={pickerOpen} onClose={() => setPickerOpen(false)}>
        <div data-simple-local-gesture>
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="font-mono text-[9px] font-black tracking-[.18em] text-cyan-700 uppercase">{t('SMART PRESETS')}</p>
              <h2 className="mt-1 font-display text-xl font-bold text-ink">{t('Choose a workout')}</h2>
              <p className="mt-1 text-[11px] font-semibold leading-relaxed text-ink-soft">{t('Up to seven matches, ranked for this day.')}</p>
            </div>
            <button type="button" onClick={() => setPickerOpen(false)} aria-label={t('Close')} className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-ink/5 text-lg font-black text-ink">×</button>
          </div>

          <div className="mt-4 max-h-[52dvh] space-y-2 overflow-y-auto">
            {presets.map((preset, index) => (
              <button
                key={preset.signature}
                type="button"
                onClick={() => openLogger(preset.signature)}
                className="flex w-full items-center gap-3 rounded-2xl border border-cyan-100/80 bg-white/82 px-3 py-3 text-left shadow-[0_12px_32px_-28px_rgba(8,145,178,.8)] transition active:scale-[.985]"
              >
                <span className="grid h-8 w-8 shrink-0 place-items-center rounded-xl bg-cyan-50 font-mono text-[10px] font-black text-cyan-800">{String(index + 1).padStart(2, '0')}</span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-black text-ink">{presetTitle(preset, language, t('Workout'))}</span>
                  <span className="mt-0.5 block truncate text-[9px] font-semibold text-ink-faint">
                    {preset.exercises.length} {t('exercises')} · {index === 0
                      ? t('Best match today')
                      : preset.reason === 'sequence'
                        ? t('Follows your last workout')
                        : preset.reason === 'same-weekday'
                          ? t('Same weekday rhythm')
                          : t('Recently used')}
                  </span>
                </span>
                <span aria-hidden className="font-black text-cyan-700">›</span>
              </button>
            ))}
            {presets.length === 0 && (
              <div className="rounded-2xl bg-cyan-50/60 px-4 py-5 text-center">
                <DumbbellIcon className="mx-auto h-6 w-6 text-cyan-700" />
                <p className="mt-2 text-xs font-black text-ink">{t('No saved workouts yet')}</p>
                <p className="mt-1 text-[10px] font-semibold text-ink-faint">{t('Create one once, then it will be ranked here automatically.')}</p>
              </div>
            )}
          </div>

          <button
            type="button"
            onClick={() => openLogger(null)}
            className="mt-4 flex w-full items-center justify-center gap-2 rounded-2xl bg-[#071624] px-4 py-3 text-sm font-black text-white shadow-[0_18px_42px_-26px_rgba(7,22,36,.9)] active:scale-[.99]"
          >
            <DumbbellIcon className="h-4 w-4" />
            {t('Expand')}
          </button>
        </div>
      </Sheet>

      <ManualWorkoutLogger
        open={loggerOpen}
        onClose={closeLogger}
        onSaved={onSaved}
        date={date}
        initialPresetSignature={initialPresetSignature}
        accent={accent}
      />
    </div>
  )
}
