import { useEffect, useMemo, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import type { LoggedFoodEntry, LoggedMeal } from '../../lib/food'
import type { IntroLanguage } from '../../lib/introLanguage'
import {
  comfortZone,
  daylineRatio,
  fallbackMealTime,
  isQuietClock,
  minuteToClock,
  timedMeal,
  zonedClock,
  zonedDateTimeToIso,
  type MealComfortZone,
  type TimedMeal,
} from '../../lib/mealTiming'
import { useLanguage } from '../../lib/i18n'
import { ACCENTS } from '../../lib/theme'
import { GlassCard } from '../ui'

const COPY = {
  en: {
    eyebrow: 'LIVE METABOLIC DAYLINE',
    title: 'Eat. Settle. Move.',
    subtitle: 'Your meals and a calm estimate of when training may feel more comfortable.',
    local: 'local time',
    finished: 'Meal finished',
    recorded: 'recorded',
    estimated: 'estimated',
    save: 'Save time',
    saving: 'Saving',
    saveFailed: 'This finish time could not be saved. Please try again.',
    close: 'Close',
    settling: 'Settling',
    transition: 'Tradeoff window',
    ready: 'Comfort window',
    in: 'in',
    now: 'NOW',
    noMeals: 'Log a meal or snack and its comfort window will appear here.',
    note: 'Comfort estimate only. Workout intensity, meal composition and personal tolerance still matter.',
    light: 'light',
    standard: 'standard',
    substantial: 'substantial',
    large: 'large',
  },
  ro: {
    eyebrow: 'CRONOLOGIE METABOLICĂ LIVE',
    title: 'Mănâncă. Așteaptă. Mișcă-te.',
    subtitle: 'Mesele tale și o estimare calmă a momentului în care antrenamentul poate fi mai confortabil.',
    local: 'ora locală',
    finished: 'Masa s-a încheiat',
    recorded: 'înregistrată',
    estimated: 'estimată',
    save: 'Salvează ora',
    saving: 'Se salvează',
    saveFailed: 'Ora de final nu a putut fi salvată. Încearcă din nou.',
    close: 'Închide',
    settling: 'Digestie în curs',
    transition: 'Fereastră de compromis',
    ready: 'Fereastră confortabilă',
    in: 'în',
    now: 'ACUM',
    noMeals: 'Înregistrează o masă sau o gustare, iar fereastra de confort va apărea aici.',
    note: 'Doar estimare de confort. Intensitatea, compoziția mesei și toleranța personală contează.',
    light: 'ușoară',
    standard: 'standard',
    substantial: 'consistentă',
    large: 'mare',
  },
  th: {
    eyebrow: 'ไทม์ไลน์เมตาบอลิซึมแบบสด',
    title: 'กิน พักย่อย แล้วขยับ',
    subtitle: 'มื้ออาหารของคุณพร้อมเวลาประมาณที่การฝึกอาจรู้สึกสบายขึ้น',
    local: 'เวลาท้องถิ่น',
    finished: 'กินมื้อเสร็จ',
    recorded: 'บันทึกแล้ว',
    estimated: 'โดยประมาณ',
    save: 'บันทึกเวลา',
    saving: 'กำลังบันทึก',
    saveFailed: 'บันทึกเวลาที่กินเสร็จไม่ได้ โปรดลองอีกครั้ง',
    close: 'ปิด',
    settling: 'กำลังย่อย',
    transition: 'ช่วงประนีประนอม',
    ready: 'ช่วงที่สบายขึ้น',
    in: 'ในอีก',
    now: 'ตอนนี้',
    noMeals: 'บันทึกมื้ออาหารหรือของว่าง แล้วช่วงเวลาที่สบายขึ้นจะแสดงที่นี่',
    note: 'เป็นเพียงการประเมินความสบาย ความหนักของการฝึก องค์ประกอบอาหาร และความทนของแต่ละคนยังมีผล',
    light: 'เบา',
    standard: 'ปกติ',
    substantial: 'มื้อหนัก',
    large: 'มื้อใหญ่มาก',
  },
} satisfies Record<IntroLanguage, Record<string, string>>

const TICKS = [
  { minute: 180, label: '03', opacity: 0.13 },
  { minute: 240, label: '04', opacity: 0.26 },
  { minute: 300, label: '05', opacity: 0.54 },
  { minute: 420, label: '07', opacity: 0.86 },
  { minute: 600, label: '10', opacity: 0.62 },
  { minute: 780, label: '13', opacity: 0.86 },
  { minute: 960, label: '16', opacity: 0.62 },
  { minute: 1140, label: '19', opacity: 0.86 },
  { minute: 1320, label: '22', opacity: 0.56 },
  { minute: 1440, label: '00', opacity: 0.34 },
  { minute: 1500, label: '01', opacity: 0.22 },
  { minute: 1560, label: '02', opacity: 0.11 },
] as const

const ZONE_COLOR: Record<MealComfortZone, string> = {
  settling: '#fb7185',
  transition: '#f59e0b',
  ready: '#10b981',
}

function labelLayout(events: TimedMeal[], height: number, compact: boolean): Map<string, number> {
  const pad = compact ? 24 : 28
  const gap = compact ? 53 : 59
  const ordered = events
    .map((event) => ({ id: event.meal.id, actual: daylineRatio(event.minute) * height }))
    .sort((left, right) => left.actual - right.actual)
  const positions = ordered.map((event, index) =>
    Math.max(pad, Math.min(height - pad, index === 0 ? event.actual : Math.max(event.actual, 0))),
  )
  for (let index = 1; index < positions.length; index += 1) {
    positions[index] = Math.max(positions[index], positions[index - 1] + gap)
  }
  if ((positions.at(-1) ?? 0) > height - pad) {
    positions[positions.length - 1] = height - pad
    for (let index = positions.length - 2; index >= 0; index -= 1) {
      positions[index] = Math.min(positions[index], positions[index + 1] - gap)
    }
  }
  return new Map(ordered.map((event, index) => [event.id, Math.max(pad, positions[index])]))
}

function minutesLabel(minutes: number): string {
  if (minutes < 60) return `${Math.max(1, Math.round(minutes))} min`
  const hours = Math.floor(minutes / 60)
  const remainder = Math.round(minutes % 60)
  return remainder ? `${hours} h ${remainder} min` : `${hours} h`
}

export function MealDayline({
  date,
  meals,
  entries,
  timeZone,
  fallbackTimes = {},
  compact = false,
  onMealFinishedAt,
  onOpenMeal,
}: {
  date: string
  meals: LoggedMeal[]
  entries: LoggedFoodEntry[]
  timeZone: string
  fallbackTimes?: Record<string, string>
  compact?: boolean
  onMealFinishedAt: (mealId: string, finishedAt: string) => Promise<unknown>
  onOpenMeal?: (meal: LoggedMeal) => void
}) {
  const { language } = useLanguage()
  const copy = COPY[language]
  const [now, setNow] = useState(() => new Date())
  const [editing, setEditing] = useState<string | null>(null)
  const [timeDraft, setTimeDraft] = useState('12:00')
  const [saving, setSaving] = useState(false)
  const [saveError, setSaveError] = useState('')
  const timeInputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    const update = () => setNow(new Date())
    const timer = window.setInterval(update, 30_000)
    document.addEventListener('visibilitychange', update)
    return () => {
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', update)
    }
  }, [])

  useEffect(() => {
    setNow(new Date())
  }, [meals])

  const currentClock = zonedClock(now, timeZone)
  const isLiveDate = currentClock.date === date
  const events = useMemo(() => meals
    .map((meal) => timedMeal(meal, entries, timeZone, fallbackTimes[meal.id] ?? fallbackMealTime(meal)))
    .sort((left, right) => left.lineMinute - right.lineMinute), [entries, fallbackTimes, meals, timeZone])
  const height = Math.max(compact ? 390 : 520, events.length * (compact ? 58 : 64))
  const labels = useMemo(() => labelLayout(events, height, compact), [compact, events, height])
  const nowY = daylineRatio(currentClock.minute) * height
  const liveEvents = isLiveDate
    ? events.filter((event) => event.recorded && Date.parse(event.meal.logged_at) <= now.getTime())
    : []
  const latest = liveEvents
    .slice()
    .sort((left, right) => Date.parse(left.meal.logged_at) - Date.parse(right.meal.logged_at))
    .at(-1) ?? null
  const elapsed = latest ? Math.max(0, (now.getTime() - Date.parse(latest.meal.logged_at)) / 60_000) : null
  const currentZone = latest && elapsed != null ? comfortZone(elapsed, latest.window) : null
  const readyIn = latest && elapsed != null ? Math.max(0, latest.window.readyAfterMinutes - elapsed) : null
  const transitionIn = latest && elapsed != null ? Math.max(0, latest.window.transitionAfterMinutes - elapsed) : null
  const quiet = isQuietClock(currentClock.minute)

  const beginEdit = (event: TimedMeal) => {
    setEditing(event.meal.id)
    setTimeDraft(event.time)
    setSaveError('')
  }

  const saveTime = async () => {
    if (!editing || saving) return
    setSaving(true)
    setSaveError('')
    try {
      const visibleTime = timeInputRef.current?.value || timeDraft
      await onMealFinishedAt(editing, zonedDateTimeToIso(date, visibleTime, timeZone))
      setEditing(null)
    } catch {
      setSaveError(copy.saveFailed)
    } finally {
      setSaving(false)
    }
  }

  const activeEvent = events.find((event) => event.meal.id === editing) ?? null
  const railX = compact ? 52 : 58

  return (
    <GlassCard accent={ACCENTS.emerald} className="overflow-hidden p-0" data-no-translate>
      <div className="relative overflow-hidden bg-[radial-gradient(circle_at_18%_12%,rgba(34,211,238,.14),transparent_34%),radial-gradient(circle_at_85%_26%,rgba(16,185,129,.13),transparent_30%),linear-gradient(145deg,rgba(5,14,24,.985),rgba(8,27,27,.97))] px-3 pt-4 pb-3 text-white sm:px-4">
        <div className="pointer-events-none absolute inset-0 opacity-45 [background-image:linear-gradient(rgba(255,255,255,.025)_1px,transparent_1px)] [background-size:100%_24px]" />
        <div className="relative flex items-start justify-between gap-3 px-1">
          <div>
            <p className="font-mono text-[8px] font-black tracking-[.22em] text-cyan-200/65 uppercase">{copy.eyebrow}</p>
            <h3 className={`mt-1 font-display font-black ${compact ? 'text-lg' : 'text-xl'}`}>{copy.title}</h3>
            {!compact && <p className="mt-1 max-w-lg text-[11px] leading-relaxed text-white/48">{copy.subtitle}</p>}
          </div>
          <div className="shrink-0 rounded-2xl border border-white/8 bg-white/[.055] px-2.5 py-2 text-right">
            <p className="font-mono text-[12px] font-black text-cyan-100">{currentClock.time}</p>
            <p className="mt-0.5 max-w-[8rem] truncate font-mono text-[7px] font-bold tracking-wide text-white/34">{timeZone.replace(/_/g, ' ')}</p>
          </div>
        </div>

        <div className="relative mt-3" style={{ height }}>
          <div
            className="absolute top-0 bottom-0 w-[18px] -translate-x-1/2 rounded-full border border-white/[.055] bg-slate-400/10"
            style={{ left: railX }}
          />
          <div
            className="absolute top-0 bottom-0 w-[5px] -translate-x-1/2 rounded-full"
            style={{
              left: railX,
              background: 'linear-gradient(to bottom,rgba(100,116,139,.52) 0%,rgba(100,116,139,.34) 8.3%,rgba(16,185,129,.78) 14%,rgba(16,185,129,.82) 79%,rgba(100,116,139,.48) 81.25%,rgba(100,116,139,.25) 100%)',
              boxShadow: '0 0 18px rgba(16,185,129,.2)',
            }}
          />

          {TICKS.map((tick) => (
            <div
              key={tick.minute}
              className="pointer-events-none absolute left-0 right-0 -translate-y-1/2"
              style={{ top: `${daylineRatio(tick.minute) * 100}%`, opacity: tick.opacity }}
            >
              <span className="absolute left-0 w-8 text-right font-mono text-[8px] font-black text-white">{tick.label}</span>
              <span className="absolute h-px w-2 bg-white" style={{ left: railX - 4 }} />
            </div>
          ))}

          {latest && (() => {
            const start = daylineRatio(latest.minute) * height
            const transition = daylineRatio(latest.minute + latest.window.transitionAfterMinutes) * height
            const ready = daylineRatio(latest.minute + latest.window.readyAfterMinutes) * height
            const boundedStart = Math.max(0, Math.min(height, start))
            const boundedTransition = Math.max(boundedStart, Math.min(height, transition))
            const boundedReady = Math.max(boundedTransition, Math.min(height, ready))
            return (
              <>
                <motion.div initial={{ scaleY: 0 }} animate={{ scaleY: 1 }} transition={{ duration: 0.55 }} className="absolute z-10 w-[9px] origin-top -translate-x-1/2 rounded-full bg-gradient-to-b from-rose-400 to-amber-400" style={{ left: railX, top: boundedStart, height: boundedTransition - boundedStart, boxShadow: '0 0 18px rgba(251,113,133,.58)' }} />
                <motion.div initial={{ scaleY: 0 }} animate={{ scaleY: 1 }} transition={{ duration: 0.55, delay: 0.08 }} className="absolute z-10 w-[9px] origin-top -translate-x-1/2 rounded-full bg-gradient-to-b from-amber-400 to-emerald-400" style={{ left: railX, top: boundedTransition, height: boundedReady - boundedTransition, boxShadow: '0 0 18px rgba(245,158,11,.42)' }} />
              </>
            )
          })()}

          <svg className="pointer-events-none absolute inset-0 z-10 h-full w-full overflow-visible" aria-hidden>
            {events.map((event) => {
              const actual = daylineRatio(event.minute) * height
              const label = labels.get(event.meal.id) ?? actual
              return <path key={event.meal.id} d={`M ${railX} ${actual} C ${railX + 11} ${actual}, ${railX + 12} ${label}, ${railX + 25} ${label}`} fill="none" stroke={event.recorded ? 'rgba(103,232,249,.48)' : 'rgba(255,255,255,.18)'} strokeWidth="1.5" strokeDasharray={event.recorded ? undefined : '3 4'} />
            })}
          </svg>

          {events.map((event) => {
            const actual = daylineRatio(event.minute) * height
            const label = labels.get(event.meal.id) ?? actual
            return (
              <div key={event.meal.id}>
                <motion.button
                  type="button"
                  initial={{ scale: 0, opacity: 0 }}
                  animate={{ scale: 1, opacity: 1 }}
                  transition={{ duration: 0.36 }}
                  onClick={() => beginEdit(event)}
                  aria-label={`${copy.finished} ${event.meal.display_name} ${event.time}`}
                  className="absolute z-20 h-4 w-4 -translate-x-1/2 -translate-y-1/2 rounded-full border-[3px] border-[#07151c] bg-cyan-200 shadow-[0_0_15px_rgba(103,232,249,.75)]"
                  style={{ left: railX, top: actual }}
                />
                <motion.button
                  type="button"
                  initial={{ opacity: 0, x: 8 }}
                  animate={{ opacity: 1, x: 0 }}
                  onClick={() => beginEdit(event)}
                  onDoubleClick={() => onOpenMeal?.(event.meal)}
                  className="absolute right-0 z-20 -translate-y-1/2 rounded-2xl border border-white/8 bg-white/[.075] px-2.5 py-2 text-left shadow-[0_12px_34px_-22px_rgba(34,211,238,.8)] backdrop-blur-md transition active:scale-[.985]"
                  style={{ left: railX + 27, top: label }}
                >
                  <div className="flex items-center justify-between gap-2">
                    <p className="min-w-0 truncate text-[11px] font-black text-white">{event.meal.display_name}</p>
                    <span className="shrink-0 font-mono text-[10px] font-black text-cyan-100">{event.time}</span>
                  </div>
                  <div className="mt-0.5 flex items-center justify-between gap-2">
                    <span className="truncate text-[8px] font-semibold text-white/36">{Math.round(event.meal.total_kcal)} kcal · {copy[event.window.load]}</span>
                    <span className={`shrink-0 font-mono text-[7px] font-black uppercase ${event.recorded ? 'text-emerald-200/70' : 'text-white/28'}`}>{event.recorded ? copy.recorded : copy.estimated}</span>
                  </div>
                </motion.button>
              </div>
            )
          })}

          {isLiveDate && (
            <motion.div
              className="pointer-events-none absolute right-0 left-0 z-30 -translate-y-1/2"
              animate={{ top: nowY }}
              transition={{ duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
            >
              <div className="absolute right-0 left-0 top-0 h-px bg-gradient-to-r from-transparent via-white/20 to-transparent" />
              <div
                className="absolute grid h-[22px] w-[22px] -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full border-[5px] border-[#08161d]"
                style={{
                  left: railX,
                  background: quiet ? '#94a3b8' : currentZone ? ZONE_COLOR[currentZone] : '#67e8f9',
                  boxShadow: `0 0 24px ${quiet ? 'rgba(148,163,184,.6)' : currentZone ? ZONE_COLOR[currentZone] : 'rgba(103,232,249,.75)'}`,
                }}
              />
              <span
                className="absolute -translate-x-full -translate-y-1/2 rounded-full bg-white/10 px-1.5 py-1 font-mono text-[7px] font-black tracking-wider whitespace-nowrap text-white/75 backdrop-blur"
                style={{ left: railX - 9 }}
              >
                {copy.now}
              </span>
            </motion.div>
          )}

          {events.length === 0 && (
            <div className="absolute inset-0 grid place-items-center pl-20 pr-5 text-center">
              <p className="max-w-xs text-[11px] leading-relaxed font-semibold text-white/42">{copy.noMeals}</p>
            </div>
          )}
        </div>

        <div className="relative mt-2 rounded-2xl border border-white/8 bg-white/[.055] px-3 py-2.5">
          {latest && currentZone ? (
            <div className="flex items-center gap-2.5">
              <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: ZONE_COLOR[currentZone], boxShadow: `0 0 14px ${ZONE_COLOR[currentZone]}` }} />
              <div className="min-w-0 flex-1">
                <p className="truncate text-[10px] font-black text-white">{copy[currentZone]} · {latest.meal.display_name}</p>
                <p className="mt-0.5 text-[8px] font-semibold text-white/38">
                  {currentZone === 'ready'
                    ? `${copy.ready} ${minuteToClock(latest.minute + latest.window.readyAfterMinutes)}`
                    : currentZone === 'transition'
                      ? `${copy.ready} ${copy.in} ${minutesLabel(readyIn ?? 0)}`
                      : `${copy.transition} ${copy.in} ${minutesLabel(transitionIn ?? 0)} · ${copy.ready} ${minuteToClock(latest.minute + latest.window.readyAfterMinutes)}`}
                </p>
              </div>
            </div>
          ) : (
            <p className="text-[9px] leading-relaxed font-semibold text-white/38">{copy.note}</p>
          )}
        </div>

        <AnimatePresence>
          {activeEvent && (
            <motion.div
              initial={{ opacity: 0, y: 8, height: 0 }}
              animate={{ opacity: 1, y: 0, height: 'auto' }}
              exit={{ opacity: 0, y: 6, height: 0 }}
              className="relative mt-2 overflow-hidden rounded-2xl border border-cyan-200/15 bg-cyan-100/[.075]"
            >
              <div className="flex items-end gap-2 p-3">
                <label className="min-w-0 flex-1">
                  <span className="block truncate text-[9px] font-black text-cyan-100">{copy.finished} · {activeEvent.meal.display_name}</span>
                  <input
                    type="time"
                    ref={timeInputRef}
                    defaultValue={timeDraft}
                    onInput={(event) => setTimeDraft(event.currentTarget.value)}
                    onChange={(event) => setTimeDraft(event.currentTarget.value)}
                    onBlur={(event) => setTimeDraft(event.currentTarget.value)}
                    className="mt-1.5 w-full rounded-xl border border-white/10 bg-[#07151c]/80 px-3 py-2 font-mono text-sm font-black text-white outline-none focus:border-cyan-300/50"
                  />
                </label>
                <button type="button" disabled={saving} onClick={() => void saveTime()} className="min-h-10 shrink-0 rounded-xl bg-gradient-to-r from-cyan-400 to-emerald-400 px-3 text-[10px] font-black text-[#051019] disabled:opacity-50">{saving ? copy.saving : copy.save}</button>
                <button type="button" onClick={() => setEditing(null)} aria-label={copy.close} className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-white/8 font-black text-white/55">×</button>
              </div>
              {saveError && <p className="px-3 pb-3 text-[9px] font-semibold text-rose-300">{saveError}</p>}
            </motion.div>
          )}
        </AnimatePresence>
        {latest && currentZone && (
          <p className="relative mt-2 px-1 text-[7.5px] leading-relaxed font-medium text-white/25">{copy.note}</p>
        )}
      </div>
    </GlassCard>
  )
}
