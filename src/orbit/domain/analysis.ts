import { geographicDistanceM, pointAtDistance, polylineDistanceM } from './geo.ts'
import type {
  OrbitRoute,
  OrbitRun,
  PersonalSegment,
  RouteDna,
  RunMission,
  RunSplit,
  SegmentEffort,
  TrackSample,
} from './types.ts'

export interface MissionExecution {
  state: 'matched' | 'partly_matched' | 'harder_than_planned' | 'insufficient_data'
  headline: string
  details: string[]
}

export interface RunDebriefAnalysis {
  mission: MissionExecution
  pace_stability_pct: number | null
  split_classification: 'negative' | 'even' | 'positive' | 'insufficient_data'
  cardiac_drift_pct: number | null
  final_third_change_pct: number | null
  training_load: number | null
  recovery_cost: 'low' | 'moderate' | 'high' | null
  facts: string[]
}

function mean(values: number[]): number | null {
  return values.length > 0 ? values.reduce((sum, value) => sum + value, 0) / values.length : null
}

function standardDeviation(values: number[]): number | null {
  const average = mean(values)
  if (average == null || values.length < 2) return null
  return Math.sqrt(values.reduce((sum, value) => sum + (value - average) ** 2, 0) / values.length)
}

export function paceStabilityPct(splits: RunSplit[]): number | null {
  const paces = splits.filter((split) => split.distance_m >= 900).map((split) => split.pace_sec_km)
  const average = mean(paces)
  const deviation = standardDeviation(paces)
  if (average == null || deviation == null || average <= 0) return null
  return Math.round((deviation / average) * 10_000) / 100
}

export function classifySplits(splits: RunSplit[]): 'negative' | 'even' | 'positive' | 'insufficient_data' {
  const paces = splits.filter((split) => split.distance_m >= 900).map((split) => split.pace_sec_km)
  if (paces.length < 4) return 'insufficient_data'
  const midpoint = Math.floor(paces.length / 2)
  const first = mean(paces.slice(0, midpoint))!
  const second = mean(paces.slice(-midpoint))!
  const change = (second - first) / first
  if (change <= -0.02) return 'negative'
  if (change >= 0.02) return 'positive'
  return 'even'
}

export function cardiacDriftPct(samples: TrackSample[]): number | null {
  const valid = samples.filter((sample) => sample.heart_rate_bpm != null)
  if (valid.length < 20 || valid.at(-1)!.recorded_at - valid[0].recorded_at < 30 * 60 * 1000) return null
  const midpoint = Math.floor(valid.length / 2)
  const halves = [valid.slice(0, midpoint), valid.slice(-midpoint)]
  const efficiency = halves.map((half) => {
    const distanceM = polylineDistanceM(half)
    const durationS = (half.at(-1)!.recorded_at - half[0].recorded_at) / 1000
    const speedMps = durationS > 0 ? distanceM / durationS : 0
    const heartRate = mean(half.map((sample) => sample.heart_rate_bpm!)) ?? 0
    return heartRate > 0 ? speedMps / heartRate : 0
  })
  if (efficiency[0] <= 0 || efficiency[1] <= 0) return null
  return Math.round(((efficiency[0] - efficiency[1]) / efficiency[0]) * 1000) / 10
}

export function finalThirdChangePct(splits: RunSplit[]): number | null {
  const paces = splits.filter((split) => split.distance_m >= 900).map((split) => split.pace_sec_km)
  if (paces.length < 3) return null
  const third = Math.max(1, Math.floor(paces.length / 3))
  const first = mean(paces.slice(0, third))!
  const final = mean(paces.slice(-third))!
  return Math.round(((final - first) / first) * 1000) / 10
}

function missionExecution(run: OrbitRun, stability: number | null): MissionExecution {
  const effort = run.check_in.perceived_effort
  const easyMission = ['recovery', 'easy', 'aerobic_base', 'run_walk'].includes(run.mission)
  const hardMission = ['tempo', 'threshold', 'intervals', 'hills', 'marathon_pace', 'performance_test'].includes(run.mission)
  if (run.metrics.distance_m < 500 || run.metrics.moving_s < 300) {
    return { state: 'insufficient_data', headline: 'Not enough recorded movement for a reliable mission assessment.', details: [] }
  }
  if (easyMission && effort != null && effort >= 7) {
    return {
      state: 'harder_than_planned',
      headline: 'This run was harder than the selected mission.',
      details: ['APEX will protect the next demanding session rather than treating extra effort as automatically better.'],
    }
  }
  if (run.mission === 'recovery' && effort != null && effort <= 4) {
    return { state: 'matched', headline: 'The run stayed appropriately controlled for recovery.', details: [] }
  }
  if (hardMission && effort != null && effort <= 4) {
    return { state: 'partly_matched', headline: 'The session was controlled, but the intended quality stimulus may have been incomplete.', details: [] }
  }
  if (stability != null && stability <= 6) {
    return { state: 'matched', headline: 'Pacing remained controlled and matched the selected mission well.', details: [] }
  }
  return { state: 'partly_matched', headline: 'The useful work was completed, with some pacing variation to refine next time.', details: [] }
}

export function analyzeRun(run: OrbitRun): RunDebriefAnalysis {
  const stability = paceStabilityPct(run.metrics.splits)
  const split = classifySplits(run.metrics.splits)
  const drift = cardiacDriftPct(run.samples)
  const finalThird = finalThirdChangePct(run.metrics.splits)
  const effort = run.check_in.perceived_effort
  const trainingLoad = effort != null ? Math.round(run.metrics.moving_s / 60 * effort) : null
  const recoveryCost = effort == null
    ? null
    : effort >= 8 || run.metrics.moving_s >= 120 * 60
      ? 'high'
      : effort >= 5 || run.metrics.moving_s >= 60 * 60
        ? 'moderate'
        : 'low'
  const facts: string[] = []
  if (split === 'negative') facts.push('The second half was faster than the first half.')
  if (split === 'positive') facts.push('The second half was slower than the first half.')
  if (split === 'even') facts.push('The two halves were paced evenly.')
  if (drift != null) facts.push(`Aerobic decoupling was approximately ${Math.abs(drift).toFixed(1)}%.`)
  if (finalThird != null && finalThird <= -2) facts.push('The final third was stronger than the opening third.')
  if (finalThird != null && finalThird >= 4) facts.push('The final third faded relative to the opening third.')
  return {
    mission: missionExecution(run, stability),
    pace_stability_pct: stability,
    split_classification: split,
    cardiac_drift_pct: drift,
    final_third_change_pct: finalThird,
    training_load: trainingLoad,
    recovery_cost: recoveryCost,
    facts,
  }
}

function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b)
  const midpoint = Math.floor(sorted.length / 2)
  return sorted.length % 2 === 0 ? (sorted[midpoint - 1] + sorted[midpoint]) / 2 : sorted[midpoint]
}

export function buildRouteDna(route: OrbitRoute, runs: OrbitRun[]): RouteDna | null {
  const matches = runs.filter((run) => run.route_id === route.id && run.status === 'completed')
  if (matches.length < 2) return null
  const paces = matches.map((run) => run.metrics.avg_pace_sec_km).filter((value): value is number => value != null)
  const heartRates = matches.map((run) => run.metrics.heart_rate_avg).filter((value): value is number => value != null)
  const elevations = matches.map((run) => run.metrics.elevation_gain_m).filter((value): value is number => value != null)
  const controlled = matches
    .filter((run) => (run.check_in.perceived_effort ?? 10) <= 6 && run.metrics.avg_pace_sec_km != null)
    .sort((a, b) => a.metrics.avg_pace_sec_km! - b.metrics.avg_pace_sec_km!)
  const recent = [...matches].sort((a, b) => b.started_at.localeCompare(a.started_at)).slice(0, 3)
  const earlier = [...matches].sort((a, b) => a.started_at.localeCompare(b.started_at)).slice(0, 3)
  const recentPace = mean(recent.map((run) => run.metrics.avg_pace_sec_km).filter((value): value is number => value != null))
  const earlierPace = mean(earlier.map((run) => run.metrics.avg_pace_sec_km).filter((value): value is number => value != null))
  let recentTrend = 'Not enough comparable pace data yet.'
  if (recentPace != null && earlierPace != null && matches.length >= 3) {
    const delta = (recentPace - earlierPace) / earlierPace
    recentTrend = delta < -0.02 ? 'Recent controlled attempts are faster.' : delta > 0.02 ? 'Recent attempts are slower or more demanding.' : 'Recent performance is stable.'
  }
  let interpretation = 'Repeated runs are building a useful private baseline.'
  const firstHr = earlier.map((run) => run.metrics.heart_rate_avg).filter((value): value is number => value != null)
  const recentHr = recent.map((run) => run.metrics.heart_rate_avg).filter((value): value is number => value != null)
  if (recentPace != null && earlierPace != null && mean(recentHr) != null && mean(firstHr) != null) {
    if (recentPace < earlierPace * 0.98 && mean(recentHr)! <= mean(firstHr)! * 1.02) interpretation = 'Faster at a similar heart rate, suggesting improved efficiency.'
    else if (Math.abs(recentPace - earlierPace) / earlierPace < 0.02 && mean(recentHr)! < mean(firstHr)! * 0.97) interpretation = 'Similar pace at a lower heart rate, suggesting improved efficiency.'
    else if (recentPace < earlierPace * 0.98 && mean(recentHr)! > mean(firstHr)! * 1.04) interpretation = 'Faster, but with clearly greater cardiovascular effort.'
  }
  return {
    route_id: route.id,
    completions: matches.length,
    typical_distance_m: Math.round(median(matches.map((run) => run.metrics.distance_m))),
    typical_elevation_gain_m: elevations.length > 0 ? Math.round(median(elevations)) : null,
    typical_duration_s: Math.round(median(matches.map((run) => run.metrics.moving_s))),
    typical_pace_sec_km: paces.length > 0 ? Math.round(median(paces)) : null,
    typical_heart_rate: heartRates.length > 0 ? Math.round(median(heartRates)) : null,
    pace_consistency_pct: paceStabilityPct(matches.flatMap((run) => run.metrics.splits)),
    best_controlled_run_id: controlled[0]?.id ?? null,
    recent_trend: recentTrend,
    interpretation,
  }
}

function sampleIndexNearDistance(samples: TrackSample[], targetM: number): number {
  const point = pointAtDistance(samples, targetM)
  return point ? samples.indexOf(point) : -1
}

export function segmentEffort(run: OrbitRun, segment: PersonalSegment): SegmentEffort | null {
  const startIndex = sampleIndexNearDistance(run.samples, segment.start_distance_m)
  const endIndex = sampleIndexNearDistance(run.samples, segment.end_distance_m)
  if (startIndex < 0 || endIndex <= startIndex) return null
  const samples = run.samples.slice(startIndex, endIndex + 1)
  const distanceM = samples.reduce((total, sample, index) => index === 0 ? 0 : total + geographicDistanceM(samples[index - 1], sample), 0)
  const durationS = (samples.at(-1)!.recorded_at - samples[0].recorded_at) / 1000
  if (distanceM < 50 || durationS <= 0) return null
  const heartRates = samples.map((sample) => sample.heart_rate_bpm).filter((value): value is number => value != null)
  const cadence = samples.map((sample) => sample.cadence_spm).filter((value): value is number => value != null)
  const startElevation = samples[0].elevation_m
  const endElevation = samples.at(-1)!.elevation_m
  return {
    run_id: run.id,
    segment_id: segment.id,
    duration_s: Math.round(durationS),
    pace_sec_km: Math.round(durationS / (distanceM / 1000)),
    heart_rate_avg: heartRates.length > 0 ? Math.round(mean(heartRates)!) : null,
    cadence_avg: cadence.length > 0 ? Math.round(mean(cadence)!) : null,
    elevation_delta_m: startElevation != null && endElevation != null ? Math.round(endElevation - startElevation) : null,
  }
}

export function missionLabel(mission: RunMission): string {
  return mission.split('_').map((word) => word[0].toUpperCase() + word.slice(1)).join(' ')
}
