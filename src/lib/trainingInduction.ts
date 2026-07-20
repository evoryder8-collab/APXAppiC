import type { PersonaSlug } from './persona'
import type {
  DayType,
  Exercise,
  Program,
  ProgramDay,
  ProgramSlug,
  RepUnit,
  TrainingGoal,
  TrainingInactivity,
  TrainingInductionProfile,
  TrainingPainArea,
  TrainingPlanCaution,
  TrainingVenue,
} from './types'

export interface EquipmentOption {
  id: string
  en: string
  ro: string
  th: string
  aliases: string[]
}

export const EQUIPMENT_CATALOG: EquipmentOption[] = [
  { id: 'adjustable_dumbbells', en: 'Adjustable dumbbells', ro: 'Gantere reglabile', th: 'ดัมเบลปรับน้ำหนัก', aliases: ['dumbbell', 'dumbells', 'dum', 'weights', 'gantere'] },
  { id: 'fixed_dumbbells', en: 'Fixed dumbbells', ro: 'Gantere fixe', th: 'ดัมเบลน้ำหนักคงที่', aliases: ['dumbbell', 'dumbells', 'dum', 'weights', 'gantere'] },
  { id: 'resistance_bands', en: 'Resistance bands', ro: 'Benzi elastice', th: 'ยางยืดออกกำลังกาย', aliases: ['band', 'bands', 'elastic', 'benzi'] },
  { id: 'bench', en: 'Training bench', ro: 'Bancă de antrenament', th: 'ม้านั่งออกกำลังกาย', aliases: ['bench', 'banca', 'bancă'] },
  { id: 'pullup_bar', en: 'Pull-up bar', ro: 'Bară de tracțiuni', th: 'บาร์โหน', aliases: ['pull up', 'pullup', 'bar', 'bara', 'bară'] },
  { id: 'kettlebell', en: 'Kettlebell', ro: 'Kettlebell', th: 'เคตเทิลเบล', aliases: ['kettle', 'kb'] },
  { id: 'suspension_trainer', en: 'Suspension trainer', ro: 'Sistem de suspensie', th: 'สายฝึกแบบแขวน', aliases: ['trx', 'suspension', 'rings', 'inele'] },
  { id: 'barbell_plates', en: 'Barbell and plates', ro: 'Haltere și discuri', th: 'บาร์เบลและแผ่นน้ำหนัก', aliases: ['barbell', 'plates', 'haltera', 'discuri'] },
  { id: 'rack', en: 'Squat rack', ro: 'Cadru pentru genuflexiuni', th: 'แร็คสควอต', aliases: ['rack', 'cage', 'power rack'] },
  { id: 'cable_machine', en: 'Cable machine', ro: 'Aparat cu cabluri', th: 'เครื่องเคเบิล', aliases: ['cable', 'pulley', 'cablu'] },
  { id: 'cardio_machine', en: 'Cardio machine', ro: 'Aparat cardio', th: 'เครื่องคาร์ดิโอ', aliases: ['bike', 'treadmill', 'rower', 'skierg', 'bicicleta', 'banda'] },
  { id: 'mat', en: 'Exercise mat', ro: 'Saltea de antrenament', th: 'เสื่อออกกำลังกาย', aliases: ['mat', 'saltea', 'yoga'] },
]

function fold(value: string): string {
  return value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase().trim()
}

export function searchEquipment(query: string, language: 'en' | 'ro' | 'th' = 'en'): EquipmentOption[] {
  const needle = fold(query)
  if (!needle) return EQUIPMENT_CATALOG.slice(0, 6)
  return EQUIPMENT_CATALOG
    .map((item) => {
      const values = [item[language], item.en, item.ro, item.th, ...item.aliases].map(fold)
      const starts = values.some((value) => value.startsWith(needle))
      const contains = values.some((value) => value.includes(needle))
      return { item, rank: starts ? 0 : contains ? 1 : 2 }
    })
    .filter((entry) => entry.rank < 2)
    .sort((left, right) => left.rank - right.rank || left.item.en.localeCompare(right.item.en))
    .map((entry) => entry.item)
}

export function isTrainingInductionEligible(persona: PersonaSlug): boolean {
  return persona !== 'constantine'
}

export interface TrainingInductionInput {
  start_date: string
  inactivity: TrainingInactivity
  venue: TrainingVenue
  equipment: string[]
  pain_areas: TrainingPainArea[]
  recent_operation: boolean
  chronic_lower_back_pain: boolean
  sessions_per_week: 2 | 3 | 4
  goal: TrainingGoal
}

export interface TrainingAssessment {
  caution: TrainingPlanCaution
  sessions_per_week: 2 | 3 | 4
  reasons: string[]
}

export function assessTrainingInput(input: TrainingInductionInput): TrainingAssessment {
  if (input.recent_operation) {
    return {
      caution: 'clearance',
      sessions_per_week: 2,
      reasons: ['Recent operation reported', 'Loaded training waits for clinician clearance'],
    }
  }
  const longLayoff = input.inactivity === 'six_to_twelve_months' || input.inactivity === 'over_one_year'
  const cautious = longLayoff || input.chronic_lower_back_pain || input.pain_areas.length > 0
  return {
    caution: cautious ? 'cautious' : 'standard',
    sessions_per_week: cautious && input.sessions_per_week === 4 ? 3 : input.sessions_per_week,
    reasons: [
      ...(longLayoff ? ['Long training gap reported'] : []),
      ...(input.chronic_lower_back_pain ? ['Chronic lower-back pain reported'] : []),
      ...(input.pain_areas.length > 0 ? ['Current joint discomfort reported'] : []),
    ],
  }
}

interface ExerciseSpec {
  name: string
  sets?: number
  reps: [number, number]
  unit?: RepUnit
  perSide?: boolean
  rest?: number
  increment?: number
  notes?: string
  optional?: boolean
}

interface SessionSpec {
  name: string
  type: DayType
  minutes: number
  warmup: string
  exercises: ExerciseSpec[]
}

function homeExerciseNames(equipment: string[]): {
  squat: string
  hinge: string
  push: string
  row: string
  press: string
  pull: string
  carry: string
} {
  const dumbbells = equipment.includes('adjustable_dumbbells') || equipment.includes('fixed_dumbbells')
  const bands = equipment.includes('resistance_bands')
  const pullup = equipment.includes('pullup_bar')
  return {
    squat: dumbbells ? 'Goblet Squat' : 'Controlled Chair Squat',
    hinge: dumbbells ? 'Dumbbell Romanian Deadlift' : bands ? 'Band Hip Hinge' : 'Bodyweight Hip Hinge',
    push: dumbbells ? 'Dumbbell Floor Press' : 'Incline Push-Up',
    row: dumbbells ? 'One-Arm Dumbbell Row' : bands ? 'Band Row' : 'Towel Isometric Row',
    press: dumbbells ? 'Seated Dumbbell Press' : bands ? 'Band Overhead Press' : 'Incline Pike Press',
    pull: pullup ? 'Assisted Pull-Up' : bands ? 'Band Lat Pulldown' : 'Prone Lat Sweep',
    carry: dumbbells ? 'Suitcase Carry' : 'Backpack Carry',
  }
}

function clearanceSessions(): SessionSpec[] {
  const warmup = 'Begin only after the clinician managing the operation has cleared these movements. Use a pain-free range.'
  return [
    {
      name: 'Clearance Reset A', type: 'mobility', minutes: 18, warmup,
      exercises: [
        { name: 'Diaphragmatic Breathing', sets: 2, reps: [60, 90], unit: 'seconds' },
        { name: 'Pain-Free Joint Circles', sets: 2, reps: [5, 8], perSide: true },
        { name: 'Supported Sit-to-Stand', sets: 2, reps: [6, 10], rest: 60, notes: 'Stop with pain, instability or unusual symptoms.' },
        { name: 'Easy Walk', sets: 1, reps: [8, 12], unit: 'minutes' },
      ],
    },
    {
      name: 'Clearance Reset B', type: 'mobility', minutes: 18, warmup,
      exercises: [
        { name: 'Easy Walk', sets: 1, reps: [10, 15], unit: 'minutes' },
        { name: 'Wall Shoulder Slide', sets: 2, reps: [6, 10], rest: 45 },
        { name: 'Supported Calf Raise', sets: 2, reps: [8, 12], rest: 45 },
        { name: 'Gentle Mobility Flow', sets: 1, reps: [4, 6], unit: 'minutes' },
      ],
    },
  ]
}

function gymSessions(phase: 'transition' | 'main', count: 2 | 3 | 4): SessionSpec[] {
  const main = phase === 'main'
  const sets = main ? 3 : 2
  const warmup = 'Five minutes easy cardio, then two gradual practice sets for the first loaded movement.'
  const fullBody: SessionSpec[] = [
    {
      name: 'Full Body A', type: 'upper', minutes: main ? 52 : 38, warmup,
      exercises: [
        { name: 'Leg Press', sets, reps: [8, 12], rest: 105, increment: 5 },
        { name: 'Machine Chest Press', sets, reps: [8, 12], rest: 90, increment: 2.5 },
        { name: 'Seated Cable Row', sets, reps: [8, 12], rest: 90, increment: 2.5 },
        { name: 'Seated Leg Curl', sets, reps: [10, 15], rest: 75, increment: 2.5 },
        { name: 'Pallof Press', sets: 2, reps: [8, 12], perSide: true, rest: 45 },
      ],
    },
    {
      name: 'Full Body B', type: 'legs_b', minutes: main ? 54 : 40, warmup,
      exercises: [
        { name: 'Dumbbell Romanian Deadlift', sets, reps: [8, 12], rest: 105, increment: 2.5 },
        { name: 'Lat Pulldown', sets, reps: [8, 12], rest: 90, increment: 2.5 },
        { name: 'Machine Shoulder Press', sets, reps: [8, 12], rest: 90, increment: 2.5 },
        { name: 'Supported Split Squat', sets, reps: [8, 10], perSide: true, rest: 90, increment: 2.5 },
        { name: 'Farmer Carry', sets: 3, reps: [30, 45], unit: 'seconds', rest: 60, increment: 2.5 },
      ],
    },
    {
      name: 'Full Body C', type: 'upper', minutes: main ? 52 : 38, warmup,
      exercises: [
        { name: 'Hack Squat', sets, reps: [8, 12], rest: 105, increment: 5 },
        { name: 'Incline Dumbbell Press', sets, reps: [8, 12], rest: 90, increment: 2.5 },
        { name: 'Chest-Supported Row', sets, reps: [8, 12], rest: 90, increment: 2.5 },
        { name: 'Cable Lateral Raise', sets: 2, reps: [12, 18], rest: 45, increment: 1 },
        { name: 'Dead Bug', sets: 2, reps: [8, 12], perSide: true, rest: 45 },
      ],
    },
  ]
  if (count < 4) return fullBody.slice(0, count)
  return [
    { ...fullBody[0], name: 'Upper A', type: 'upper', exercises: fullBody[0].exercises.slice(1) },
    {
      name: 'Lower A', type: 'legs_a', minutes: main ? 50 : 36, warmup,
      exercises: [fullBody[0].exercises[0], fullBody[0].exercises[3], fullBody[1].exercises[3], fullBody[2].exercises[4]],
    },
    { ...fullBody[2], name: 'Upper B', type: 'upper', exercises: fullBody[2].exercises.slice(1) },
    {
      name: 'Lower B', type: 'legs_b', minutes: main ? 50 : 36, warmup,
      exercises: [fullBody[2].exercises[0], fullBody[1].exercises[0], fullBody[0].exercises[3], fullBody[1].exercises[4]],
    },
  ]
}

function homeSessions(phase: 'transition' | 'main', count: 2 | 3 | 4, equipment: string[]): SessionSpec[] {
  const main = phase === 'main'
  const sets = main ? 3 : 2
  const names = homeExerciseNames(equipment)
  const warmup = 'Five minutes of pain-free joint preparation, then one easy practice set.'
  const fullBody: SessionSpec[] = [
    {
      name: 'Home Full Body A', type: 'upper', minutes: main ? 44 : 30, warmup,
      exercises: [
        { name: names.squat, sets, reps: [8, 12], rest: 90, increment: 2 },
        { name: names.push, sets, reps: [8, 15], rest: 75, increment: 2 },
        { name: names.row, sets, reps: [8, 15], perSide: names.row.includes('One-Arm'), rest: 75, increment: 2 },
        { name: 'Dead Bug', sets: 2, reps: [8, 12], perSide: true, rest: 30 },
        { name: names.carry, sets: 3, reps: [30, 45], unit: 'seconds', perSide: true, rest: 45, increment: 2 },
      ],
    },
    {
      name: 'Home Full Body B', type: 'legs_b', minutes: main ? 46 : 32, warmup,
      exercises: [
        { name: names.hinge, sets, reps: [8, 12], rest: 90, increment: 2 },
        { name: names.press, sets, reps: [8, 12], rest: 75, increment: 2 },
        { name: names.pull, sets, reps: [6, 12], rest: 90, increment: 1 },
        { name: 'Supported Reverse Lunge', sets: 2, reps: [8, 10], perSide: true, rest: 75 },
        { name: 'Side Plank', sets: 2, reps: [20, 35], unit: 'seconds', perSide: true, rest: 30 },
      ],
    },
    {
      name: 'Home Full Body C', type: 'upper', minutes: main ? 44 : 30, warmup,
      exercises: [
        { name: 'Step-Up', sets, reps: [8, 12], perSide: true, rest: 75, increment: 2 },
        { name: names.push, sets, reps: [8, 15], rest: 75, increment: 2 },
        { name: names.row, sets, reps: [8, 15], perSide: names.row.includes('One-Arm'), rest: 75, increment: 2 },
        { name: 'Hip Thrust', sets, reps: [10, 15], rest: 75, increment: 2 },
        { name: 'Bird-Dog', sets: 2, reps: [6, 10], perSide: true, rest: 30 },
      ],
    },
  ]
  if (count < 4) return fullBody.slice(0, count)
  return [
    { ...fullBody[0], name: 'Home Upper A', type: 'upper', exercises: fullBody[0].exercises.slice(1) },
    { ...fullBody[0], name: 'Home Lower A', type: 'legs_a', exercises: [fullBody[0].exercises[0], fullBody[1].exercises[0], fullBody[1].exercises[3], fullBody[0].exercises[3]] },
    { ...fullBody[2], name: 'Home Upper B', type: 'upper', exercises: [fullBody[2].exercises[1], fullBody[2].exercises[2], fullBody[1].exercises[1], fullBody[2].exercises[4]] },
    { ...fullBody[1], name: 'Home Lower B', type: 'legs_b', exercises: [fullBody[2].exercises[0], fullBody[2].exercises[3], fullBody[1].exercises[0], fullBody[1].exercises[4]] },
  ]
}

function hash32(value: string, seed: number): number {
  let hash = seed >>> 0
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  hash ^= hash >>> 16
  hash = Math.imul(hash, 0x7feb352d)
  hash ^= hash >>> 15
  return hash >>> 0
}

function stableUuid(userId: string, label: string): string {
  const input = `${userId}:training-induction:${label}`
  const raw = [0x811c9dc5, 0x9e3779b9, 0x85ebca6b, 0xc2b2ae35]
    .map((seed) => hash32(input, seed).toString(16).padStart(8, '0'))
    .join('')
  const variant = ((parseInt(raw[16], 16) & 0x3) | 0x8).toString(16)
  return `${raw.slice(0, 8)}-${raw.slice(8, 12)}-4${raw.slice(13, 16)}-${variant}${raw.slice(17, 20)}-${raw.slice(20, 32)}`
}

function addDaysIso(dateIso: string, days: number): string {
  const date = new Date(`${dateIso}T12:00:00Z`)
  date.setUTCDate(date.getUTCDate() + days)
  return date.toISOString().slice(0, 10)
}

function weekdaysFor(count: 2 | 3 | 4): number[] {
  if (count === 2) return [1, 4]
  if (count === 3) return [1, 3, 5]
  return [1, 2, 4, 6]
}

export interface GeneratedTrainingPlan {
  programs: Program[]
  program_days: ProgramDay[]
  exercises: Exercise[]
  induction: TrainingInductionProfile
}

export function generateTrainingPlan(
  userId: string,
  input: TrainingInductionInput,
  existingPrograms: Program[] = [],
  completedAt = new Date().toISOString(),
): GeneratedTrainingPlan {
  const assessment = assessTrainingInput(input)
  const count = assessment.sessions_per_week
  const mainStart = addDaysIso(input.start_date, 84)
  const programFor = (slug: 'transition' | 'main'): Program => {
    const existing = existingPrograms.find((program) => program.slug === slug)
    const venue = input.venue === 'gym' ? 'Gym' : 'Home'
    return {
      id: existing?.id ?? stableUuid(userId, `program:${slug}`),
      user_id: userId,
      slug,
      name: slug === 'transition' ? `12-Week ${venue} Foundation` : `Personal ${venue} Main Phase`,
      description: slug === 'transition'
        ? 'Weeks 1-4 restore, weeks 5-8 build, weeks 9-12 progress. A simple schedule built from your answers.'
        : 'Your follow-on strength and muscle phase, using the same equipment, recovery limits and weekly rhythm.',
    }
  }
  const programs = [programFor('transition'), programFor('main')]
  const program_days: ProgramDay[] = []
  const exercises: Exercise[] = []
  const dayIds: Record<'transition' | 'main', string[]> = { transition: [], main: [] }

  const buildPhase = (slug: 'transition' | 'main'): void => {
    const phase = slug
    const programme = programs.find((row) => row.slug === slug)!
    const sessions = assessment.caution === 'clearance'
      ? clearanceSessions()
      : input.venue === 'gym'
        ? gymSessions(phase, count)
        : homeSessions(phase, count, input.equipment)
    const weekdays = weekdaysFor(count)
    sessions.forEach((session, sessionIndex) => {
      const weekday = weekdays[sessionIndex]
      const dayId = stableUuid(userId, `${slug}:day:${weekday}`)
      dayIds[slug].push(dayId)
      program_days.push({
        id: dayId,
        user_id: userId,
        program_id: programme.id,
        weekday,
        name: session.name,
        day_type: session.type,
        est_minutes: session.minutes,
        warmup_note: assessment.caution === 'cautious'
          ? `${session.warmup} Start with 3-4 reps in reserve and keep every movement pain-free.`
          : session.warmup,
        sort_order: sessionIndex,
      })
      const addExercise = (spec: ExerciseSpec, index: number, lite: boolean): void => {
        const sets = Math.max(1, (spec.sets ?? 2) - (lite ? 1 : 0))
        exercises.push({
          id: stableUuid(userId, `${slug}:day:${weekday}:${lite ? 'lite' : 'full'}:${index}`),
          user_id: userId,
          program_day_id: dayId,
          name: spec.name,
          sets,
          rep_min: spec.reps[0],
          rep_max: spec.reps[1],
          rep_unit: spec.unit ?? 'reps',
          per_side: spec.perSide ?? false,
          rest_sec: spec.rest ?? 60,
          tempo_up_s: 1,
          tempo_down_s: assessment.caution === 'standard' ? 2 : 3,
          tempo_pause_s: 0,
          tempo_note: '',
          notes: spec.notes ?? (assessment.caution === 'cautious' ? 'Pain-free range. Stop with at least 3 reps in reserve.' : 'Progress only after every rep is controlled.'),
          increment_kg: spec.increment ?? 0,
          is_lite: lite,
          optional: spec.optional ?? false,
          sort_order: index,
        })
      }
      session.exercises.forEach((exercise, index) => addExercise(exercise, index, false))
      session.exercises.slice(0, 3).forEach((exercise, index) => addExercise(exercise, index, true))
    })
  }

  buildPhase('transition')
  buildPhase('main')

  return {
    programs,
    program_days,
    exercises,
    induction: {
      version: 1,
      completed_at: completedAt,
      start_date: input.start_date,
      main_start_date: mainStart,
      transition_weeks: 12,
      inactivity: input.inactivity,
      venue: input.venue,
      equipment: [...input.equipment],
      pain_areas: [...input.pain_areas],
      recent_operation: input.recent_operation,
      chronic_lower_back_pain: input.chronic_lower_back_pain,
      sessions_per_week: count,
      goal: input.goal,
      caution: assessment.caution,
      transition_day_ids: dayIds.transition,
      main_day_ids: dayIds.main,
    },
  }
}

export function activeInductionDayIds(
  induction: TrainingInductionProfile | null | undefined,
  slug: ProgramSlug,
): Set<string> | null {
  if (!induction || (slug !== 'transition' && slug !== 'main')) return null
  return new Set(slug === 'transition' ? induction.transition_day_ids : induction.main_day_ids)
}

export function isInsideInductionWindow(
  induction: TrainingInductionProfile | null | undefined,
  slug: ProgramSlug,
  dateIso: string,
): boolean {
  if (!induction || (slug !== 'transition' && slug !== 'main')) return true
  if (slug === 'transition') return dateIso >= induction.start_date && dateIso < induction.main_start_date
  return dateIso >= induction.main_start_date
}

export function inductionWeek(induction: TrainingInductionProfile, dateIso: string): number {
  const start = new Date(`${induction.start_date}T12:00:00Z`).getTime()
  const date = new Date(`${dateIso}T12:00:00Z`).getTime()
  return Math.floor((date - start) / 604_800_000) + 1
}
