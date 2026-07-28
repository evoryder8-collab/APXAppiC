import { useEffect, useMemo, useState } from 'react'
import { ACCENTS } from '../lib/theme'
import type { AppData, Profile, Settings, WatchActivityCheckin as WatchEntry } from '../lib/types'
import { PAL_LABELS } from '../lib/activity'
import { normalizeWatchActivityHistory, recommendActivityMode } from '../lib/personalProtocol'
import { translateInterfaceText, useLanguage } from '../lib/i18n'

interface Props {
  date: string
  data: AppData
  profile: Profile
  settings: Settings
  onSettingsChange: (patch: Partial<Settings>) => void
  onProfileChange: (patch: Partial<Profile>) => void
  compact?: boolean
  detailed?: boolean
}

function numberDraft(value: number | null | undefined): string {
  return value == null || value === 0 ? '' : String(value)
}

function cleanNumber(value: string): number {
  const number = Number(value)
  return Number.isFinite(number) ? Math.max(0, Math.round(number)) : 0
}

export function WatchActivityCheckin({
  date,
  data,
  profile,
  settings,
  onSettingsChange,
  onProfileChange,
  compact = false,
  detailed = false,
}: Props) {
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const [open, setOpen] = useState(false)
  const history = useMemo(() => normalizeWatchActivityHistory(settings.addons.watch_activity_history), [settings.addons.watch_activity_history])
  const existing = history.find((entry) => entry.date === date)
  const [steps, setSteps] = useState(() => numberDraft(existing?.steps))
  const [calories, setCalories] = useState(() => numberDraft(existing?.active_calories))
  const [minutes, setMinutes] = useState(() => numberDraft(existing?.exercise_minutes))

  useEffect(() => {
    setSteps(numberDraft(existing?.steps))
    setCalories(numberDraft(existing?.active_calories))
    setMinutes(numberDraft(existing?.exercise_minutes))
  }, [date, existing?.active_calories, existing?.exercise_minutes, existing?.steps])

  const completedSessions = data.workout_sessions.filter((session) => session.date === date && session.completed)
  const completedSessionIds = new Set(completedSessions.map((session) => session.id))
  const completedDayTypes = new Set(completedSessions.flatMap((session) => {
    const day = data.program_days.find((candidate) => candidate.id === session.program_day_id)
    return day ? [day.day_type] : []
  }))
  const hasT25 = data.workout_logs.some((row) =>
    completedSessionIds.has(row.session_id) && /focus\s*t25|hiit/i.test(row.exercise_name) && !row.skipped,
  )
  const activityLogs = data.activity_logs.filter((entry) => entry.date === date)
  const massageAppointments = activityLogs
    .filter((entry) => entry.type_id === 'massage-session' || entry.type_id === 'deep-tissue-massage')
    .reduce((sum, entry) => sum + Math.max(0, Number(entry.quantity) || 0), 0)
  const gimbalMinutes = activityLogs
    .filter((entry) => entry.type_id === 'gimbal-filming')
    .reduce((sum, entry) => sum + Math.max(0, Number(entry.duration_min) || 0), 0)

  const recommendation = recommendActivityMode(profile.persona, {
    steps: cleanNumber(steps),
    activeCalories: cleanNumber(calories),
    exerciseMinutes: cleanNumber(minutes),
  }, {
    strengthCompleted: [...completedDayTypes].some((type) => ['legs_a', 'legs_b', 'push', 'pull', 'upper'].includes(type)),
    focusT25Completed: hasT25,
    substantialWalkingOrHousework: cleanNumber(steps) >= 7500,
    massageAppointments,
    demandingMassageAppointments: activityLogs.filter((entry) => entry.type_id === 'deep-tissue-massage').reduce((sum, entry) => sum + Number(entry.quantity), 0),
    gimbalMinutes,
  })

  const persist = (selectedLevel = profile.activity_level): void => {
    const next: WatchEntry = {
      date,
      steps: cleanNumber(steps),
      active_calories: cleanNumber(calories),
      exercise_minutes: cleanNumber(minutes),
      suggested_level: recommendation.level,
      selected_level: selectedLevel,
      updated_at: new Date().toISOString(),
    }
    const nextHistory = [next, ...history.filter((entry) => entry.date !== date)]
      .sort((left, right) => right.date.localeCompare(left.date))
      .slice(0, 730)
    onSettingsChange({ addons: { ...settings.addons, watch_activity_history: nextHistory } })
  }

  const copy = language === 'ro'
    ? {
        title: 'Activitate Apple Watch',
        body: 'Ajută APEX să recomande un mod pentru întreaga zi. Valorile nu se adaugă peste antrenamentul APEX.',
        steps: 'Pași',
        calories: 'Calorii active',
        minutes: 'Minute de exercițiu',
        suggested: 'Mod sugerat',
        use: 'Folosește acest mod',
        selected: 'Modul selectat rămâne alegerea ta.',
      }
    : language === 'th'
      ? {
          title: 'กิจกรรมจาก Apple Watch',
          body: 'ช่วย APEX แนะนำโหมดสำหรับทั้งวัน ค่านี้จะไม่บวกซ้ำกับการฝึก APEX',
          steps: 'ก้าว',
          calories: 'แคลอรีที่เคลื่อนไหว',
          minutes: 'นาทีออกกำลังกาย',
          suggested: 'โหมดที่แนะนำ',
          use: 'ใช้โหมดนี้',
          selected: 'โหมดที่เลือกยังเป็นการตัดสินใจของคุณ',
        }
      : {
          title: 'Apple Watch activity',
          body: 'Helps APEX recommend one whole-day mode. These values are not added on top of an APEX workout.',
          steps: 'Steps',
          calories: 'Active calories',
          minutes: 'Exercise minutes',
          suggested: 'Suggested mode',
          use: 'Use this mode',
          selected: 'The selected mode remains your choice.',
        }

  return (
    <details open={open} onToggle={(event) => setOpen(event.currentTarget.open)} className={`rounded-3xl border border-cyan-100/80 bg-white/52 p-3 shadow-sm ${compact ? 'min-h-[5.25rem]' : ''}`} data-simple-local-gesture>
      <summary className="flex cursor-pointer list-none items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="font-display text-sm font-black text-ink">{copy.title}</p>
          {(existing || detailed) && <p className="mt-0.5 truncate text-[9px] font-semibold text-ink-faint">{existing ? `${existing.steps.toLocaleString()} ${copy.steps.toLocaleLowerCase()} · ${t(PAL_LABELS[existing.suggested_level])}` : copy.body}</p>}
        </div>
        <span className="grid h-8 w-8 place-items-center rounded-full bg-cyan-50 text-sm font-black text-cyan-800">{open ? '−' : '+'}</span>
      </summary>
      <div className="mt-3 border-t border-ink/6 pt-3">
        {detailed && <p className="mb-3 text-[10px] leading-relaxed font-semibold text-ink-soft">{copy.body}</p>}
        <div className="grid grid-cols-3 gap-2">
          {[
            { label: copy.steps, value: steps, set: setSteps, max: 100000 },
            { label: copy.calories, value: calories, set: setCalories, max: 5000 },
            { label: copy.minutes, value: minutes, set: setMinutes, max: 1440 },
          ].map((field) => (
            <label key={field.label} className="min-w-0">
              <span className="mb-1 block truncate text-[8px] font-black text-ink-faint">{field.label}</span>
              <input
                aria-label={field.label}
                type="number"
                inputMode="numeric"
                min="0"
                max={field.max}
                value={field.value}
                onChange={(event) => field.set(event.target.value)}
                onBlur={() => persist()}
                onKeyDown={(event) => event.key === 'Enter' && event.currentTarget.blur()}
                className="w-full rounded-xl border border-cyan-100 bg-white/88 px-2 py-2 text-center font-mono text-sm font-black text-ink outline-none focus:border-cyan-400"
              />
            </label>
          ))}
        </div>
        <div className="mt-3 flex items-center justify-between gap-3 rounded-2xl p-3" style={{ background: ACCENTS.ice.wash }}>
          <div>
            <p className="font-mono text-[8px] font-black tracking-wide text-cyan-800 uppercase">{copy.suggested}</p>
            <p className="mt-0.5 text-sm font-black text-ink">{t(PAL_LABELS[recommendation.level])}</p>
            <p className="mt-0.5 text-[8px] font-semibold text-ink-faint">{copy.selected}</p>
          </div>
          {profile.activity_level !== recommendation.level && (
            <button type="button" onClick={() => { persist(recommendation.level); onProfileChange({ activity_level: recommendation.level }) }} className="shrink-0 rounded-xl bg-cyan-700 px-3 py-2 text-[9px] font-black text-white">{copy.use}</button>
          )}
        </div>
      </div>
    </details>
  )
}
