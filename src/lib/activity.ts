import type { ActivityLevel, ActivityLog, Goal, Profile } from './types'

export type ActivityInputStyle = 'count' | 'duration' | 'distance' | 'steps' | 'watch_kcal'
export type ActivitySource = 'manual' | 'workout_module' | 'event_prefill'
export type ActivityCategory = 'therapy' | 'camera' | 'work' | 'life' | 'training' | 'device'

export interface ActivityType {
  id: string
  category: ActivityCategory
  name: string
  shortName: string
  icon: string
  met: number
  inputStyle: ActivityInputStyle
  defaultDurationMin: number | null
  isTrainingLinked: boolean
  notes: string
  distanceFactor?: number
  supportsWatch?: boolean
}

export interface ActivityBlock {
  id: string
  typeId: string
  quantity: number
  durationMin: number | null
  distanceKm: number | null
  steps: number | null
  watchKcal: number | null
  source: ActivitySource
  reconciled: boolean
}

export interface ActivityPreset {
  label: string
  typeId: string
  patch: Partial<ActivityBlock>
}

export interface ActivityEstimate {
  bmr: number
  floorKcal: number
  rawBlockKcal: number
  adjustedBlockKcal: number
  tdee: number
  pal: number
  level: ActivityLevel
  targetKcal: number
  safetyFloorKcal: number
  safetyClamped: boolean
  proteinG: number
  fatG: number
  carbsG: number
  calibrationK: number
}

export interface CalibrationDay {
  date: string
  intakeKcal: number | null
  morningWeightKg: number | null
  predictedTdee: number | null
}

export interface CalibrationResult {
  eligible: boolean
  previousK: number
  nextK: number
  observedTdee: number | null
  predictedTdee: number | null
  weightChangePerWeekKg: number | null
}

export const ACTIVITY_CATEGORIES: Array<{ id: ActivityCategory; label: string }> = [
  { id: 'therapy', label: 'Hands-on therapy' },
  { id: 'camera', label: 'Camera work' },
  { id: 'work', label: 'General work' },
  { id: 'life', label: 'Errands and life' },
  { id: 'training', label: 'Training' },
  { id: 'device', label: 'Device import' },
]

/* This is the app fallback for the shared database catalog. The production
   migration will seed the same stable ids once, with authenticated read-only
   access for normal users. No entry contains a user-specific body value. */
export const ACTIVITY_CATALOG: ActivityType[] = [
  {
    id: 'massage-session', category: 'therapy', name: 'Massage session given', shortName: 'Massage',
    icon: 'hands', met: 4, inputStyle: 'count', defaultDurationMin: 60, isTrainingLinked: false,
    notes: 'Choose the number of sessions and 30, 60, or 90 minutes each.',
  },
  {
    id: 'deep-tissue-massage', category: 'therapy', name: 'Sports or deep-tissue massage', shortName: 'Deep tissue',
    icon: 'hands', met: 4.5, inputStyle: 'count', defaultDurationMin: 60, isTrainingLinked: false,
    notes: 'Heavier hands-on work with more sustained force.',
  },
  {
    id: 'gimbal-filming', category: 'camera', name: 'Handheld or gimbal filming', shortName: 'Gimbal filming',
    icon: 'camera', met: 3.2, inputStyle: 'duration', defaultDurationMin: 240, isTrainingLinked: false,
    notes: 'Moving while filming with handheld or stabilized camera equipment.',
  },
  {
    id: 'tripod-shoot', category: 'camera', name: 'Static or tripod shoot', shortName: 'Tripod shoot',
    icon: 'tripod', met: 2.3, inputStyle: 'duration', defaultDurationMin: 120, isTrainingLinked: false,
    notes: 'Standing for a shoot with limited movement.',
  },
  {
    id: 'active-photo-shoot', category: 'camera', name: 'Active photo shoot', shortName: 'Photo shoot',
    icon: 'camera', met: 3, inputStyle: 'duration', defaultDurationMin: 120, isTrainingLinked: false,
    notes: 'Repositioning, crouching, and moving around the set.',
  },
  {
    id: 'event-rig-carry', category: 'camera', name: 'Event day rig carry', shortName: 'Rig carry',
    icon: 'case', met: 3.5, inputStyle: 'duration', defaultDurationMin: 120, isTrainingLinked: false,
    notes: 'Bags, rig handling, and moving between venues.',
  },
  {
    id: 'desk-editing', category: 'work', name: 'Desk or editing work', shortName: 'Desk work',
    icon: 'desk', met: 1.2, inputStyle: 'duration', defaultDurationMin: 240, isTrainingLinked: false,
    notes: 'Covered by the floor. Log it if useful for context, but it adds no calories.',
  },
  {
    id: 'standing-job', category: 'work', name: 'Standing job', shortName: 'Standing job',
    icon: 'stand', met: 2.2, inputStyle: 'duration', defaultDurationMin: 240, isTrainingLinked: false,
    notes: 'Retail, teaching, reception, or another mostly standing shift.',
  },
  {
    id: 'nurse-server-shift', category: 'work', name: 'Nurse or server shift', shortName: 'Walking shift',
    icon: 'walk', met: 3.3, inputStyle: 'duration', defaultDurationMin: 480, isTrainingLinked: false,
    notes: 'A shift with frequent walking and limited sitting.',
  },
  {
    id: 'manual-labor', category: 'work', name: 'Manual labor or construction', shortName: 'Manual labor',
    icon: 'hammer', met: 4.5, inputStyle: 'duration', defaultDurationMin: 240, isTrainingLinked: false,
    notes: 'Sustained lifting, carrying, digging, or construction work.',
  },
  {
    id: 'active-childcare', category: 'work', name: 'Active childcare or park play', shortName: 'Active childcare',
    icon: 'play', met: 3, inputStyle: 'duration', defaultDurationMin: 60, isTrainingLinked: false,
    notes: 'Playing, carrying, chasing, and moving with children.',
  },
  {
    id: 'supermarket-trip', category: 'life', name: 'Supermarket trip', shortName: 'Supermarket',
    icon: 'cart', met: 3, inputStyle: 'count', defaultDurationMin: 25, isTrainingLinked: false,
    notes: 'Walking the store and carrying groceries. Count 25 minutes per trip.',
  },
  {
    id: 'household-cleaning', category: 'life', name: 'Household cleaning', shortName: 'Cleaning',
    icon: 'home', met: 3, inputStyle: 'count', defaultDurationMin: 30, isTrainingLinked: false,
    notes: 'Count in 30-minute blocks.',
  },
  {
    id: 'casual-walk', category: 'life', name: 'Dog walk or casual walk', shortName: 'Casual walk',
    icon: 'walk', met: 3, inputStyle: 'duration', defaultDurationMin: 30, isTrainingLinked: false,
    notes: 'Use time when distance is not known.', supportsWatch: true,
  },
  {
    id: 'walking-distance', category: 'life', name: 'Walking distance', shortName: 'Walk distance',
    icon: 'route', met: 3, inputStyle: 'distance', defaultDurationMin: null, isTrainingLinked: false,
    notes: 'Uses 0.5 kcal per kilogram per kilometre.', distanceFactor: 0.5, supportsWatch: true,
  },
  {
    id: 'travel-day', category: 'life', name: 'Travel day on feet', shortName: 'Travel day',
    icon: 'case', met: 2.5, inputStyle: 'duration', defaultDurationMin: 120, isTrainingLinked: false,
    notes: 'Airport walking, queues, and luggage handling.',
  },
  {
    id: 'incidental-steps', category: 'life', name: 'Steps not already covered by the blocks above.', shortName: 'Incidental steps',
    icon: 'steps', met: 1.2, inputStyle: 'steps', defaultDurationMin: null, isTrainingLinked: false,
    notes: 'Use only steps that are not part of a logged run, walk, shift, or filming block.',
  },
  {
    id: 'apex-strength', category: 'training', name: 'APEX home strength session', shortName: 'APEX strength',
    icon: 'strength', met: 5, inputStyle: 'duration', defaultDurationMin: 20, isTrainingLinked: true,
    notes: 'Short home strength session, usually 15 to 20 minutes.', supportsWatch: true,
  },
  {
    id: 'full-gym', category: 'training', name: 'Full gym session', shortName: 'Full gym',
    icon: 'strength', met: 6, inputStyle: 'duration', defaultDurationMin: 60, isTrainingLinked: true,
    notes: 'A complete 45 to 60-minute resistance session.', supportsWatch: true,
  },
  {
    id: 'focus-hiit', category: 'training', name: 'FocusT25 or HIIT', shortName: 'HIIT 25',
    icon: 'bolt', met: 8.5, inputStyle: 'duration', defaultDurationMin: 25, isTrainingLinked: true,
    notes: 'High-intensity interval work.', supportsWatch: true,
  },
  {
    id: 'mobility', category: 'training', name: 'Mobility or stretch session', shortName: 'Mobility',
    icon: 'mobility', met: 2.5, inputStyle: 'duration', defaultDurationMin: 30, isTrainingLinked: true,
    notes: 'Focused mobility, stretching, or corrective work.',
  },
  {
    id: 'jog-run', category: 'training', name: 'Jog or run', shortName: 'Run',
    icon: 'run', met: 7, inputStyle: 'distance', defaultDurationMin: null, isTrainingLinked: true,
    notes: 'Uses 1 kcal per kilogram per kilometre, independent of pace.', distanceFactor: 1, supportsWatch: true,
  },
  {
    id: 'watch-kcal', category: 'device', name: 'My watch says', shortName: 'Watch cardio',
    icon: 'watch', met: 1.2, inputStyle: 'watch_kcal', defaultDurationMin: null, isTrainingLinked: false,
    notes: 'APEX counts 80% because wrist estimates often run high.',
  },
]

export const ACTIVITY_BY_ID = new Map(ACTIVITY_CATALOG.map((type) => [type.id, type]))

interface ActivityTypeRow {
  id: string
  category: string
  name: string
  icon: string
  met: number | string
  input_style: ActivityInputStyle
  default_duration_min: number | null
  is_training_linked: boolean
  notes: string
  distance_factor: number | string | null
  supports_watch: boolean
}

export function normalizeActivityType(row: ActivityTypeRow): ActivityType {
  const fallback = ACTIVITY_BY_ID.get(row.id)
  return {
    id: row.id,
    category: row.category as ActivityCategory,
    name: row.name,
    shortName: fallback?.shortName ?? row.name,
    icon: row.icon || fallback?.icon || 'walk',
    met: Number(row.met),
    inputStyle: row.input_style,
    defaultDurationMin: row.default_duration_min,
    isTrainingLinked: row.is_training_linked,
    notes: row.notes,
    distanceFactor: row.distance_factor == null ? fallback?.distanceFactor : Number(row.distance_factor),
    supportsWatch: row.supports_watch,
  }
}

export function activityCatalogMap(types: ActivityType[]): Map<string, ActivityType> {
  return new Map((types.length > 0 ? types : ACTIVITY_CATALOG).map((type) => [type.id, type]))
}

export const GOAL_FACTORS: Record<Goal, number> = {
  recomp: 0.89,
  maintain: 1,
  bulk: 1.07,
}

export const PAL_LABELS: Record<ActivityLevel, string> = {
  sedentary: 'Sedentary',
  light: 'Lightly active',
  moderate: 'Moderately active',
  very: 'Very active',
  extra: 'Extra active',
}

export const PAL_TONES: Record<ActivityLevel, { deep: string; bright: string; wash: string; glow: string }> = {
  sedentary: { deep: '#a16207', bright: '#d97706', wash: 'rgba(245,158,11,.11)', glow: 'rgba(245,158,11,.28)' },
  light: { deep: '#b45309', bright: '#f59e0b', wash: 'rgba(245,158,11,.14)', glow: 'rgba(245,158,11,.34)' },
  moderate: { deep: '#c2410c', bright: '#f97316', wash: 'rgba(249,115,22,.13)', glow: 'rgba(249,115,22,.34)' },
  very: { deep: '#c2410c', bright: '#ea580c', wash: 'rgba(234,88,12,.13)', glow: 'rgba(234,88,12,.36)' },
  extra: { deep: '#b91c1c', bright: '#ef4444', wash: 'rgba(239,68,68,.11)', glow: 'rgba(239,68,68,.34)' },
}

function ageOnDate(birthdate: string, at = new Date()): number {
  const birth = new Date(`${birthdate}T00:00:00`)
  let age = at.getFullYear() - birth.getFullYear()
  const month = at.getMonth() - birth.getMonth()
  if (month < 0 || (month === 0 && at.getDate() < birth.getDate())) age -= 1
  return age
}

export function activityBmr(profile: Pick<Profile, 'weight_kg' | 'height_cm' | 'birthdate' | 'sex' | 'body_fat_pct'>): number {
  if (Number.isFinite(profile.body_fat_pct) && profile.body_fat_pct > 0 && profile.body_fat_pct < 75) {
    const leanMassKg = profile.weight_kg * (1 - profile.body_fat_pct / 100)
    return 370 + 21.6 * leanMassKg
  }
  const mifflin = 10 * profile.weight_kg + 6.25 * profile.height_cm - 5 * ageOnDate(profile.birthdate)
  return mifflin + (profile.sex === 'male' ? 5 : -161)
}

export function activityLevelForPal(pal: number): ActivityLevel {
  if (pal < 1.4) return 'sedentary'
  if (pal < 1.55) return 'light'
  if (pal < 1.75) return 'moderate'
  if (pal < 2) return 'very'
  return 'extra'
}

export function emptyActivityBlock(type: ActivityType, id: string = crypto.randomUUID()): ActivityBlock {
  return {
    id,
    typeId: type.id,
    quantity: 1,
    durationMin: type.defaultDurationMin,
    distanceKm: type.inputStyle === 'distance' ? 5 : null,
    steps: type.inputStyle === 'steps' ? 5000 : null,
    watchKcal: type.inputStyle === 'watch_kcal' ? 300 : null,
    source: 'manual',
    reconciled: false,
  }
}

export function netKcalForBlock(block: ActivityBlock, weightKg: number, catalog = ACTIVITY_BY_ID): number {
  const type = catalog.get(block.typeId)
  if (!type || weightKg <= 0) return 0

  if (type.inputStyle === 'steps') {
    return Math.max(0, block.steps ?? 0) * 0.00055 * weightKg
  }

  const discountedWatch = Math.max(0, block.watchKcal ?? 0) * 0.8
  if (type.inputStyle === 'watch_kcal') return discountedWatch

  if (type.inputStyle === 'distance') {
    const distanceEstimate = Math.max(0, block.distanceKm ?? 0) * weightKg * (type.distanceFactor ?? 1)
    return Math.max(distanceEstimate, discountedWatch)
  }

  const quantity = type.inputStyle === 'count' ? Math.max(0, block.quantity) : 1
  const durationHours = Math.max(0, block.durationMin ?? 0) / 60
  const metEstimate = Math.max(0, type.met - 1.2) * weightKg * durationHours * quantity
  return type.supportsWatch ? Math.max(metEstimate, discountedWatch) : metEstimate
}

export function estimateActivityDay(
  profile: Pick<Profile, 'weight_kg' | 'height_cm' | 'birthdate' | 'sex' | 'body_fat_pct' | 'goal'> & { calibration_k?: number },
  blocks: ActivityBlock[],
  catalog = ACTIVITY_BY_ID,
): ActivityEstimate {
  const bmr = activityBmr(profile)
  const floorKcal = bmr * 1.2
  const rawBlockKcal = blocks.reduce((sum, block) => sum + netKcalForBlock(block, profile.weight_kg, catalog), 0)
  const calibrationK = Math.min(1.15, Math.max(0.85, profile.calibration_k ?? 1))
  const adjustedBlockKcal = rawBlockKcal * calibrationK
  const tdee = floorKcal + adjustedBlockKcal
  const pal = tdee / bmr
  const safetyFloorKcal = bmr * 1.05
  const proposedTarget = tdee * GOAL_FACTORS[profile.goal]
  const targetKcal = Math.max(safetyFloorKcal, proposedTarget)
  const proteinG = Math.round(profile.weight_kg * 2.2)
  const fatG = Math.round(profile.weight_kg * 0.7)
  const carbsG = Math.max(0, Math.round((targetKcal - proteinG * 4 - fatG * 9) / 4))

  return {
    bmr: Math.round(bmr),
    floorKcal: Math.round(floorKcal),
    rawBlockKcal: Math.round(rawBlockKcal),
    adjustedBlockKcal: Math.round(adjustedBlockKcal),
    tdee: Math.round(tdee),
    pal: Math.round(pal * 100) / 100,
    level: activityLevelForPal(pal),
    targetKcal: Math.round(targetKcal),
    safetyFloorKcal: Math.round(safetyFloorKcal),
    safetyClamped: proposedTarget < safetyFloorKcal,
    proteinG,
    fatG,
    carbsG,
    calibrationK,
  }
}

export function blockSummary(block: ActivityBlock, catalog = ACTIVITY_BY_ID): string {
  const type = catalog.get(block.typeId)
  if (!type) return ''
  if (type.inputStyle === 'count') return `${block.quantity} x ${block.durationMin ?? 0} min`
  if (type.inputStyle === 'duration') {
    const minutes = block.durationMin ?? 0
    return minutes >= 60 && minutes % 60 === 0 ? `${minutes / 60} h` : `${minutes} min`
  }
  if (type.inputStyle === 'distance') return `${block.distanceKm ?? 0} km`
  if (type.inputStyle === 'steps') return `${Math.round((block.steps ?? 0) / 100) / 10}k steps`
  return `${block.watchKcal ?? 0} watch kcal`
}

export function blockFromActivityLog(log: ActivityLog, catalog = ACTIVITY_BY_ID): ActivityBlock {
  const type = catalog.get(log.type_id)
  return {
    id: log.id,
    typeId: log.type_id,
    quantity: type?.inputStyle === 'steps' ? 1 : Number(log.quantity),
    durationMin: log.duration_min,
    distanceKm: log.distance_km == null ? null : Number(log.distance_km),
    steps: type?.inputStyle === 'steps' ? Number(log.quantity) : null,
    watchKcal: log.watch_kcal == null ? null : Number(log.watch_kcal),
    source: log.source,
    reconciled: log.reconciled,
  }
}

export function activityLogFromBlock(
  block: ActivityBlock,
  profile: Pick<Profile, 'user_id' | 'weight_kg'>,
  date: string,
  catalog = ACTIVITY_BY_ID,
  existing?: ActivityLog,
): ActivityLog {
  const type = catalog.get(block.typeId)
  const now = new Date().toISOString()
  return {
    id: block.id,
    user_id: profile.user_id,
    date,
    type_id: block.typeId,
    quantity: type?.inputStyle === 'steps' ? Math.max(0, block.steps ?? 0) : block.quantity,
    duration_min: block.durationMin,
    distance_km: block.distanceKm,
    watch_kcal: block.watchKcal,
    computed_kcal: Math.round(netKcalForBlock(block, profile.weight_kg, catalog)),
    source: block.source,
    reconciled: block.reconciled,
    created_at: existing?.created_at ?? now,
    updated_at: now,
  }
}

export function championshipPrefill(idFactory: () => string = () => crypto.randomUUID()): ActivityBlock[] {
  return [
    { ...emptyActivityBlock(ACTIVITY_BY_ID.get('gimbal-filming')!, idFactory()), durationMin: 480, source: 'event_prefill' },
    { ...emptyActivityBlock(ACTIVITY_BY_ID.get('travel-day')!, idFactory()), durationMin: 120, source: 'event_prefill' },
  ]
}

function ema(values: number[], span: number): number[] {
  if (values.length === 0) return []
  const alpha = 2 / (span + 1)
  const output = [values[0]]
  for (let index = 1; index < values.length; index += 1) {
    output.push(alpha * values[index] + (1 - alpha) * output[index - 1])
  }
  return output
}

export function calibrateActivityK(days: CalibrationDay[], currentK: number): CalibrationResult {
  const recent = [...days].sort((a, b) => a.date.localeCompare(b.date)).slice(-14)
  const complete = recent.filter(
    (day) => day.intakeKcal != null && day.morningWeightKg != null && day.predictedTdee != null,
  )
  const previousK = Math.min(1.15, Math.max(0.85, currentK))
  if (complete.length < 12) {
    return { eligible: false, previousK, nextK: previousK, observedTdee: null, predictedTdee: null, weightChangePerWeekKg: null }
  }

  const weights = ema(complete.map((day) => day.morningWeightKg!), 7)
  const elapsedDays = Math.max(1, complete.length - 1)
  const weightChangePerWeekKg = ((weights.at(-1)! - weights[0]) / elapsedDays) * 7
  const meanIntake = complete.reduce((sum, day) => sum + day.intakeKcal!, 0) / complete.length
  const predictedTdee = complete.reduce((sum, day) => sum + day.predictedTdee!, 0) / complete.length
  /* Positive weight change means intake exceeded expenditure, so the energy
     equivalent is subtracted from intake. Negative change raises observed TDEE. */
  const observedTdee = meanIntake - (7700 * weightChangePerWeekKg) / 7
  const nudged = previousK + 0.2 * ((observedTdee - predictedTdee) / predictedTdee)
  const nextK = Math.min(1.15, Math.max(0.85, nudged))

  return {
    eligible: true,
    previousK,
    nextK: Math.round(nextK * 10000) / 10000,
    observedTdee: Math.round(observedTdee),
    predictedTdee: Math.round(predictedTdee),
    weightChangePerWeekKg: Math.round(weightChangePerWeekKg * 1000) / 1000,
  }
}
