import { useMemo, useState } from 'react'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import type { Accent } from '../../lib/theme'
import { ACCENTS, accentVars } from '../../lib/theme'
import { todayIso } from '../../lib/plan'
import { workoutInsights } from '../../lib/workoutInsights'
import { workoutInsightsCardBlob } from '../../lib/workoutInsightsCard'
import { useStore } from '../../store/AppStore'
import { GlassCard } from '../ui'

type RangeMode = 'day' | 'week' | 'year' | 'custom'

function moveDays(isoDate: string, amount: number): string {
  const date = new Date(`${isoDate}T12:00:00.000Z`)
  date.setUTCDate(date.getUTCDate() + amount)
  return date.toISOString().slice(0, 10)
}

function moveYears(isoDate: string, amount: number): string {
  const date = new Date(`${isoDate}T12:00:00.000Z`)
  const month = date.getUTCMonth()
  date.setUTCFullYear(date.getUTCFullYear() + amount)
  if (date.getUTCMonth() !== month) date.setUTCDate(0)
  return date.toISOString().slice(0, 10)
}

function localizedRange(from: string, to: string, locale: string): string {
  const format = new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' })
  const start = format.format(new Date(`${from}T12:00:00.000Z`))
  const end = format.format(new Date(`${to}T12:00:00.000Z`))
  return from === to ? start : `${start} - ${end}`
}

function durationText(minutes: number, locale: string): string {
  const number = new Intl.NumberFormat(locale)
  const hours = Math.floor(minutes / 60)
  const remainder = minutes % 60
  if (hours === 0) return `${number.format(remainder)} min`
  if (remainder === 0) return `${number.format(hours)} h`
  return `${number.format(hours)} h ${number.format(remainder)} min`
}

export function WorkoutInsightsCard({
  anchorDate = todayIso(),
  accent = ACCENTS.violet,
}: {
  anchorDate?: string
  accent?: Accent
}) {
  const { data, toast } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const ownerID = data.profile?.user_id ?? data.settings?.user_id ?? ''
  const evidenceDates = [
    ...data.workout_sessions.filter((session) => session.user_id === ownerID && session.completed).map((session) => session.date),
    ...data.imported_activities.filter((activity) => activity.user_id === ownerID && !activity.hidden_at).map((activity) => activity.date),
  ].sort()
  const earliest = evidenceDates[0] ?? moveYears(anchorDate, -1)
  const [mode, setMode] = useState<RangeMode>('week')
  const [customFrom, setCustomFrom] = useState(earliest)
  const [customTo, setCustomTo] = useState(anchorDate)
  const [exporting, setExporting] = useState(false)
  const range = useMemo(() => {
    switch (mode) {
    case 'day': return { from: anchorDate, to: anchorDate }
    case 'week': return { from: moveDays(anchorDate, -6), to: anchorDate }
    case 'year': return { from: moveYears(anchorDate, -1), to: anchorDate }
    case 'custom': return customFrom <= customTo
      ? { from: customFrom, to: customTo }
      : { from: customTo, to: customFrom }
    }
  }, [anchorDate, customFrom, customTo, mode])
  const summary = useMemo(() => workoutInsights({
    ownerID,
    from: range.from,
    to: range.to,
    sessions: data.workout_sessions,
    logs: data.workout_logs,
    importedActivities: data.imported_activities,
  }), [data.imported_activities, data.workout_logs, data.workout_sessions, ownerID, range.from, range.to])
  const number = useMemo(() => new Intl.NumberFormat(language, { maximumFractionDigits: 2 }), [language])
  const missing = '\u2014'
  const metrics = [
    { label: t('Workouts'), value: number.format(summary.workouts) },
    { label: t('Active days'), value: number.format(summary.activeDays) },
    { label: t('Recorded time'), value: durationText(summary.durationMinutes, language) },
    { label: t('Active energy'), value: summary.activeEnergyKcal == null ? missing : `${number.format(summary.activeEnergyKcal)} kcal` },
    { label: t('Reps'), value: number.format(summary.reps) },
    { label: t('Sets / efforts'), value: number.format(summary.sets) },
    { label: t('Recorded volume'), value: summary.volumeKg == null ? missing : `${number.format(summary.volumeKg)} kg` },
    { label: t('Distance'), value: summary.distanceKm == null ? missing : `${number.format(summary.distanceKm)} km` },
  ]

  const exportPNG = async (): Promise<void> => {
    setExporting(true)
    try {
      const rangeLabel = localizedRange(summary.from, summary.to, language)
      const blob = await workoutInsightsCardBlob(summary, {
        accent,
        athleteName: data.profile?.display_name ?? t('APEX athlete'),
        locale: language,
        rangeLabel,
        labels: {
          title: t('Workout insights'),
          workouts: t('Workouts'),
          activeDays: t('Active days'),
          time: t('Recorded time'),
          energy: t('Active energy'),
          reps: t('Reps'),
          sets: t('Sets / efforts'),
          volume: t('Recorded volume'),
          distance: t('Distance'),
          anniversary: t('Anniversary'),
          verified: t('Only recorded workout facts. Linked wearable energy is counted once.'),
        },
      })
      const filename = `apex-workout-insights-${summary.from}-${summary.to}.png`
      const file = new File([blob], filename, { type: 'image/png' })
      if (navigator.share && navigator.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file], title: t('Workout insights') })
      } else {
        const url = URL.createObjectURL(blob)
        const link = document.createElement('a')
        link.href = url
        link.download = filename
        link.click()
        window.setTimeout(() => URL.revokeObjectURL(url), 1_000)
      }
    } catch (error) {
      if ((error as Error).name !== 'AbortError') toast(t('The workout card could not be rendered.'), 'error')
    } finally {
      setExporting(false)
    }
  }

  return <GlassCard accent={accent} className="overflow-hidden p-5" style={accentVars(accent)}>
    <div className="flex items-start justify-between gap-4">
      <div>
        <p className="font-mono text-[9px] font-black tracking-[.2em] uppercase" style={{ color: accent.deep }}>{t('APEX WORKOUT INSIGHTS')}</p>
        <h2 className="mt-1 font-display text-2xl font-bold text-ink">{t('Workout insights')}</h2>
        <p className="mt-1 text-xs font-semibold text-ink-soft">{localizedRange(summary.from, summary.to, language)}</p>
      </div>
      <button type="button" onClick={() => { void exportPNG() }} disabled={exporting} className="min-h-11 shrink-0 rounded-2xl px-4 text-xs font-black text-white shadow-sm disabled:opacity-60" style={{ background: accent.gradient }}>
        {exporting ? t('Rendering...') : t('Export PNG')}
      </button>
    </div>

    <div className="mt-4 grid grid-cols-4 rounded-2xl bg-ink/5 p-1" role="group" aria-label={t('Workout insight range')}>
      {(['day', 'week', 'year', 'custom'] as const).map((value) => <button key={value} type="button" aria-pressed={mode === value} onClick={() => setMode(value)} className={`min-h-10 rounded-xl px-1 text-[10px] font-black transition ${mode === value ? 'bg-white text-ink shadow-sm' : 'text-ink-soft'}`}>
        {t(value === 'day' ? 'Day' : value === 'week' ? 'Week' : value === 'year' ? 'Year' : 'Custom')}
      </button>)}
    </div>

    {mode === 'custom' && <div className="mt-3 grid grid-cols-2 gap-2">
      <label className="text-[10px] font-bold text-ink-soft">{t('From')}<input type="date" value={customFrom} max={customTo} onChange={(event) => setCustomFrom(event.target.value)} className="mt-1 min-h-11 w-full rounded-xl border border-ink/10 bg-white/70 px-2 text-xs text-ink" /></label>
      <label className="text-[10px] font-bold text-ink-soft">{t('To')}<input type="date" value={customTo} min={customFrom} max={anchorDate} onChange={(event) => setCustomTo(event.target.value)} className="mt-1 min-h-11 w-full rounded-xl border border-ink/10 bg-white/70 px-2 text-xs text-ink" /></label>
    </div>}

    {summary.anniversaryYears && <div className="mt-4 rounded-2xl px-4 py-3 text-center text-xs font-black tracking-widest text-white" style={{ background: accent.gradient }}>
      {summary.anniversaryYears} {t(summary.anniversaryYears === 1 ? 'YEAR ANNIVERSARY' : 'YEARS ANNIVERSARY')}
    </div>}

    <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
      {metrics.map((metric) => <div key={metric.label} className="min-w-0 rounded-2xl border border-white/70 bg-white/55 px-3 py-3">
        <p className="font-mono text-[8px] font-black tracking-wider text-ink-faint uppercase">{metric.label}</p>
        <p className="mt-1 break-words font-display text-lg font-bold text-ink">{metric.value}</p>
      </div>)}
    </div>
    <p className="mt-4 text-[10px] font-semibold leading-relaxed text-ink-faint">{t('Only recorded workout facts. Linked wearable energy is counted once.')}</p>
  </GlassCard>
}
