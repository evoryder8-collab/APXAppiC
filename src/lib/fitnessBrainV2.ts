/**
 * Fitness Brain v2 semantic boundary.
 *
 * Inputs are already normalized against a declared reference or personal
 * baseline. This module never turns legacy game points into physiology. It
 * keeps long-lived capacity, short-lived readiness, behavioural XP,
 * adaptation support and safety context in independent layers.
 */

export const FITNESS_BRAIN_V2_MODEL_VERSION = 2 as const
export const FITNESS_BRAIN_V2_REFERENCE_SCALE = 'apex_capacity_percentile_v2' as const

export type FitnessBrainConfidence = 'unavailable' | 'low' | 'medium' | 'high'
export type FitnessBrainFreshness = 'current' | 'aging' | 'stale'
export type CapacityDomain =
  | 'cardiorespiratory'
  | 'upper_strength'
  | 'lower_strength'
  | 'mobility_hip_posterior'
  | 'mobility_ankle'
  | 'mobility_shoulder'
  | 'balance_function'
export type DerivedCapacityDomain = 'mobility' | 'overall_fitness'
export type EvidenceSourceClass =
  | 'structured_self_report'
  | 'legacy_unverified'
  | 'supported_device'
  | 'guided_field_test'
  | 'standardized_field_test'
  | 'clinical_lab'
  | 'composite'
export type FitnessCapacityBand =
  | 'building_baseline'
  | 'foundation'
  | 'developing'
  | 'capable'
  | 'strong'
  | 'exceptional'
export type ReadinessBand = 'building_baseline' | 'reduced' | 'mixed' | 'ready' | 'strong'
export type AdaptationBand = 'unknown' | 'limited' | 'supported' | 'strong'

export interface CapacityEstimateInput {
  domain: CapacityDomain
  value: number | null
  lower_bound: number | null
  upper_bound: number | null
  reference_scale: string
  confidence: FitnessBrainConfidence
  coverage: number
  freshness: FitnessBrainFreshness
  source_class: Exclude<EvidenceSourceClass, 'composite'>
  evidence_ids: string[]
  explanation_receipts: string[]
  model_version: number
  as_of: string
}

export interface CapacityEstimate {
  domain: CapacityDomain | DerivedCapacityDomain
  value: number | null
  lower_bound: number | null
  upper_bound: number | null
  reference_scale: typeof FITNESS_BRAIN_V2_REFERENCE_SCALE
  confidence: FitnessBrainConfidence
  coverage: number
  freshness: FitnessBrainFreshness
  source_class: EvidenceSourceClass
  evidence_ids: string[]
  explanation_receipts: string[]
  model_version: typeof FITNESS_BRAIN_V2_MODEL_VERSION
  as_of: string
  band: FitnessCapacityBand
}

export interface ReadinessSignalInput {
  kind: string
  /** A source-normalizer must compare biometrics with the person's own baseline. */
  normalized_value: number
  confidence: Exclude<FitnessBrainConfidence, 'unavailable'>
  freshness: FitnessBrainFreshness
  evidence_id: string
}

export interface AdherenceEventInput {
  kind: string
  xp: number
  receipt_id: string
}

export interface AdaptationSignalInput {
  kind: string
  status: 'supportive' | 'limiting'
  receipt_id: string
}

export type HealthContextFlag = 'pain' | 'recent_operation' | 'acute_symptom' | 'clearance_required'

export interface HealthContextInput {
  flags: HealthContextFlag[]
  receipt_ids: string[]
}

export interface FitnessBrainV2Input {
  as_of: string
  capacity: CapacityEstimateInput[]
  readiness_signals: ReadinessSignalInput[]
  adherence_events: AdherenceEventInput[]
  adaptation_signals: AdaptationSignalInput[]
  health_context: HealthContextInput
}

export interface FitnessBrainV2State {
  model_version: typeof FITNESS_BRAIN_V2_MODEL_VERSION
  as_of: string
  capacity: Record<CapacityDomain | DerivedCapacityDomain, CapacityEstimate>
  readiness: {
    value: number | null
    confidence: FitnessBrainConfidence
    coverage: number
    freshness: FitnessBrainFreshness
    band: ReadinessBand
    evidence_ids: string[]
  }
  adherence: {
    xp: number
    receipt_ids: string[]
  }
  adaptation_support: {
    band: AdaptationBand
    coverage: number
    supportive_receipt_ids: string[]
    limiting_receipt_ids: string[]
  }
  health_context: {
    flags: HealthContextFlag[]
    receipt_ids: string[]
    field_test_eligible: boolean
  }
  rejected_domains: CapacityDomain[]
  issue_codes: string[]
}

export interface FitnessBrainV2Summary {
  model_version: number
  cardiorespiratory_value: number | null
  upper_strength_value: number | null
  lower_strength_value: number | null
  mobility_value: number | null
  mobility_lower_bound: number | null
  mobility_upper_bound: number | null
  mobility_confidence: FitnessBrainConfidence
  mobility_coverage: number
  mobility_freshness: FitnessBrainFreshness
  overall_value: number | null
  overall_lower_bound: number | null
  overall_upper_bound: number | null
  overall_confidence: FitnessBrainConfidence
  overall_coverage: number
  overall_freshness: FitnessBrainFreshness
  overall_band: FitnessCapacityBand
  readiness_value: number | null
  readiness_confidence: FitnessBrainConfidence
  readiness_coverage: number
  readiness_freshness: FitnessBrainFreshness
  readiness_band: ReadinessBand
  adherence_xp: number
  adaptation_band: AdaptationBand
  field_test_eligible: boolean
  rejected_domains: CapacityDomain[]
  issue_codes: string[]
}

export interface FitnessBrainV2Fixture {
  scenarios: Array<{
    name: string
    input: FitnessBrainV2Input
    expected: FitnessBrainV2Summary
  }>
}

const BASE_DOMAINS: CapacityDomain[] = [
  'cardiorespiratory',
  'upper_strength',
  'lower_strength',
  'mobility_hip_posterior',
  'mobility_ankle',
  'mobility_shoulder',
  'balance_function',
]
const MOBILITY_DOMAINS: CapacityDomain[] = [
  'mobility_hip_posterior',
  'mobility_ankle',
  'mobility_shoulder',
]
const CONFIDENCE_RANK: Record<FitnessBrainConfidence, number> = {
  unavailable: 0,
  low: 1,
  medium: 2,
  high: 3,
}
const FRESHNESS_RANK: Record<FitnessBrainFreshness, number> = {
  current: 0,
  aging: 1,
  stale: 2,
}
const SOURCE_CONFIDENCE_CAP: Record<Exclude<EvidenceSourceClass, 'composite'>, Exclude<FitnessBrainConfidence, 'unavailable'>> = {
  structured_self_report: 'low',
  legacy_unverified: 'low',
  supported_device: 'medium',
  guided_field_test: 'medium',
  standardized_field_test: 'high',
  clinical_lab: 'high',
}
const SOURCE_COVERAGE_CAP: Record<Exclude<EvidenceSourceClass, 'composite'>, number> = {
  structured_self_report: 0.55,
  legacy_unverified: 0.35,
  supported_device: 0.8,
  guided_field_test: 0.85,
  standardized_field_test: 0.95,
  clinical_lab: 1,
}
const FRESHNESS_CONFIDENCE_CAP: Record<FitnessBrainFreshness, Exclude<FitnessBrainConfidence, 'unavailable'>> = {
  current: 'high',
  aging: 'medium',
  stale: 'low',
}

function uniqueSorted(values: string[]): string[] {
  return [...new Set(values.filter((value) => value.trim().length > 0))].sort()
}

function round4(value: number): number {
  return Math.round((value + Number.EPSILON) * 10_000) / 10_000
}

function minimumConfidence(values: FitnessBrainConfidence[]): FitnessBrainConfidence {
  if (values.length === 0) return 'unavailable'
  return values.reduce((lowest, value) => (
    CONFIDENCE_RANK[value] < CONFIDENCE_RANK[lowest] ? value : lowest
  ), 'high' as FitnessBrainConfidence)
}

function cappedConfidence(
  requested: FitnessBrainConfidence,
  sourceClass: Exclude<EvidenceSourceClass, 'composite'>,
  freshness: FitnessBrainFreshness,
): FitnessBrainConfidence {
  if (requested === 'unavailable') return 'unavailable'
  return minimumConfidence([
    requested,
    SOURCE_CONFIDENCE_CAP[sourceClass],
    FRESHNESS_CONFIDENCE_CAP[freshness],
  ])
}

function worstFreshness(values: FitnessBrainFreshness[]): FitnessBrainFreshness {
  if (values.length === 0) return 'stale'
  return values.reduce((worst, value) => (
    FRESHNESS_RANK[value] > FRESHNESS_RANK[worst] ? value : worst
  ), 'current' as FitnessBrainFreshness)
}

function capacityBand(value: number | null): FitnessCapacityBand {
  if (value == null) return 'building_baseline'
  if (value < 25) return 'foundation'
  if (value < 45) return 'developing'
  if (value < 65) return 'capable'
  if (value < 85) return 'strong'
  return 'exceptional'
}

function unavailableEstimate(
  domain: CapacityDomain | DerivedCapacityDomain,
  asOf: string,
  coverage = 0,
  freshness: FitnessBrainFreshness = 'stale',
): CapacityEstimate {
  return {
    domain,
    value: null,
    lower_bound: null,
    upper_bound: null,
    reference_scale: FITNESS_BRAIN_V2_REFERENCE_SCALE,
    confidence: 'unavailable',
    coverage: round4(coverage),
    freshness,
    source_class: 'composite',
    evidence_ids: [],
    explanation_receipts: [],
    model_version: FITNESS_BRAIN_V2_MODEL_VERSION,
    as_of: asOf,
    band: 'building_baseline',
  }
}

function rejectionCode(input: CapacityEstimateInput): string | null {
  const values = [input.value, input.lower_bound, input.upper_bound]
  const allMissing = values.every((value) => value == null)
  if (allMissing) {
    return input.confidence === 'unavailable' && input.coverage === 0 ? null : 'invalid_unknown'
  }
  if (values.some((value) => value == null)) return 'partial_range'
  const value = input.value as number
  const lower = input.lower_bound as number
  const upper = input.upper_bound as number
  if (![value, lower, upper, input.coverage].every(Number.isFinite)) return 'non_finite'
  if (value < 0 || value > 100 || lower < 0 || upper > 100 || lower > value || value > upper) return 'invalid_range'
  if (input.coverage < 0 || input.coverage > 1) return 'invalid_coverage'
  if (input.reference_scale !== FITNESS_BRAIN_V2_REFERENCE_SCALE) return 'reference_scale_mismatch'
  if (input.model_version !== FITNESS_BRAIN_V2_MODEL_VERSION) return 'model_version_mismatch'
  if (input.confidence === 'unavailable') return 'invalid_confidence'
  if (uniqueSorted(input.evidence_ids).length === 0) return 'missing_evidence'
  if (uniqueSorted(input.explanation_receipts).length === 0) return 'missing_receipt'
  const width = upper - lower
  if (input.source_class === 'structured_self_report' && width < 30) return 'band_too_narrow'
  if (input.source_class === 'legacy_unverified' && width < 40) return 'band_too_narrow'
  return null
}

function normalizeEstimate(input: CapacityEstimateInput): CapacityEstimate | null {
  if (input.value == null) return null
  const confidence = cappedConfidence(input.confidence, input.source_class, input.freshness)
  if (confidence === 'unavailable') return null
  return {
    domain: input.domain,
    value: input.value,
    lower_bound: input.lower_bound,
    upper_bound: input.upper_bound,
    reference_scale: FITNESS_BRAIN_V2_REFERENCE_SCALE,
    confidence,
    coverage: round4(Math.min(input.coverage, SOURCE_COVERAGE_CAP[input.source_class])),
    freshness: input.freshness,
    source_class: input.source_class,
    evidence_ids: uniqueSorted(input.evidence_ids),
    explanation_receipts: uniqueSorted(input.explanation_receipts),
    model_version: FITNESS_BRAIN_V2_MODEL_VERSION,
    as_of: input.as_of,
    band: capacityBand(input.value),
  }
}

function average(values: number[]): number {
  return values.reduce((sum, value) => sum + value, 0) / values.length
}

function compositeEstimate(
  domain: DerivedCapacityDomain,
  estimates: CapacityEstimate[],
  asOf: string,
  coverage: number,
): CapacityEstimate {
  const known = estimates.filter((estimate) => estimate.value != null)
  if (known.length === 0) return unavailableEstimate(domain, asOf, coverage)
  const value = average(known.map((estimate) => estimate.value as number))
  return {
    domain,
    value: round4(value),
    lower_bound: round4(average(known.map((estimate) => estimate.lower_bound as number))),
    upper_bound: round4(average(known.map((estimate) => estimate.upper_bound as number))),
    reference_scale: FITNESS_BRAIN_V2_REFERENCE_SCALE,
    confidence: minimumConfidence(known.map((estimate) => estimate.confidence)),
    coverage: round4(coverage),
    freshness: worstFreshness(known.map((estimate) => estimate.freshness)),
    source_class: 'composite',
    evidence_ids: uniqueSorted(known.flatMap((estimate) => estimate.evidence_ids)),
    explanation_receipts: uniqueSorted(known.flatMap((estimate) => estimate.explanation_receipts)),
    model_version: FITNESS_BRAIN_V2_MODEL_VERSION,
    as_of: asOf,
    band: capacityBand(value),
  }
}

function composeReadiness(signals: ReadinessSignalInput[]): FitnessBrainV2State['readiness'] {
  const seen = new Set<string>()
  const valid = signals.filter((signal) => {
    if (!signal.evidence_id.trim() || seen.has(signal.evidence_id)) return false
    if (!Number.isFinite(signal.normalized_value) || signal.normalized_value < 0 || signal.normalized_value > 100) return false
    seen.add(signal.evidence_id)
    return true
  })
  const coverage = round4(Math.min(1, valid.length / 4))
  const freshness = worstFreshness(valid.map((signal) => signal.freshness))
  if (valid.length < 2) {
    return {
      value: null,
      confidence: 'unavailable',
      coverage,
      freshness,
      band: 'building_baseline',
      evidence_ids: uniqueSorted(valid.map((signal) => signal.evidence_id)),
    }
  }
  const value = round4(average(valid.map((signal) => signal.normalized_value)))
  const confidence = minimumConfidence(valid.map((signal) => minimumConfidence([
    signal.confidence,
    FRESHNESS_CONFIDENCE_CAP[signal.freshness],
  ])))
  const band: ReadinessBand = value < 40 ? 'reduced' : value < 70 ? 'mixed' : value < 85 ? 'ready' : 'strong'
  return {
    value,
    confidence,
    coverage,
    freshness,
    band,
    evidence_ids: uniqueSorted(valid.map((signal) => signal.evidence_id)),
  }
}

function composeAdherence(events: AdherenceEventInput[]): FitnessBrainV2State['adherence'] {
  const seen = new Set<string>()
  let xp = 0
  for (const event of events) {
    if (!event.receipt_id.trim() || seen.has(event.receipt_id)) continue
    if (!Number.isFinite(event.xp) || event.xp < 0 || event.xp > 100) continue
    seen.add(event.receipt_id)
    xp += Math.round(event.xp)
  }
  return { xp, receipt_ids: [...seen].sort() }
}

function composeAdaptation(signals: AdaptationSignalInput[]): FitnessBrainV2State['adaptation_support'] {
  const seen = new Set<string>()
  const valid = signals.filter((signal) => {
    if (!signal.receipt_id.trim() || seen.has(signal.receipt_id)) return false
    seen.add(signal.receipt_id)
    return true
  })
  const supportive = uniqueSorted(valid.filter((signal) => signal.status === 'supportive').map((signal) => signal.receipt_id))
  const limiting = uniqueSorted(valid.filter((signal) => signal.status === 'limiting').map((signal) => signal.receipt_id))
  let band: AdaptationBand = 'unknown'
  if (valid.length > 0) {
    if (supportive.length >= 3 && limiting.length === 0) band = 'strong'
    else if (supportive.length >= limiting.length) band = 'supported'
    else band = 'limited'
  }
  return {
    band,
    coverage: round4(Math.min(1, valid.length / 4)),
    supportive_receipt_ids: supportive,
    limiting_receipt_ids: limiting,
  }
}

export function composeFitnessBrainV2(input: FitnessBrainV2Input): FitnessBrainV2State {
  const issueCodes: string[] = []
  const rejected = new Set<CapacityDomain>()
  const capacity = {} as Record<CapacityDomain | DerivedCapacityDomain, CapacityEstimate>

  for (const domain of BASE_DOMAINS) {
    const candidates = input.capacity.filter((estimate) => estimate.domain === domain)
    if (candidates.length > 1) {
      rejected.add(domain)
      issueCodes.push(`duplicate_domain:${domain}`)
      capacity[domain] = unavailableEstimate(domain, input.as_of)
      continue
    }
    const candidate = candidates[0]
    if (!candidate) {
      capacity[domain] = unavailableEstimate(domain, input.as_of)
      continue
    }
    const code = rejectionCode(candidate)
    if (code) {
      rejected.add(domain)
      issueCodes.push(`${code}:${domain}`)
      capacity[domain] = unavailableEstimate(domain, input.as_of)
      continue
    }
    capacity[domain] = normalizeEstimate(candidate) ?? unavailableEstimate(domain, input.as_of)
  }

  const mobilityInputs = MOBILITY_DOMAINS
    .map((domain) => capacity[domain])
    .filter((estimate) => estimate.value != null)
  const mobilityCoverage = mobilityInputs.length === 0
    ? 0
    : average(mobilityInputs.map((estimate) => estimate.coverage)) * (mobilityInputs.length / MOBILITY_DOMAINS.length)
  capacity.mobility = mobilityInputs.length >= 2
    ? compositeEstimate('mobility', mobilityInputs, input.as_of, mobilityCoverage)
    : unavailableEstimate(
      'mobility',
      input.as_of,
      mobilityCoverage,
      worstFreshness(mobilityInputs.map((estimate) => estimate.freshness)),
    )

  const cardio = capacity.cardiorespiratory
  const upper = capacity.upper_strength
  const lower = capacity.lower_strength
  const strengthInputs = [upper, lower].filter((estimate) => estimate.value != null)
  const strengthCoverage = strengthInputs.length === 2
    ? average(strengthInputs.map((estimate) => estimate.coverage))
    : strengthInputs.reduce((sum, estimate) => sum + estimate.coverage, 0) / 2
  const overallCoverage = round4((cardio.coverage + strengthCoverage + capacity.mobility.coverage) / 3)
  const overallInputs = [cardio, upper, lower, capacity.mobility]
  const availableOverallInputs = overallInputs.filter((estimate) => estimate.value != null)
  const overallFreshness = worstFreshness(availableOverallInputs.map((estimate) => estimate.freshness))
  const canComposeOverall = cardio.value != null && upper.value != null && lower.value != null &&
    capacity.mobility.value != null && overallCoverage >= 0.6

  if (canComposeOverall) {
    const strength = compositeEstimate('overall_fitness', [upper, lower], input.as_of, strengthCoverage)
    const overall = compositeEstimate(
      'overall_fitness',
      [cardio, strength, capacity.mobility],
      input.as_of,
      overallCoverage,
    )
    overall.confidence = minimumConfidence(overallInputs.map((estimate) => estimate.confidence))
    overall.freshness = overallFreshness
    capacity.overall_fitness = overall
  } else {
    capacity.overall_fitness = unavailableEstimate(
      'overall_fitness',
      input.as_of,
      overallCoverage,
      overallFreshness,
    )
  }

  const flags = [...new Set(input.health_context.flags)].sort() as HealthContextFlag[]
  const receiptIDs = uniqueSorted(input.health_context.receipt_ids)

  return {
    model_version: FITNESS_BRAIN_V2_MODEL_VERSION,
    as_of: input.as_of,
    capacity,
    readiness: composeReadiness(input.readiness_signals),
    adherence: composeAdherence(input.adherence_events),
    adaptation_support: composeAdaptation(input.adaptation_signals),
    health_context: {
      flags,
      receipt_ids: receiptIDs,
      field_test_eligible: flags.length === 0,
    },
    rejected_domains: BASE_DOMAINS.filter((domain) => rejected.has(domain)),
    issue_codes: issueCodes.sort(),
  }
}

function optionalRound4(value: number | null): number | null {
  return value == null ? null : round4(value)
}

export function summarizeFitnessBrainV2(state: FitnessBrainV2State): FitnessBrainV2Summary {
  const mobility = state.capacity.mobility
  const overall = state.capacity.overall_fitness
  return {
    model_version: state.model_version,
    cardiorespiratory_value: optionalRound4(state.capacity.cardiorespiratory.value),
    upper_strength_value: optionalRound4(state.capacity.upper_strength.value),
    lower_strength_value: optionalRound4(state.capacity.lower_strength.value),
    mobility_value: optionalRound4(mobility.value),
    mobility_lower_bound: optionalRound4(mobility.lower_bound),
    mobility_upper_bound: optionalRound4(mobility.upper_bound),
    mobility_confidence: mobility.confidence,
    mobility_coverage: round4(mobility.coverage),
    mobility_freshness: mobility.freshness,
    overall_value: optionalRound4(overall.value),
    overall_lower_bound: optionalRound4(overall.lower_bound),
    overall_upper_bound: optionalRound4(overall.upper_bound),
    overall_confidence: overall.confidence,
    overall_coverage: round4(overall.coverage),
    overall_freshness: overall.freshness,
    overall_band: overall.band,
    readiness_value: optionalRound4(state.readiness.value),
    readiness_confidence: state.readiness.confidence,
    readiness_coverage: round4(state.readiness.coverage),
    readiness_freshness: state.readiness.freshness,
    readiness_band: state.readiness.band,
    adherence_xp: state.adherence.xp,
    adaptation_band: state.adaptation_support.band,
    field_test_eligible: state.health_context.field_test_eligible,
    rejected_domains: state.rejected_domains,
    issue_codes: state.issue_codes,
  }
}
