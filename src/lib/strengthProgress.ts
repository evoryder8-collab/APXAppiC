import type { AppData, JointCheckin, RepUnit } from './types'
import pushUpGuide from '../../shared/push-up-load-guide.json' with { type: 'json' }
import frequencyFamilies from '../../shared/exercise-frequency-families.json' with { type: 'json' }
import { MOVEMENTS } from '../data/movements.ts'
import { catalogExerciseByName } from '../data/exerciseCatalog.ts'
import { descriptorForExercise, isValidExerciseFacts } from './exerciseLogging.ts'
import { parseTreadmillLog } from './manualWorkout.ts'

export type JointRegion = 'arms' | 'core' | 'legs'
export type DeloadState = 'clear' | 'watch' | 'regional_deload' | 'whole_deload' | 'stop_and_review'

export interface StrengthPoint {
  sessionId: string
  date: string
  topWeight: number
  topSetName?: string
  topReps: number | null
  estimated1rm: number
  volume: number
  setWeights: Record<number, number>
}

export interface ExerciseStrengthSeries {
  key: string
  exerciseId: string | null
  name: string
  points: StrengthPoint[]
}

export type StrengthRegion = 'lower' | 'upper' | 'core' | 'other'

export interface RecordedWork {
  sets: number
  recordedReps: number | null
  liftedKg: number | null
  loadedReps: number
  missingReps: boolean
  missingVolume: boolean
}

function emptyWork(): RecordedWork {
  return { sets: 0, recordedReps: null, liftedKg: null, loadedReps: 0, missingReps: false, missingVolume: false }
}

function accumulateWork(total: RecordedWork, work: RecordedWork) {
  total.sets += work.sets
  if (work.recordedReps != null) total.recordedReps = (total.recordedReps ?? 0) + work.recordedReps
  if (work.liftedKg != null) total.liftedKg = (total.liftedKg ?? 0) + work.liftedKg
  total.loadedReps += work.loadedReps
  total.missingReps ||= work.missingReps
  total.missingVolume ||= work.missingVolume
}

export function totalRecordedWork(rows: ReadonlyArray<{ work: RecordedWork }>): RecordedWork {
  const total = emptyWork()
  for (const row of rows) accumulateWork(total, row.work)
  return total
}

interface SessionWork {
  sessionId: string
  date: string
  work: RecordedWork
}

export interface RankedExerciseHistory extends ExerciseStrengthSeries {
  sessions: SessionWork[]
  region: StrengthRegion
  work: RecordedWork
  sessionCount: number
  lastPerformedDate: string
}

export interface ExerciseFrequencyFamily {
  key: string
  name: string
  region: StrengthRegion
  work: RecordedWork
  sessionCount: number
  lastPerformedDate: string
  variants: RankedExerciseHistory[]
  sessions: SessionWork[]
}

export function exerciseChartTitle(family: { key?: string; name: string }, name: string, translate: (text: string) => string) {
  const variant = translate(name)
  const title = family.key?.startsWith('family:') ? translate(family.name) : variant
  const equipmentLabels: Record<string, string> = { dumbbell: 'With Dumbbells', barbell: 'With a Barbell', kettlebell: 'With a Kettlebell' }
  const equipment = name.trim().match(/^(?:weighted )?(dumbbell|barbell|kettlebell) (.+)$/i)
  if (family.key?.startsWith('family:') && equipment && [family.name.toLowerCase(), family.name.toLowerCase() + 's'].includes(equipment[2].toLowerCase())) {
    return { title, subtitle: translate(equipmentLabels[equipment[1].toLowerCase()]) }
  }
  const folded = variant.trim().toLocaleLowerCase()
  const familyName = title.trim().toLocaleLowerCase()
  if (folded === familyName) return { title, subtitle: '' }
  for (const suffix of [' ' + familyName, ' ' + familyName + 's']) {
    if (folded.endsWith(suffix)) return { title, subtitle: variant.trim().slice(0, -suffix.length).trim() }
  }
  return { title, subtitle: variant }
}

const familyByMovement = new Map(frequencyFamilies.flatMap(family => family.movementIDs.map(id => [id, family] as const)))
const familyAlias = (name: string) => name.toLowerCase().replace(/[^a-z0-9]/g, '')
const equivalentMovementByLabel = new Map(frequencyFamilies.flatMap(family =>
  Object.entries(family.equivalentLabels ?? {}).flatMap(([id, labels]) => labels.map(label => [label.toLowerCase(), id] as const))))
const familyByAlias = new Map(frequencyFamilies.flatMap(family => family.aliases.map(name => [familyAlias(name), family] as const)))

function frequencyOrder(a: Pick<RankedExerciseHistory, 'key' | 'name' | 'sessionCount' | 'lastPerformedDate'>, b: typeof a) {
  return b.sessionCount - a.sessionCount || b.lastPerformedDate.localeCompare(a.lastPerformedDate)
    || a.name.localeCompare(b.name, 'en') || a.key.localeCompare(b.key, 'en')
}

export interface SessionStrengthInsight {
  key: string
  name: string
  current: StrengthPoint
  previous: StrengthPoint | null
  reference: StrengthPoint | null
  daysCompared: number | null
  loadDelta: number | null
  estimated1rmDelta: number | null
}

export interface JointAssessment {
  state: DeloadState
  affected: JointRegion[]
  average: number
  highest: number
  rising: JointRegion[]
}

const movementsById = new Map(MOVEMENTS.map((movement) => [movement.id, movement]))
const lowerMuscles = new Set(['adductors', 'ankle_stabilisers', 'calves', 'foot_intrinsics', 'glute_medius', 'glutes', 'hamstrings', 'hip_flexors', 'hips', 'quadriceps', 'soleus', 'tibialis'])
const upperMuscles = new Set(['biceps', 'chest', 'deep_neck_flexors', 'forearms', 'front_delts', 'lats', 'lower_traps', 'mid_traps', 'neck', 'rear_delts', 'rotator_cuff', 'side_delts', 'traps', 'triceps', 'upper_back'])
const coreMuscles = new Set(['core', 'erectors', 'obliques', 'spinal_erectors'])

function strengthRegion(primary = ''): StrengthRegion {
  if (lowerMuscles.has(primary)) return 'lower'
  if (upperMuscles.has(primary)) return 'upper'
  if (coreMuscles.has(primary)) return 'core'
  return 'other'
}

const levelPushUps = new Set(pushUpGuide.floorNames.map(familyAlias))
const alternativePushUps = new Set(pushUpGuide.floorReferenceNames.map(familyAlias))
const elevatedPushUps = new Set(pushUpGuide.feetElevatedNames.map(familyAlias))
const narrowPushUps = new Set(pushUpGuide.narrowGripNames.map(familyAlias))

export type PushUpSetup = 'floor' | 'alternative' | 'elevated' | 'narrow'
function pushUpSetup(name: string, movementID: string | null | undefined): PushUpSetup | undefined {
  const label = familyAlias(name)
  if (narrowPushUps.has(label) && (!movementID || pushUpGuide.narrowGripMovementIDs.includes(movementID))) return 'narrow'
  if (elevatedPushUps.has(label) && (!movementID || pushUpGuide.feetElevatedMovementIDs.includes(movementID))) return 'elevated'
  if (movementID && !pushUpGuide.floorMovementIDs.includes(movementID)) return
  if (alternativePushUps.has(label)) return 'alternative'
  if (levelPushUps.has(label)) return 'floor'
}

function historyMovement(name: string, movementId: string | null) {
  const equivalentId = equivalentMovementByLabel.get(name.trim().toLowerCase().replace(/\s+/g, ' '))
  let descriptor = descriptorForExercise({ name, movement_id: movementId ?? equivalentId })
  if (!descriptor.movementId) {
    const catalog = catalogExerciseByName(name)
    if (catalog) descriptor = descriptorForExercise({ name, movement_id: catalog.movementID })
  }
  const movement = movementsById.get(descriptor.movementId ?? '')
  const bandEquipment = movement?.equipment.includes('bands') === true
  const bandLabel = /\b(?:bands?|banded)\b/i.test(name)
  const equipmentWords = name.toLowerCase().replace(/\bdbs?\b/g, 'dumbbell')
    .replace(/\bbbs?\b/g, 'barbell').replace(/\bkbs?\b/g, 'kettlebell')
    .match(/\b(?:barbell|dumbbell|kettlebell|cable|machine|backpack|smith)s?\b/g) ?? []
  const canonicalEquipment = movement && `${movement.name} ${movement.id}`.toLowerCase()
  const differentEquipment = canonicalEquipment && equipmentWords.some((word) => !canonicalEquipment.includes(word.replace(/s$/, '')))
  // The training catalogue also uses substitute IDs, e.g. Barbell Curl maps to Dumbbell Curl.
  const explicitFamily = familyByAlias.get(familyAlias(name))
  const movementFamily = familyByMovement.get(descriptor.movementId ?? '')
  const substitute = explicitFamily && movementFamily && explicitFamily !== movementFamily
  const composite = /[+\/]|\bor\b/i.test(name)
  const key = descriptor.movementId && !substitute && !composite && !differentEquipment && (!bandLabel || bandEquipment)
    ? `movement:${descriptor.movementId.toLowerCase()}`
    : `name:${name.toLowerCase().replace(/\s+/g, ' ')}`
  // Composite programme slots can refer to just their first movement in the catalogue.
  const family = explicitFamily ?? (composite ? undefined : movementFamily)
  const region = family?.region
  const hasRepField = descriptor.fields.includes('reps') && (!movement || movement.repUnit === 'reps')
  const pushSetup = pushUpSetup(name, movementId)
  const sameExternalLoad = !composite || pushSetup === 'narrow' || ['hip_thrust', 'biceps_curl', 'calf_raise'].includes(explicitFamily?.id ?? '')
    || (explicitFamily?.id === 'push_up' && movementId === 'weighted_push_up')
  const assisted = /\b(?:assisted|counterweight(?:ed)?)\b/i.test(`${name} ${movement?.id.replaceAll('_', ' ') ?? ''}`)
  const bodyweight = descriptor.kind === 'bodyweight' || (family?.id === 'push_up' && !descriptor.movementId)
  const measuresExternalWeight = sameExternalLoad && !substitute && !assisted && !bandLabel && !bandEquipment
  return {
    descriptor, key, family, hasRepField, bodyweight, measuresExternalWeight, entityType: movement?.entityType,
    pushUpSetup: pushSetup,
    displayName: movement && movement.id === equivalentId ? movement.name : name,
    catalogUnit: movement?.repUnit,
    region: region === 'lower' || region === 'upper' || region === 'core' || region === 'other'
      ? region : strengthRegion(movement?.primaryMuscles[0]),
    comparableLoad: descriptor.kind === 'strength' && !bodyweight && measuresExternalWeight,
  }
}

function daysBetween(earlier: string, later: string): number {
  return Math.max(0, Math.round((Date.parse(`${later}T12:00:00Z`) - Date.parse(`${earlier}T12:00:00Z`)) / 86_400_000))
}

export function distinctInsightTexts(lines: string[], limit = 3): string[] {
  if (limit <= 0) return []
  return [...new Set(lines)].slice(0, limit)
}

export function estimatedOneRepMax(weight: number, reps: number | null): number {
  if (!Number.isFinite(weight) || weight <= 0) return 0
  if (reps == null || reps <= 1) return Math.round(weight * 10) / 10
  /* Epley is intentionally capped at 15 reps; higher-rep sets are poor
     maximal-strength estimators and should not create spectacular fake gains. */
  const boundedReps = Math.min(15, reps)
  return Math.round(weight * (1 + boundedReps / 30) * 10) / 10
}

type WorkoutHistoryInput = Pick<AppData, 'workout_sessions' | 'workout_logs' | 'exercises'> & {
  profile?: { user_id: string } | null
  settings?: { user_id: string } | null
}

export function* performedWorkoutObservations(data: WorkoutHistoryInput, range?: { from: string; to: string }) {
  const owner = data.profile?.user_id ?? data.settings?.user_id
  if (!owner) return
  const sessions = new Map(data.workout_sessions
    .filter((session) => session.user_id === owner && session.completed
      && (!range || (session.date >= range.from && session.date <= range.to)))
    .map((session) => [session.id, session]))
  const ownedExercises = data.exercises.filter(exercise => exercise.user_id === owner)
  const prescribedUnits = new Map(ownedExercises.map(exercise => [exercise.id, exercise.rep_unit]))
  const unitsByName = new Map<string, RepUnit | 'ambiguous'>()
  for (const exercise of ownedExercises) {
    const key = exercise.name.trim().toLowerCase()
    const previous = unitsByName.get(key)
    unitsByName.set(key, previous && previous !== exercise.rep_unit ? 'ambiguous' : exercise.rep_unit)
  }
  const movements = new Map<string, ReturnType<typeof historyMovement>>()
  const seen = new Set<string>()
  for (const log of data.workout_logs) {
    const session = sessions.get(log.session_id)
    if (!session || log.user_id !== owner || log.skipped || seen.has(log.id)) continue
    seen.add(log.id)
    const treadmill = parseTreadmillLog(log.exercise_name)
    const name = (treadmill?.name ?? log.exercise_name).trim()
    if (!name) continue
    const lookup = JSON.stringify([log.movement_id ?? null, name])
    const movement = movements.get(lookup) ?? historyMovement(name, log.movement_id ?? null)
    movements.set(lookup, movement)
    const normalized = name.toLowerCase()
    const unit = prescribedUnits.get(log.exercise_id ?? '') ?? unitsByName.get(normalized)
    // Programme revisions used both checkmarks and minutes for Focus T25 episodes.
    const episode = normalized.startsWith('focus t25 · ') || normalized === 'focust25 session (shaun t), alpha or beta cycle'
      || normalized === 'any 10-min hiit video' || normalized === 'functional stretch flow (saved youtube favorite)'
    const repBased = !episode && !treadmill && movement.hasRepField && (!unit || unit === 'reps' || unit === 'max')
    const weight = log.weight_kg
    const loaded = repBased && movement.comparableLoad && weight != null && Number.isFinite(weight) && weight > 0
    const reps = log.reps != null && Number.isFinite(log.reps) && log.reps > 0 ? log.reps : null
    const kind = movement.descriptor.kind
    const timed = unit === 'seconds' || unit === 'minutes'
      || ((!unit || unit === 'max') && kind === 'isometric' && movement.catalogUnit === 'seconds')
    // Early players stored the completed quantity in reps, including seconds and checkmarks.
    const historicalQuantity = episode || unit === 'check' || (timed && (kind === 'strength' || kind === 'bodyweight' || kind === 'isometric'))
    const quantity = log.duration_seconds ?? reps
    const performed = historicalQuantity ? quantity != null && Number.isFinite(quantity) && quantity > 0 : isValidExerciseFacts({
      weight, reps, rir: log.rir, contacts: log.contacts, rounds: log.rounds,
      workSeconds: log.work_seconds, recoverySeconds: log.recovery_seconds,
      durationSeconds: log.duration_seconds ?? (treadmill && treadmill.metrics.durationMin * 60),
      distanceMeters: log.distance_meters ?? (treadmill && treadmill.metrics.distanceKm * 1_000),
    }, movement.descriptor)
    // Old strength receipts sometimes recorded a working load without reps.
    if (!performed && !(loaded && log.reps == null)) continue

    yield { session, log, movement, name: movement.displayName, loadedWeight: loaded ? weight : null, reps, repBased }
  }
}

export function buildExerciseFamilies(data: WorkoutHistoryInput, range?: { from: string; to: string }): ExerciseFrequencyFamily[] {
  const sessionTimes = new Map<string, number>()
  function sessionOrder(a: Pick<SessionWork, 'sessionId' | 'date'>, b: typeof a) {
    return a.date.localeCompare(b.date)
      || (sessionTimes.get(a.sessionId) ?? 0) - (sessionTimes.get(b.sessionId) ?? 0)
      || a.sessionId.localeCompare(b.sessionId)
  }
  const groups = new Map<string, {
    family: (typeof frequencyFamilies)[number] | undefined
    history: Omit<RankedExerciseHistory, 'sessionCount' | 'points' | 'sessions'>
    performed: Map<string, SessionWork>
    points: Map<string, StrengthPoint>
  }>()

  for (const { session, log, movement, name, loadedWeight, reps, repBased } of performedWorkoutObservations(data, range)) {
    const group = groups.get(movement.key) ?? {
      family: movement.family,
      history: {
        key: movement.key, exerciseId: log.exercise_id, name, region: movement.region,
        lastPerformedDate: session.date, work: emptyWork(),
      },
      performed: new Map<string, SessionWork>(), points: new Map<string, StrengthPoint>(),
    }
    groups.set(movement.key, group)
    sessionTimes.set(session.id, Date.parse(session.started_at ?? session.completed_at ?? '') || 0)
    const sessionWork = group.performed.get(session.id) ?? { sessionId: session.id, date: session.date, work: emptyWork() }
    group.performed.set(session.id, sessionWork)
    if (session.date > group.history.lastPerformedDate
      || (session.date === group.history.lastPerformedDate && name.localeCompare(group.history.name, 'en') < 0)) {
      group.history.lastPerformedDate = session.date
      group.history.name = name
      group.history.exerciseId = log.exercise_id
    }

    const setWork = emptyWork()
    setWork.sets = 1
    if (repBased) {
      const weight = log.weight_kg
      const measured = movement.measuresExternalWeight && weight != null && Number.isFinite(weight) && weight > 0
      const missingWeight = (weight == null || !Number.isFinite(weight)) && !movement.bodyweight
      setWork.recordedReps = reps
      setWork.liftedKg = measured && reps != null ? weight * reps : null
      setWork.loadedReps = measured ? reps ?? 0 : 0
      setWork.missingReps = reps == null
      setWork.missingVolume = movement.measuresExternalWeight && (missingWeight || (measured && reps == null))
    }
    accumulateWork(group.history.work, setWork)
    accumulateWork(sessionWork.work, setWork)
    if (loadedWeight == null) continue
    const weight = loadedWeight
    const point = group.points.get(session.id) ?? {
      sessionId: session.id, date: session.date, topWeight: 0, topReps: null,
      estimated1rm: 0, volume: 0, setWeights: {},
    }
    if (weight > point.topWeight || (weight === point.topWeight && (reps ?? 0) > (point.topReps ?? 0))) {
      point.topWeight = weight
      point.topSetName = name
      point.topReps = reps
    }
    point.estimated1rm = Math.max(point.estimated1rm, estimatedOneRepMax(weight, reps))
    point.volume += weight * (reps ?? 0)
    point.setWeights[log.set_no] = weight
    group.points.set(session.id, point)
  }

  const families = new Map<string, { row: ExerciseFrequencyFamily; sessions: Map<string, SessionWork> }>()
  for (const { history, performed, points, family } of groups.values()) {
    const variant = {
      ...history, sessionCount: performed.size, sessions: [...performed.values()].sort(sessionOrder),
      points: [...points.values()].sort(sessionOrder),
    }
    const key = family ? `family:${family.id}` : variant.key
    const entry = families.get(key) ?? {
      row: { key, name: family?.name ?? variant.name, region: variant.region,
        lastPerformedDate: variant.lastPerformedDate, sessionCount: 0, work: emptyWork(), variants: [], sessions: [] },
      sessions: new Map<string, SessionWork>(),
    }
    for (const [id, observation] of performed) {
      const previous = entry.sessions.get(id)
      if (previous) accumulateWork(previous.work, observation.work)
      else entry.sessions.set(id, { ...observation, work: { ...observation.work } })
    }
    entry.row.sessionCount = entry.sessions.size
    accumulateWork(entry.row.work, variant.work)
    entry.row.variants.push(variant)
    if (variant.lastPerformedDate > entry.row.lastPerformedDate) entry.row.lastPerformedDate = variant.lastPerformedDate
    families.set(key, entry)
  }
  return [...families.values()].map(({ row, sessions }) => {
    row.sessions = [...sessions.values()].sort(sessionOrder)
    row.variants.sort(frequencyOrder)
    return row
  }).sort(frequencyOrder)
}

export function buildStrengthSeries(data: AppData): RankedExerciseHistory[] {
  return buildExerciseFamilies(data).flatMap((family) => family.variants.filter((variant) => variant.points.length > 0))
}

export function sessionStrengthInsights(data: AppData, sessionId: string): SessionStrengthInsight[] {
  const currentSession = data.workout_sessions.find((session) => session.id === sessionId)
  if (!currentSession) return []

  return buildStrengthSeries(data).flatMap((series) => {
    const current = series.points.find((point) => point.sessionId === sessionId)
    if (!current) return []
    const prior = series.points.filter((point) => point.date < currentSession.date)
    const previous = prior.at(-1) ?? null
    /* Prefer a meaningful 30-90 day comparison. If history is newer, the
       earliest prior point is still more honest than fabricating a horizon. */
    const inNinetyDays = prior.filter((point) => daysBetween(point.date, currentSession.date) <= 90)
    const reference = inNinetyDays[0] ?? previous
    return [{
      key: series.key,
      name: series.name,
      current,
      previous,
      reference,
      daysCompared: reference ? daysBetween(reference.date, currentSession.date) : null,
      loadDelta: reference ? Math.round((current.topWeight - reference.topWeight) * 10) / 10 : null,
      estimated1rmDelta: reference ? Math.round((current.estimated1rm - reference.estimated1rm) * 10) / 10 : null,
    }]
  }).sort((a, b) => (b.loadDelta ?? -Infinity) - (a.loadDelta ?? -Infinity))
}

export function assessJointCheckin(current: JointCheckin, previous?: JointCheckin | null): JointAssessment {
  const regions: JointRegion[] = ['arms', 'core', 'legs']
  const scores = regions.map((region) => current[region])
  const affected = regions.filter((region) => current[region] >= 5)
  const rising = previous
    ? regions.filter((region) => current[region] - previous[region] >= 2)
    : []
  const highest = Math.max(...scores)
  const average = Math.round((scores.reduce((sum, score) => sum + score, 0) / scores.length) * 10) / 10
  const severe = regions.filter((region) => current[region] >= 9)
  const high = regions.filter((region) => current[region] >= 7)
  const elevated = regions.filter((region) => current[region] >= 6)

  let state: DeloadState = 'clear'
  if (severe.length > 0) state = 'stop_and_review'
  else if (high.length >= 2 || elevated.length >= 2 || average >= 7) state = 'whole_deload'
  else if (high.length === 1) state = 'regional_deload'
  else if (affected.length > 0 || rising.length > 0) state = 'watch'

  return { state, affected: severe.length > 0 ? severe : affected, average, highest, rising }
}

export function checkinDue(checkins: JointCheckin[], today: string, intervalDays = 7): boolean {
  const latest = [...checkins].sort((a, b) => b.date.localeCompare(a.date))[0]
  return !latest || daysBetween(latest.date, today) >= intervalDays
}
