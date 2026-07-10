/*
 * RPG stat engine + the interconnection brain. Deterministic daily replay
 * from the baseline date to today: running it twice always yields the same
 * snapshots (idempotent), and missed days catch up automatically.
 *
 * The brain: nutrition, training types and recovery talk to each other.
 *  - Protein at target on a strength day amplifies strength XP (+15%),
 *    a deep calorie deficit dampens it (-15%).
 *  - Hydration at target on a T25 day amplifies endurance XP (+10%).
 *  - Mobility within 48 h of a leg day pays a joint-health synergy bonus.
 *  - Apple Health imports feed stats at reduced credit (unverified plan),
 *    and a measured VO2max anchors the Endurance stat to reality.
 *  - Days without data never punish. Absence is only absence of gain;
 *    decay is the same physiology it always was.
 * Every rule that fires is logged as a SynergyEvent so the Avatar page can
 * show its reasoning in plain language.
 */
import { differenceInCalendarDays } from 'date-fns'
import type { AppData, DayType, Profile, RpgSnapshot } from './types'
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

const JUNE_BASELINE: StatBlock = {
  health: 68,
  joint: 58,
  flexibility: 65,
  endurance: 70,
  strength_upper: 70,
  strength_lower: 78,
}

const MATTHEW_BASELINE: StatBlock = {
  health: 72,
  joint: 65,
  flexibility: 60,
  endurance: 82,
  strength_upper: 72,
  strength_lower: 68,
}

export function baselineForProfile(profile: Profile | null): StatBlock {
  if (profile?.persona === 'june') return { ...JUNE_BASELINE }
  if (profile?.persona === 'matthew') return { ...MATTHEW_BASELINE }
  return { ...BASELINE }
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
const IMPORT_CREDIT = 0.6 // imported workouts: real signal, unverified plan

export type SynergyKind =
  | 'protein_strength'
  | 'deficit_strength'
  | 'hydration_endurance'
  | 'mobility_after_legs'
  | 'vo2_anchor'
  | 'import_feed'
  | 'deload_honored'

export interface SynergyEvent {
  date: string
  kind: SynergyKind
  label: string
}

export interface EngineResult {
  snapshots: RpgSnapshot[]
  synergies: SynergyEvent[]
}

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

/* Map a measured VO2max (mL/kg/min) onto the 0-100 game scale */
export function vo2ToStat(vo2: number): number {
  return Math.min(95, Math.max(20, vo2 * 1.35))
}

interface DayActivity {
  types: Array<{ type: DayType; quality: number; deload: boolean; recovery: boolean }>
  overrides: number
  overloadUpper: number
  overloadLower: number
  waterL: number | null
  kcal: number | null
  protein: number | null
  importStrengthMin: number
  importEnduranceMin: number
  importMobilityMin: number
  vo2: number | null
  streak: number
}

const UPPER_TYPES: DayType[] = ['push', 'pull', 'upper']
const LOWER_TYPES: DayType[] = ['legs_a', 'legs_b']
const FLEX_TYPES: DayType[] = ['mobility', 'fix']

export function computeEngine(data: AppData, throughDate: string): EngineResult {
  const profile = data.profile
  if (!profile) return { snapshots: [], synergies: [] }
  const start = profile.baseline_date
  const total = differenceInCalendarDays(
    new Date(throughDate + 'T12:00:00'),
    new Date(start + 'T12:00:00'),
  )
  if (total < 0) return { snapshots: [], synergies: [] }

  const dayTypeById = new Map(data.program_days.map((d) => [d.id, d.day_type]))
  const targets = computeTargets(profile)

  /* Pre-index activity by date */
  const activity = new Map<string, DayActivity>()
  const getDay = (date: string): DayActivity => {
    let a = activity.get(date)
    if (!a) {
      a = {
        types: [], overrides: 0, overloadUpper: 0, overloadLower: 0,
        waterL: null, kcal: null, protein: null,
        importStrengthMin: 0, importEnduranceMin: 0, importMobilityMin: 0,
        vo2: null, streak: 0,
      }
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
  for (const imp of data.imported_activities) {
    const a = getDay(imp.date)
    if (imp.kind === 'strength') a.importStrengthMin += imp.duration_min
    else if (imp.kind === 'endurance') a.importEnduranceMin += imp.duration_min
    else a.importMobilityMin += imp.duration_min
  }
  for (const m of data.health_metrics) {
    if (m.vo2max != null) getDay(m.date).vo2 = m.vo2max
  }

  /* Streak per date (consecutive days with a completed APEX session) */
  let streak = 0
  for (let i = 0; i <= total; i++) {
    const date = addDaysIso(start, i)
    const a = activity.get(date)
    if (a && a.types.length > 0) streak += 1
    else streak = 0
    if (a) a.streak = streak
  }

  const snapshots: RpgSnapshot[] = []
  const synergies: SynergyEvent[] = []
  let s: StatBlock = baselineForProfile(profile)
  let lastLegsOffset = -99 // day index of the last completed leg session

  /* --- pre-baseline Apple Health history informs the starting point. The 6b
     calibration stays the anchor; measured reality corrects it, and history
     from before the app never decays anything. --- */
  const preVo2 = data.health_metrics
    .filter((m) => m.vo2max != null && m.date < start)
    .sort((a, b) => a.date.localeCompare(b.date))
    .pop()
  if (preVo2?.vo2max != null) {
    const anchor = vo2ToStat(preVo2.vo2max)
    s.endurance += (anchor - s.endurance) * 0.5
    synergies.push({
      date: start,
      kind: 'vo2_anchor',
      label: `Baseline calibrated: VO2max ${preVo2.vo2max.toFixed(1)} from your watch pulled Endurance toward ${anchor.toFixed(0)}`,
    })
  }
  const preWindowStart = addDaysIso(start, -60)
  const preCounts = { strength: 0, endurance: 0, mobility: 0 }
  for (const imp of data.imported_activities) {
    if (imp.date >= preWindowStart && imp.date < start) preCounts[imp.kind] += 1
  }
  if (preCounts.strength + preCounts.endurance + preCounts.mobility > 0) {
    s.strength_upper += Math.min(6, preCounts.strength * 0.5)
    s.endurance += Math.min(6, preCounts.endurance * 0.5)
    s.flexibility += Math.min(6, preCounts.mobility * 0.5)
    synergies.push({
      date: start,
      kind: 'import_feed',
      label: `Baseline credit: ${preCounts.strength + preCounts.endurance + preCounts.mobility} Apple Health workouts in the 60 days before APEX`,
    })
  }
  s = {
    health: clamp(s.health), joint: clamp(s.joint), flexibility: clamp(s.flexibility),
    endurance: clamp(s.endurance), strength_upper: clamp(s.strength_upper), strength_lower: clamp(s.strength_lower),
  }

  for (let i = 0; i <= total; i++) {
    const date = addDaysIso(start, i)
    const a = activity.get(date)
    const streakMult = 1 + Math.min(a?.streak ?? 0, 30) * 0.005

    {
      if (i > 0) {
        /* Age drag on the physical stats, every single day */
        s.endurance -= AGE_DRAG_PER_DAY
        s.flexibility -= AGE_DRAG_PER_DAY
        s.strength_upper -= AGE_DRAG_PER_DAY
        s.strength_lower -= AGE_DRAG_PER_DAY
      }

      const fed = {
        endurance: false, flexibility: false, upper: false, lower: false,
        joint: false, health: false,
      }

      if (a) {
        /* --- the brain: nutrition context for this training day --- */
        const proteinHit = a.protein != null && a.protein >= targets.protein_g * 0.95
        const deepDeficit = a.kcal != null && a.kcal < targets.kcal * 0.85
        const hydrated = a.waterL != null && a.waterL >= 2.5
        const hasStrengthSession = a.types.some(
          (t) => !t.recovery && (UPPER_TYPES.includes(t.type) || LOWER_TYPES.includes(t.type)),
        )
        let strengthMult = 1
        if (hasStrengthSession && proteinHit) {
          strengthMult *= 1.15
          synergies.push({ date, kind: 'protein_strength', label: 'Protein target hit on a strength day. Strength XP +15%' })
        }
        if (hasStrengthSession && deepDeficit) {
          strengthMult *= 0.85
          synergies.push({ date, kind: 'deficit_strength', label: 'Deep calorie deficit under a strength session. XP tempered -15%, recovery costs energy' })
        }

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
            synergies.push({ date, kind: 'deload_honored', label: 'Deload honored. Joint Health banked the recovery' })
          }
          if (t.type === 't25') {
            let m = 1
            if (hydrated) {
              m = 1.1
              synergies.push({ date, kind: 'hydration_endurance', label: 'Hydration at target fueled the T25 engine. Endurance XP +10%' })
            }
            s.endurance += 3.2 * m * q * headroom(s.endurance)
            fed.endurance = true
          } else if (FLEX_TYPES.includes(t.type)) {
            let jm = 1
            if (i - lastLegsOffset <= 2) {
              jm = 1.25
              synergies.push({ date, kind: 'mobility_after_legs', label: 'Mobility within 48 h of a leg day. Joint synergy bonus +25%' })
            }
            s.flexibility += 2.8 * q * headroom(s.flexibility)
            s.joint += 1.4 * jm * q * headroom(s.joint)
            fed.flexibility = true
            fed.joint = true
          } else if (LOWER_TYPES.includes(t.type)) {
            const boost = s.strength_lower < s.strength_upper - CONVERGENCE_GAP ? LEG_XP_BOOST : 1
            s.strength_lower += 2.6 * boost * strengthMult * q * headroom(s.strength_lower)
            fed.lower = true
            lastLegsOffset = i
          } else if (UPPER_TYPES.includes(t.type)) {
            s.strength_upper += 2.0 * strengthMult * q * headroom(s.strength_upper)
            fed.upper = true
          }
        }

        /* --- Apple Health imports feed stats at reduced credit --- */
        if (a.importEnduranceMin >= 8 && !fed.endurance) {
          const scale = Math.min(1.3, a.importEnduranceMin / 30)
          s.endurance += 3.2 * IMPORT_CREDIT * scale * headroom(s.endurance)
          fed.endurance = true
          synergies.push({ date, kind: 'import_feed', label: `Apple Watch cardio (${a.importEnduranceMin} min) fed Endurance` })
        }
        if (a.importStrengthMin >= 8 && !fed.upper) {
          const scale = Math.min(1.3, a.importStrengthMin / 35)
          s.strength_upper += 2.0 * IMPORT_CREDIT * scale * headroom(s.strength_upper)
          fed.upper = true
          synergies.push({ date, kind: 'import_feed', label: `Apple Watch strength work (${a.importStrengthMin} min) fed Strength` })
        }
        if (a.importMobilityMin >= 8 && !fed.flexibility) {
          s.flexibility += 2.8 * IMPORT_CREDIT * headroom(s.flexibility)
          fed.flexibility = true
          synergies.push({ date, kind: 'import_feed', label: `Imported mobility session (${a.importMobilityMin} min) fed Flexibility` })
        }

        s.strength_upper += a.overloadUpper * 0.7 * headroom(s.strength_upper)
        s.strength_lower += a.overloadLower * 0.7 * LEG_XP_BOOST * headroom(s.strength_lower)
        s.joint -= Math.min(a.overrides, 2) * 1.5

        /* Health feeds on behavior: hydration and the calorie/protein window */
        let healthFed = false
        if (hydrated) {
          s.health += 1.2 * streakMult * headroom(s.health)
          healthFed = true
        }
        if (
          a.kcal != null && a.protein != null &&
          Math.abs(a.kcal - targets.kcal) <= targets.kcal * 0.1 &&
          a.protein >= targets.protein_g * 0.95
        ) {
          s.health += 1.4 * streakMult * headroom(s.health)
          healthFed = true
        }
        fed.health = healthFed

        /* --- measured VO2max anchors Endurance to reality --- */
        if (a.vo2 != null) {
          const anchor = vo2ToStat(a.vo2)
          s.endurance += (anchor - s.endurance) * 0.5
          fed.endurance = true
          synergies.push({ date, kind: 'vo2_anchor', label: `VO2max measured at ${a.vo2.toFixed(1)}. Endurance anchored toward ${anchor.toFixed(0)}` })
        }
      }

      if (i > 0) {
        if (!fed.endurance) s.endurance = decay(s.endurance, FLOORS.endurance, HALF_LIFE.endurance)
        if (!fed.flexibility) s.flexibility = decay(s.flexibility, FLOORS.flexibility, HALF_LIFE.flexibility)
        if (!fed.upper) s.strength_upper = decay(s.strength_upper, FLOORS.strength_upper, HALF_LIFE.strength_upper)
        if (!fed.lower) s.strength_lower = decay(s.strength_lower, FLOORS.strength_lower, HALF_LIFE.strength_lower)
        if (!fed.joint) s.joint = decay(s.joint, FLOORS.joint, HALF_LIFE.joint)
        if (!fed.health) s.health = decay(s.health, FLOORS.health, HALF_LIFE.health)
      }

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
  return { snapshots, synergies }
}

/* Back-compat wrapper */
export function computeSnapshots(data: AppData, throughDate: string): RpgSnapshot[] {
  return computeEngine(data, throughDate).snapshots
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
  statKey: 'endurance' | 'flexibility' | 'strength_lower' | 'strength_upper' | 'joint' | 'health' | 'recovery'
  headline: string
  detail: string
  prescription: string
  dayType: DayType | null
  severity: number
}

export function whatYourBodyNeeds(data: AppData, snapshots: RpgSnapshot[]): StatAdvice[] {
  if (snapshots.length === 0) return []
  const now = snapshots[snapshots.length - 1]
  const persona = data.profile?.persona ?? 'constantine'
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
  /* imported activities also count as feeding for advice purposes */
  for (const imp of data.imported_activities) {
    const key = imp.kind === 'strength' ? 'upper' : imp.kind === 'endurance' ? 'endurance' : 'flexibility'
    if (!lastFed[key] || imp.date > (lastFed[key] as string)) lastFed[key] = imp.date
  }

  const today = snapshots[snapshots.length - 1].date
  const daysSince = (d: string | null): number | null =>
    d == null ? null : differenceInCalendarDays(new Date(today + 'T12:00:00'), new Date(d + 'T12:00:00'))
  const starving = (d: number | null, limit: number): boolean => d == null || d > limit
  const starveScore = (d: number | null): number => (d ?? 20)

  const advices: StatAdvice[] = []
  const trend = (a: number, b: number): number => a - b

  /* Recovery flag from resting heart rate (Apple Health) */
  const rhr = data.health_metrics
    .filter((m) => m.resting_hr != null)
    .sort((a, b) => a.date.localeCompare(b.date))
  if (rhr.length >= 10) {
    const recent = rhr.slice(-7)
    const base = rhr.slice(-37, -7)
    if (recent.length >= 3 && base.length >= 10) {
      const avg = (arr: typeof rhr): number => arr.reduce((s2, m) => s2 + (m.resting_hr ?? 0), 0) / arr.length
      const delta = avg(recent) - avg(base)
      if (delta >= 4) {
        advices.push({
          stat: 'Recovery',
          statKey: 'recovery',
          headline: `Resting heart rate up ${delta.toFixed(0)} bpm this week`,
          detail: 'An elevated resting pulse against your own baseline usually means accumulated fatigue, poor sleep or illness brewing.',
          prescription: 'Favor mobility and sleep for 2-3 days. Keep loads honest, skip PR attempts.',
          dayType: 'mobility',
          severity: delta,
        })
      }
    }
  }

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
            ? 'No cardio logged yet'
            : `No cardio in ${endStarve} days`,
      detail: 'Aerobic adaptations fade fastest, on a half-life of roughly 12 days without a stimulus.',
      prescription: persona === 'matthew'
        ? 'Use Tuesday’s controlled SkiErg intervals or Saturday’s team challenge to restore the trend.'
        : persona === 'june'
          ? 'Use a brisk recovery walk or a short, tolerable conditioning block without stealing from glute recovery.'
          : 'One FocusT25 session restores the trend. Saturday is the slot.',
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
      detail: persona === 'june'
        ? 'Tissue adapts to frequency, and massage work adds repeated loading that makes Thursday’s corrective reset valuable.'
        : 'Tissue adapts to frequency. Missing the weekly mobility reset shows up within a week.',
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
      detail: 'Leg XP is boosted 1.25x until the sub-bars converge. Keep lower-body work present without forcing fatigue.',
      prescription: persona === 'matthew'
        ? 'Protect Monday’s weighted squats and Friday’s split squats while keeping every rep clean.'
        : 'Protect Monday and Friday so the lower body can close the gap.',
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

/* ---------------- Written whole-body assessment ---------------- */

export interface BodyAssessment {
  title: string
  summary: string
  confidence: 'Building signal' | 'Moderate signal' | 'Strong signal'
  strengths: string[]
  priorities: string[]
}

type AssessmentStat = 'health' | 'joint' | 'flexibility' | 'endurance' | 'strength'

const ASSESSMENT_LABELS: Record<AssessmentStat, string> = {
  health: 'Health',
  joint: 'Joint health',
  flexibility: 'Flexibility',
  endurance: 'Endurance',
  strength: 'Strength',
}

const LOW_STAT_ACTION: Record<AssessmentStat, string> = {
  health: 'Make hydration, protein and a complete evening log the daily floor; those are the fastest controllable inputs to your Health score.',
  joint: 'Keep the next deload and mobility block intact, and avoid load jumps that require Guardian overrides.',
  flexibility: 'Add two short mobility exposures this week, especially after long work blocks or repetitive positions.',
  endurance: 'Restore one focused cardio session this week and arrive hydrated; endurance is the quickest quality to detrain.',
  strength: 'Protect the next two strength sessions and progress only when the logged reps and RIR support it.',
}

export function assessBodyState(data: AppData, snapshots: RpgSnapshot[]): BodyAssessment | null {
  const profile = data.profile
  const now = snapshots[snapshots.length - 1]
  if (!profile || !now) return null

  const before = snapshots[Math.max(0, snapshots.length - 15)] ?? now
  const overallDelta = now.overall - before.overall
  const stats = (Object.keys(ASSESSMENT_LABELS) as AssessmentStat[])
    .map((key) => ({ key, label: ASSESSMENT_LABELS[key], value: now[key] }))
    .sort((a, b) => b.value - a.value)
  const strongest = stats[0]
  const weakest = stats[stats.length - 1]
  const spread = strongest.value - weakest.value

  const recentStart = addDaysIso(now.date, -13)
  const recentLogs = data.daily_logs.filter((log) => log.date >= recentStart && log.date <= now.date)
  const recentSessions = data.workout_sessions.filter(
    (session) => session.completed && session.date >= recentStart && session.date <= now.date,
  )
  const evidenceDays = new Set<string>()
  for (const log of recentLogs) evidenceDays.add(log.date)
  for (const session of recentSessions) evidenceDays.add(session.date)
  for (const metric of data.health_metrics) {
    if (metric.date >= recentStart && metric.date <= now.date) evidenceDays.add(metric.date)
  }
  for (const activity of data.imported_activities) {
    if (activity.date >= recentStart && activity.date <= now.date) evidenceDays.add(activity.date)
  }
  const confidence: BodyAssessment['confidence'] =
    evidenceDays.size >= 10 ? 'Strong signal' : evidenceDays.size >= 5 ? 'Moderate signal' : 'Building signal'

  const trendSentence =
    overallDelta > 0.4
      ? `Your Overall score has risen ${overallDelta.toFixed(1)} points over the comparison window, so the current direction is productive.`
      : overallDelta < -0.4
        ? `Your Overall score has fallen ${Math.abs(overallDelta).toFixed(1)} points over the comparison window, which points to an underfed training or recovery input.`
        : 'Your Overall score is broadly stable, so the next improvement will come from consistently feeding the weakest quality.'
  const balanceSentence =
    spread <= 8
      ? 'The profile is relatively balanced, with no single quality dramatically behind the rest.'
      : `${weakest.label} is the clearest limiter at ${weakest.value.toFixed(0)}, while ${strongest.label} currently leads at ${strongest.value.toFixed(0)}.`

  const title =
    now.overall >= 75
      ? 'Strong foundation — refine the weak link'
      : now.overall >= 60
        ? 'Solid base with a clear next unlock'
        : now.overall >= 45
          ? 'Rebuilding phase — consistency will compound quickly'
          : 'Foundation phase — make the basics repeatable'

  const strengths: string[] = [
    `${strongest.label} is your strongest current signal at ${strongest.value.toFixed(0)}.`,
  ]
  if (overallDelta > 0.4) strengths.push(`Momentum is positive: Overall +${overallDelta.toFixed(1)}.`)
  if (recentSessions.length > 0) {
    strengths.push(`${recentSessions.length} planned session${recentSessions.length === 1 ? '' : 's'} completed in the last 14 days.`)
  }

  const targets = computeTargets(profile)
  const loggedProteinDays = recentLogs.filter((log) => log.protein_g != null)
  const proteinHitRate = loggedProteinDays.length === 0
    ? null
    : loggedProteinDays.filter((log) => (log.protein_g ?? 0) >= targets.protein_g * 0.95).length / loggedProteinDays.length
  const hydratedDays = recentLogs.filter((log) => log.water_l > 0)
  const hydrationHitRate = hydratedDays.length === 0
    ? null
    : hydratedDays.filter((log) => log.water_l >= targets.water_l * 0.9).length / hydratedDays.length
  if (proteinHitRate != null && proteinHitRate >= 0.7) strengths.push(`Protein was on target on ${Math.round(proteinHitRate * 100)}% of logged days.`)
  if (hydrationHitRate != null && hydrationHitRate >= 0.7) strengths.push(`Hydration was on target on ${Math.round(hydrationHitRate * 100)}% of logged days.`)
  if (strengths.length < 2) {
    const runnerUp = stats[1]
    strengths.push(`${runnerUp.label} is the next strongest quality at ${runnerUp.value.toFixed(0)}, giving you a useful base to build from.`)
  }
  if (strengths.length < 3) {
    strengths.push(
      now.strength_upper > now.strength_lower + CONVERGENCE_GAP
        ? `Upper-body strength has retained a solid base at ${now.strength_upper.toFixed(0)} while the lower body catches up.`
        : 'Upper- and lower-body strength are close enough to progress as one balanced system.',
    )
  }

  const priorities: string[] = [LOW_STAT_ACTION[weakest.key]]
  if (now.strength_lower < now.strength_upper - CONVERGENCE_GAP) {
    priorities.push(`Close the upper/lower strength gap (${now.strength_upper.toFixed(0)} vs ${now.strength_lower.toFixed(0)}) by protecting both weekly lower-body exposures.`)
  }
  if (recentLogs.length < 5) {
    priorities.push('Log at least five of the next seven days; more intake and hydration evidence will make this assessment materially sharper.')
  } else if (hydrationHitRate != null && hydrationHitRate < 0.6) {
    priorities.push(`Hydration reached target on only ${Math.round(hydrationHitRate * 100)}% of logged days. Build a repeatable 2.5–3 L rhythm.`)
  } else if (proteinHitRate != null && proteinHitRate < 0.6) {
    priorities.push(`Protein reached target on only ${Math.round(proteinHitRate * 100)}% of logged days. Distribute it across the target-aligned meals.`)
  }
  if (priorities.length < 2) {
    priorities.push('Keep strength, cardio and mobility exposures present every week so one stat does not improve at the expense of another.')
  }

  return {
    title,
    summary: `${balanceSentence} ${trendSentence}`,
    confidence,
    strengths: strengths.slice(0, 3),
    priorities: priorities.slice(0, 3),
  }
}
