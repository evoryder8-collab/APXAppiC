/*
 * RPG stat engine. Deterministic daily recompute from the baseline date to
 * today: running it twice always yields the same snapshots (idempotent), and
 * missed days are caught up automatically because the whole history replays.
 * Decay mirrors detraining physiology: aerobic fitness fades in weeks,
 * flexibility follows frequency, strength persists longest.
 */
import { differenceInCalendarDays } from 'date-fns'
import type { AppData, DayType, RpgSnapshot } from './types'
import { computeTargets } from './nutrition'

export interface StatBlock {
  health: number
  joint: number
  flexibility: number
  endurance: number
  strength_upper: number
  strength_lower: number
}

export const BASELINE: StatBlock = {
  health: 60,
  joint: 55,
  flexibility: 40,
  endurance: 45,
  strength_upper: 60, // childhood upper-only training kept the top half ahead
  strength_lower: 42, // legs neglected during growth years, still catching up
}

const FLOORS: StatBlock = {
  health: 40,
  joint: 35,
  flexibility: 28,
  endurance: 30,
  strength_upper: 45,
  strength_lower: 32,
}

/* Half-lives in days for decay toward the floor when a stat starves */
const HALF_LIFE: StatBlock = {
  health: 10,
  joint: 40,
  flexibility: 8.5,
  endurance: 12,
  strength_upper: 31,
  strength_lower: 31,
}

/* Weights for the Overall composite */
const WEIGHTS = { strength: 0.25, endurance: 0.2, flexibility: 0.15, joint: 0.2, health: 0.2 }

export const LEG_XP_BOOST = 1.25 // permanent until the sub-bars converge
const AGE_DRAG_PER_DAY = 0.45 / 365 // standing still slowly costs you
const CONVERGENCE_GAP = 3

export function overallOf(s: StatBlock): number {
  const strength = (s.strength_upper + s.strength_lower) / 2
  return (
    WEIGHTS.strength * strength +
    WEIGHTS.endurance * s.endurance +
    WEIGHTS.flexibility * s.flexibility +
    WEIGHTS.joint * s.joint +
    WEIGHTS.health * s.health
  )
}

function clamp(v: number): number {
  return Math.min(100, Math.max(0, v))
}

function decay(value: number, floor: number, halfLife: number): number {
  return floor + (value - floor) * Math.pow(2, -1 / halfLife)
}

/* Diminishing returns: gains shrink as a stat approaches the ceiling */
function headroom(stat: number): number {
  return Math.max(0.1, 1 - stat / 110)
}

interface DayActivity {
  types: Array<{ type: DayType; quality: number; deload: boolean; recovery: boolean }>
  overrides: number
  overloadUpper: number
  overloadLower: number
  waterL: number | null
  kcal: number | null
  protein: number | null
  streak: number
}

const UPPER_TYPES: DayType[] = ['push', 'pull', 'upper']
const LOWER_TYPES: DayType[] = ['legs_a', 'legs_b']
const FLEX_TYPES: DayType[] = ['mobility', 'fix']

export function computeSnapshots(data: AppData, throughDate: string): RpgSnapshot[] {
  const profile = data.profile
  if (!profile) return []
  const start = profile.baseline_date
  const total = differenceInCalendarDays(
    new Date(throughDate + 'T12:00:00'),
    new Date(start + 'T12:00:00'),
  )
  if (total < 0) return []

  const dayTypeById = new Map(data.program_days.map((d) => [d.id, d.day_type]))
  const targets = computeTargets(profile)

  /* Pre-index activity by date */
  const activity = new Map<string, DayActivity>()
  const getDay = (date: string): DayActivity => {
    let a = activity.get(date)
    if (!a) {
      a = { types: [], overrides: 0, overloadUpper: 0, overloadLower: 0, waterL: null, kcal: null, protein: null, streak: 0 }
      activity.set(date, a)
    }
    return a
  }

  const sessionById = new Map(data.workout_sessions.map((s) => [s.id, s]))
  for (const s of data.workout_sessions) {
    if (!s.completed) continue
    const type = dayTypeById.get(s.program_day_id)
    if (!type) continue
    getDay(s.date).types.push({
      type,
      quality: s.quality_score || 1,
      deload: s.is_deload,
      recovery: s.is_event_recovery,
    })
  }
  for (const log of data.workout_logs) {
    const s = sessionById.get(log.session_id)
    if (!s) continue
    if (log.override_flag) getDay(s.date).overrides += 1
  }
  /* Progressive overload events: top weight for an exercise rises vs previous session */
  const byExercise = new Map<string, Array<{ date: string; w: number }>>()
  for (const log of data.workout_logs) {
    if (!log.exercise_id || log.skipped || log.weight_kg == null) continue
    const s = sessionById.get(log.session_id)
    if (!s) continue
    const arr = byExercise.get(log.exercise_id) ?? []
    arr.push({ date: s.date, w: log.weight_kg })
    byExercise.set(log.exercise_id, arr)
  }
  const exerciseDayById = new Map(data.exercises.map((e) => [e.id, e.program_day_id]))
  for (const [exId, arr] of byExercise) {
    const byDate = new Map<string, number>()
    for (const { date, w } of arr) byDate.set(date, Math.max(byDate.get(date) ?? 0, w))
    const dates = [...byDate.keys()].sort()
    for (let i = 1; i < dates.length; i++) {
      if ((byDate.get(dates[i]) ?? 0) > (byDate.get(dates[i - 1]) ?? 0)) {
        const dayId = exerciseDayById.get(exId)
        const type = dayId ? dayTypeById.get(dayId) : undefined
        const a = getDay(dates[i])
        if (type && LOWER_TYPES.includes(type)) a.overloadLower += 1
        else a.overloadUpper += 1
      }
    }
  }
  for (const d of data.daily_logs) {
    const a = getDay(d.date)
    a.waterL = d.water_l
    a.kcal = d.kcal
    a.protein = d.protein_g
  }

  /* Streak per date (consecutive completed days up to and including date) */
  let streak = 0
  for (let i = 0; i <= total; i++) {
    const date = addDaysIso(start, i)
    const a = activity.get(date)
    if (a && a.types.length > 0) streak += 1
    else streak = 0
    if (a) a.streak = streak
  }

  const snapshots: RpgSnapshot[] = []
  let s: StatBlock = { ...BASELINE }

  for (let i = 0; i <= total; i++) {
    const date = addDaysIso(start, i)
    const a = activity.get(date)
    const streakMult = 1 + Math.min(a?.streak ?? 0, 30) * 0.005

    if (i > 0) {
      /* Age drag on the physical stats, every single day */
      s.endurance -= AGE_DRAG_PER_DAY
      s.flexibility -= AGE_DRAG_PER_DAY
      s.strength_upper -= AGE_DRAG_PER_DAY
      s.strength_lower -= AGE_DRAG_PER_DAY

      const fed = {
        endurance: false,
        flexibility: false,
        upper: false,
        lower: false,
        joint: false,
        health: false,
      }

      if (a) {
        for (const t of a.types) {
          const q = Math.max(0, Math.min(1, t.quality)) * streakMult
          if (t.recovery) {
            s.joint += 1.8 * q * headroom(s.joint)
            fed.joint = true
            continue
          }
          if (t.deload) {
            s.joint += 2.5 * q * headroom(s.joint)
            fed.joint = true
          }
          if (t.type === 't25') {
            s.endurance += 3.2 * q * headroom(s.endurance)
            fed.endurance = true
          } else if (FLEX_TYPES.includes(t.type)) {
            s.flexibility += 2.8 * q * headroom(s.flexibility)
            s.joint += 1.4 * q * headroom(s.joint)
            fed.flexibility = true
            fed.joint = true
          } else if (LOWER_TYPES.includes(t.type)) {
            const boost = s.strength_lower < s.strength_upper - CONVERGENCE_GAP ? LEG_XP_BOOST : 1
            s.strength_lower += 2.6 * boost * q * headroom(s.strength_lower)
            fed.lower = true
          } else if (UPPER_TYPES.includes(t.type)) {
            s.strength_upper += 2.0 * q * headroom(s.strength_upper)
            fed.upper = true
          }
        }
        s.strength_upper += a.overloadUpper * 0.7 * headroom(s.strength_upper)
        s.strength_lower += a.overloadLower * 0.7 * LEG_XP_BOOST * headroom(s.strength_lower)
        s.joint -= Math.min(a.overrides, 2) * 1.5

        /* Health feeds on behavior: hydration and hitting the calorie/protein window */
        let healthFed = false
        if (a.waterL != null && a.waterL >= 2.5) {
          s.health += 1.2 * streakMult * headroom(s.health)
          healthFed = true
        }
        if (
          a.kcal != null &&
          a.protein != null &&
          Math.abs(a.kcal - targets.kcal) <= targets.kcal * 0.1 &&
          a.protein >= targets.protein_g * 0.95
        ) {
          s.health += 1.4 * streakMult * headroom(s.health)
          healthFed = true
        }
        fed.health = healthFed
      }

      if (!fed.endurance) s.endurance = decay(s.endurance, FLOORS.endurance, HALF_LIFE.endurance)
      if (!fed.flexibility) s.flexibility = decay(s.flexibility, FLOORS.flexibility, HALF_LIFE.flexibility)
      if (!fed.upper) s.strength_upper = decay(s.strength_upper, FLOORS.strength_upper, HALF_LIFE.strength_upper)
      if (!fed.lower) s.strength_lower = decay(s.strength_lower, FLOORS.strength_lower, HALF_LIFE.strength_lower)
      if (!fed.joint) s.joint = decay(s.joint, FLOORS.joint, HALF_LIFE.joint)
      if (!fed.health) s.health = decay(s.health, FLOORS.health, HALF_LIFE.health)

      s = {
        health: clamp(s.health),
        joint: clamp(s.joint),
        flexibility: clamp(s.flexibility),
        endurance: clamp(s.endurance),
        strength_upper: clamp(s.strength_upper),
        strength_lower: clamp(s.strength_lower),
      }
    }

    snapshots.push({
      id: `snap-${date}`,
      user_id: profile.user_id,
      date,
      overall: round1(overallOf(s)),
      health: round1(s.health),
      joint: round1(s.joint),
      flexibility: round1(s.flexibility),
      endurance: round1(s.endurance),
      strength: round1((s.strength_upper + s.strength_lower) / 2),
      strength_upper: round1(s.strength_upper),
      strength_lower: round1(s.strength_lower),
    })
  }
  return snapshots
}

function round1(v: number): number {
  return Math.round(v * 10) / 10
}

function addDaysIso(startIso: string, days: number): string {
  const d = new Date(startIso + 'T12:00:00')
  d.setDate(d.getDate() + days)
  return d.toISOString().slice(0, 10)
}

/* ---------------- Recommendation engine ---------------- */

export interface StatAdvice {
  stat: string
  statKey: 'endurance' | 'flexibility' | 'strength_lower' | 'strength_upper' | 'joint' | 'health'
  headline: string
  detail: string
  prescription: string
  dayType: DayType | null
  severity: number
}

export function whatYourBodyNeeds(data: AppData, snapshots: RpgSnapshot[]): StatAdvice[] {
  if (snapshots.length === 0) return []
  const now = snapshots[snapshots.length - 1]
  const twoWeeksAgo = snapshots[Math.max(0, snapshots.length - 15)]

  const dayTypeById = new Map(data.program_days.map((d) => [d.id, d.day_type]))
  const lastFed: Record<string, string | null> = { endurance: null, flexibility: null, lower: null, upper: null }
  for (const s of data.workout_sessions) {
    if (!s.completed) continue
    const type = dayTypeById.get(s.program_day_id)
    if (!type) continue
    const key =
      type === 't25' ? 'endurance'
      : FLEX_TYPES.includes(type) ? 'flexibility'
      : LOWER_TYPES.includes(type) ? 'lower'
      : UPPER_TYPES.includes(type) ? 'upper'
      : null
    if (key && (!lastFed[key] || s.date > (lastFed[key] as string))) lastFed[key] = s.date
  }
  const today = snapshots[snapshots.length - 1].date
  const daysSince = (d: string | null): number | null =>
    d == null ? null : differenceInCalendarDays(new Date(today + 'T12:00:00'), new Date(d + 'T12:00:00'))
  const starving = (d: number | null, limit: number): boolean => d == null || d > limit
  const starveScore = (d: number | null): number => (d ?? 20)

  const advices: StatAdvice[] = []
  const trend = (a: number, b: number): number => a - b

  const endTrend = trend(now.endurance, twoWeeksAgo.endurance)
  const endStarve = daysSince(lastFed.endurance)
  if (endTrend < -1 || starving(endStarve, 7)) {
    advices.push({
      stat: 'Endurance & VO2max',
      statKey: 'endurance',
      headline:
        endTrend < -1
          ? `Endurance down ${Math.abs(endTrend).toFixed(1)} points in 2 weeks`
          : endStarve == null
            ? 'No T25 logged yet'
            : `No T25 in ${endStarve} days`,
      detail: 'Aerobic adaptations fade fastest, on a half-life of roughly 12 days without a stimulus.',
      prescription: 'One FocusT25 session restores the trend. Saturday is the slot.',
      dayType: 't25',
      severity: Math.abs(Math.min(endTrend, 0)) + starveScore(endStarve) / 6,
    })
  }
  const flexTrend = trend(now.flexibility, twoWeeksAgo.flexibility)
  const flexStarve = daysSince(lastFed.flexibility)
  if (flexTrend < -1 || starving(flexStarve, 6)) {
    advices.push({
      stat: 'Body Flexibility',
      statKey: 'flexibility',
      headline:
        flexTrend < -1
          ? `Flexibility down ${Math.abs(flexTrend).toFixed(1)} points over 2 weeks`
          : flexStarve == null
            ? 'No mobility work logged yet'
            : `${flexStarve} days since mobility work`,
      detail: 'Tissue adapts to frequency. Missing Mobility Thursdays shows up within a week.',
      prescription: 'Two 10-minute sessions this week restore the trend.',
      dayType: 'mobility',
      severity: Math.abs(Math.min(flexTrend, 0)) + starveScore(flexStarve) / 5,
    })
  }
  if (now.strength_lower < now.strength_upper - CONVERGENCE_GAP) {
    advices.push({
      stat: 'Strength, lower',
      statKey: 'strength_lower',
      headline: `Strength-Lower is your lagging stat (${now.strength_lower.toFixed(0)} vs ${now.strength_upper.toFixed(0)} upper)`,
      detail: 'Leg XP is boosted 1.25x until the sub-bars converge. A skipped day should never be a leg day.',
      prescription: 'Protect Monday and Friday. They close the childhood gap.',
      dayType: 'legs_a',
      severity: (now.strength_upper - now.strength_lower) / 4 + (starving(daysSince(lastFed.lower), 5) ? 2 : 0),
    })
  }
  const jointTrend = trend(now.joint, twoWeeksAgo.joint)
  if (jointTrend < -1.5) {
    advices.push({
      stat: 'Joint Health Balance',
      statKey: 'joint',
      headline: `Joint Health down ${Math.abs(jointTrend).toFixed(1)} points`,
      detail: 'Guardian overrides, skipped deloads and missed mobility all land here. Tendons remodel on a weeks-to-months timescale.',
      prescription: 'Take the next deload seriously and keep face pulls honest.',
      dayType: 'mobility',
      severity: Math.abs(jointTrend),
    })
  }
  const healthTrend = trend(now.health, twoWeeksAgo.health)
  if (healthTrend < -1.5) {
    advices.push({
      stat: 'Health',
      statKey: 'health',
      headline: `Health slipping, ${Math.abs(healthTrend).toFixed(1)} points in 2 weeks`,
      detail: 'Hydration at 2.5-3 L and calories within 10% of goal with protein hit are what feed this stat.',
      prescription: 'Tonight: log the day and drink up. 20 seconds.',
      dayType: null,
      severity: Math.abs(healthTrend),
    })
  }
  const upperStarve = daysSince(lastFed.upper)
  if (starving(upperStarve, 6)) {
    advices.push({
      stat: 'Strength, upper',
      statKey: 'strength_upper',
      headline:
        upperStarve == null
          ? 'No push or pull day logged yet'
          : `${upperStarve} days since a push or pull day`,
      detail: 'Strength persists longest, but it is not immortal. Half-life sits around a month.',
      prescription: 'Any push or pull session this week holds the line.',
      dayType: 'push',
      severity: starveScore(upperStarve) / 4,
    })
  }
  return advices.sort((a, b) => b.severity - a.severity).slice(0, 3)
}
