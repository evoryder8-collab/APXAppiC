import type { MissionRecommendation, OrbitRun, RouteCandidate, RouteRequest, RunMission } from './types.ts'

export interface MissionContext {
  campaignMission?: RunMission | null
  campaignTitle?: string
  campaignDurationMin?: number
  lowerBodyYesterday: boolean
  lowerBodyToday: boolean
  lowerBodyTomorrow: boolean
  recoveryStable: boolean
  enduranceTrend: 'rising' | 'stable' | 'declining' | 'unknown'
  availableMinutes: number
  recentRuns: OrbitRun[]
}

export function recommendMission(context: MissionContext): MissionRecommendation {
  if (context.campaignMission) {
    return {
      mission: context.campaignMission,
      title: context.campaignTitle ?? 'Today’s campaign run',
      duration_min: context.campaignDurationMin ?? Math.min(45, context.availableMinutes),
      reason: 'This mission is the next prescription in your Marathon Campaign and already accounts for the surrounding training week.',
      confidence: 'high',
    }
  }
  if (context.lowerBodyYesterday || context.lowerBodyToday) {
    return {
      mission: 'recovery',
      title: 'Short recovery run',
      duration_min: Math.min(28, context.availableMinutes),
      reason: context.lowerBodyToday
        ? 'Today already contains lower-body strength work, so Orbit keeps the run short and controlled.'
        : 'Yesterday contained lower-body strength work, so Orbit protects recovery while preserving running rhythm.',
      confidence: 'high',
    }
  }
  if (context.enduranceTrend === 'declining' && context.recoveryStable) {
    return {
      mission: 'aerobic_base',
      title: 'Aerobic base run',
      duration_min: Math.min(42, context.availableMinutes),
      reason: 'Endurance has begun to decay while recovery remains stable, making controlled aerobic work the most useful stimulus today.',
      confidence: 'high',
    }
  }
  const lastSevenDays = context.recentRuns.filter((run) => Date.now() - new Date(run.started_at).getTime() <= 7 * 86_400_000)
  if (lastSevenDays.length === 0) {
    return {
      mission: 'easy',
      title: 'Easy re-entry run',
      duration_min: Math.min(30, context.availableMinutes),
      reason: 'There is no recent run to justify demanding work, so Orbit begins with a controlled baseline.',
      confidence: 'moderate',
    }
  }
  if (context.lowerBodyTomorrow) {
    return {
      mission: 'easy',
      title: 'Easy run before strength',
      duration_min: Math.min(35, context.availableMinutes),
      reason: 'Tomorrow contains lower-body work, so today’s run should add aerobic volume without carrying avoidable fatigue forward.',
      confidence: 'high',
    }
  }
  const recentRouteIds = lastSevenDays.map((run) => run.route_id).filter(Boolean)
  const repetitive = recentRouteIds.length >= 3 && new Set(recentRouteIds).size === 1
  if (repetitive) {
    return {
      mission: 'exploration',
      title: 'Exploration run',
      duration_min: Math.min(40, context.availableMinutes),
      reason: 'Your recent route history is highly repetitive and today has no strict pace requirement.',
      confidence: 'moderate',
    }
  }
  return {
    mission: 'aerobic_base',
    title: 'Aerobic base run',
    duration_min: Math.min(42, context.availableMinutes),
    reason: 'Controlled aerobic work offers the best return today without competing with the rest of your APEX programme.',
    confidence: 'moderate',
  }
}

function missionFit(candidate: RouteCandidate, mission: RunMission): number {
  let score = 50
  if (mission === 'recovery' || mission === 'easy') {
    if (candidate.terrain === 'flat') score += 22
    if (candidate.navigation_complexity === 'low') score += 18
  }
  if (mission === 'tempo' || mission === 'threshold' || mission === 'marathon_pace') {
    if (candidate.navigation_complexity === 'low') score += 22
    if (candidate.surface === 'road' || candidate.surface === 'path') score += 12
    if (candidate.terrain !== 'hilly') score += 10
  }
  if (mission === 'hills') {
    if (candidate.terrain === 'hilly') score += 32
    else if (candidate.terrain === 'rolling') score += 16
  }
  if (mission === 'exploration') {
    score += Math.round((100 - (candidate.familiarity_pct ?? 50)) * 0.35)
  }
  if (mission === 'long_run') {
    if (candidate.navigation_complexity !== 'high') score += 14
    if (candidate.shape === 'loop') score += 10
  }
  return score
}

export function scoreRouteCandidate(candidate: RouteCandidate, request: RouteRequest): number {
  const targetM = request.distance_km * 1000
  const distanceError = Math.abs(candidate.distance_m - targetM) / Math.max(targetM, 1)
  let score = missionFit(candidate, request.mission) - distanceError * 45
  if (candidate.shape === request.shape) score += 8
  if (candidate.surface === request.surface || request.surface === 'mixed') score += 6
  if (candidate.terrain === request.terrain) score += 8
  if (request.simple_navigation && candidate.navigation_complexity === 'low') score += 10
  if (request.familiarity === 'exploratory' && (candidate.familiarity_pct ?? 50) < 35) score += 10
  if (request.familiarity === 'familiar' && (candidate.familiarity_pct ?? 50) > 65) score += 10
  return Math.round(Math.max(0, Math.min(100, score)))
}

export function explainRoute(candidate: RouteCandidate, mission: RunMission): string {
  if (mission === 'recovery') return candidate.terrain === 'flat' && candidate.navigation_complexity === 'low'
    ? 'Best recovery option: mostly flat with lower navigation complexity.'
    : 'Recovery option with a manageable route shape. Keep effort controlled on any rise.'
  if (mission === 'tempo' || mission === 'threshold') return candidate.navigation_complexity === 'low'
    ? 'Best quality option: longer uninterrupted sections with fewer major turns.'
    : 'Quality option with some navigation changes. Use the clearest uninterrupted section for the work block.'
  if (mission === 'hills') return 'Best hill option: repeated elevation changes suit controlled climbing work.'
  if (mission === 'exploration') return 'Best exploration option: designed to differ from your familiar route pattern.'
  if (mission === 'marathon_pace') return 'Marathon-specific option: stable route geometry supports disciplined pace work.'
  return 'Balanced option for today’s mission, distance and navigation preference.'
}
