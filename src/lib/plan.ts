/*
 * Plan adjustment engine: takes a calendar date and produces the session the
 * app actually prescribes, after deloads, event tapers, the championship leg
 * rule, return-from-layoff deloads and the Full/Lite toggle.
 */
import { differenceInCalendarDays, getISODay } from 'date-fns'
import type {
  AppData,
  CalendarEvent,
  Exercise,
  ProgramDay,
  ProgramSlug,
} from './types'

export interface PlannedExercise extends Exercise {
  planned_sets: number
  swapped: boolean
}

export interface PlannedDay {
  programDay: ProgramDay | null
  exercises: PlannedExercise[]
  warmup: string
  badges: string[]
  isDeload: boolean
  isEventDay: boolean
  isRecoveryMicro: boolean
  taperFactor: number // 1 = untouched
  legsBlocked: boolean
  layoffDeload: boolean
}

function iso(d: Date): string {
  return d.toISOString().slice(0, 10)
}

function parse(date: string): Date {
  return new Date(date + 'T12:00:00')
}

/* Corrective swap set used when heavy pulling/spinal loading is removed pre-event */
function swapExercises(userId: string, dayId: string): PlannedExercise[] {
  const base = {
    user_id: userId,
    program_day_id: dayId,
    rep_unit: 'reps' as const,
    per_side: false,
    tempo_up_s: 1,
    tempo_down_s: 2,
    tempo_pause_s: 0,
    tempo_note: '',
    increment_kg: 0,
    is_lite: false,
    optional: false,
    swapped: true,
  }
  return [
    { ...base, id: 'swap-1', name: 'Band Pull-Aparts', sets: 3, planned_sets: 3, rep_min: 20, rep_max: 20, rest_sec: 30, notes: 'Taper swap: keeps the mid-back fresh without loading', sort_order: 0 },
    { ...base, id: 'swap-2', name: 'Band Face Pulls (2s hold)', sets: 3, planned_sets: 3, rep_min: 15, rep_max: 20, rest_sec: 30, tempo_pause_s: 2, notes: 'Taper swap', sort_order: 1 },
    { ...base, id: 'swap-3', name: 'Thoracic Extension over chair edge', sets: 1, planned_sets: 1, rep_min: 60, rep_max: 90, rep_unit: 'seconds', rest_sec: 0, notes: 'Taper swap', sort_order: 2 },
  ]
}

/* 5-10 min recovery micro-session shown during event days */
function recoveryMicro(userId: string, dayId: string): PlannedExercise[] {
  const base = {
    user_id: userId,
    program_day_id: dayId,
    per_side: false,
    tempo_up_s: 1,
    tempo_down_s: 2,
    tempo_pause_s: 0,
    tempo_note: '',
    increment_kg: 0,
    is_lite: false,
    optional: false,
    swapped: true,
  }
  return [
    { ...base, id: 'micro-1', name: 'Dead Hangs', sets: 2, planned_sets: 2, rep_min: 0, rep_max: 0, rep_unit: 'max', rest_sec: 45, notes: 'Thoracic decompression after camera hours', sort_order: 0 },
    { ...base, id: 'micro-2', name: 'Couch Stretch', sets: 1, planned_sets: 1, rep_min: 60, rep_max: 90, rep_unit: 'seconds', per_side: true, rest_sec: 0, notes: '', sort_order: 1 },
    { ...base, id: 'micro-3', name: 'Band Pull-Aparts', sets: 3, planned_sets: 3, rep_min: 20, rep_max: 20, rep_unit: 'reps', rest_sec: 30, notes: '', sort_order: 2 },
  ]
}

const HEAVY_PULL_SPINAL = /pull-up|row|rdl|deadlift|squat|leg press|hip thrust|lunge/i

export interface EventContext {
  event: CalendarEvent
  daysUntilStart: number // positive = before event
  daysSinceEnd: number // positive = after event
  isDuring: boolean
}

export function eventContextFor(date: string, events: CalendarEvent[]): EventContext | null {
  const d = parse(date)
  let best: EventContext | null = null
  for (const ev of events) {
    const start = parse(ev.start_date)
    const end = parse(ev.end_date)
    const until = differenceInCalendarDays(start, d)
    const since = differenceInCalendarDays(d, end)
    const ctx: EventContext = {
      event: ev,
      daysUntilStart: until,
      daysSinceEnd: since,
      isDuring: until <= 0 && since <= 0,
    }
    const relevant = ctx.isDuring || (until > 0 && until <= 7) || (since > 0 && since <= 2)
    if (!relevant) continue
    /* prefer during > closest approach > rebound */
    if (
      !best ||
      (ctx.isDuring && !best.isDuring) ||
      (!best.isDuring && Math.abs(until) < Math.abs(best.daysUntilStart))
    ) {
      best = ctx
    }
  }
  return best
}

export function taperFactorFor(daysUntilStart: number): number {
  if (daysUntilStart >= 5 || daysUntilStart < 1) return 1
  if (daysUntilStart >= 3) return 0.75 // day -4, -3
  return 0.5 // day -2, -1
}

/* Gradient position 0..1 for calendar tinting across the 5 approach days */
export function approachRamp(date: string, events: CalendarEvent[]): number | null {
  const ctx = eventContextFor(date, events)
  if (!ctx) return null
  if (ctx.isDuring) return 1
  if (ctx.daysUntilStart >= 1 && ctx.daysUntilStart <= 5) {
    return (5 - ctx.daysUntilStart + 1) / 5
  }
  return null
}

export function lastCompletedSessionDate(data: AppData): string | null {
  let last: string | null = null
  for (const s of data.workout_sessions) {
    if (s.completed && (!last || s.date > last)) last = s.date
  }
  return last
}

/* Return-from-layoff: any gap of 3+ weeks triggers a deload week */
export function layoffActive(data: AppData, date: string): boolean {
  const last = lastCompletedSessionDate(data)
  if (!last) return false
  const gap = differenceInCalendarDays(parse(date), parse(last))
  return gap >= 21
}

export function planForDate(
  data: AppData,
  slug: ProgramSlug,
  date: string,
  lite: boolean,
): PlannedDay {
  const program = data.programs.find((p) => p.slug === slug)
  const weekday = getISODay(parse(date))
  const programDay =
    data.program_days.find((d) => d.program_id === program?.id && d.weekday === weekday) ?? null

  const empty: PlannedDay = {
    programDay,
    exercises: [],
    warmup: '',
    badges: [],
    isDeload: false,
    isEventDay: false,
    isRecoveryMicro: false,
    taperFactor: 1,
    legsBlocked: false,
    layoffDeload: false,
  }
  if (!program || !programDay) return empty

  const userId = program.user_id
  const badges: string[] = []
  let exercises: PlannedExercise[] = data.exercises
    .filter((e) => e.program_day_id === programDay.id && e.is_lite === lite)
    .sort((a, b) => a.sort_order - b.sort_order)
    .map((e) => ({ ...e, planned_sets: e.sets, swapped: false }))

  /* Fall back to full list if a day has no dedicated lite rows */
  if (lite && exercises.length === 0) {
    exercises = data.exercises
      .filter((e) => e.program_day_id === programDay.id && !e.is_lite)
      .sort((a, b) => a.sort_order - b.sort_order)
      .slice(0, 2)
      .map((e) => ({ ...e, planned_sets: e.sets, swapped: false }))
    badges.push('Lite: first two exercises only')
  }
  if (lite) badges.push('Lite day: every set 0-1 RIR')

  const constantineProtocol = (data.profile?.persona ?? 'constantine') === 'constantine'
  let warmup = constantineProtocol
    ? 'Band Pull-Aparts 3x20 (mid-back activation)'
    : (programDay.warmup_note || 'Five minutes of pain-free joint preparation')
  if (constantineProtocol && programDay.warmup_note) warmup += `. ${programDay.warmup_note}`

  const ctx = eventContextFor(date, data.events)
  let taperFactor = 1
  let isEventDay = false
  let isRecoveryMicro = false
  let legsBlocked = false

  const isLegDay = programDay.day_type === 'legs_a' || programDay.day_type === 'legs_b'

  if (ctx) {
    if (ctx.isDuring) {
      isEventDay = true
      isRecoveryMicro = true
      exercises = recoveryMicro(userId, programDay.id)
      warmup = 'Event day. 5-10 minutes keeps the streak and your back alive.'
      badges.push(`${ctx.event.name}: recovery micro-session`)
    } else if (ctx.daysUntilStart >= 1 && ctx.daysUntilStart <= 7) {
      if (
        ctx.event.type === 'filming_championship' &&
        isLegDay &&
        ctx.daysUntilStart <= 7
      ) {
        legsBlocked = true
        exercises = swapExercises(userId, programDay.id)
        badges.push('Championship rule: no leg training in the final 7 days')
      }
      taperFactor = taperFactorFor(ctx.daysUntilStart)
      if (taperFactor < 1) {
        badges.push(
          `Taper: ${Math.round((1 - taperFactor) * 100)}% fewer sets, ${ctx.daysUntilStart} day${ctx.daysUntilStart === 1 ? '' : 's'} to ${ctx.event.name}`,
        )
      }
      if (ctx.daysUntilStart <= 3 && !legsBlocked) {
        const before = exercises.length
        const kept = exercises.filter((e) => !HEAVY_PULL_SPINAL.test(e.name))
        if (kept.length < before) {
          exercises = [...kept, ...swapExercises(userId, programDay.id)].map((e, i) => ({
            ...e,
            sort_order: i,
          }))
          badges.push('Final 72 h: heavy pulling and spinal loading swapped for thoracic work')
        }
      }
    } else if (ctx.daysSinceEnd >= 1 && ctx.daysSinceEnd <= 2) {
      taperFactor = 0.75
      badges.push(`Rebound day ${ctx.daysSinceEnd} of 2 after ${ctx.event.name}: reduced load`)
    }
  }

  const isDeload = data.deload_marks.some((m) => m.date === date)
  const layoffDeload = !isEventDay && layoffActive(data, date)
  if (layoffDeload) {
    badges.push('Return from layoff: deload week. Minus 1 set, 3-4 RIR, lighter loads')
    if (programDay.day_type === 't25') {
      badges.push('T25 holds until week 2. Swap in mobility instead')
    }
  }
  if (isDeload) badges.push('Deload day: minus 1 set per exercise, 3-4 RIR, lighter')

  exercises = exercises.map((e) => {
    let sets = e.planned_sets
    if (taperFactor < 1) sets = Math.max(1, Math.round(sets * taperFactor))
    if ((isDeload || layoffDeload) && !isRecoveryMicro) sets = Math.max(1, sets - 1)
    return { ...e, planned_sets: sets }
  })

  /* Optional add-on protocols, Main Phase only, off by default */
  const addons = data.settings?.addons
  if (slug === 'main' && addons && !isEventDay) {
    const base = {
      user_id: userId,
      program_day_id: programDay.id,
      per_side: false,
      rep_unit: 'max' as const,
      rep_min: 0,
      rep_max: 0,
      tempo_up_s: 1,
      tempo_down_s: 2,
      tempo_pause_s: 0,
      tempo_note: '',
      notes: '',
      increment_kg: 0,
      is_lite: false,
      optional: false,
      swapped: false,
    }
    if (addons.endurance1 && weekday === 4) {
      const weeks = Math.floor(
        differenceInCalendarDays(parse(date), parse(data.profile?.baseline_date ?? date)) / 7,
      )
      if (weeks % 2 === 0) {
        exercises.push(
          { ...base, id: 'addon-e1a', name: 'Endurance test: max BW pushups', sets: 1, planned_sets: 1, rest_sec: 120, sort_order: 90 },
          { ...base, id: 'addon-e1b', name: 'Endurance test: max BW pull-ups', sets: 1, planned_sets: 1, rest_sec: 0, sort_order: 91 },
        )
        badges.push('Endurance Phase 1: biweekly max test')
      }
    }
    if (addons.endurance2 && weekday === 2) {
      exercises.push({ ...base, id: 'addon-e2', name: 'BW pushups to failure (strip backpack)', sets: 1, planned_sets: 1, rest_sec: 0, sort_order: 92 })
      badges.push('Endurance Phase 2 (needs 40+ BW pushups)')
    }
    if (addons.endurance3 && weekday === 7) {
      exercises.push({ ...base, id: 'addon-e3', name: 'Pull-up ladder 1-2-3-4-5-4-3-2-1, 10s between rungs', sets: 1, planned_sets: 1, rest_sec: 0, sort_order: 93 })
      badges.push('Endurance Phase 3 (needs 15+ BW pull-ups)')
    }
  }

  return {
    programDay,
    exercises,
    warmup,
    badges,
    isDeload: isDeload || layoffDeload,
    isEventDay,
    isRecoveryMicro,
    taperFactor,
    legsBlocked,
    layoffDeload,
  }
}

export function todayIso(): string {
  return iso(new Date())
}
