import {
  FITNESS_BRAIN_V2_MODEL_VERSION,
  FITNESS_BRAIN_V2_REFERENCE_SCALE,
  composeFitnessBrainV2,
  type CapacityDomain,
  type CapacityEstimateInput,
  type EvidenceSourceClass,
  type FitnessBrainConfidence,
  type FitnessBrainV2Input,
  type FitnessBrainV2State,
} from './fitnessBrainV2.ts'
import type { FitnessEvidenceRecord } from './types.ts'
import type { FitnessEvidenceSource } from './fitnessEvidence.ts'

export const FITNESS_BRAIN_PRESENTATION_MODEL_VERSION = 1 as const

export type FitnessBrainShadowPlatform = 'web' | 'ios'
export type FitnessBrainShadowProfileKind = 'standard' | 'bespoke'
export type FitnessBrainShadowAgeBand = 'under_30' | '30_44' | '45_59' | '60_plus' | 'unknown'
export type FitnessBrainShadowSexGroup = 'female' | 'male' | 'unknown'
export type LegacyOverallBand = 'unavailable' | '0_19' | '20_39' | '40_59' | '60_79' | '80_100'
export type ShadowDisagreementBand = 'unavailable' | 'under_5' | '5_to_14' | '15_to_24' | '25_plus'
export type ShadowCoverageBand = 'none' | 'low' | 'partial' | 'sufficient'
export type FitnessBrainInvariantCode =
  | 'missing_data_changed_capacity'
  | 'readiness_changed_capacity'
  | 'adherence_changed_capacity'
  | 'adaptation_changed_capacity'
  | 'health_context_changed_capacity'
  | 'overall_confidence_exceeded_domain'
  | 'capacity_value_outside_bounds'

type CountedSourceClass = Exclude<EvidenceSourceClass, 'composite'>

export interface FitnessBrainShadowRunInput {
  observed_on: string
  platform: FitnessBrainShadowPlatform
  profile_kind: FitnessBrainShadowProfileKind
  age_band: FitnessBrainShadowAgeBand
  sex_group: FitnessBrainShadowSexGroup
  legacy_overall: number | null
  v2_input: FitnessBrainV2Input
}

export interface FitnessBrainShadowObservation {
  observed_on: string
  platform: FitnessBrainShadowPlatform
  profile_kind: FitnessBrainShadowProfileKind
  age_band: FitnessBrainShadowAgeBand
  sex_group: FitnessBrainShadowSexGroup
  presentation_model_version: typeof FITNESS_BRAIN_PRESENTATION_MODEL_VERSION
  shadow_model_version: typeof FITNESS_BRAIN_V2_MODEL_VERSION
  legacy_overall_band: LegacyOverallBand
  shadow_overall_band: FitnessBrainV2State['capacity']['overall_fitness']['band']
  absolute_disagreement_band: ShadowDisagreementBand
  overall_coverage_band: ShadowCoverageBand
  overall_confidence: FitnessBrainConfidence
  source_distribution: Partial<Record<CountedSourceClass, number>>
  issue_codes: string[]
  invariant_codes: FitnessBrainInvariantCode[]
}

export interface FitnessBrainShadowFixture {
  scenarios: Array<{
    name: string
    input: FitnessBrainShadowRunInput
    expected: FitnessBrainShadowObservation
  }>
}

export interface FitnessBrainShadowRuntimeInput {
  owner_id: string
  observed_on: string
  platform: FitnessBrainShadowPlatform
  profile_kind: FitnessBrainShadowProfileKind | null | undefined
  birthdate: string | null | undefined
  sex: string | null | undefined
  legacy_snapshots: Array<{
    user_id: string
    date: string
    overall: number
  }>
  fitness_evidence: FitnessEvidenceRecord[]
}

export interface FitnessBrainShadowRPCPayload {
  p_observed_on: string
  p_platform: FitnessBrainShadowPlatform
  p_presentation_model_version: number
  p_shadow_model_version: number
  p_legacy_overall_band: LegacyOverallBand
  p_shadow_overall_band: FitnessBrainV2State['capacity']['overall_fitness']['band']
  p_absolute_disagreement_band: ShadowDisagreementBand
  p_overall_coverage_band: ShadowCoverageBand
  p_overall_confidence: FitnessBrainConfidence
  p_source_distribution: FitnessBrainShadowObservation['source_distribution']
  p_issue_codes: string[]
  p_invariant_codes: FitnessBrainInvariantCode[]
}

const capacityDomains: Array<CapacityDomain | 'mobility' | 'overall_fitness'> = [
  'cardiorespiratory',
  'upper_strength',
  'lower_strength',
  'mobility_hip_posterior',
  'mobility_ankle',
  'mobility_shoulder',
  'balance_function',
  'mobility',
  'overall_fitness',
]

const confidenceRank: Readonly<Record<FitnessBrainConfidence, number>> = {
  unavailable: 0,
  low: 1,
  medium: 2,
  high: 3,
}

const directMetricDomains: Partial<Record<FitnessEvidenceRecord['metric'], CapacityDomain>> = {
  cardio_capacity_score: 'cardiorespiratory',
  upper_body_strength_score: 'upper_strength',
  lower_body_strength_score: 'lower_strength',
  balance_score: 'balance_function',
}

function legacyOverallBand(value: number | null): LegacyOverallBand {
  if (value == null || !Number.isFinite(value)) return 'unavailable'
  if (value < 20) return '0_19'
  if (value < 40) return '20_39'
  if (value < 60) return '40_59'
  if (value < 80) return '60_79'
  return '80_100'
}

function disagreementBand(legacy: number | null, shadow: number | null): ShadowDisagreementBand {
  if (legacy == null || shadow == null || !Number.isFinite(legacy) || !Number.isFinite(shadow)) {
    return 'unavailable'
  }
  const delta = Math.abs(legacy - shadow)
  if (delta < 5) return 'under_5'
  if (delta < 15) return '5_to_14'
  if (delta < 25) return '15_to_24'
  return '25_plus'
}

function coverageBand(coverage: number): ShadowCoverageBand {
  if (coverage <= 0) return 'none'
  if (coverage < 0.35) return 'low'
  if (coverage < 0.6) return 'partial'
  return 'sufficient'
}

function capacitySignature(state: FitnessBrainV2State): string {
  return JSON.stringify(capacityDomains.map((domain) => {
    const estimate = state.capacity[domain]
    return [
      domain,
      estimate.value,
      estimate.lower_bound,
      estimate.upper_bound,
      estimate.confidence,
      estimate.coverage,
      estimate.freshness,
      estimate.band,
    ]
  }))
}

function capacityChanged(left: FitnessBrainV2State, right: FitnessBrainV2State): boolean {
  return capacitySignature(left) !== capacitySignature(right)
}

function hasValueOutsideBounds(state: FitnessBrainV2State): boolean {
  return capacityDomains.some((domain) => {
    const estimate = state.capacity[domain]
    if (estimate.value == null) return false
    return estimate.lower_bound == null
      || estimate.upper_bound == null
      || estimate.value < estimate.lower_bound
      || estimate.value > estimate.upper_bound
  })
}

function overallConfidenceExceededDomain(state: FitnessBrainV2State): boolean {
  const overall = state.capacity.overall_fitness
  if (overall.confidence === 'unavailable') return false
  const required = [
    state.capacity.cardiorespiratory,
    state.capacity.upper_strength,
    state.capacity.lower_strength,
    state.capacity.mobility,
  ]
  return required.some((estimate) => confidenceRank[overall.confidence] > confidenceRank[estimate.confidence])
}

export function auditFitnessBrainShadowInvariants(
  input: FitnessBrainV2Input,
  state = composeFitnessBrainV2(input),
): FitnessBrainInvariantCode[] {
  const codes = new Set<FitnessBrainInvariantCode>()
  const withoutReadiness = composeFitnessBrainV2({ ...input, readiness_signals: [] })
  const withoutAdherence = composeFitnessBrainV2({ ...input, adherence_events: [] })
  const withoutAdaptation = composeFitnessBrainV2({ ...input, adaptation_signals: [] })
  const withoutHealthContext = composeFitnessBrainV2({
    ...input,
    health_context: { flags: [], receipt_ids: [] },
  })
  const withoutExplicitMissing = composeFitnessBrainV2({
    ...input,
    capacity: input.capacity.filter((estimate) => estimate.value != null),
  })

  if (capacityChanged(state, withoutReadiness)) codes.add('readiness_changed_capacity')
  if (capacityChanged(state, withoutAdherence)) codes.add('adherence_changed_capacity')
  if (capacityChanged(state, withoutAdaptation)) codes.add('adaptation_changed_capacity')
  if (capacityChanged(state, withoutHealthContext)) codes.add('health_context_changed_capacity')
  if (capacityChanged(state, withoutExplicitMissing)) codes.add('missing_data_changed_capacity')
  if (overallConfidenceExceededDomain(state)) codes.add('overall_confidence_exceeded_domain')
  if (hasValueOutsideBounds(state)) codes.add('capacity_value_outside_bounds')
  return [...codes].sort()
}

function sourceDistribution(input: FitnessBrainV2Input): Partial<Record<CountedSourceClass, number>> {
  const counts: Partial<Record<CountedSourceClass, number>> = {}
  for (const estimate of input.capacity) {
    counts[estimate.source_class] = (counts[estimate.source_class] ?? 0) + 1
  }
  return Object.fromEntries(Object.entries(counts).sort(([left], [right]) => left.localeCompare(right)))
}

const safeIssueCode = /^(?:duplicate_domain|invalid_unknown|missing_value|invalid_bounds|out_of_range|non_finite|invalid_coverage|invalid_model_version|invalid_reference_scale|invalid_confidence|missing_evidence|missing_receipt|band_too_narrow):[a-z_]+$/

export function composeFitnessBrainShadowObservation(
  input: FitnessBrainShadowRunInput,
): FitnessBrainShadowObservation {
  const state = composeFitnessBrainV2(input.v2_input)
  const overall = state.capacity.overall_fitness
  return {
    observed_on: input.observed_on,
    platform: input.platform,
    profile_kind: input.profile_kind,
    age_band: input.age_band,
    sex_group: input.sex_group,
    presentation_model_version: FITNESS_BRAIN_PRESENTATION_MODEL_VERSION,
    shadow_model_version: FITNESS_BRAIN_V2_MODEL_VERSION,
    legacy_overall_band: legacyOverallBand(input.legacy_overall),
    shadow_overall_band: overall.band,
    absolute_disagreement_band: disagreementBand(input.legacy_overall, overall.value),
    overall_coverage_band: coverageBand(overall.coverage),
    overall_confidence: overall.confidence,
    source_distribution: sourceDistribution(input.v2_input),
    issue_codes: [...new Set(state.issue_codes.filter((code) => safeIssueCode.test(code)))].sort(),
    invariant_codes: auditFitnessBrainShadowInvariants(input.v2_input, state),
  }
}

function runtimeAgeBand(
  birthdate: string | null | undefined,
  observedOn: string,
): FitnessBrainShadowAgeBand {
  const birth = birthdate?.match(/^(\d{4})-(\d{2})-(\d{2})$/)
  const observed = observedOn.match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!birth || !observed) return 'unknown'
  const birthMonthDay = Number(birth[2]) * 100 + Number(birth[3])
  const observedMonthDay = Number(observed[2]) * 100 + Number(observed[3])
  const age = Number(observed[1]) - Number(birth[1]) - (observedMonthDay < birthMonthDay ? 1 : 0)
  if (!Number.isInteger(age) || age < 0 || age > 120) return 'unknown'
  if (age < 30) return 'under_30'
  if (age < 45) return '30_44'
  if (age < 60) return '45_59'
  return '60_plus'
}

export function buildFitnessBrainShadowRuntimeObservation(
  runtime: FitnessBrainShadowRuntimeInput,
): FitnessBrainShadowObservation {
  const latestLegacy = runtime.legacy_snapshots
    .filter((snapshot) => snapshot.user_id === runtime.owner_id && snapshot.date <= runtime.observed_on)
    .filter((snapshot) => Number.isFinite(snapshot.overall))
    .sort((left, right) => left.date.localeCompare(right.date))
    .at(-1)
  const normalizedSex = runtime.sex?.trim().toLocaleLowerCase()
  return composeFitnessBrainShadowObservation({
    observed_on: runtime.observed_on,
    platform: runtime.platform,
    profile_kind: runtime.profile_kind === 'bespoke' ? 'bespoke' : 'standard',
    age_band: runtimeAgeBand(runtime.birthdate, runtime.observed_on),
    sex_group: normalizedSex === 'female' || normalizedSex === 'woman'
      ? 'female'
      : normalizedSex === 'male' || normalizedSex === 'man'
        ? 'male'
        : 'unknown',
    legacy_overall: latestLegacy?.overall ?? null,
    v2_input: {
      as_of: runtime.observed_on,
      capacity: buildShadowCapacityInputs(
        runtime.fitness_evidence,
        runtime.owner_id,
        runtime.observed_on,
      ),
      readiness_signals: [],
      adherence_events: [],
      adaptation_signals: [],
      health_context: { flags: [], receipt_ids: [] },
    },
  })
}

export function fitnessBrainShadowRPCPayload(
  observation: FitnessBrainShadowObservation,
): FitnessBrainShadowRPCPayload {
  return {
    p_observed_on: observation.observed_on,
    p_platform: observation.platform,
    p_presentation_model_version: observation.presentation_model_version,
    p_shadow_model_version: observation.shadow_model_version,
    p_legacy_overall_band: observation.legacy_overall_band,
    p_shadow_overall_band: observation.shadow_overall_band,
    p_absolute_disagreement_band: observation.absolute_disagreement_band,
    p_overall_coverage_band: observation.overall_coverage_band,
    p_overall_confidence: observation.overall_confidence,
    p_source_distribution: observation.source_distribution,
    p_issue_codes: observation.issue_codes,
    p_invariant_codes: observation.invariant_codes,
  }
}

export function fitnessBrainShadowOutboxKey(
  observation: FitnessBrainShadowObservation,
): string {
  return [
    'fitness-brain-shadow',
    observation.observed_on,
    observation.platform,
    observation.shadow_model_version,
  ].join(':')
}

function sourceClass(source: FitnessEvidenceSource): CountedSourceClass {
  switch (source) {
    case 'supported_device': return 'supported_device'
    case 'guided_apex_field_test': return 'guided_field_test'
    case 'indirect_calorimetry':
    case 'dexa_measurement':
    case 'dexa_derived_estimate':
    case 'clinical_measurement': return 'clinical_lab'
    case 'legacy_unverified': return 'legacy_unverified'
    case 'structured_self_report':
    case 'user_entered_external_result': return 'structured_self_report'
  }
}

function freshness(measuredAt: string, asOf: string): CapacityEstimateInput['freshness'] {
  const measured = Date.parse(measuredAt)
  const current = Date.parse(`${asOf}T23:59:59.999Z`)
  if (!Number.isFinite(measured) || !Number.isFinite(current)) return 'stale'
  const days = Math.max(0, (current - measured) / 86_400_000)
  if (days <= 90) return 'current'
  if (days <= 365) return 'aging'
  return 'stale'
}

function numericMetadata(record: FitnessEvidenceRecord, key: string): number | null {
  const value = record.metadata[key]
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

function evidenceCoverage(record: FitnessEvidenceRecord): number {
  const declared = numericMetadata(record, 'coverage')
  if (declared != null) return Math.min(1, Math.max(0, declared))
  const answered = numericMetadata(record, 'answered_count')
  if (answered != null) return Math.min(0.55, Math.max(0, answered / 3) * 0.55)
  return record.source === 'legacy_unverified' ? 0.25 : 0.35
}

function capacityInput(
  record: FitnessEvidenceRecord,
  domain: CapacityDomain,
  asOf: string,
): CapacityEstimateInput | null {
  if (record.unit !== 'score_0_100') return null
  const lower = numericMetadata(record, 'lower_bound')
  const upper = numericMetadata(record, 'upper_bound')
  if (lower == null || upper == null || lower < 0 || upper > 100 || lower > record.value || upper < record.value) {
    return null
  }
  return {
    domain,
    value: record.value,
    lower_bound: lower,
    upper_bound: upper,
    reference_scale: FITNESS_BRAIN_V2_REFERENCE_SCALE,
    confidence: record.confidence,
    coverage: evidenceCoverage(record),
    freshness: freshness(record.measured_at, asOf),
    source_class: sourceClass(record.source),
    evidence_ids: [record.id],
    explanation_receipts: [`evidence:${record.metric}:${record.id}`],
    model_version: FITNESS_BRAIN_V2_MODEL_VERSION,
    as_of: asOf,
  }
}

export function buildShadowCapacityInputs(
  records: FitnessEvidenceRecord[],
  ownerID: string,
  asOf: string,
): CapacityEstimateInput[] {
  const owned = records.filter((record) => record.user_id === ownerID)
  const superseded = new Set(owned.flatMap((record) => record.supersedes_id ? [record.supersedes_id] : []))
  const latest = new Map<CapacityDomain, FitnessEvidenceRecord>()

  for (const record of owned) {
    if (superseded.has(record.id)) continue
    const domain = directMetricDomains[record.metric]
    if (!domain) continue
    const existing = latest.get(domain)
    if (!existing || `${record.measured_at}:${record.imported_at}:${record.id}` > `${existing.measured_at}:${existing.imported_at}:${existing.id}`) {
      latest.set(domain, record)
    }
  }

  return [...latest.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .flatMap(([domain, record]) => {
      const input = capacityInput(record, domain, asOf)
      return input ? [input] : []
    })
}

export interface FitnessBrainRolloutEvidence {
  observation_count: number
  smallest_subgroup_count: number
  sufficient_coverage_rate: number
  disagreement_outlier_rate: number
  invariant_violation_count: number
  scientific_review_complete: boolean
  privacy_review_complete: boolean
  claim_review_complete: boolean
  owner_activation_approved: boolean
}

export interface FitnessBrainRolloutDecision {
  mode: 'shadow_only' | 'eligible_for_controlled_activation'
  blockers: string[]
}

export function evaluateFitnessBrainRolloutGate(
  evidence: FitnessBrainRolloutEvidence,
): FitnessBrainRolloutDecision {
  const blockers: string[] = []
  if (evidence.observation_count < 1_000) blockers.push('minimum_observations_not_met')
  if (evidence.smallest_subgroup_count < 100) blockers.push('subgroup_sample_not_met')
  if (evidence.sufficient_coverage_rate < 0.8) blockers.push('coverage_not_met')
  if (evidence.disagreement_outlier_rate > 0.05) blockers.push('outlier_rate_too_high')
  if (evidence.invariant_violation_count !== 0) blockers.push('invariant_violation_present')
  if (!evidence.scientific_review_complete) blockers.push('scientific_review_required')
  if (!evidence.privacy_review_complete) blockers.push('privacy_review_required')
  if (!evidence.claim_review_complete) blockers.push('claim_review_required')
  if (!evidence.owner_activation_approved) blockers.push('owner_activation_required')
  return blockers.length === 0
    ? { mode: 'eligible_for_controlled_activation', blockers }
    : { mode: 'shadow_only', blockers }
}
