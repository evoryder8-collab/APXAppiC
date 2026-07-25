import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import type { LoggedFoodEntry, LoggedMeal, MealSlot } from '../../lib/food'
import type { IntroLanguage } from '../../lib/introLanguage'
import { mealRowSwipeOffset, MEAL_ROW_REVEAL_PX } from '../../lib/mealExperience'
import {
  DAYLINE_DURATION_MINUTES,
  DAYLINE_START_MINUTE,
  comfortZone,
  daylineRatio,
  fallbackMealTime,
  isQuietClock,
  mealStartStorageKey,
  minuteToClock,
  normalizeMealTimelineSnap,
  resolvePostWorkoutNutrition,
  snapDaylineMinute,
  timedMeal,
  timedWorkout,
  zonedClock,
  zonedDateTimeToIso,
  type MealComfortWindow,
  type MealComfortZone,
  type MealStartLog,
  type MealTimelineSnapMinutes,
  type RecoveryNutritionLog,
} from '../../lib/mealTiming'
import type { WorkoutSession } from '../../lib/types'
import { useLanguage } from '../../lib/i18n'
import { ACCENTS } from '../../lib/theme'
import { GlassCard } from '../ui'

export interface MealDaylineSlot {
  id: string
  label: string
  time: string
  slot: MealSlot
  mealId: string | null
}

interface DaylineMealItem {
  key: string
  label: string
  time: string
  minute: number
  lineMinute: number
  recorded: boolean
  timingSource: 'recorded_start' | 'recorded_finish' | 'scheduled'
  startedAt: string | null
  comfortMinute: number
  meal: LoggedMeal | null
  slot: MealDaylineSlot | null
  window: MealComfortWindow | null
}

const COPY = {
  en: {
    eyebrow: 'LIVE METABOLIC DAYLINE',
    title: 'Eat. Settle. Move. Recover.',
    subtitle: 'Meals, training and recovery timing in one place.',
    finished: 'Meal finished',
    started: 'Eating started',
    setStart: 'Set start',
    editStart: 'Edit start time',
    saveMealStart: 'Save start',
    dragHint: 'Hold and move',
    snap: 'snap',
    finishOnly: 'finish recorded',
    recorded: 'recorded',
    estimated: 'scheduled',
    save: 'Save time',
    saving: 'Saving',
    saveFailed: 'This time could not be saved. Please try again.',
    close: 'Close',
    settling: 'Settling',
    transition: 'Tradeoff window',
    ready: 'Comfort window',
    in: 'in',
    now: 'NOW',
    noMeals: 'Tap the dayline to add a meal at any time.',
    note: 'Comfort estimate only. Workout intensity, meal composition and personal tolerance still matter.',
    light: 'light',
    standard: 'standard',
    substantial: 'substantial',
    large: 'large',
    addMeal: 'Add meal',
    delete: 'Delete',
    workoutDone: 'Workout completed',
    recoveryWindow: 'RECOVERY NUTRITION',
    recoveryOpen: 'Protein opportunity is open',
    recoveryBody: 'Aim for 20 to 40 g of high-quality protein within two hours. Add carbohydrate based on session load and today’s target.',
    recoveryFast: 'If another hard session starts within four hours, prioritize faster carbohydrate replacement.',
    recoveryNoCliff: 'This is a broad recovery window, not a minute-by-minute anabolic cliff.',
    recordStart: 'Eating started',
    saveStart: 'Save start',
    startError: 'Choose a time at or after the workout finished.',
    loggedGap: 'after training',
    score: 'timing signal',
    inferred: 'Estimated from meal finish. Record the eating start for an exact signal.',
    logRecoveryMeal: 'Add post-workout meal',
    remaining: 'left in the high-value window',
    complete: 'The broad two-hour window has passed. Recovery still depends most on the full day.',
  },
  ro: {
    eyebrow: 'CRONOLOGIE METABOLICĂ LIVE',
    title: 'Mănâncă. Așteaptă. Mișcă-te. Recuperează.',
    subtitle: 'Mesele, antrenamentul și recuperarea într-un singur loc.',
    finished: 'Masa s-a încheiat',
    started: 'Ai început să mănânci',
    setStart: 'Începe masa',
    editStart: 'Editează ora de început',
    saveMealStart: 'Salvează începutul',
    dragHint: 'Ține apăsat și mută',
    snap: 'pas',
    finishOnly: 'final înregistrat',
    recorded: 'înregistrată',
    estimated: 'programată',
    save: 'Salvează ora',
    saving: 'Se salvează',
    saveFailed: 'Ora nu a putut fi salvată. Încearcă din nou.',
    close: 'Închide',
    settling: 'Digestie în curs',
    transition: 'Fereastră de compromis',
    ready: 'Fereastră confortabilă',
    in: 'în',
    now: 'ACUM',
    noMeals: 'Atinge cronologia pentru a adăuga o masă la orice oră.',
    note: 'Doar estimare de confort. Intensitatea, compoziția mesei și toleranța personală contează.',
    light: 'ușoară',
    standard: 'standard',
    substantial: 'consistentă',
    large: 'mare',
    addMeal: 'Adaugă o masă',
    delete: 'Șterge',
    workoutDone: 'Antrenament finalizat',
    recoveryWindow: 'NUTRIȚIE PENTRU RECUPERARE',
    recoveryOpen: 'Fereastra pentru proteine este deschisă',
    recoveryBody: 'Țintește 20 până la 40 g de proteine de calitate în două ore. Adaugă carbohidrați după efort și obiectivul zilei.',
    recoveryFast: 'Dacă urmează alt antrenament greu în mai puțin de patru ore, prioritizează refacerea rapidă a carbohidraților.',
    recoveryNoCliff: 'Este o fereastră largă de recuperare, nu un prag anabolic de la minut la minut.',
    recordStart: 'Ai început să mănânci',
    saveStart: 'Salvează începutul',
    startError: 'Alege o oră egală sau ulterioară finalului antrenamentului.',
    loggedGap: 'după antrenament',
    score: 'semnal temporal',
    inferred: 'Estimat din ora de final a mesei. Înregistrează începutul pentru un semnal exact.',
    logRecoveryMeal: 'Adaugă masa de după antrenament',
    remaining: 'rămase în fereastra principală',
    complete: 'Fereastra largă de două ore a trecut. Recuperarea depinde în continuare mai ales de întreaga zi.',
  },
  th: {
    eyebrow: 'ไทม์ไลน์เมตาบอลิซึมแบบสด',
    title: 'กิน พักย่อย ฝึก และฟื้นตัว',
    subtitle: 'มื้ออาหาร การฝึก และเวลาฟื้นตัวอยู่ในที่เดียว',
    finished: 'กินมื้อเสร็จ',
    started: 'เริ่มกิน',
    setStart: 'ตั้งเวลาเริ่ม',
    editStart: 'แก้ไขเวลาเริ่มกิน',
    saveMealStart: 'บันทึกเวลาเริ่ม',
    dragHint: 'แตะค้างแล้วเลื่อน',
    snap: 'ช่วง',
    finishOnly: 'บันทึกเวลาจบแล้ว',
    recorded: 'บันทึกแล้ว',
    estimated: 'ตามกำหนด',
    save: 'บันทึกเวลา',
    saving: 'กำลังบันทึก',
    saveFailed: 'บันทึกเวลาไม่ได้ โปรดลองอีกครั้ง',
    close: 'ปิด',
    settling: 'กำลังย่อย',
    transition: 'ช่วงประนีประนอม',
    ready: 'ช่วงที่สบายขึ้น',
    in: 'ในอีก',
    now: 'ตอนนี้',
    noMeals: 'แตะไทม์ไลน์เพื่อเพิ่มมื้ออาหารในเวลาที่ต้องการ',
    note: 'เป็นเพียงการประเมินความสบาย ความหนักของการฝึก องค์ประกอบอาหาร และความทนของแต่ละคนยังมีผล',
    light: 'เบา',
    standard: 'ปกติ',
    substantial: 'มื้อหนัก',
    large: 'มื้อใหญ่มาก',
    addMeal: 'เพิ่มมื้ออาหาร',
    delete: 'ลบ',
    workoutDone: 'ฝึกเสร็จแล้ว',
    recoveryWindow: 'โภชนาการเพื่อการฟื้นตัว',
    recoveryOpen: 'ช่วงรับโปรตีนกำลังเปิดอยู่',
    recoveryBody: 'รับโปรตีนคุณภาพ 20 ถึง 40 กรัมภายในสองชั่วโมง และเติมคาร์โบไฮเดรตตามความหนักของการฝึกและเป้าหมายวันนี้',
    recoveryFast: 'หากมีการฝึกหนักอีกครั้งภายในสี่ชั่วโมง ให้เน้นเติมคาร์โบไฮเดรตเร็วขึ้น',
    recoveryNoCliff: 'นี่เป็นช่วงฟื้นตัวที่กว้าง ไม่ใช่เส้นตายรายนาที',
    recordStart: 'เริ่มกินเวลา',
    saveStart: 'บันทึกเวลาเริ่ม',
    startError: 'เลือกเวลาที่ตรงกับหรือหลังจากการฝึกเสร็จ',
    loggedGap: 'หลังฝึก',
    score: 'สัญญาณเวลา',
    inferred: 'ประเมินจากเวลาที่กินเสร็จ บันทึกเวลาเริ่มกินเพื่อให้แม่นยำ',
    logRecoveryMeal: 'เพิ่มมื้อหลังฝึก',
    remaining: 'ที่เหลือในช่วงสำคัญ',
    complete: 'ช่วงกว้างสองชั่วโมงผ่านไปแล้ว การฟื้นตัวยังขึ้นกับอาหารตลอดทั้งวันเป็นหลัก',
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

const EMPTY_FALLBACK_TIMES: Record<string, string> = {}
const EMPTY_DAYLINE_SLOTS: MealDaylineSlot[] = []
const EMPTY_WORKOUT_SESSIONS: WorkoutSession[] = []
const EMPTY_RECOVERY_NUTRITION: Record<string, RecoveryNutritionLog> = {}
const EMPTY_MEAL_START_TIMES: Record<string, MealStartLog> = {}

function labelLayout(items: DaylineMealItem[], height: number, compact: boolean): Map<string, number> {
  const pad = compact ? 30 : 34
  const gap = compact ? 64 : 70
  const ordered = items
    .map((item) => ({ key: item.key, actual: daylineRatio(item.minute) * height }))
    .sort((left, right) => left.actual - right.actual)
  if (!ordered.length) return new Map()
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
  return new Map(ordered.map((event, index) => [event.key, Math.max(pad, positions[index])]))
}

function minutesLabel(minutes: number): string {
  if (minutes < 60) return `${Math.max(1, Math.round(minutes))} min`
  const hours = Math.floor(minutes / 60)
  const remainder = Math.round(minutes % 60)
  return remainder ? `${hours} h ${remainder} min` : `${hours} h`
}

function clockMinute(value: string): number {
  const [hours, minutes] = value.split(':').map(Number)
  return Math.max(0, Math.min(1439, hours * 60 + minutes))
}

function TimelineSwipeCard({
  id,
  open,
  onOpenChange,
  onActivate,
  onDelete,
  onLongPressMove,
  onLongPressEnd,
  onLongPressCancel,
  deleteLabel,
  children,
}: {
  id: string
  open: boolean
  onOpenChange: (id: string | null) => void
  onActivate: () => void
  onDelete: () => Promise<void>
  onLongPressMove?: (clientY: number) => void
  onLongPressEnd?: (clientY: number) => void
  onLongPressCancel?: () => void
  deleteLabel: string
  children: ReactNode
}) {
  const start = useRef<{ x: number; y: number } | null>(null)
  const latestTouch = useRef<{ x: number; y: number } | null>(null)
  const holdTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const repositioning = useRef(false)
  const [drag, setDrag] = useState<number | null>(null)
  const suppressClick = useRef(false)
  const settled = open ? -MEAL_ROW_REVEAL_PX : 0

  const clearHold = () => {
    if (holdTimer.current) clearTimeout(holdTimer.current)
    holdTimer.current = null
  }

  useEffect(() => () => clearHold(), [])

  return (
    <div
      data-dayline-card
      data-simple-local-gesture
      data-nutrition-local-gesture
      className="relative overflow-hidden rounded-2xl [touch-action:pan-y]"
      onTouchStart={(event) => {
        event.stopPropagation()
        const touch = event.touches[0]
        start.current = touch ? { x: touch.clientX, y: touch.clientY } : null
        latestTouch.current = start.current
        repositioning.current = false
        setDrag(null)
        clearHold()
        if (touch && onLongPressMove && onLongPressEnd) {
          holdTimer.current = setTimeout(() => {
            const point = latestTouch.current
            if (!point) return
            repositioning.current = true
            suppressClick.current = true
            onOpenChange(null)
            onLongPressMove(point.y)
            navigator.vibrate?.(12)
          }, 460)
        }
      }}
      onTouchMove={(event) => {
        event.stopPropagation()
        const touch = event.touches[0]
        if (!touch || !start.current) return
        latestTouch.current = { x: touch.clientX, y: touch.clientY }
        if (repositioning.current) {
          event.preventDefault()
          onLongPressMove?.(touch.clientY)
          return
        }
        const dx = touch.clientX - start.current.x
        const dy = touch.clientY - start.current.y
        if (Math.hypot(dx, dy) > 9) clearHold()
        if (Math.abs(dx) <= Math.abs(dy) * 1.15) return
        suppressClick.current = true
        event.preventDefault()
        setDrag(Math.max(-MEAL_ROW_REVEAL_PX, Math.min(0, settled + dx)))
      }}
      onTouchEnd={(event) => {
        event.stopPropagation()
        const tracked = start.current
        const touch = event.changedTouches[0]
        const wasRepositioning = repositioning.current
        clearHold()
        start.current = null
        latestTouch.current = null
        repositioning.current = false
        setDrag(null)
        if (!tracked || !touch) return
        if (wasRepositioning) {
          onLongPressEnd?.(touch.clientY)
          return
        }
        const next = mealRowSwipeOffset(tracked, { x: touch.clientX, y: touch.clientY }, open)
        onOpenChange(next < 0 ? id : null)
      }}
      onTouchCancel={(event) => {
        event.stopPropagation()
        clearHold()
        if (repositioning.current) onLongPressCancel?.()
        start.current = null
        latestTouch.current = null
        repositioning.current = false
        setDrag(null)
      }}
    >
      <button
        type="button"
        tabIndex={open ? 0 : -1}
        aria-hidden={!open}
        aria-label={deleteLabel}
        onClick={(event) => {
          event.stopPropagation()
          void onDelete().finally(() => onOpenChange(null))
        }}
        className="absolute inset-y-0 right-0 flex w-[104px] flex-col items-center justify-center bg-rose-600 text-white transition-opacity"
        style={{ opacity: open || (drag ?? 0) < -1 ? 1 : 0 }}
      >
        <span className="grid h-8 w-8 place-items-center rounded-full bg-white/15 text-lg font-black">×</span>
        <span className="mt-1 text-[8px] font-black tracking-wide uppercase">{deleteLabel}</span>
      </button>
      <div
        role="button"
        tabIndex={0}
        onClick={(event) => {
          event.stopPropagation()
          if (suppressClick.current) {
            suppressClick.current = false
            return
          }
          if (open) onOpenChange(null)
          else onActivate()
        }}
        onKeyDown={(event) => {
          if (event.key !== 'Enter' && event.key !== ' ') return
          event.preventDefault()
          if (open) onOpenChange(null)
          else onActivate()
        }}
        className="relative w-full text-left transition-transform duration-200 ease-out"
        style={{ transform: `translate3d(${drag ?? settled}px,0,0)` }}
      >
        {children}
      </div>
    </div>
  )
}

export function MealDayline({
  date,
  meals,
  entries,
  timeZone,
  fallbackTimes = EMPTY_FALLBACK_TIMES,
  compact = false,
  slots = EMPTY_DAYLINE_SLOTS,
  sessions = EMPTY_WORKOUT_SESSIONS,
  recoveryNutrition = EMPTY_RECOVERY_NUTRITION,
  mealStartTimes = EMPTY_MEAL_START_TIMES,
  snapMinutes = 30,
  onMealFinishedAt,
  onMealStartedAt,
  onSlotTimeChanged,
  onOpenMeal,
  onOpenSlot,
  onAddAtTime,
  onDeleteMeal,
  onRecoveryMealStarted,
  onOpenRecoveryMeal,
}: {
  date: string
  meals: LoggedMeal[]
  entries: LoggedFoodEntry[]
  timeZone: string
  fallbackTimes?: Record<string, string>
  compact?: boolean
  slots?: MealDaylineSlot[]
  sessions?: WorkoutSession[]
  recoveryNutrition?: Readonly<Record<string, RecoveryNutritionLog>>
  mealStartTimes?: Readonly<Record<string, MealStartLog>>
  snapMinutes?: MealTimelineSnapMinutes
  onMealFinishedAt?: (mealId: string, finishedAt: string) => Promise<unknown>
  onMealStartedAt?: (meal: LoggedMeal, startedAt: string) => Promise<void> | void
  onSlotTimeChanged?: (slotId: string, time: string) => Promise<void> | void
  onOpenMeal?: (meal: LoggedMeal) => void
  onOpenSlot?: (slot: MealDaylineSlot) => void
  onAddAtTime?: (time: string) => void
  onDeleteMeal?: (meal: LoggedMeal) => Promise<void>
  onRecoveryMealStarted?: (sessionId: string, startedAt: string, mealId: string | null) => Promise<void> | void
  onOpenRecoveryMeal?: () => void
}) {
  const { language } = useLanguage()
  const copy = COPY[language]
  const [now, setNow] = useState(() => new Date())
  const [editing, setEditing] = useState<string | null>(null)
  const [editingStart, setEditingStart] = useState<string | null>(null)
  const [timeDraft, setTimeDraft] = useState('12:00')
  const [startDraft, setStartDraft] = useState('12:00')
  const [saving, setSaving] = useState(false)
  const [saveError, setSaveError] = useState('')
  const [revealedMeal, setRevealedMeal] = useState<string | null>(null)
  const [addTime, setAddTime] = useState<string | null>(null)
  const [addPinned, setAddPinned] = useState(false)
  const [recoveryDraft, setRecoveryDraft] = useState('')
  const [recoveryError, setRecoveryError] = useState('')
  const [dragPreview, setDragPreview] = useState<{ id: string; minute: number; time: string } | null>(null)
  const timelineRef = useRef<HTMLDivElement>(null)
  const timeInputRef = useRef<HTMLInputElement>(null)
  const startInputRef = useRef<HTMLInputElement>(null)

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
  }, [meals, sessions])

  const currentClock = zonedClock(now, timeZone)
  const isLiveDate = currentClock.date === date
  const items = useMemo(() => {
    const byId = new Map(meals.map((meal) => [meal.id, meal]))
    const used = new Set<string>()
    const configured: DaylineMealItem[] = slots.map((slot) => {
      const meal = slot.mealId ? byId.get(slot.mealId) ?? null : null
      if (meal) used.add(meal.id)
      if (meal) {
        const event = timedMeal(
          meal,
          entries,
          timeZone,
          slot.time,
          mealStartTimes[mealStartStorageKey(meal)] ?? mealStartTimes[meal.id],
        )
        return {
          key: `slot:${slot.id}`,
          label: slot.label,
          time: event.time,
          minute: event.minute,
          lineMinute: event.lineMinute,
          recorded: event.recorded,
          timingSource: event.timingSource,
          startedAt: event.startedAt,
          comfortMinute: event.comfortMinute,
          meal,
          slot,
          window: event.window,
        }
      }
      const minute = clockMinute(slot.time)
      return {
        key: `slot:${slot.id}`,
        label: slot.label,
        time: slot.time,
        minute,
        lineMinute: minute < DAYLINE_START_MINUTE ? minute + 1440 : minute,
        recorded: false,
        timingSource: 'scheduled' as const,
        startedAt: null,
        comfortMinute: minute,
        meal: null,
        slot,
        window: null,
      }
    })
    const extras: DaylineMealItem[] = meals.filter((meal) => !used.has(meal.id)).map((meal) => {
      const event = timedMeal(
        meal,
        entries,
        timeZone,
        fallbackTimes[meal.id] ?? fallbackMealTime(meal),
        mealStartTimes[mealStartStorageKey(meal)] ?? mealStartTimes[meal.id],
      )
      return {
        key: `meal:${meal.id}`,
        label: meal.display_name,
        time: event.time,
        minute: event.minute,
        lineMinute: event.lineMinute,
        recorded: event.recorded,
        timingSource: event.timingSource,
        startedAt: event.startedAt,
        comfortMinute: event.comfortMinute,
        meal,
        slot: null,
        window: event.window,
      }
    })
    return [...configured, ...extras].sort((left, right) => left.lineMinute - right.lineMinute)
  }, [entries, fallbackTimes, mealStartTimes, meals, slots, timeZone])

  const displayItems = useMemo(() => items.map((item) => {
    if (!dragPreview || dragPreview.id !== item.key) return item
    return {
      ...item,
      time: dragPreview.time,
      minute: ((dragPreview.minute % 1440) + 1440) % 1440,
      lineMinute: dragPreview.minute,
      recorded: Boolean(item.meal),
      timingSource: item.meal ? 'recorded_start' as const : 'scheduled' as const,
    }
  }), [dragPreview, items])

  const height = Math.max(compact ? 440 : 560, displayItems.length * (compact ? 68 : 74))
  const labels = useMemo(() => labelLayout(displayItems, height, compact), [compact, displayItems, height])
  const nowY = daylineRatio(currentClock.minute) * height
  const recordedEvents = displayItems.filter((item) => item.meal && item.recorded && Date.parse(item.meal.logged_at) <= now.getTime())
  const latest = isLiveDate
    ? recordedEvents.slice().sort((left, right) => Date.parse(left.meal!.logged_at) - Date.parse(right.meal!.logged_at)).at(-1) ?? null
    : null
  const elapsed = latest ? Math.max(0, (now.getTime() - Date.parse(latest.meal!.logged_at)) / 60_000) : null
  const currentZone = latest?.window && elapsed != null ? comfortZone(elapsed, latest.window) : null
  const readyIn = latest?.window && elapsed != null ? Math.max(0, latest.window.readyAfterMinutes - elapsed) : null
  const transitionIn = latest?.window && elapsed != null ? Math.max(0, latest.window.transitionAfterMinutes - elapsed) : null
  const quiet = isQuietClock(currentClock.minute)
  const workouts = useMemo(() => sessions
    .filter((session) => session.date === date)
    .flatMap((session) => {
      const timed = timedWorkout(session, timeZone)
      return timed ? [timed] : []
    })
    .sort((left, right) => left.completedLineMinute - right.completedLineMinute), [date, sessions, timeZone])
  const recoveryRelations = useMemo(() => resolvePostWorkoutNutrition({
    sessions: sessions.filter((session) => session.date === date),
    meals,
    timeZone,
    recoveryNutrition,
    mealStartTimes,
  }), [date, mealStartTimes, meals, recoveryNutrition, sessions, timeZone])
  const latestWorkout = workouts.at(-1) ?? null
  const latestRecovery = latestWorkout
    ? recoveryRelations.find((relation) => relation.sessionId === latestWorkout.session.id) ?? null
    : null
  const recoveryElapsed = latestWorkout && isLiveDate
    ? Math.max(0, (now.getTime() - Date.parse(latestWorkout.session.completed_at!)) / 60_000)
    : null
  const recoveryRemaining = recoveryElapsed == null ? null : Math.max(0, 120 - recoveryElapsed)

  useEffect(() => {
    if (!latestWorkout) {
      setRecoveryDraft('')
      return
    }
    const explicit = recoveryNutrition[latestWorkout.session.id]
    setRecoveryDraft(explicit ? zonedClock(explicit.started_at, timeZone).time : currentClock.time)
  }, [latestWorkout?.session.id, recoveryNutrition, timeZone])

  const beginEdit = (item: DaylineMealItem) => {
    if (!item.meal || !onMealFinishedAt) return
    setEditing(item.meal.id)
    setEditingStart(null)
    setTimeDraft(zonedClock(item.meal.logged_at, timeZone).time)
    setSaveError('')
  }

  const beginStartEdit = (item: DaylineMealItem) => {
    if (!item.meal || !onMealStartedAt) return
    setEditingStart(item.meal.id)
    setEditing(null)
    setStartDraft(item.startedAt ? zonedClock(item.startedAt, timeZone).time : currentClock.time)
    setSaveError('')
  }

  const saveTime = async () => {
    if (!editing || saving || !onMealFinishedAt) return
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

  const saveStartTime = async () => {
    if (!editingStart || saving || !onMealStartedAt) return
    setSaving(true)
    setSaveError('')
    try {
      const meal = items.find((item) => item.meal?.id === editingStart)?.meal
      if (!meal) throw new Error('Meal unavailable')
      const visibleTime = startInputRef.current?.value || startDraft
      await onMealStartedAt(meal, zonedDateTimeToIso(date, visibleTime, timeZone))
      setEditingStart(null)
    } catch {
      setSaveError(copy.saveFailed)
    } finally {
      setSaving(false)
    }
  }

  const saveRecoveryStart = async () => {
    if (!latestWorkout || !recoveryDraft || !onRecoveryMealStarted) return
    const startedAt = zonedDateTimeToIso(date, recoveryDraft, timeZone)
    if (Date.parse(startedAt) < Date.parse(latestWorkout.session.completed_at!) - 60_000) {
      setRecoveryError(copy.startError)
      return
    }
    setRecoveryError('')
    setSaving(true)
    try {
      await onRecoveryMealStarted(latestWorkout.session.id, startedAt, latestRecovery?.mealId ?? null)
    } catch {
      setRecoveryError(copy.saveFailed)
    } finally {
      setSaving(false)
    }
  }

  const activeEvent = items.find((item) => item.meal?.id === editing) ?? null
  const activeStartEvent = items.find((item) => item.meal?.id === editingStart) ?? null
  const railX = compact ? 52 : 58
  const addMinute = addTime ? clockMinute(addTime) : null
  const resolvedSnap = normalizeMealTimelineSnap(snapMinutes)

  const positionFromPointer = (clientY: number, bounds: DOMRect): string => {
    const ratio = Math.max(0, Math.min(1, (clientY - bounds.top) / Math.max(1, bounds.height)))
    return minuteToClock(DAYLINE_START_MINUTE + ratio * DAYLINE_DURATION_MINUTES)
  }

  const snappedPositionFromPointer = (clientY: number): { minute: number; time: string } | null => {
    const bounds = timelineRef.current?.getBoundingClientRect()
    if (!bounds) return null
    const ratio = Math.max(0, Math.min(1, (clientY - bounds.top) / Math.max(1, bounds.height)))
    const minute = snapDaylineMinute(
      DAYLINE_START_MINUTE + ratio * DAYLINE_DURATION_MINUTES,
      resolvedSnap,
    )
    return { minute, time: minuteToClock(minute) }
  }

  const previewReposition = (item: DaylineMealItem, clientY: number) => {
    const next = snappedPositionFromPointer(clientY)
    if (!next) return
    setDragPreview({ id: item.key, ...next })
  }

  const commitReposition = async (item: DaylineMealItem, clientY: number) => {
    const next = snappedPositionFromPointer(clientY)
    setDragPreview(next ? { id: item.key, ...next } : null)
    try {
      if (!next) return
      if (item.meal && onMealStartedAt) {
        await onMealStartedAt(item.meal, zonedDateTimeToIso(date, next.time, timeZone))
      } else if (item.slot && onSlotTimeChanged) {
        await onSlotTimeChanged(item.slot.id, next.time)
      }
    } catch {
      setSaveError(copy.saveFailed)
    } finally {
      setDragPreview(null)
    }
  }

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

        <div
          ref={timelineRef}
          className="relative mt-3"
          style={{ height }}
          onPointerMove={(event) => {
            if (!onAddAtTime || event.pointerType !== 'mouse') return
            if ((event.target as HTMLElement).closest('[data-dayline-card]')) return
            setAddPinned(false)
            setAddTime(positionFromPointer(event.clientY, event.currentTarget.getBoundingClientRect()))
          }}
          onPointerLeave={() => {
            if (!addPinned) setAddTime(null)
          }}
          onPointerUp={(event) => {
            if (!onAddAtTime || event.pointerType === 'mouse') return
            if ((event.target as HTMLElement).closest('[data-dayline-card]')) return
            setAddPinned(true)
            setAddTime(positionFromPointer(event.clientY, event.currentTarget.getBoundingClientRect()))
          }}
        >
          <div className="absolute top-0 bottom-0 w-[18px] -translate-x-1/2 rounded-full border border-white/[.055] bg-slate-400/10" style={{ left: railX }} />
          <div
            className="absolute top-0 bottom-0 w-[5px] -translate-x-1/2 rounded-full"
            style={{
              left: railX,
              background: 'linear-gradient(to bottom,rgba(100,116,139,.52) 0%,rgba(100,116,139,.34) 8.3%,rgba(16,185,129,.78) 14%,rgba(16,185,129,.82) 79%,rgba(100,116,139,.48) 81.25%,rgba(100,116,139,.25) 100%)',
              boxShadow: '0 0 18px rgba(16,185,129,.2)',
            }}
          />

          {TICKS.map((tick) => (
            <div key={tick.minute} className="pointer-events-none absolute left-0 right-0 -translate-y-1/2" style={{ top: `${daylineRatio(tick.minute) * 100}%`, opacity: tick.opacity }}>
              <span className="absolute left-0 w-8 text-right font-mono text-[8px] font-black text-white">{tick.label}</span>
              <span className="absolute h-px w-2 bg-white" style={{ left: railX - 4 }} />
            </div>
          ))}

          {latest?.window && (() => {
            const start = daylineRatio(latest.comfortMinute) * height
            const transition = daylineRatio(latest.comfortMinute + latest.window.transitionAfterMinutes) * height
            const ready = daylineRatio(latest.comfortMinute + latest.window.readyAfterMinutes) * height
            const boundedStart = Math.max(0, Math.min(height, start))
            const boundedTransition = Math.max(boundedStart, Math.min(height, transition))
            const boundedReady = Math.max(boundedTransition, Math.min(height, ready))
            return (
              <>
                <motion.div initial={{ scaleY: 0 }} animate={{ scaleY: 1 }} className="absolute z-10 w-[9px] origin-top -translate-x-1/2 rounded-full bg-gradient-to-b from-rose-400 to-amber-400" style={{ left: railX, top: boundedStart, height: boundedTransition - boundedStart, boxShadow: '0 0 18px rgba(251,113,133,.58)' }} />
                <motion.div initial={{ scaleY: 0 }} animate={{ scaleY: 1 }} className="absolute z-10 w-[9px] origin-top -translate-x-1/2 rounded-full bg-gradient-to-b from-amber-400 to-emerald-400" style={{ left: railX, top: boundedTransition, height: boundedReady - boundedTransition, boxShadow: '0 0 18px rgba(245,158,11,.42)' }} />
              </>
            )
          })()}

          {workouts.map((workout) => {
            const start = daylineRatio(workout.completedMinute) * height
            const end = daylineRatio(workout.completedMinute + 120) * height
            return (
              <div key={workout.session.id}>
                <motion.div initial={{ scaleY: 0 }} animate={{ scaleY: 1 }} className="absolute z-[11] w-[11px] origin-top -translate-x-1/2 rounded-full bg-gradient-to-b from-emerald-300 via-cyan-300 to-cyan-300/15" style={{ left: railX, top: start, height: Math.max(8, Math.min(height, end) - start), boxShadow: '0 0 20px rgba(52,211,153,.72)' }} />
                <div className="pointer-events-none absolute right-1 z-[16] -translate-y-full rounded-full border border-emerald-200/15 bg-[#07151c]/85 px-2 py-1 font-mono text-[7px] font-black text-emerald-200/75 backdrop-blur" style={{ top: start - 4 }}>
                  ✓ {copy.workoutDone} · {workout.completedTime}
                </div>
              </div>
            )
          })}

          <svg className="pointer-events-none absolute inset-0 z-10 h-full w-full overflow-visible" aria-hidden>
            {displayItems.map((item) => {
              const actual = daylineRatio(item.minute) * height
              const label = labels.get(item.key) ?? actual
              return <path key={item.key} d={`M ${railX} ${actual} C ${railX + 11} ${actual}, ${railX + 12} ${label}, ${railX + 25} ${label}`} fill="none" stroke={item.recorded ? 'rgba(103,232,249,.48)' : 'rgba(255,255,255,.18)'} strokeWidth="1.5" strokeDasharray={item.recorded ? undefined : '3 4'} />
            })}
          </svg>

          {displayItems.map((item) => {
            const actual = daylineRatio(item.minute) * height
            const finishActual = daylineRatio(item.comfortMinute) * height
            const label = labels.get(item.key) ?? actual
            const card = (
              <div
                className={`border px-2.5 py-2 ${item.meal ? 'border-white/8' : 'border-dashed border-white/12'}`}
                style={{
                  background: item.meal
                    ? 'linear-gradient(145deg,#183038 0%,#10232a 100%)'
                    : 'linear-gradient(145deg,#10252a 0%,#0c1d23 100%)',
                }}
              >
                <div className="flex items-center justify-between gap-2">
                  <p className="min-w-0 truncate text-[11px] font-black text-white">{item.meal?.display_name ?? item.label}</p>
                  {item.meal && onMealStartedAt ? (
                    <button
                      type="button"
                      data-dayline-time-control
                      onTouchStart={(event) => event.stopPropagation()}
                      onTouchMove={(event) => event.stopPropagation()}
                      onTouchEnd={(event) => event.stopPropagation()}
                      onClick={(event) => {
                        event.stopPropagation()
                        beginStartEdit(item)
                      }}
                      aria-label={`${copy.editStart} ${item.meal.display_name}`}
                      className={`shrink-0 rounded-lg border px-2 py-1 font-mono text-[8px] font-black transition active:scale-95 ${item.startedAt ? 'border-emerald-200/20 bg-emerald-300/12 text-emerald-100' : 'border-cyan-200/18 bg-cyan-300/10 text-cyan-100'}`}
                    >
                      {item.startedAt ? `▶ ${item.time}` : `▶ ${copy.setStart}`}
                    </button>
                  ) : (
                    <span className="shrink-0 font-mono text-[10px] font-black text-cyan-100">{item.time}</span>
                  )}
                </div>
                <div className="mt-0.5 flex items-center justify-between gap-2">
                  <span className="truncate text-[8px] font-semibold text-white/36">{item.meal && item.window ? `${Math.round(item.meal.total_kcal)} kcal · ${copy[item.window.load]}` : copy.addMeal}</span>
                  <span className={`shrink-0 font-mono text-[7px] font-black uppercase ${item.timingSource === 'recorded_start' ? 'text-emerald-200/70' : 'text-white/28'}`}>
                    {item.timingSource === 'recorded_start' ? copy.started : item.timingSource === 'recorded_finish' ? copy.finishOnly : copy.estimated}
                  </span>
                </div>
                {(item.meal ? onMealStartedAt : onSlotTimeChanged) && (
                  <div className="mt-1 flex items-center justify-end gap-1 font-mono text-[6.5px] font-black tracking-wide text-white/25 uppercase">
                    <span aria-hidden>⋮⋮</span>
                    <span>{copy.dragHint} · {resolvedSnap} min {copy.snap}</span>
                  </div>
                )}
              </div>
            )
            return (
              <div key={item.key}>
                {item.meal && onMealFinishedAt ? (
                  <motion.button
                    type="button"
                    initial={{ scale: 0, opacity: 0 }}
                    animate={{ scale: 1, opacity: 1 }}
                    onClick={(event) => {
                      event.stopPropagation()
                      beginEdit(item)
                    }}
                    aria-label={`${copy.finished} ${item.meal.display_name} ${zonedClock(item.meal.logged_at, timeZone).time}`}
                    className="absolute z-20 h-4 w-4 -translate-x-1/2 -translate-y-1/2 rounded-full border-[3px] border-[#07151c] bg-cyan-200 shadow-[0_0_15px_rgba(103,232,249,.75)]"
                    style={{ left: railX, top: finishActual }}
                  />
                ) : (
                  <span className="absolute z-20 grid h-4 w-4 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full border-2 border-[#07151c] bg-white/20 text-[8px] font-black text-white/55" style={{ left: railX, top: actual }}>+</span>
                )}
                <motion.div initial={{ opacity: 0, x: 8 }} animate={{ opacity: 1, x: 0 }} className="absolute right-0 z-20 -translate-y-1/2" style={{ left: railX + 27, top: label }}>
                  {item.meal && onDeleteMeal ? (
                    <TimelineSwipeCard
                      id={item.meal.id}
                      open={revealedMeal === item.meal.id}
                      onOpenChange={setRevealedMeal}
                      deleteLabel={copy.delete}
                      onActivate={() => onOpenMeal ? onOpenMeal(item.meal!) : beginEdit(item)}
                      onDelete={() => onDeleteMeal(item.meal!)}
                      onLongPressMove={onMealStartedAt ? (clientY) => previewReposition(item, clientY) : undefined}
                      onLongPressEnd={onMealStartedAt ? (clientY) => void commitReposition(item, clientY) : undefined}
                      onLongPressCancel={() => setDragPreview(null)}
                    >
                      {card}
                    </TimelineSwipeCard>
                  ) : (
                    <button
                      data-dayline-card
                      data-simple-local-gesture
                      data-nutrition-local-gesture
                      type="button"
                      onClick={(event) => {
                        event.stopPropagation()
                        if (item.meal) {
                          if (onOpenMeal) onOpenMeal(item.meal)
                          else beginEdit(item)
                        } else if (item.slot) onOpenSlot?.(item.slot)
                      }}
                      className="w-full overflow-hidden rounded-2xl text-left shadow-[0_12px_34px_-22px_rgba(34,211,238,.8)] transition active:scale-[.985]"
                    >
                      {card}
                    </button>
                  )}
                </motion.div>
              </div>
            )
          })}

          {isLiveDate && (
            <motion.div className="pointer-events-none absolute right-0 left-0 z-30 -translate-y-1/2" animate={{ top: nowY }} transition={{ duration: 0.7, ease: [0.16, 1, 0.3, 1] }}>
              <div className="absolute right-0 left-0 top-0 h-px bg-gradient-to-r from-transparent via-white/20 to-transparent" />
              <div className="absolute grid h-[22px] w-[22px] -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full border-[5px] border-[#08161d]" style={{ left: railX, background: quiet ? '#94a3b8' : currentZone ? ZONE_COLOR[currentZone] : '#67e8f9', boxShadow: `0 0 24px ${quiet ? 'rgba(148,163,184,.6)' : currentZone ? ZONE_COLOR[currentZone] : 'rgba(103,232,249,.75)'}` }} />
              <span className="absolute -translate-x-full -translate-y-1/2 rounded-full bg-white/10 px-1.5 py-1 font-mono text-[7px] font-black tracking-wider whitespace-nowrap text-white/75 backdrop-blur" style={{ left: railX - 9 }}>{copy.now}</span>
            </motion.div>
          )}

          {addTime && addMinute != null && onAddAtTime && (
            <motion.button
              type="button"
              initial={{ scale: 0, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              onPointerDown={(event) => event.stopPropagation()}
              onPointerUp={(event) => event.stopPropagation()}
              onClick={(event) => {
                event.stopPropagation()
                onAddAtTime(addTime)
                setAddTime(null)
                setAddPinned(false)
              }}
              className="absolute z-40 flex -translate-y-1/2 items-center gap-1.5 rounded-full border border-cyan-100/25 bg-cyan-300 px-2.5 py-1.5 font-mono text-[8px] font-black text-cyan-950 shadow-[0_0_24px_rgba(103,232,249,.75)]"
              style={{ left: railX + 13, top: daylineRatio(addMinute) * height }}
            >
              <span className="text-sm leading-none">+</span>{addTime}
            </motion.button>
          )}

          {displayItems.length === 0 && (
            <div className="pointer-events-none absolute inset-0 grid place-items-center pl-20 pr-5 text-center">
              <p className="max-w-xs text-[11px] leading-relaxed font-semibold text-white/42">{copy.noMeals}</p>
            </div>
          )}
        </div>

        {latestWorkout && (
          <div className="relative mt-2 overflow-hidden rounded-2xl border border-emerald-200/12 bg-emerald-100/[.075] p-3">
            <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_90%_0%,rgba(52,211,153,.16),transparent_46%)]" />
            <div className="relative flex items-start justify-between gap-3">
              <div>
                <p className="font-mono text-[8px] font-black tracking-[.16em] text-emerald-200/65">{copy.recoveryWindow}</p>
                <p className="mt-1 text-[11px] font-black text-white">{copy.recoveryOpen}</p>
                <p className="mt-1 text-[8px] leading-relaxed font-semibold text-white/42">{copy.recoveryBody}</p>
                {recoveryRemaining != null && <p className="mt-1 font-mono text-[8px] font-black text-cyan-200/65">{recoveryRemaining > 0 ? `${minutesLabel(recoveryRemaining)} ${copy.remaining}` : copy.complete}</p>}
              </div>
              {latestRecovery?.timingScore != null && (
                <div className="shrink-0 rounded-xl border border-white/8 bg-white/[.06] px-2.5 py-2 text-center">
                  <p className="font-mono text-xl font-black text-emerald-200">{latestRecovery.timingScore}</p>
                  <p className="font-mono text-[6px] font-black tracking-wide text-white/35 uppercase">{copy.score}</p>
                </div>
              )}
            </div>
            {latestRecovery?.source === 'inferred_finish' && <p className="relative mt-2 text-[8px] font-semibold text-amber-200/55">{copy.inferred}</p>}
            {onRecoveryMealStarted && (
              <div className="relative mt-2 grid grid-cols-[minmax(0,1fr)_auto] gap-2">
                <label>
                  <span className="block text-[8px] font-black text-white/45">{copy.recordStart}</span>
                  <input type="time" value={recoveryDraft} onChange={(event) => setRecoveryDraft(event.target.value)} className="mt-1 w-full rounded-xl border border-white/10 bg-[#07151c]/80 px-3 py-2 font-mono text-sm font-black text-white outline-none focus:border-emerald-300/50" />
                </label>
                <button type="button" disabled={saving} onClick={() => void saveRecoveryStart()} className="mt-[18px] min-h-10 rounded-xl bg-gradient-to-r from-emerald-300 to-cyan-300 px-3 text-[9px] font-black text-[#051019] disabled:opacity-50">{copy.saveStart}</button>
              </div>
            )}
            {latestRecovery?.source === 'recorded_start' && latestRecovery.gapMinutes != null && (
              <p className="relative mt-2 font-mono text-[8px] font-black text-emerald-200/65">{latestRecovery.gapMinutes} min {copy.loggedGap}</p>
            )}
            {recoveryError && <p className="relative mt-2 text-[8px] font-semibold text-rose-300">{recoveryError}</p>}
            <div className="relative mt-2 flex flex-wrap gap-2">
              {onOpenRecoveryMeal && <button type="button" onClick={onOpenRecoveryMeal} className="rounded-xl bg-white/8 px-3 py-2 text-[9px] font-black text-cyan-100">{copy.logRecoveryMeal}</button>}
            </div>
            <p className="relative mt-2 text-[7.5px] leading-relaxed font-medium text-white/25">{copy.recoveryNoCliff} {copy.recoveryFast}</p>
          </div>
        )}

        <div className="relative mt-2 rounded-2xl border border-white/8 bg-white/[.055] px-3 py-2.5">
          {latest && currentZone && latest.window ? (
            <div className="flex items-center gap-2.5">
              <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: ZONE_COLOR[currentZone], boxShadow: `0 0 14px ${ZONE_COLOR[currentZone]}` }} />
              <div className="min-w-0 flex-1">
                <p className="truncate text-[10px] font-black text-white">{copy[currentZone]} · {latest.meal?.display_name}</p>
                <p className="mt-0.5 text-[8px] font-semibold text-white/38">
                  {currentZone === 'ready'
                    ? `${copy.ready} ${minuteToClock(latest.comfortMinute + latest.window.readyAfterMinutes)}`
                    : currentZone === 'transition'
                      ? `${copy.ready} ${copy.in} ${minutesLabel(readyIn ?? 0)}`
                      : `${copy.transition} ${copy.in} ${minutesLabel(transitionIn ?? 0)} · ${copy.ready} ${minuteToClock(latest.comfortMinute + latest.window.readyAfterMinutes)}`}
                </p>
              </div>
            </div>
          ) : (
            <p className="text-[9px] leading-relaxed font-semibold text-white/38">{copy.note}</p>
          )}
        </div>

        <AnimatePresence>
          {activeStartEvent?.meal && (
            <motion.div initial={{ opacity: 0, y: 8, height: 0 }} animate={{ opacity: 1, y: 0, height: 'auto' }} exit={{ opacity: 0, y: 6, height: 0 }} className="relative mt-2 overflow-hidden rounded-2xl border border-emerald-200/15 bg-emerald-100/[.075]">
              <div className="flex items-end gap-2 p-3">
                <label className="min-w-0 flex-1">
                  <span className="block truncate text-[9px] font-black text-emerald-100">{copy.started} · {activeStartEvent.meal.display_name}</span>
                  <input
                    type="time"
                    ref={startInputRef}
                    value={startDraft}
                    onChange={(event) => setStartDraft(event.target.value)}
                    className="mt-1.5 w-full rounded-xl border border-white/10 bg-[#07151c]/80 px-3 py-2 font-mono text-sm font-black text-white outline-none focus:border-emerald-300/50"
                  />
                </label>
                <button type="button" disabled={saving} onClick={() => void saveStartTime()} className="min-h-10 shrink-0 rounded-xl bg-gradient-to-r from-emerald-300 to-cyan-300 px-3 text-[10px] font-black text-[#051019] disabled:opacity-50">{saving ? copy.saving : copy.saveMealStart}</button>
                <button type="button" onClick={() => setEditingStart(null)} aria-label={copy.close} className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-white/8 font-black text-white/55">×</button>
              </div>
              {saveError && <p className="px-3 pb-3 text-[9px] font-semibold text-rose-300">{saveError}</p>}
            </motion.div>
          )}
        </AnimatePresence>

        <AnimatePresence>
          {activeEvent?.meal && (
            <motion.div initial={{ opacity: 0, y: 8, height: 0 }} animate={{ opacity: 1, y: 0, height: 'auto' }} exit={{ opacity: 0, y: 6, height: 0 }} className="relative mt-2 overflow-hidden rounded-2xl border border-cyan-200/15 bg-cyan-100/[.075]">
              <div className="flex items-end gap-2 p-3">
                <label className="min-w-0 flex-1">
                  <span className="block truncate text-[9px] font-black text-cyan-100">{copy.finished} · {activeEvent.meal.display_name}</span>
                  <input type="time" ref={timeInputRef} defaultValue={timeDraft} onInput={(event) => setTimeDraft(event.currentTarget.value)} onChange={(event) => setTimeDraft(event.currentTarget.value)} className="mt-1.5 w-full rounded-xl border border-white/10 bg-[#07151c]/80 px-3 py-2 font-mono text-sm font-black text-white outline-none focus:border-cyan-300/50" />
                </label>
                <button type="button" disabled={saving} onClick={() => void saveTime()} className="min-h-10 shrink-0 rounded-xl bg-gradient-to-r from-cyan-400 to-emerald-400 px-3 text-[10px] font-black text-[#051019] disabled:opacity-50">{saving ? copy.saving : copy.save}</button>
                <button type="button" onClick={() => setEditing(null)} aria-label={copy.close} className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-white/8 font-black text-white/55">×</button>
              </div>
              {saveError && <p className="px-3 pb-3 text-[9px] font-semibold text-rose-300">{saveError}</p>}
            </motion.div>
          )}
        </AnimatePresence>
        {latest && currentZone && <p className="relative mt-2 px-1 text-[7.5px] leading-relaxed font-medium text-white/25">{copy.note}</p>}
      </div>
    </GlassCard>
  )
}
