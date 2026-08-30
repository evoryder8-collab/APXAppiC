import type { ActivityLevel } from './types.ts'
import type { FitnessEvidenceDraft } from './fitnessEvidence.ts'

export const ONBOARDING_BASELINE_VERSION = 1 as const
export const ONBOARDING_MOVEMENT_DOMAINS = [
  'cardiorespiratory',
  'upper_strength',
  'lower_strength',
  'mobility',
] as const

export type OnboardingMovementDomain = (typeof ONBOARDING_MOVEMENT_DOMAINS)[number]
export type OnboardingActivityPattern =
  | 'mostly_seated'
  | 'mixed_day'
  | 'on_feet'
  | 'physical_work'
  | 'not_sure'
export type OnboardingMovementAnswer =
  | 'not_tested'
  | 'foundation'
  | 'developing'
  | 'capable'
  | 'strong'
export type OnboardingBaselineBand =
  | 'building_baseline'
  | 'foundation'
  | 'developing'
  | 'capable'
  | 'strong'

export interface OnboardingBaselineAnswers {
  activity_pattern: string
  cardiorespiratory: string
  upper_strength: string
  lower_strength: string
  mobility: string
}

export interface OnboardingBaselineEvaluationInput {
  user_id: string
  measured_at: string
  imported_at: string
  answers: OnboardingBaselineAnswers
}

export interface OnboardingBaselineBands {
  cardiorespiratory: OnboardingBaselineBand
  upper_strength: OnboardingBaselineBand
  lower_strength: OnboardingBaselineBand
  mobility: OnboardingBaselineBand
  overall_fitness: 'building_baseline'
}

export type OnboardingBaselineResult =
  | {
    status: 'accepted'
    activity_level: ActivityLevel
    bands: OnboardingBaselineBands
    evidence: FitnessEvidenceDraft[]
  }
  | { status: 'rejected'; reason: 'unsupported_answer' | 'invalid_boundary' }

interface BandDefinition {
  value: number
  lowerBound: number
  upperBound: number
}

const activityLevels: Record<OnboardingActivityPattern, ActivityLevel> = {
  mostly_seated: 'sedentary',
  mixed_day: 'light',
  on_feet: 'moderate',
  physical_work: 'very',
  // Unknown must not silently receive the old moderate default. A sedentary
  // provisional baseline is conservative and the raw uncertainty is retained.
  not_sure: 'sedentary',
}

const bandDefinitions: Record<Exclude<OnboardingMovementAnswer, 'not_tested'>, BandDefinition> = {
  foundation: { value: 30, lowerBound: 20, upperBound: 39 },
  developing: { value: 47, lowerBound: 40, upperBound: 54 },
  capable: { value: 62, lowerBound: 55, upperBound: 69 },
  strong: { value: 77, lowerBound: 70, upperBound: 84 },
}

const evidenceMetrics: Record<OnboardingMovementDomain, string> = {
  cardiorespiratory: 'cardio_capacity_score',
  upper_strength: 'upper_body_strength_score',
  lower_strength: 'lower_body_strength_score',
  mobility: 'flexibility_score',
}

const activityPatternSet = new Set<OnboardingActivityPattern>(Object.keys(activityLevels) as OnboardingActivityPattern[])
const movementAnswerSet = new Set<OnboardingMovementAnswer>(['not_tested', ...Object.keys(bandDefinitions)] as OnboardingMovementAnswer[])

function validTimestamp(value: string): boolean {
  return value.trim().length > 0 && Number.isFinite(Date.parse(value))
}

function stableEvidenceKey(
  userId: string,
  metric: string,
  answer: OnboardingMovementAnswer,
  measuredAt: string,
): string {
  return `onboarding-v1:${userId}:${metric}:${answer}:${measuredAt.slice(0, 10)}`
}

export function evaluateOnboardingBaseline(
  input: OnboardingBaselineEvaluationInput,
): OnboardingBaselineResult {
  const userId = input.user_id.trim()
  const activityPattern = input.answers.activity_pattern as OnboardingActivityPattern
  if (!userId || !validTimestamp(input.measured_at) || !validTimestamp(input.imported_at)) {
    return { status: 'rejected', reason: 'invalid_boundary' }
  }
  if (!activityPatternSet.has(activityPattern)) {
    return { status: 'rejected', reason: 'unsupported_answer' }
  }

  const answers = Object.fromEntries(ONBOARDING_MOVEMENT_DOMAINS.map((domain) => [
    domain,
    input.answers[domain] as OnboardingMovementAnswer,
  ])) as Record<OnboardingMovementDomain, OnboardingMovementAnswer>
  if (ONBOARDING_MOVEMENT_DOMAINS.some((domain) => !movementAnswerSet.has(answers[domain]))) {
    return { status: 'rejected', reason: 'unsupported_answer' }
  }

  const evidence: FitnessEvidenceDraft[] = []
  const bands = Object.fromEntries(ONBOARDING_MOVEMENT_DOMAINS.map((domain) => {
    const answer = answers[domain]
    if (answer === 'not_tested') return [domain, 'building_baseline']
    const definition = bandDefinitions[answer]
    const metric = evidenceMetrics[domain]
    evidence.push({
      user_id: userId,
      metric,
      value: definition.value,
      unit: 'score_0_100',
      source: 'structured_self_report',
      protocol: 'apex_onboarding_pulse_v1',
      device: null,
      measured_at: input.measured_at,
      imported_at: input.imported_at,
      requested_confidence: 'low',
      metadata: {
        assessment_version: ONBOARDING_BASELINE_VERSION,
        anchor: answer,
        band: answer,
        domain,
        lower_bound: definition.lowerBound,
        upper_bound: definition.upperBound,
        display_precision: 'band_only',
      },
      supersedes_id: null,
      client_idempotency_key: stableEvidenceKey(userId, metric, answer, input.measured_at),
    })
    return [domain, answer]
  })) as Omit<OnboardingBaselineBands, 'overall_fitness'>

  return {
    status: 'accepted',
    activity_level: activityLevels[activityPattern],
    bands: { ...bands, overall_fitness: 'building_baseline' },
    evidence,
  }
}

export function summarizeOnboardingBaseline(
  result: OnboardingBaselineResult,
): OnboardingBaselineFixtureExpected {
  if (result.status === 'rejected') return result
  return {
    status: 'accepted',
    activity_level: result.activity_level,
    bands: result.bands,
    evidence: result.evidence.map((item) => {
      const metadata = item.metadata as Record<string, unknown>
      return {
        metric: item.metric,
        value: item.value,
        lower_bound: metadata.lower_bound as number,
        upper_bound: metadata.upper_bound as number,
        band: metadata.band as OnboardingBaselineBand,
      }
    }),
  }
}

export type OnboardingBaselineFixtureExpected =
  | {
    status: 'accepted'
    activity_level: ActivityLevel
    bands: OnboardingBaselineBands
    evidence: Array<{
      metric: string
      value: number
      lower_bound: number
      upper_bound: number
      band: OnboardingBaselineBand
    }>
  }
  | { status: 'rejected'; reason: 'unsupported_answer' | 'invalid_boundary' }

export interface OnboardingBaselineFixture {
  version: number
  user_id: string
  measured_at: string
  imported_at: string
  scenarios: Array<{
    name: string
    input: OnboardingBaselineAnswers
    expected: OnboardingBaselineFixtureExpected
  }>
}
