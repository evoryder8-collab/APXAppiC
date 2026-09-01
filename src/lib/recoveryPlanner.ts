import type { Exercise, Program, ProgramDay, Settings } from './types.ts'
import { isInsideInductionWindow } from './trainingInduction.ts'

export type RecoveryPlanTarget = 'joint' | 'flexibility'
export type RecoveryPlanSource = 'guided' | 'external'

export interface RecoveryPlanResult {
  planId: string
  days: ProgramDay[]
  exercises: Exercise[]
}

interface BuildRecoveryPlanInput {
  ownerId: string
  startDate: string
  target: RecoveryPlanTarget
  source: RecoveryPlanSource
  programs: Program[]
  settings: Settings | null
  existingDays: ProgramDay[]
  makeId?: () => string
}

function utcDate(date: string): Date {
  return new Date(`${date}T12:00:00Z`)
}

function addDays(date: string, amount: number): string {
  const value = utcDate(date)
  value.setUTCDate(value.getUTCDate() + amount)
  return value.toISOString().slice(0, 10)
}

function isoWeekday(date: string): number {
  const weekday = utcDate(date).getUTCDay()
  return weekday === 0 ? 7 : weekday
}

function daysApart(left: string, right: string): number {
  return Math.abs((utcDate(left).getTime() - utcDate(right).getTime()) / 86_400_000)
}

export function recoveryDayMatchesDate(day: ProgramDay, date: string): boolean {
  if (day.scheduled_date) return day.scheduled_date === date
  return day.weekday === isoWeekday(date)
}

function trainingLoad(date: string, existingDays: ProgramDay[]): number {
  return existingDays.reduce((total, day) => {
    if (day.is_active === false || !recoveryDayMatchesDate(day, date)) return total
    if (day.scheduled_date) return total + 12
    if (day.day_type === 'mobility' || day.day_type === 'fix') return total + 1
    if (day.day_type === 'custom' || day.day_type === 'coach') return total + 3
    if (day.day_type === 't25') return total + 4
    return total + 6
  }, 0)
}

/**
 * Selects exact dates, not weekdays. Each seven-day block is planned on its
 * own, favouring the lowest existing load and separating the pair by at least
 * 48 hours whenever there is a choice.
 */
export function scheduledRecoveryDates(
  startDate: string,
  existingDays: ProgramDay[],
  weeks = 4,
  sessionsPerWeek = 2,
): string[] {
  const result: string[] = []
  for (let week = 0; week < weeks; week += 1) {
    const candidates = Array.from({ length: 7 }, (_, offset) => addDays(startDate, week * 7 + offset))
    const ranked = [...candidates].sort((left, right) =>
      trainingLoad(left, existingDays) - trainingLoad(right, existingDays) || left.localeCompare(right),
    )
    const selected: string[] = []
    if (ranked[0]) selected.push(ranked[0])
    while (selected.length < sessionsPerWeek) {
      const remaining = ranked.filter((date) => !selected.includes(date))
      const separated = remaining.filter((date) => selected.every((chosen) => daysApart(date, chosen) >= 2))
      const pool = separated.length > 0 ? separated : remaining
      const next = [...pool].sort((left, right) => {
        const leftGap = Math.min(...selected.map((chosen) => daysApart(left, chosen)))
        const rightGap = Math.min(...selected.map((chosen) => daysApart(right, chosen)))
        const leftScore = trainingLoad(left, existingDays) + Math.abs(3 - leftGap) * 0.25
        const rightScore = trainingLoad(right, existingDays) + Math.abs(3 - rightGap) * 0.25
        return leftScore - rightScore || left.localeCompare(right)
      })[0]
      if (!next) break
      selected.push(next)
    }
    result.push(...selected.sort())
  }
  return result
}

function recoveryProgram(
  programs: Program[],
  settings: Settings | null,
  ownerId: string,
  date: string,
): Program | null {
  const owned = programs.filter((program) => program.user_id === ownerId)
  const induction = settings?.user_id === ownerId ? settings.addons.training_induction : null
  const transition = owned.find((program) => program.slug === 'transition')
  const main = owned.find((program) => program.slug === 'main')
  if (transition && isInsideInductionWindow(induction, 'transition', date)) return transition
  if (main && isInsideInductionWindow(induction, 'main', date)) return main
  if (!induction) return main ?? transition ?? null
  return null
}

interface ExerciseTemplate {
  name: string
  movementId: string
  sets: number
  min: number
  max: number
  unit: Exercise['rep_unit']
  perSide: boolean
  rest: number
  note: string
}

const JOINT_ROUTINE: ExerciseTemplate[] = [
  { name: 'Cat-Cow', movementId: 'cat_cow', sets: 2, min: 6, max: 8, unit: 'reps', perSide: false, rest: 15, note: 'Move slowly through a comfortable range.' },
  { name: 'Wall Slide', movementId: 'wall_slide', sets: 2, min: 8, max: 10, unit: 'reps', perSide: false, rest: 15, note: 'Keep the motion smooth and pain-free.' },
  { name: 'Ankle Mobility Rock', movementId: 'joint_circles', sets: 2, min: 8, max: 10, unit: 'reps', perSide: true, rest: 15, note: 'Keep the heel grounded; do not force range.' },
  { name: '90/90 Hip Mobility', movementId: 'ninety_ninety_hip', sets: 2, min: 20, max: 30, unit: 'seconds', perSide: true, rest: 15, note: 'Use light tension, never sharp pain.' },
]

const FLEXIBILITY_ROUTINE: ExerciseTemplate[] = [
  { name: '90/90 Hip Mobility', movementId: 'ninety_ninety_hip', sets: 2, min: 20, max: 30, unit: 'seconds', perSide: true, rest: 15, note: 'Use light tension, never sharp pain.' },
  { name: 'Hip Flexor Stretch', movementId: 'hip_flexor_stretch', sets: 2, min: 20, max: 30, unit: 'seconds', perSide: true, rest: 15, note: 'Keep the pelvis controlled and breathe normally.' },
  { name: 'Thoracic Rotation', movementId: 'thoracic_extension', sets: 2, min: 6, max: 8, unit: 'reps', perSide: true, rest: 15, note: 'Rotate only through a comfortable range.' },
  { name: "Child's Pose", movementId: 'childs_pose', sets: 2, min: 20, max: 30, unit: 'seconds', perSide: false, rest: 15, note: 'Breathe easily and stop if symptoms worsen.' },
]

function exerciseRows(
  ownerId: string,
  dayId: string,
  target: RecoveryPlanTarget,
  source: RecoveryPlanSource,
  makeId: () => string,
): Exercise[] {
  const templates: ExerciseTemplate[] = source === 'external'
    ? [{
        name: 'Mobility Flow', movementId: 'mobility_flow', sets: 1, min: 10, max: 15,
        unit: 'minutes', perSide: false, rest: 0,
        note: 'Follow a mobility or recovery routine you trust. Log it only after you complete it.',
      }]
    : target === 'joint' ? JOINT_ROUTINE : FLEXIBILITY_ROUTINE
  return templates.map((template, index) => ({
    id: makeId(),
    user_id: ownerId,
    program_day_id: dayId,
    name: template.name,
    movement_id: template.movementId,
    sets: template.sets,
    rep_min: template.min,
    rep_max: template.max,
    rep_unit: template.unit,
    per_side: template.perSide,
    rest_sec: template.rest,
    tempo_up_s: 2,
    tempo_down_s: 2,
    tempo_pause_s: 0,
    tempo_note: 'Controlled, comfortable movement',
    notes: template.note,
    increment_kg: 0,
    is_lite: false,
    optional: false,
    sort_order: index,
  }))
}

export function buildRecoveryPlan(input: BuildRecoveryPlanInput): RecoveryPlanResult {
  const makeId = input.makeId ?? (() => crypto.randomUUID())
  const planId = makeId()
  const dates = scheduledRecoveryDates(input.startDate, input.existingDays)
  const days: ProgramDay[] = []
  const exercises: Exercise[] = []
  for (const [index, date] of dates.entries()) {
    const program = recoveryProgram(input.programs, input.settings, input.ownerId, date)
    if (!program) continue
    const dayId = makeId()
    const day: ProgramDay = {
      id: dayId,
      user_id: input.ownerId,
      program_id: program.id,
      weekday: isoWeekday(date),
      name: input.target === 'joint' ? 'Joint care' : 'Flexibility reset',
      day_type: 'mobility',
      est_minutes: input.source === 'external' ? 15 : input.target === 'joint' ? 12 : 14,
      warmup_note: 'Move in a comfortable, pain-free range. Stop if symptoms worsen.',
      sort_order: 900 + index,
      session_mode: 'guided',
      is_active: true,
      scheduled_date: date,
      recovery_plan_id: planId,
      recovery_target: input.target,
      recovery_source: input.source,
    }
    days.push(day)
    exercises.push(...exerciseRows(input.ownerId, dayId, input.target, input.source, makeId))
  }
  return { planId, days, exercises }
}

export function futureRecoveryRowsToDeactivate(
  existingDays: ProgramDay[],
  ownerId: string,
  target: RecoveryPlanTarget,
  today: string,
  protectedDayIds: ReadonlySet<string> = new Set(),
): ProgramDay[] {
  return existingDays
    .filter((day) =>
      day.user_id === ownerId
      && day.is_active !== false
      && day.recovery_target === target
      && Boolean(day.recovery_plan_id)
      && Boolean(day.scheduled_date)
      && !protectedDayIds.has(day.id)
      && (day.scheduled_date as string) >= today,
    )
    .map((day) => ({ ...day, is_active: false }))
}
