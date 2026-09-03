import type { PersonaSlug } from './persona'
import type { IntroLanguage } from './introLanguage'
import type {
  DayType,
  AppData,
  Exercise,
  Program,
  ProgramDay,
  ProgramSlug,
  RepUnit,
  SessionMode,
  TrainingGoal,
  TrainingInactivity,
  TrainingInductionProfile,
  TrainingPainArea,
  TrainingPlanCaution,
  TrainingPlanWeeks,
  TrainingSessionsPerWeek,
  TrainingVenue,
  Settings,
} from './types'

import { estimateSessionSeconds, followAlongFields } from './sessionShape.ts'
import { GOAL_INTENT } from './planGenerator.ts'
import type { TrainingIntent } from './liftingTempo.ts'

export interface EquipmentOption {
  id: string
  en: string
  ro: string
  th: string
  aliases: string[]
}

export const EQUIPMENT_CATALOG: EquipmentOption[] = [
  { id: 'weighted_vest', en: 'Weighted vest', ro: 'Vestă cu greutăți', th: 'เสื้อกั๊กถ่วงน้ำหนัก', aliases: ['vest', 'weight vest', 'weighted', 'vesta', 'vestă'] },
  { id: 'weighted_backpack', en: 'Weighted backpack', ro: 'Rucsac cu greutăți', th: 'กระเป๋าเป้ถ่วงน้ำหนัก', aliases: ['backpack', 'ruck', 'rucksack', 'weighted', 'rucsac'] },
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

export function isTrainingInductionEligible(_persona: PersonaSlug): boolean {
  return true
}

export interface TrainingInductionInput {
  start_date: string
  inactivity: TrainingInactivity
  venue: TrainingVenue
  equipment: string[]
  pain_areas: TrainingPainArea[]
  recent_operation: boolean
  chronic_lower_back_pain: boolean
  acute_symptoms?: boolean
  sessions_per_week: TrainingSessionsPerWeek
  plan_weeks: TrainingPlanWeeks
  available_minutes?: number
  goal: TrainingGoal
  baseline_assessment?: {
    version: 1
    activity_pattern: string
    movement: {
      cardiorespiratory: string
      upper_strength: string
      lower_strength: string
      mobility: string
    }
  }
}

export const TRAINING_PLAN_WEEK_OPTIONS: readonly TrainingPlanWeeks[] = [4, 8, 12, 26]

export const TRAINING_INDUCTION_REQUIRED_ANSWERS = [
  'inactivity',
  'frequency',
  'safety',
  'venue',
  'goal',
  'duration',
] as const

export type TrainingInductionRequiredAnswer = typeof TRAINING_INDUCTION_REQUIRED_ANSWERS[number]

const TRAINING_INDUCTION_ANSWER_REQUIRED_TEXT: Record<IntroLanguage, string> = {
  en: 'Complete this step before continuing.',
  ro: 'Finalizează acest pas înainte de a continua.',
  th: 'ทำขั้นตอนนี้ให้ครบก่อนดำเนินการต่อ',
}

export function trainingInductionAnswerRequiredText(language: IntroLanguage): string {
  return TRAINING_INDUCTION_ANSWER_REQUIRED_TEXT[language]
}

const TRAINING_INDUCTION_ACUTE_SYMPTOMS_TEXT: Record<IntroLanguage, string> = {
  en: 'Exercise has caused chest pain, faintness or unusual breathlessness',
  ro: 'Efortul a provocat durere în piept, senzație de leșin sau lipsă de aer neobișnuită',
  th: 'การออกกำลังกายทำให้เจ็บหน้าอก หน้ามืด หรือหายใจไม่อิ่มผิดปกติ',
}

export function trainingInductionAcuteSymptomsText(language: IntroLanguage): string {
  return TRAINING_INDUCTION_ACUTE_SYMPTOMS_TEXT[language]
}

const TRAINING_INACTIVITY_OPTIONS = new Set<TrainingInactivity>([
  'currently_training',
  'under_1_month',
  'one_to_three_months',
  'three_to_six_months',
  'six_to_twelve_months',
  'over_one_year',
])
const TRAINING_VENUE_OPTIONS = new Set<TrainingVenue>(['home', 'gym', 'outdoors'])
const TRAINING_GOAL_OPTIONS = new Set<TrainingGoal>(['rebuild', 'muscle', 'fat_loss', 'strength', 'endurance'])
const TRAINING_INACTIVITY_INPUT_MAP: Record<string, TrainingInactivity> = {
  currently_training: 'currently_training',
  under_1_month: 'under_1_month',
  one_to_three_months: 'one_to_three_months',
  under_three_months: 'one_to_three_months',
  three_to_six_months: 'three_to_six_months',
  six_to_twelve_months: 'six_to_twelve_months',
  over_one_year: 'over_one_year',
}
const TRAINING_PAIN_INPUT_MAP: Record<string, TrainingPainArea> = {
  shoulder: 'shoulders', shoulders: 'shoulders',
  elbow: 'elbows', elbows: 'elbows',
  wrist: 'wrists', wrists: 'wrists',
  hip: 'hips', hips: 'hips',
  knee: 'knees', knees: 'knees',
  ankle: 'ankles', ankles: 'ankles',
}
const TRAINING_GOAL_INPUT_MAP: Record<string, TrainingGoal> = {
  rebuild: 'rebuild', general: 'rebuild', fat_loss: 'fat_loss', endurance: 'endurance',
  muscle: 'muscle', hypertrophy: 'muscle', strength: 'strength',
}

function hasOwnOption<T>(options: Record<string, T>, value: unknown): value is string {
  return typeof value === 'string' && Object.prototype.hasOwnProperty.call(options, value)
}

/** A value becomes an answer only after the person chose it on this pass.
 * Existing committed plans seed every acknowledgement when reopened, while
 * new builders cannot silently accept convenient-looking defaults. */
export function isTrainingInductionStepComplete(
  step: number,
  input: TrainingInductionInput,
  answered: ReadonlySet<TrainingInductionRequiredAnswer>,
): boolean {
  switch (step) {
    case 0:
      return answered.has('inactivity')
        && answered.has('frequency')
        && TRAINING_INACTIVITY_OPTIONS.has(input.inactivity)
        && Number.isInteger(input.sessions_per_week)
        && input.sessions_per_week >= 2
        && input.sessions_per_week <= 7
    case 1:
      return answered.has('safety')
        && typeof input.recent_operation === 'boolean'
        && typeof input.chronic_lower_back_pain === 'boolean'
        && Array.isArray(input.pain_areas)
    case 2:
      return answered.has('venue') && TRAINING_VENUE_OPTIONS.has(input.venue)
    case 3:
      return answered.has('goal') && TRAINING_GOAL_OPTIONS.has(input.goal)
    case 4:
      return answered.has('duration') && TRAINING_PLAN_WEEK_OPTIONS.includes(input.plan_weeks)
    default:
      return true
  }
}

function normalizedPlanWeeks(value: unknown): TrainingPlanWeeks {
  return TRAINING_PLAN_WEEK_OPTIONS.includes(value as TrainingPlanWeeks)
    ? value as TrainingPlanWeeks
    : 12
}

export interface TrainingAssessment {
  caution: TrainingPlanCaution
  sessions_per_week: TrainingSessionsPerWeek
  reasons: string[]
}

function jsonRecord(value: unknown): Record<string, unknown> | null {
  return value != null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : []
}

function profileGenerationRevision(value: unknown): number {
  const raw = jsonRecord(value)?.generation_revision
  return typeof raw === 'number' && Number.isFinite(raw) ? Math.max(0, Math.trunc(raw)) : 0
}

/** Preserve only answers that were actually present and valid in persisted
 * cross-platform JSON. Normalized form defaults are not user answers. */
export function trainingInductionAnswersFromProfile(
  value: unknown,
): Set<TrainingInductionRequiredAnswer> {
  const raw = jsonRecord(value)
  const answers = new Set<TrainingInductionRequiredAnswer>()
  if (!raw) return answers

  if (hasOwnOption(TRAINING_INACTIVITY_INPUT_MAP, raw.inactivity)) {
    answers.add('inactivity')
  }
  if (typeof raw.sessions_per_week === 'number'
    && Number.isInteger(raw.sessions_per_week)
    && raw.sessions_per_week >= 2
    && raw.sessions_per_week <= 7) {
    answers.add('frequency')
  }
  if (typeof raw.recent_operation === 'boolean'
    && typeof raw.chronic_lower_back_pain === 'boolean'
    && typeof raw.acute_symptoms === 'boolean'
    && Array.isArray(raw.pain_areas)
    && raw.pain_areas.every((area) => hasOwnOption(TRAINING_PAIN_INPUT_MAP, area))) {
    answers.add('safety')
  }
  if (typeof raw.venue === 'string' && TRAINING_VENUE_OPTIONS.has(raw.venue as TrainingVenue)) {
    answers.add('venue')
  }
  if (hasOwnOption(TRAINING_GOAL_INPUT_MAP, raw.goal)) {
    answers.add('goal')
  }
  if (TRAINING_PLAN_WEEK_OPTIONS.includes(raw.plan_weeks as TrainingPlanWeeks)) {
    answers.add('duration')
  }
  return answers
}

export function isTrainingInductionNothingToFlag(input: TrainingInductionInput): boolean {
  return !input.recent_operation
    && !input.chronic_lower_back_pain
    && input.acute_symptoms !== true
    && input.pain_areas.length === 0
}

/** Supabase settings JSON is shared with native and legacy builds, so validate
 * and translate it before the typed web form or generator sees it. */
export function trainingInputFromProfile(value: unknown, fallbackStartDate: string): TrainingInductionInput {
  const raw = jsonRecord(value) ?? {}
  const venue: TrainingVenue = raw.venue === 'gym' || raw.venue === 'outdoors' ? raw.venue : 'home'
  const rawSessions = typeof raw.sessions_per_week === 'number' && Number.isFinite(raw.sessions_per_week)
    ? Math.trunc(raw.sessions_per_week)
    : 3
  const baselineAssessment = jsonRecord(raw.baseline_assessment)
  const movement = jsonRecord(baselineAssessment?.movement)
  const availableMinutes = typeof raw.available_minutes === 'number' && Number.isFinite(raw.available_minutes)
    ? Math.trunc(raw.available_minutes)
    : undefined
  return {
    start_date: typeof raw.start_date === 'string' && raw.start_date ? raw.start_date : fallbackStartDate,
    inactivity: hasOwnOption(TRAINING_INACTIVITY_INPUT_MAP, raw.inactivity)
      ? TRAINING_INACTIVITY_INPUT_MAP[raw.inactivity]
      : 'one_to_three_months',
    venue,
    equipment: stringArray(raw.equipment),
    pain_areas: sortedIds(
      stringArray(raw.pain_areas).flatMap((area) => hasOwnOption(TRAINING_PAIN_INPUT_MAP, area) ? [TRAINING_PAIN_INPUT_MAP[area]] : []),
    ) as TrainingPainArea[],
    recent_operation: raw.recent_operation === true,
    chronic_lower_back_pain: raw.chronic_lower_back_pain === true,
    acute_symptoms: raw.acute_symptoms === true,
    sessions_per_week: Math.min(7, Math.max(2, rawSessions)) as TrainingSessionsPerWeek,
    plan_weeks: normalizedPlanWeeks(raw.plan_weeks),
    ...(availableMinutes != null && availableMinutes >= 15 && availableMinutes <= 180
      ? { available_minutes: availableMinutes }
      : {}),
    goal: hasOwnOption(TRAINING_GOAL_INPUT_MAP, raw.goal) ? TRAINING_GOAL_INPUT_MAP[raw.goal] : 'rebuild',
    ...(baselineAssessment && movement
      ? {
        baseline_assessment: {
          version: 1 as const,
          activity_pattern: typeof baselineAssessment.activity_pattern === 'string'
            ? baselineAssessment.activity_pattern
            : '',
          movement: {
            cardiorespiratory: typeof movement.cardiorespiratory === 'string' ? movement.cardiorespiratory : '',
            upper_strength: typeof movement.upper_strength === 'string' ? movement.upper_strength : '',
            lower_strength: typeof movement.lower_strength === 'string' ? movement.lower_strength : '',
            mobility: typeof movement.mobility === 'string' ? movement.mobility : '',
          },
        },
      }
      : {}),
  }
}

/** A committed plan is proof that the questionnaire was answered. It is the
 * only settings-only state allowed to recreate a missing profile; Skip and an
 * interrupted pending write deliberately remain profileless. */
export function missingProfileTrainingGoal(
  data: Pick<AppData, 'profile' | 'settings'>,
  authenticatedUserId: string,
): TrainingGoal | null {
  if (data.profile || data.settings?.user_id !== authenticatedUserId) return null
  const induction = jsonRecord(data.settings.addons.training_induction)
  if (!induction) return null
  return trainingInputFromProfile(induction, '1970-01-01').goal
}

export function assessTrainingInput(input: TrainingInductionInput): TrainingAssessment {
  if (input.recent_operation || input.acute_symptoms === true) {
    return {
      caution: 'clearance',
      sessions_per_week: 2,
      reasons: [
        input.recent_operation ? 'Recent operation reported' : 'Exercise warning symptom reported',
        'Loaded training waits for clinician clearance',
      ],
    }
  }
  const longLayoff = input.inactivity === 'six_to_twelve_months' || input.inactivity === 'over_one_year'
  const cautious = longLayoff || input.chronic_lower_back_pain || input.pain_areas.length > 0
  return {
    caution: cautious ? 'cautious' : 'standard',
    sessions_per_week: cautious
      ? Math.min(input.sessions_per_week, 3) as 2 | 3
      : input.sessions_per_week,
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
  workGroupKey?: string
  workGroupPosition?: number
}

interface SessionSpec {
  name: string
  type: DayType
  minutes: number
  warmup: string
  exercises: ExerciseSpec[]
}

/** High frequency distributes the same work instead of silently multiplying it.
 * Volume-equated reviews find no meaningful hypertrophy advantage from frequency
 * alone (PMID 30558493), so loaded sessions are capped at two hard sets and
 * separated by low-load mobility/capacity work. */
function capHardSets(session: SessionSpec, cap = 2): SessionSpec {
  return {
    ...session,
    exercises: session.exercises.map((exercise) => ({
      ...exercise,
      sets: Math.min(exercise.sets ?? 2, cap),
    })),
  }
}

function withoutWorkGroup(exercise: ExerciseSpec): ExerciseSpec {
  return { ...exercise, workGroupKey: undefined, workGroupPosition: undefined }
}

function mobilityAndCoreSession(prefix = ''): SessionSpec {
  return {
    name: `${prefix}Mobility & Core`,
    type: 'mobility',
    minutes: 26,
    warmup: 'Keep this session deliberately easy. Finish feeling better than you started.',
    exercises: [
      { name: '90/90 Hip Mobility', sets: 1, reps: [60, 90], unit: 'seconds', perSide: true, rest: 20 },
      { name: 'Cat-Cow', sets: 2, reps: [6, 10], rest: 20 },
      { name: 'Thoracic Extension', sets: 2, reps: [6, 10], rest: 20 },
      { name: 'Dead Bug', sets: 2, reps: [6, 10], perSide: true, rest: 30 },
      { name: 'Walking', sets: 1, reps: [10, 15], unit: 'minutes', rest: 0 },
    ],
  }
}

function recoverySession(prefix = ''): SessionSpec {
  return {
    name: `${prefix}Recovery Session`,
    type: 'mobility',
    minutes: 30,
    warmup: 'This is a training day, not another hard day. Keep breathing conversational and every movement pain-free.',
    exercises: [
      { name: 'Walking', sets: 1, reps: [18, 25], unit: 'minutes', rest: 0 },
      { name: '90/90 Hip Mobility', sets: 1, reps: [60, 90], unit: 'seconds', perSide: true, rest: 20 },
      { name: 'Diaphragmatic Breathing', sets: 1, reps: [90, 120], unit: 'seconds', rest: 0 },
    ],
  }
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
  const weightedVest = equipment.includes('weighted_vest')
  const weightedBackpack = equipment.includes('weighted_backpack')
  return {
    squat: dumbbells ? 'Goblet Squat' : weightedVest ? 'Weighted Vest Squat' : weightedBackpack ? 'Backpack Front Squat' : 'Controlled Chair Squat',
    hinge: dumbbells ? 'Dumbbell Romanian Deadlift' : weightedBackpack ? 'Backpack Romanian Deadlift' : bands ? 'Band Hip Hinge' : 'Bodyweight Hip Hinge',
    push: dumbbells ? 'Dumbbell Floor Press' : weightedVest ? 'Weighted Vest Push-Up' : 'Incline Push-Up',
    row: dumbbells ? 'One-Arm Dumbbell Row' : weightedBackpack ? 'Backpack Row' : bands ? 'Band Row' : 'Towel Isometric Row',
    press: dumbbells ? 'Seated Dumbbell Press' : bands ? 'Band Overhead Press' : 'Incline Pike Press',
    pull: pullup ? 'Assisted Pull-Up' : bands ? 'Band Lat Pulldown' : 'Prone Lat Sweep',
    carry: dumbbells ? 'Suitcase Carry' : weightedBackpack ? 'Loaded Backpack Carry' : weightedVest ? 'Weighted Vest March' : 'March in Place',
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

function gymSessions(phase: 'transition' | 'main', count: TrainingSessionsPerWeek): SessionSpec[] {
  const main = phase === 'main'
  const sets = main ? 3 : 2
  const warmup = 'Five minutes easy cardio, then two gradual practice sets for the first loaded movement.'
  const fullBody: SessionSpec[] = [
    {
      name: 'Full Body A', type: 'upper', minutes: main ? 52 : 38, warmup,
      exercises: [
        { name: 'Leg Press', sets, reps: [8, 12], rest: 105, increment: 5 },
        { name: 'Machine Chest Press', sets, reps: [8, 12], rest: 90, increment: 2.5, workGroupKey: main ? undefined : 'upper-pair', workGroupPosition: 1 },
        { name: 'Seated Cable Row', sets, reps: [8, 12], rest: 90, increment: 2.5, workGroupKey: main ? undefined : 'upper-pair', workGroupPosition: 2 },
        { name: 'Seated Leg Curl', sets, reps: [10, 15], rest: 75, increment: 2.5 },
        { name: 'Pallof Press', sets: 2, reps: [8, 12], perSide: true, rest: 45 },
      ],
    },
    {
      name: 'Full Body B', type: 'legs_b', minutes: main ? 54 : 40, warmup,
      exercises: [
        { name: 'Dumbbell Romanian Deadlift', sets, reps: [8, 12], rest: 105, increment: 2.5 },
        { name: 'Lat Pulldown', sets, reps: [8, 12], rest: 90, increment: 2.5, workGroupKey: main ? undefined : 'upper-pair', workGroupPosition: 1 },
        { name: 'Machine Shoulder Press', sets, reps: [8, 12], rest: 90, increment: 2.5, workGroupKey: main ? undefined : 'upper-pair', workGroupPosition: 2 },
        { name: 'Supported Split Squat', sets, reps: [8, 10], perSide: true, rest: 90, increment: 2.5 },
        { name: 'Farmer Carry', sets: 3, reps: [30, 45], unit: 'seconds', rest: 60, increment: 2.5 },
      ],
    },
    {
      name: 'Full Body C', type: 'upper', minutes: main ? 52 : 38, warmup,
      exercises: [
        { name: 'Hack Squat', sets, reps: [8, 12], rest: 105, increment: 5 },
        { name: 'Incline Dumbbell Press', sets, reps: [8, 12], rest: 90, increment: 2.5, workGroupKey: main ? undefined : 'upper-pair', workGroupPosition: 1 },
        { name: 'Chest-Supported Row', sets, reps: [8, 12], rest: 90, increment: 2.5, workGroupKey: main ? undefined : 'upper-pair', workGroupPosition: 2 },
        { name: 'Cable Lateral Raise', sets: 2, reps: [12, 18], rest: 45, increment: 1 },
        { name: 'Dead Bug', sets: 2, reps: [8, 12], perSide: true, rest: 45 },
      ],
    },
  ]
  if (count < 4) return fullBody.slice(0, count)
  const split: SessionSpec[] = [
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
  const capacity: SessionSpec = {
    name: 'Capacity & Core', type: 'fix', minutes: main ? 38 : 28, warmup,
    exercises: [fullBody[1].exercises[1], fullBody[2].exercises[4], fullBody[1].exercises[4]],
  }
  if (count === 5) return [...split, capacity]
  if (count >= 6) {
    return [
      capHardSets(split[0]),
      capHardSets(split[1]),
      mobilityAndCoreSession(),
      capHardSets(split[2]),
      capHardSets(split[3]),
      capHardSets(capacity),
      recoverySession(),
    ].slice(0, count)
  }
  return split
}

function homeSessions(
  phase: 'transition' | 'main',
  count: TrainingSessionsPerWeek,
  equipment: string[],
  venueLabel: string,
): SessionSpec[] {
  const main = phase === 'main'
  const sets = main ? 3 : 2
  const names = homeExerciseNames(equipment)
  const warmup = 'Five minutes of pain-free joint preparation, then one easy practice set.'
  const fullBody: SessionSpec[] = [
    {
      name: `${venueLabel} Full Body A`, type: 'upper', minutes: main ? 44 : 30, warmup,
      exercises: [
        { name: names.squat, sets, reps: [8, 12], rest: 90, increment: 2 },
        { name: names.push, sets, reps: [8, 15], rest: 75, increment: 2, workGroupKey: main ? undefined : 'upper-pair', workGroupPosition: 1 },
        { name: names.row, sets, reps: [8, 15], perSide: names.row.includes('One-Arm'), rest: 75, increment: 2, workGroupKey: main ? undefined : 'upper-pair', workGroupPosition: 2 },
        { name: 'Dead Bug', sets: 2, reps: [8, 12], perSide: true, rest: 30 },
        { name: names.carry, sets: 3, reps: [30, 45], unit: 'seconds', perSide: true, rest: 45, increment: 2 },
      ],
    },
    {
      name: `${venueLabel} Full Body B`, type: 'legs_b', minutes: main ? 46 : 32, warmup,
      exercises: [
        { name: names.hinge, sets, reps: [8, 12], rest: 90, increment: 2 },
        { name: names.press, sets, reps: [8, 12], rest: 75, increment: 2, workGroupKey: main ? undefined : 'upper-pair', workGroupPosition: 1 },
        { name: names.pull, sets, reps: [6, 12], rest: 90, increment: 1, workGroupKey: main ? undefined : 'upper-pair', workGroupPosition: 2 },
        { name: 'Supported Reverse Lunge', sets: 2, reps: [8, 10], perSide: true, rest: 75 },
        { name: 'Side Plank', sets: 2, reps: [20, 35], unit: 'seconds', perSide: true, rest: 30 },
      ],
    },
    {
      name: `${venueLabel} Full Body C`, type: 'upper', minutes: main ? 44 : 30, warmup,
      exercises: [
        { name: 'Step-Up', sets, reps: [8, 12], perSide: true, rest: 75, increment: 2 },
        { name: names.push, sets, reps: [8, 15], rest: 75, increment: 2, workGroupKey: main ? undefined : 'upper-pair', workGroupPosition: 1 },
        { name: names.row, sets, reps: [8, 15], perSide: names.row.includes('One-Arm'), rest: 75, increment: 2, workGroupKey: main ? undefined : 'upper-pair', workGroupPosition: 2 },
        { name: 'Hip Thrust', sets, reps: [10, 15], rest: 75, increment: 2 },
        { name: 'Bird-Dog', sets: 2, reps: [6, 10], perSide: true, rest: 30 },
      ],
    },
  ]
  if (count < 4) return fullBody.slice(0, count)
  const split: SessionSpec[] = [
    { ...fullBody[0], name: `${venueLabel} Upper A`, type: 'upper', exercises: fullBody[0].exercises.slice(1) },
    { ...fullBody[0], name: `${venueLabel} Lower A`, type: 'legs_a', exercises: [fullBody[0].exercises[0], fullBody[1].exercises[0], fullBody[1].exercises[3], fullBody[0].exercises[3]] },
    { ...fullBody[2], name: `${venueLabel} Upper B`, type: 'upper', exercises: [fullBody[2].exercises[1], fullBody[2].exercises[2], withoutWorkGroup(fullBody[1].exercises[1]), fullBody[2].exercises[4]] },
    { ...fullBody[1], name: `${venueLabel} Lower B`, type: 'legs_b', exercises: [fullBody[2].exercises[0], fullBody[2].exercises[3], fullBody[1].exercises[0], fullBody[1].exercises[4]] },
  ]
  const capacity: SessionSpec = {
    ...fullBody[0],
    name: `${venueLabel} Capacity & Core`,
    type: 'fix',
    minutes: main ? 34 : 24,
    exercises: [fullBody[0].exercises[4], fullBody[1].exercises[4], fullBody[2].exercises[4]],
  }
  if (count === 5) return [...split, capacity]
  if (count >= 6) {
    const prefix = `${venueLabel} `
    return [
      capHardSets(split[0]),
      capHardSets(split[1]),
      mobilityAndCoreSession(prefix),
      capHardSets(split[2]),
      capHardSets(split[3]),
      capHardSets(capacity),
      recoverySession(prefix),
    ].slice(0, count)
  }
  return split
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

function weekdaysFor(count: TrainingSessionsPerWeek): number[] {
  if (count === 2) return [1, 4]
  if (count === 3) return [1, 3, 5]
  if (count === 4) return [1, 2, 4, 6]
  if (count === 5) return [1, 2, 4, 5, 7]
  return Array.from({ length: count }, (_, index) => index + 1)
}

export interface GeneratedTrainingPlan {
  programs: Program[]
  program_days: ProgramDay[]
  exercises: Exercise[]
  induction: TrainingInductionProfile
}

type TrainingAddons = Settings['addons']

const ARCHIVED_DAY_IDS_KEY = 'training_induction_archived_day_ids' as const
const PROTECTED_ORIGINAL_DAY_IDS_KEY = 'training_induction_protected_original_day_ids' as const
const PENDING_DAY_IDS_KEY = 'training_induction_pending_day_ids' as const
const GENERATION_REVISION_KEY = 'training_induction_generation_revision' as const

function sortedIds(ids: Iterable<string>): string[] {
  return [...new Set(ids)].sort()
}

function claimedDayIds(induction: unknown): string[] {
  const raw = jsonRecord(induction)
  return raw ? [...stringArray(raw.transition_day_ids), ...stringArray(raw.main_day_ids)] : []
}

export function archivedTrainingDayIds(addons: TrainingAddons | null | undefined): Set<string> {
  return new Set(stringArray(addons?.[ARCHIVED_DAY_IDS_KEY]))
}

export function pendingTrainingDayIds(addons: TrainingAddons | null | undefined): Set<string> {
  return new Set(stringArray(addons?.[PENDING_DAY_IDS_KEY]))
}

function storedProtectedOriginalDayIds(addons: TrainingAddons | null | undefined): Set<string> {
  return new Set(stringArray(addons?.[PROTECTED_ORIGINAL_DAY_IDS_KEY]))
}

function ownerSuppliedOriginalDayIds(userId: string): Set<string> {
  const ids: Record<string, string[]> = {
    '9a0fffbc-bb02-40ac-834a-d4e339b32574': [
      '11111111-0000-4000-8000-000000000052',
      '11111111-0000-4000-8000-000000000062',
      '11111111-0000-4000-8000-000000000069',
      '11111111-0000-4000-8000-000000000077',
      '52429d97-dea9-49af-b4bc-f678ad447417',
      '11111111-0000-4000-8000-000000000095',
      '11111111-0000-4000-8000-000000000102',
    ],
    'f1cc8158-0480-47c9-a2f1-bd03890182f9': [
      '7e4651e2-59cf-4ef4-b89b-7a451a8c220b',
      '411f4f19-12bf-41ec-aec1-229fe8712603',
      '1cb7f1d2-ce9d-4c51-b33b-43a6be21e3a0',
      'c0612b35-da03-4b4d-8410-16e570bc71c9',
      '59a496e3-3cda-4d73-806a-b940eace1878',
      '808d17fa-4b8f-4550-8e9c-1379e0fc677d',
      'fa9ea127-023a-4e10-b48d-5eed854deacc',
    ],
  }
  return new Set(ids[userId] ?? [])
}

function generatedDayIdCandidates(userId: string, throughRevision: number): Set<string> {
  const candidates = new Set<string>()
  for (let revision = 0; revision <= throughRevision; revision += 1) {
    const suffix = revision > 0 ? `:generation:${revision}` : ''
    for (const slug of ['transition', 'main'] as const) {
      for (let weekday = 1; weekday <= 7; weekday += 1) {
        candidates.add(stableUuid(userId, `${slug}:day:${weekday}${suffix}`))
      }
    }
  }
  return candidates
}

function protectedOriginalDayIds(data: AppData, userId: string): Set<string> {
  const presentOwnedIds = new Set(data.program_days
    .filter((day) => day.user_id === userId)
    .map((day) => day.id))
  const protectedIds = new Set([...storedProtectedOriginalDayIds(data.settings?.addons)]
    .filter((id) => presentOwnedIds.has(id)))
  for (const id of ownerSuppliedOriginalDayIds(userId)) {
    if (presentOwnedIds.has(id)) protectedIds.add(id)
  }
  return protectedIds
}

function inferredOriginalDayIds(data: AppData, userId: string): Set<string> {
  const addons = data.settings?.addons
  const explicit = ownerSuppliedOriginalDayIds(userId)
  const pending = pendingTrainingDayIds(addons)
  const throughRevision = Math.max(
    trainingGenerationRevision(addons),
    profileGenerationRevision(addons?.training_induction),
  ) + 1
  const generated = generatedDayIdCandidates(userId, throughRevision)
  return new Set(data.program_days
    .filter((day) => (
      day.user_id === userId
      && !pending.has(day.id)
      && (!generated.has(day.id) || explicit.has(day.id))
    ))
    .map((day) => day.id))
}

export function protectOriginalTrainingProgrammeAddons(data: AppData): TrainingAddons | null {
  const settings = data.settings
  const userId = data.profile?.user_id ?? settings?.user_id
  if (!settings || !userId) return null
  const protectedIds = sortedIds([
    ...protectedOriginalDayIds(data, userId),
    ...inferredOriginalDayIds(data, userId),
  ])
  if (protectedIds.length === 0) return settings.addons
  return { ...settings.addons, [PROTECTED_ORIGINAL_DAY_IDS_KEY]: protectedIds }
}

export function repairProtectedOriginalTrainingProgrammeAddons(data: AppData): TrainingAddons | null {
  const settings = data.settings
  const userId = data.profile?.user_id ?? settings?.user_id
  if (!settings || !userId) return null
  const protectedAddons = protectOriginalTrainingProgrammeAddons(data) ?? settings.addons
  const protectedIds = protectedOriginalDayIds(
    { ...data, settings: { ...settings, addons: protectedAddons } },
    userId,
  )
  const repairedArchive = sortedIds([...archivedTrainingDayIds(protectedAddons)]
    .filter((id) => !protectedIds.has(id)))
  const currentArchive = sortedIds(archivedTrainingDayIds(settings.addons))
  const currentProtected = sortedIds(storedProtectedOriginalDayIds(settings.addons))
  const nextProtected = sortedIds(storedProtectedOriginalDayIds(protectedAddons))
  if (
    JSON.stringify(currentArchive) === JSON.stringify(repairedArchive)
    && JSON.stringify(currentProtected) === JSON.stringify(nextProtected)
  ) return null
  const repaired = { ...protectedAddons }
  if (repairedArchive.length > 0) repaired[ARCHIVED_DAY_IDS_KEY] = repairedArchive
  else delete repaired[ARCHIVED_DAY_IDS_KEY]
  return repaired
}

export function canRestoreOriginalTrainingProgramme(data: AppData): boolean {
  const settings = data.settings
  const userId = data.profile?.user_id ?? settings?.user_id
  if (!settings || !userId) return false
  return protectedOriginalDayIds(data, userId).size > 0
    || claimedDayIds(settings.addons.training_induction).length > 0
    || pendingTrainingDayIds(settings.addons).size > 0
}

export function trainingGenerationRevision(addons: TrainingAddons | null | undefined): number {
  const value = addons?.[GENERATION_REVISION_KEY]
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, Math.trunc(value)) : 0
}

export function invalidateTrainingPlanAddons(
  addons: TrainingAddons,
  additionalDayIds: Iterable<string> = [],
): TrainingAddons {
  const active = claimedDayIds(addons.training_induction)
  const additional = [...additionalDayIds]
  const hasMarker = Object.prototype.hasOwnProperty.call(addons, 'training_induction')
  const activeRevision = profileGenerationRevision(addons.training_induction)
  const revision = hasMarker || additional.length > 0
    ? Math.max(trainingGenerationRevision(addons), activeRevision) + 1
    : trainingGenerationRevision(addons)
  const protectedIds = storedProtectedOriginalDayIds(addons)
  return {
    ...addons,
    newbie_mode: false,
    training_induction: null,
    [ARCHIVED_DAY_IDS_KEY]: sortedIds([
      ...archivedTrainingDayIds(addons),
      ...active,
      ...additional,
    ].filter((id) => !protectedIds.has(id))),
    [GENERATION_REVISION_KEY]: revision,
  }
}

export function markPendingTrainingPlanAddons(
  addons: TrainingAddons,
  plan: GeneratedTrainingPlan,
): TrainingAddons {
  const nextPending = plan.program_days.map((day) => day.id)
  const nextPendingSet = new Set(nextPending)
  const stalePending = [...pendingTrainingDayIds(addons)].filter((id) => !nextPendingSet.has(id))
  return {
    ...addons,
    [ARCHIVED_DAY_IDS_KEY]: sortedIds([...archivedTrainingDayIds(addons), ...stalePending]),
    [PENDING_DAY_IDS_KEY]: sortedIds(nextPending),
    [GENERATION_REVISION_KEY]: plan.induction.generation_revision ?? 0,
  }
}

export function commitTrainingPlanAddons(
  addons: TrainingAddons,
  plan: GeneratedTrainingPlan,
): TrainingAddons {
  const committed = { ...addons }
  delete committed[PENDING_DAY_IDS_KEY]
  delete committed.training_induction_skipped
  return {
    ...committed,
    newbie_mode: true,
    training_induction: plan.induction,
    [GENERATION_REVISION_KEY]: plan.induction.generation_revision ?? 0,
  }
}

function legacyGeneratedDayIds(data: AppData, userId: string): string[] {
  const candidates = new Set<string>()
  for (const slug of ['transition', 'main'] as const) {
    for (let weekday = 1; weekday <= 7; weekday += 1) {
      candidates.add(stableUuid(userId, `${slug}:day:${weekday}`))
    }
  }
  const archived = archivedTrainingDayIds(data.settings?.addons)
  const protectedIds = protectedOriginalDayIds(data, userId)
  return data.program_days
    .filter((day) => day.user_id === userId && candidates.has(day.id) && !archived.has(day.id) && !protectedIds.has(day.id))
    .map((day) => day.id)
}

export function restoreTrainingPlanAddons(data: AppData): TrainingAddons | null {
  const settings = data.settings
  if (!settings) return null
  const addons = protectOriginalTrainingProgrammeAddons(data) ?? settings.addons
  const userId = data.profile?.user_id ?? settings.user_id
  const protectedIds = protectedOriginalDayIds(
    { ...data, settings: { ...settings, addons } },
    userId,
  )
  const active = claimedDayIds(addons.training_induction)
  const pending = [...pendingTrainingDayIds(addons)]
  const legacy = legacyGeneratedDayIds(data, userId)
  const hasObjectMarker = jsonRecord(addons.training_induction) != null
  const removesGeneratedPlan = Boolean(addons.newbie_mode || hasObjectMarker || active.length || pending.length || legacy.length)
  if (!removesGeneratedPlan && protectedIds.size === 0) return null

  const restored = { ...addons }
  delete restored[PENDING_DAY_IDS_KEY]
  return {
    ...restored,
    newbie_mode: false,
    training_induction: null,
    [ARCHIVED_DAY_IDS_KEY]: sortedIds([
      ...archivedTrainingDayIds(addons),
      ...active,
      ...pending,
      ...legacy,
    ].filter((id) => !protectedIds.has(id))),
    [GENERATION_REVISION_KEY]: Math.max(
      trainingGenerationRevision(addons),
      profileGenerationRevision(addons.training_induction),
    ) + (removesGeneratedPlan ? 1 : 0),
  }
}

export function activeTrainingProgramDays(data: AppData): ProgramDay[] {
  const userId = data.profile?.user_id ?? data.settings?.user_id
  if (!userId) return []
  const archived = archivedTrainingDayIds(data.settings?.addons)
  const pending = pendingTrainingDayIds(data.settings?.addons)
  const protectedIds = protectedOriginalDayIds(data, userId)
  return data.program_days.filter((day) =>
    day.user_id === userId
      && day.is_active !== false
      && (!archived.has(day.id) || protectedIds.has(day.id))
      && !pending.has(day.id))
}

export function generateTrainingPlan(
  userId: string,
  input: TrainingInductionInput,
  existingPrograms: Program[] = [],
  completedAt = new Date().toISOString(),
  generationRevision = 0,
): GeneratedTrainingPlan {
  const rawInput = jsonRecord(input)
  input = trainingInputFromProfile(
    input,
    typeof rawInput?.start_date === 'string'
      ? rawInput.start_date
      : new Date().toISOString().slice(0, 10),
  )
  const assessment = assessTrainingInput(input)
  const count = assessment.sessions_per_week
  const planWeeks = input.plan_weeks
  const transitionWeeks = Math.min(12, planWeeks)
  const mainStart = addDaysIso(input.start_date, transitionWeeks * 7)
  const endDate = addDaysIso(input.start_date, planWeeks * 7)
  const programFor = (slug: 'transition' | 'main'): Program => {
    const generatedId = stableUuid(userId, `program:${slug}`)
    const existing = existingPrograms.find((program) => program.user_id === userId && program.slug === slug)
    if (existing && existing.id !== generatedId) return existing
    const venue = input.venue === 'gym' ? 'Gym' : input.venue === 'outdoors' ? 'Outdoor' : 'Home'
    return {
      id: generatedId,
      user_id: userId,
      slug,
      name: slug === 'transition' ? `${transitionWeeks}-Week ${venue} Foundation` : `Personal ${venue} Main Phase`,
      description: slug === 'transition'
        ? transitionWeeks === 4
          ? 'Weeks 1-4 restore consistency. A simple schedule built from your answers.'
          : transitionWeeks === 8
            ? 'Weeks 1-4 restore, weeks 5-8 build. A simple schedule built from your answers.'
            : 'Weeks 1-4 restore, weeks 5-8 build, weeks 9-12 progress. A simple schedule built from your answers.'
        : 'Your follow-on strength and muscle phase, using the same equipment, recovery limits and weekly rhythm.',
    }
  }
  const programs = [programFor('transition'), programFor('main')]
  /* Deliberately not inferred from the questionnaire. Whether somebody wants
   * to be paced through a session or to track it themselves is a preference,
   * not a conclusion to be drawn from their layoff length or their goal, and
   * guessing it makes the behaviour unpredictable. Every generated day is
   * offered both ways, equally, at the point of starting one. */
  const sessionMode: SessionMode = 'guided'
  const revisionSuffix = generationRevision > 0 ? `:generation:${generationRevision}` : ''
  const venueLabel = input.venue === 'gym' ? 'Gym' : input.venue === 'outdoors' ? 'Outdoor' : 'Home'

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
        : homeSessions(phase, count, input.equipment, venueLabel)
    const weekdays = weekdaysFor(count)
    sessions.forEach((session, sessionIndex) => {
      const weekday = weekdays[sessionIndex]
      const dayId = stableUuid(userId, `${slug}:day:${weekday}${revisionSuffix}`)
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
        session_mode: sessionMode,
      })
      /* A generated plan is followed along with, so its pacing has to come
       * from the movement rather than from one number per template. Anyone
       * training under caution is timed like a rebuild block regardless of
       * the goal they picked, because that is what the caution is for. */
      const followAlong = (spec: ExerciseSpec) => {
        const intent: TrainingIntent = assessment.caution === 'standard'
          ? GOAL_INTENT[input.goal]
          : 'rebuild'
        const fields = followAlongFields(spec.name, intent, {
          rest_sec: spec.rest ?? 60,
          per_side: spec.perSide ?? false,
          increment_kg: spec.increment ?? 0,
        })
        return {
          movement_id: fields.movement_id,
          per_side: fields.per_side,
          rest_sec: fields.rest_sec,
          tempo_up_s: fields.tempo_up_s,
          tempo_down_s: fields.tempo_down_s,
          tempo_pause_s: fields.tempo_pause_s,
          tempo_note: fields.tempo_note,
        }
      }

      const addExercise = (spec: ExerciseSpec, index: number, lite: boolean): void => {
        const sets = Math.max(1, (spec.sets ?? 2) - (lite ? 1 : 0))
        exercises.push({
          id: stableUuid(userId, `${slug}:day:${weekday}:${lite ? 'lite' : 'full'}:${index}${revisionSuffix}`),
          user_id: userId,
          program_day_id: dayId,
          name: spec.name,
          work_group_id: spec.workGroupKey
            ? stableUuid(userId, `${slug}:day:${weekday}:work-group:${spec.workGroupKey}${revisionSuffix}`)
            : null,
          work_group_position: spec.workGroupKey ? (spec.workGroupPosition ?? null) : null,
          sets,
          rep_min: spec.reps[0],
          rep_max: spec.reps[1],
          rep_unit: spec.unit ?? 'reps',
          ...followAlong(spec),
          notes: spec.notes ?? (assessment.caution === 'cautious' ? 'Pain-free range. Stop with at least 3 reps in reserve.' : 'Progress only after every rep is controlled.'),
          increment_kg: spec.increment ?? 0,
          is_lite: lite,
          optional: spec.optional ?? false,
          sort_order: index,
        })
      }
      session.exercises.forEach((exercise, index) => addExercise(exercise, index, false))
      session.exercises.slice(0, 3).forEach((exercise, index) => addExercise(exercise, index, true))

      const dayExercises = exercises.filter((e) => e.program_day_id === dayId && !e.is_lite)
      const dayIndex = program_days.findIndex((d) => d.id === dayId)
      if (dayIndex >= 0 && dayExercises.length > 0) {
        program_days[dayIndex] = {
          ...program_days[dayIndex],
          est_minutes: Math.max(1, Math.round(
            estimateSessionSeconds(dayExercises, 180) / 60)),
        }
      }
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
      generation_revision: generationRevision,
      completed_at: completedAt,
      start_date: input.start_date,
      main_start_date: mainStart,
      end_date: endDate,
      plan_weeks: planWeeks,
      transition_weeks: transitionWeeks,
      inactivity: input.inactivity,
      venue: input.venue,
      equipment: [...input.equipment],
      pain_areas: [...input.pain_areas],
      recent_operation: input.recent_operation,
      chronic_lower_back_pain: input.chronic_lower_back_pain,
      acute_symptoms: input.acute_symptoms === true,
      sessions_per_week: count,
      goal: input.goal,
      caution: assessment.caution,
      weekly_load_strategy: count >= 7
        ? 'distributed_with_recovery'
        : count >= 6
          ? 'distributed'
          : 'standard',
      ...(input.available_minutes != null && input.available_minutes >= 15 && input.available_minutes <= 180
        ? { available_minutes: Math.trunc(input.available_minutes) }
        : {}),
      ...(input.baseline_assessment ? { baseline_assessment: input.baseline_assessment } : {}),
      ...(count >= 6 ? { hard_set_cap: 2 } : {}),
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
  const raw = jsonRecord(induction)
  return new Set(stringArray(raw?.[slug === 'transition' ? 'transition_day_ids' : 'main_day_ids']))
}

export function isInsideInductionWindow(
  induction: TrainingInductionProfile | null | undefined,
  slug: ProgramSlug,
  dateIso: string,
): boolean {
  if (!induction || (slug !== 'transition' && slug !== 'main')) return true
  const raw = jsonRecord(induction)
  const start = raw?.start_date
  const mainStart = raw?.main_start_date
  if (typeof start !== 'string' || typeof mainStart !== 'string') return false
  const end = raw?.end_date
  if (typeof end === 'string' && dateIso >= end) return false
  if (slug === 'transition') return dateIso >= start && dateIso < mainStart
  return dateIso >= mainStart && (typeof end !== 'string' || dateIso < end)
}

export function inductionWeek(induction: TrainingInductionProfile, dateIso: string): number {
  const start = new Date(`${induction.start_date}T12:00:00Z`).getTime()
  const date = new Date(`${dateIso}T12:00:00Z`).getTime()
  return Math.floor((date - start) / 604_800_000) + 1
}
