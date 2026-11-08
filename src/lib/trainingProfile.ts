import type { OrbitRun } from '../orbit/domain/types'
import { canonicalTrainingGoal } from './nutrition.ts'
import { ACTIVITY_KIND } from './healthImport.ts'
import type { AppData } from './types'
import { performedWorkoutObservations } from './strengthProgress.ts'
import { isAPEXWorkoutSourceBundle } from './wearableWorkoutLinking.ts'

type ProfileRun = Pick<OrbitRun, 'id' | 'user_id' | 'client_idempotency_key' | 'local_date' | 'started_at' | 'ended_at' | 'status'>
  & { metrics: Pick<OrbitRun['metrics'], 'distance_m'> }
type TrainingType = 'Resistance' | 'Cardio' | 'Mobility'
type Focus = 'Limited history' | 'Resistance-focused' | 'Running-focused' | 'Cardio-focused' | 'Mobility-focused' | 'Mixed training'
type Comparison = { name: string; reps: number; previous: number; recent: number }

export interface TrainingProfile {
  focus: Focus
  muscleGrowthGoal?: boolean
  workouts: number
  counts: Record<TrainingType, number>
  running: number
  medianReps: number | null
  comparison: Comparison | null
}

const dayMilliseconds = 86_400_000
const median = (values: number[]) => {
  if (!values.length) return null
  values.sort((a,b) => a - b)
  return (values[Math.floor((values.length - 1) / 2)] + values[Math.floor(values.length / 2)]) / 2
}

const runNames = new Set(['run', 'running', 'indoorrun', 'outdoorrun'])
const importModes = new Map<string, TrainingType>()
for (const [name, kind] of Object.entries(ACTIVITY_KIND)) {
  importModes.set(name.toLowerCase(), kind === 'strength' ? 'Resistance' : kind === 'endurance' ? 'Cardio' : 'Mobility')
}
for (const name of [...runNames, 'indoorwalk','outdoorwalk','walking','indoorcycling','outdoorcycling','indoorcycle','outdoorcycle','hiit','stairclimber']) importModes.set(name,'Cardio')
for (const name of ['barre','stretching','mobility']) importModes.set(name,'Mobility')
for (const name of ['strengthtraining','weighttraining']) importModes.set(name,'Resistance')

export function trainingProfile(data: AppData, runs: ProfileRun[], today: string): TrainingProfile {
  const owner = data.profile?.user_id ?? data.settings?.user_id
  const end = Date.parse(today + 'T12:00:00Z')
  const daysAgo = (days: number) => new Date(end - days * dayMilliseconds).toISOString().slice(0,10)
  const from = daysAgo(89)
  const split = daysAgo(44)
  const types = { Resistance: new Set<string>(), Cardio: new Set<string>(), Mobility: new Set<string>() }
  const running = new Set<string>()
  const recentReps = new Map<string, number>()
  const comparisons = new Map<string, {
    key: string; name: string; reps: number; previous: Map<string, number>; recent: Map<string, number>
  }>()
  for (const { session, name, movement, loadedWeight, repBased, reps } of performedWorkoutObservations(data, { from, to: today })) {
    const type = movement.entityType
    const receipt = 'session:' + session.id
    if (movement.descriptor.kind === 'cardio' || type === 'conditioning_complex') {
      types.Cardio.add(receipt)
      if (movement.descriptor.movementId === 'run_outdoor'
        || (movement.descriptor.movementId === 'treadmill' && /\brun(?:ning)?\b/i.test(name))) running.add(receipt)
      continue
    }
    if (type === 'mobility_drill' || type === 'yoga_pose' || type === 'balance_drill') {
      types.Mobility.add(receipt)
      continue
    }
    const supportedResistance = type === 'resistance_isometric' || (repBased && reps != null
      && (type === 'resistance_dynamic' || (!type && (movement.family != null || loadedWeight != null))))
    if (!supportedResistance) continue
    types.Resistance.add(receipt)
    if (!repBased || reps == null) continue
    const recent = session.date >= split
    if (recent) recentReps.set(receipt, (recentReps.get(receipt) ?? 0) + reps)
    if (loadedWeight == null || !movement.measuresExternalWeight) continue
    const key = JSON.stringify([movement.key, reps])
    const row = comparisons.get(key) ?? {
      name, key: movement.key, reps, previous: new Map<string, number>(), recent: new Map<string,number>(),
    }
    const period = recent ? row.recent : row.previous
    period.set(receipt, Math.max(period.get(receipt) ?? 0, loadedWeight))
    comparisons.set(key, row)
  }

  const ownedReceipts = new Map(data.workout_sessions.filter(s => s.user_id === owner && s.completed).map(s => [s.id,s]))
  const importedRuns = new Map<string, number[]>()
  const externalIDs = new Set<string>()
  const hidden = new Set(data.imported_activities.filter(a => a.user_id === owner && a.hidden_at).map(a => a.healthkit_workout_id || a.id))
  const imports = data.imported_activities.filter(a => a.user_id === owner && !hidden.has(a.healthkit_workout_id || a.id)
    && !isAPEXWorkoutSourceBundle(a.source_bundle_id) && Number.isFinite(a.duration_min) && a.duration_min > 0)
    .sort((a,b) => Number(Boolean(b.apex_workout_session_id)) - Number(Boolean(a.apex_workout_session_id)))
  for (const activity of imports) {
    const labels = [activity.workout_name_key,activity.activity].map(text =>
      (text ?? '').toLowerCase().replace(/^health\.workout\./, '').replace(/[^a-z]/g, ''))
    const label = labels.find(key => importModes.has(key))
    if (!label) continue
    const linked = activity.apex_workout_session_id ? ownedReceipts.get(activity.apex_workout_session_id) : undefined
    if (activity.apex_workout_session_id && !linked) continue
    const date = linked?.date ?? activity.date
    const id = activity.healthkit_workout_id || activity.id
    if (date < from || date > today || externalIDs.has(id)) continue
    externalIDs.add(id)
    const receipt = linked ? 'session:' + linked.id : 'external:' + id
    const kind = importModes.get(label)!
    types[kind].add(receipt)
    if (kind === 'Cardio' && runNames.has(label)) {
      running.add(receipt)
      const started = Date.parse(activity.started_at ?? '')
      if (Number.isFinite(started)) {
        const starts = importedRuns.get(activity.date) ?? []
        starts.push(started)
        importedRuns.set(activity.date, starts)
      }
    }
  }
  const orbitKeys = new Set<string>()
  for (const run of runs) {
    if (run.user_id !== owner || run.status !== 'completed' || run.local_date < from || run.local_date > today
      || !Number.isFinite(run.metrics.distance_m) || run.metrics.distance_m <= 0) continue
    const start = Date.parse(run.started_at)
    const key = run.client_idempotency_key || run.id
    if (!(Date.parse(run.ended_at) > start) || orbitKeys.has(key)) continue
    orbitKeys.add(key)
    if (importedRuns.get(run.local_date)?.some(time => Math.abs(time - start) <= 120_000)) continue
    const receipt = 'orbit:' + run.id
    running.add(receipt)
    types.Cardio.add(receipt)
  }

  const workouts = new Set([...types.Resistance,...types.Cardio,...types.Mobility]).size
  const counts = { Resistance:types.Resistance.size, Cardio:types.Cardio.size, Mobility:types.Mobility.size }
  const occurrences = counts.Resistance + counts.Cardio + counts.Mobility
  let focus: Focus = 'Limited history'
  if (workouts >= 3) {
    if (counts.Resistance >= occurrences * 0.6) focus = 'Resistance-focused'
    else if (running.size >= occurrences * 0.6) focus = 'Running-focused'
    else if (counts.Cardio >= occurrences * 0.6) focus = 'Cardio-focused'
    else if (counts.Mobility >= occurrences * 0.6) focus = 'Mobility-focused'
    else focus = 'Mixed training'
  }
  const best = [...comparisons.values()].filter(v => v.previous.size && v.recent.size)
    .sort((a,b) => (b.previous.size + b.recent.size) - (a.previous.size + a.recent.size)
      || a.key.localeCompare(b.key, 'en') || a.reps - b.reps)[0]
  const comparison = best ? { name:best.name, reps:best.reps,
    previous:median([...best.previous.values()])!, recent:median([...best.recent.values()])! } : null
  const addons = owner && data.settings?.user_id === owner ? data.settings.addons : undefined
  const goal = (addons?.training_induction ?? addons?.training_induction_baseline)?.goal
  return { focus, workouts, counts, running:running.size, medianReps:median([...recentReps.values()]), comparison,
    muscleGrowthGoal: canonicalTrainingGoal(goal) === 'muscle' }
}

export function athleteTitle(profile: TrainingProfile): string {
  switch (profile.focus) {
    case 'Resistance-focused': return profile.muscleGrowthGoal ? 'Bodybuilder' : 'Strength athlete'
    case 'Running-focused': return 'Runner'
    case 'Cardio-focused': return 'Endurance athlete'
    case 'Mobility-focused': return 'Mobility athlete'
    case 'Mixed training': return 'All-rounder'
    case 'Limited history': return 'Building your baseline'
  }
}

export function trainingProfileLines(profile: TrainingProfile, locale: string, t: (text: string) => string): string[] {
  const format = new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format
  const lines = [t('Classified workouts') + ' ' + format(profile.workouts) + ' · ' + t('Workouts per week') + ' ' + format(profile.workouts * 7 / 90)]
  const counts = Object.entries(profile.counts).filter(([,count]) => count > 0)
  if (counts.length) lines.push(counts.map(([label,count]) => t(label) + ' ' + format(count)).join(' · '))
  if (profile.running) lines.push(t('Running') + ' · ' + format(profile.running))
  if (counts.reduce((total,[,count]) => total + count,0) > profile.workouts) lines.push(t('Mixed workouts can count in more than one category.'))
  if (profile.workouts < 3) lines.push(t('A pattern needs at least three classified workouts.'))
  if (profile.medianReps != null) lines.push(t('Recent median reps per resistance session') + ' · ' + format(profile.medianReps))
  if (profile.comparison) {
    const { name, reps, previous, recent } = profile.comparison
    lines.push(t('Matched working load') + ' · ' + t(name) + ' × ' + format(reps))
    lines.push(t('Previous 45 days') + ' ' + format(previous) + ' kg · ' + t('Last 45 days') + ' ' + format(recent) + ' kg')
    lines.push(t('Median session-best load at the same rep count.'))
  }
  return lines
}
