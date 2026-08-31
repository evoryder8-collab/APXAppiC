import {
  normalizeFitnessEvidence,
  type FitnessEvidenceDraft,
  type FitnessEvidenceMetric,
  type FitnessEvidenceNormalizationResult,
  type NormalizedFitnessEvidence,
} from './fitnessEvidence.ts'
import type { OnboardingBaselineBand, OnboardingBaselineBands } from './onboardingBaseline.ts'

export const BASELINE_CALIBRATION_VERSION = 1

export type BaselineCalibrationAnswer = 'not_tested' | 'foundation' | 'developing' | 'capable' | 'strong'
export type BaselineCalibrationDomain = 'cardiorespiratory' | 'upper_strength' | 'lower_strength' | 'mobility'

export interface BaselineCalibrationAnswers {
  cardiorespiratory: BaselineCalibrationAnswer[]
  upper_strength: BaselineCalibrationAnswer[]
  lower_strength: BaselineCalibrationAnswer[]
  mobility: BaselineCalibrationAnswer[]
}

export interface BaselineCalibrationEvidenceSummary {
  metric: string
  value: number
  lower_bound: number
  upper_bound: number
  band: OnboardingBaselineBand
  answered_count: number
}

export type BaselineCalibrationSummary =
  | {
      status: 'accepted'
      bands: OnboardingBaselineBands
      evidence: BaselineCalibrationEvidenceSummary[]
    }
  | { status: 'rejected'; reason: string }

export interface BaselineCalibrationFixture {
  version: number
  user_id: string
  measured_at: string
  imported_at: string
  scenarios: Array<{
    name: string
    input: BaselineCalibrationAnswers
    expected: BaselineCalibrationSummary
  }>
}

export type BaselineCalibrationResult =
  | {
      status: 'accepted'
      bands: OnboardingBaselineBands
      evidence: FitnessEvidenceDraft[]
    }
  | { status: 'rejected'; reason: string }

export interface BaselineCalibrationDraft {
  step: number
  answers: BaselineCalibrationAnswers
  answered_question_ids: string[]
}

interface LegacyBaselineCalibrationDraft {
  step: number
  answers: BaselineCalibrationAnswers
  answered_question_ids?: string[]
}

export interface BaselineCalibrationQuestionOption {
  value: Exclude<BaselineCalibrationAnswer, 'not_tested'>
  label: string
}

export interface BaselineCalibrationQuestion {
  id: string
  domain: BaselineCalibrationDomain
  answer_index: number
  section_title: string
  prompt: string
  options: BaselineCalibrationQuestionOption[]
}

export interface CalibrationDraftStorage {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
  removeItem(key: string): void
}

const domains: readonly BaselineCalibrationDomain[] = [
  'cardiorespiratory',
  'upper_strength',
  'lower_strength',
  'mobility',
]

const question = (
  id: string,
  domain: BaselineCalibrationDomain,
  answerIndex: number,
  sectionTitle: string,
  prompt: string,
  labels: [string, string, string, string],
): BaselineCalibrationQuestion => ({
  id,
  domain,
  answer_index: answerIndex,
  section_title: sectionTitle,
  prompt,
  options: (['foundation', 'developing', 'capable', 'strong'] as const).map((value, index) => ({
    value,
    label: labels[index],
  })),
})

export const baselineCalibrationQuestions: BaselineCalibrationQuestion[] = [
  question('stamina.duration', 'cardiorespiratory', 0, 'Stamina',
    'How long can you keep up a brisk walk or easy cycle without needing to stop?',
    ['Less than 5 minutes', 'About 5–15 minutes', 'About 20–40 minutes', 'More than 40 minutes comfortably']),
  question('stamina.stairs', 'cardiorespiratory', 1, 'Stamina',
    'What happens when you climb two flights of stairs at your usual pace?',
    ['I need to stop or struggle', 'I finish but need time to recover', 'I finish with controlled breathing', 'I could comfortably keep climbing']),
  question('stamina.frequency', 'cardiorespiratory', 2, 'Stamina',
    'In a typical week, how often do you do purposeful cardio?',
    ['Rarely or never', 'About once', 'Two or three times', 'Four or more times']),
  question('upper.push', 'upper_strength', 0, 'Upper body',
    'Which best matches a recent, pain-free pushing effort?',
    ['A wall push feels challenging', 'I can do inclined push-ups', 'I can do floor push-ups with control', 'I train challenging presses regularly']),
  question('upper.pull', 'upper_strength', 1, 'Upper body',
    'Which best matches a recent, pain-free pulling effort?',
    ['I have not done pulling work', 'I can do light supported rows', 'I can do challenging rows with control', 'I can do pull-ups or heavy pulls']),
  question('upper.frequency', 'upper_strength', 2, 'Upper body',
    'How often do you train your upper body with gradually harder work?',
    ['Rarely or never', 'A few times per month', 'Once or twice per week', 'Three or more times per week']),
  question('lower.capacity', 'lower_strength', 0, 'Lower body',
    'How do repeated chair stands or stairs usually feel?',
    ['Difficult or I need support', 'Manageable but tiring', 'Comfortable and controlled', 'Easy for many repetitions']),
  question('lower.range', 'lower_strength', 1, 'Lower body',
    'Which best matches your recent, pain-free squat or lunge range?',
    ['Limited or unsteady', 'Controlled to chair height', 'Deep and controlled with body weight', 'Challenging full-range reps with load']),
  question('lower.frequency', 'lower_strength', 2, 'Lower body',
    'How often do you train your lower body with gradually harder work?',
    ['Rarely or never', 'A few times per month', 'Once or twice per week', 'Three or more times per week']),
  question('mobility.hinge', 'mobility', 0, 'Mobility',
    'With straight knees, how far can you comfortably reach toward the floor?',
    ['My hands stay above my knees', 'My fingertips reach my shins', 'My fingertips reach my toes', 'My palms reach the floor comfortably']),
  question('mobility.ankle', 'mobility', 1, 'Mobility',
    'Keeping your heel down, how far can your knee move past your toes?',
    ['It does not reach my toes', 'It reaches my toes', 'It moves a little past my toes', 'I control deep ankle range under load']),
  question('mobility.shoulder', 'mobility', 2, 'Mobility',
    'When you raise both arms overhead, what feels comfortable?',
    ['My arms stop in front of my head', 'My arms reach near my ears with effort', 'My arms align with my ears comfortably', 'I control full overhead range under load']),
]

const questionIDs = new Set(baselineCalibrationQuestions.map((item) => item.id))

export function isBaselineCalibrationQuestionAnswered(
  draft: Pick<BaselineCalibrationDraft, 'answered_question_ids'>,
  questionID: string,
): boolean {
  return draft.answered_question_ids.includes(questionID)
}

const allowedAnswers = new Set<BaselineCalibrationAnswer>([
  'not_tested',
  'foundation',
  'developing',
  'capable',
  'strong',
])

const definitions: Readonly<Record<Exclude<BaselineCalibrationAnswer, 'not_tested'>, {
  value: number
  lower: number
  upper: number
  rank: number
}>> = {
  foundation: { value: 30, lower: 20, upper: 39, rank: 0 },
  developing: { value: 47, lower: 40, upper: 54, rank: 1 },
  capable: { value: 62, lower: 55, upper: 69, rank: 2 },
  strong: { value: 77, lower: 70, upper: 84, rank: 3 },
}

const metrics: Readonly<Record<BaselineCalibrationDomain, FitnessEvidenceMetric>> = {
  cardiorespiratory: 'cardio_capacity_score',
  upper_strength: 'upper_body_strength_score',
  lower_strength: 'lower_body_strength_score',
  mobility: 'flexibility_score',
}

function fnv1a32(value: string): string {
  let hash = 0x811c9dc5
  for (const byte of new TextEncoder().encode(value)) {
    hash ^= byte
    hash = Math.imul(hash, 0x01000193) >>> 0
  }
  return hash.toString(16).padStart(8, '0')
}

function validBoundary(userID: string, measuredAt: string, importedAt: string): boolean {
  if (!userID.trim()) return false
  return Number.isFinite(Date.parse(measuredAt)) && Number.isFinite(Date.parse(importedAt))
}

export function evaluateBaselineCalibration(input: {
  user_id: string
  measured_at: string
  imported_at: string
  answers: BaselineCalibrationAnswers
}): BaselineCalibrationResult {
  const owner = input.user_id.trim()
  if (!validBoundary(owner, input.measured_at, input.imported_at)) {
    return { status: 'rejected', reason: 'invalid_boundary' }
  }

  const bands: OnboardingBaselineBands = {
    cardiorespiratory: 'building_baseline',
    upper_strength: 'building_baseline',
    lower_strength: 'building_baseline',
    mobility: 'building_baseline',
    overall_fitness: 'building_baseline',
  }
  const evidence: FitnessEvidenceDraft[] = []

  for (const domain of domains) {
    const submitted = input.answers[domain]
    if (!Array.isArray(submitted) || submitted.length !== 3 || submitted.some((answer) => !allowedAnswers.has(answer))) {
      return { status: 'rejected', reason: 'unsupported_answer' }
    }
    const answered = submitted.filter((answer): answer is Exclude<BaselineCalibrationAnswer, 'not_tested'> => answer !== 'not_tested')
    if (answered.length < 2) continue

    const ordered = [...answered].sort((left, right) => definitions[left].rank - definitions[right].rank)
    const median = ordered[Math.floor((ordered.length - 1) / 2)]
    const definition = definitions[median]
    const lower = Math.min(...answered.map((answer) => definitions[answer].lower))
    const upper = Math.max(...answered.map((answer) => definitions[answer].upper))
    bands[domain] = median
    const metric = metrics[domain]
    const digest = fnv1a32(`${domain}:${submitted.join(',')}`)
    evidence.push({
      user_id: owner,
      metric,
      value: definition.value,
      unit: 'score_0_100',
      source: 'structured_self_report',
      protocol: 'apex_baseline_calibration_v1',
      device: null,
      measured_at: input.measured_at,
      imported_at: input.imported_at,
      requested_confidence: 'low',
      metadata: {
        calibration_version: BASELINE_CALIBRATION_VERSION,
        route: 'manual_questionnaire',
        domain,
        anchors: submitted,
        answered_count: answered.length,
        band: median,
        lower_bound: lower,
        upper_bound: upper,
        display_precision: 'band_only',
      },
      supersedes_id: null,
      client_idempotency_key: `calibration-v1:${owner}:${metric}:${input.measured_at.slice(0, 10)}:${digest}`,
    })
  }

  return { status: 'accepted', bands, evidence }
}

export function summarizeBaselineCalibration(result: BaselineCalibrationResult): BaselineCalibrationSummary {
  if (result.status === 'rejected') return result
  return {
    status: 'accepted',
    bands: result.bands,
    evidence: result.evidence.map((item) => {
      const metadata = item.metadata as Record<string, unknown>
      return {
        metric: item.metric,
        value: item.value,
        lower_bound: Number(metadata.lower_bound),
        upper_bound: Number(metadata.upper_bound),
        band: metadata.band as OnboardingBaselineBand,
        answered_count: Number(metadata.answered_count),
      }
    }),
  }
}

export function buildManualCalibrationEvidence(input: {
  user_id: string
  metric: FitnessEvidenceMetric
  value: number
  unit: string
  declared_source: string
  measured_at: string
  imported_at: string
}): FitnessEvidenceNormalizationResult {
  const declaredSource = input.declared_source.trim()
  if (!declaredSource || declaredSource.length > 80) {
    return { status: 'rejected', reason: 'invalid_text_field' }
  }
  const digest = fnv1a32(`${input.metric}:${input.value}:${input.unit}:${declaredSource.toLowerCase()}`)
  return normalizeFitnessEvidence({
    user_id: input.user_id,
    metric: input.metric,
    value: input.value,
    unit: input.unit,
    source: 'user_entered_external_result',
    protocol: 'apex_manual_result_v1',
    device: null,
    measured_at: input.measured_at,
    imported_at: input.imported_at,
    requested_confidence: 'low',
    metadata: {
      calibration_version: BASELINE_CALIBRATION_VERSION,
      route: 'recent_result',
      declared_source: declaredSource,
      verification: 'user_entered',
    },
    supersedes_id: null,
    client_idempotency_key: `calibration-result-v1:${input.user_id}:${input.metric}:${input.measured_at.slice(0, 10)}:${digest}`,
  }, 'user', input.imported_at)
}

export type DxaCalibrationEvidenceResult =
  | { status: 'accepted'; evidence: NormalizedFitnessEvidence[] }
  | { status: 'rejected'; reason: string }

export function buildDxaCalibrationEvidence(input: {
  user_id: string
  body_fat_percentage: number | null
  resting_metabolic_rate: number | null
  declared_source: string
  measured_at: string
  imported_at: string
}): DxaCalibrationEvidenceResult {
  const requested = [
    input.body_fat_percentage == null ? null : {
      metric: 'body_fat_percentage' as const,
      value: input.body_fat_percentage,
      unit: 'percent',
    },
    input.resting_metabolic_rate == null ? null : {
      metric: 'resting_metabolic_rate' as const,
      value: input.resting_metabolic_rate,
      unit: 'kcal_per_day',
    },
  ].filter((item): item is NonNullable<typeof item> => item !== null)
  if (requested.length === 0) return { status: 'rejected', reason: 'missing_value' }

  const evidence: NormalizedFitnessEvidence[] = []
  for (const item of requested) {
    const result = buildManualCalibrationEvidence({
      user_id: input.user_id,
      metric: item.metric,
      value: item.value,
      unit: item.unit,
      declared_source: input.declared_source,
      measured_at: input.measured_at,
      imported_at: input.imported_at,
    })
    if (result.status === 'rejected') return result
    evidence.push(result.evidence)
  }
  return { status: 'accepted', evidence }
}

export function baselineCalibrationAuthority(_profileKind: 'standard' | 'bespoke' | string) {
  return {
    can_refine_evidence: true,
    can_replace_programme: false,
    can_authorize_bespoke: false,
  } as const
}

function draftKey(userID: string): string {
  return `apex.baseline-calibration.v1.${userID.trim().toLowerCase()}`
}

export function saveBaselineCalibrationDraft(
  storage: CalibrationDraftStorage,
  userID: string,
  draft: BaselineCalibrationDraft | LegacyBaselineCalibrationDraft,
): void {
  if (!userID.trim()) return
  storage.setItem(draftKey(userID), JSON.stringify(draft))
}

export function loadBaselineCalibrationDraft(
  storage: CalibrationDraftStorage,
  userID: string,
): BaselineCalibrationDraft | null {
  if (!userID.trim()) return null
  const raw = storage.getItem(draftKey(userID))
  if (!raw) return null
  try {
    const value = JSON.parse(raw) as LegacyBaselineCalibrationDraft
    if (!Number.isInteger(value.step) || value.step < 0 || value.step > 13) return null
    for (const domain of domains) {
      const answers = value.answers?.[domain]
      if (!Array.isArray(answers) || answers.length !== 3 || answers.some((answer) => !allowedAnswers.has(answer))) {
        return null
      }
    }
    const migratedIDs = Array.isArray(value.answered_question_ids)
      ? value.answered_question_ids.filter((id): id is string => typeof id === 'string' && questionIDs.has(id))
      : baselineCalibrationQuestions.flatMap((item) => (
        value.answers[item.domain][item.answer_index] === 'not_tested' ? [] : [item.id]
      ))
    const answeredQuestionIDs = [...new Set(migratedIDs)]
    let step = value.step
    if (!Array.isArray(value.answered_question_ids) && value.step > 0) {
      const firstUnanswered = baselineCalibrationQuestions.findIndex((item) => !answeredQuestionIDs.includes(item.id))
      step = firstUnanswered < 0 ? 13 : firstUnanswered + 1
    }
    return { step, answers: value.answers, answered_question_ids: answeredQuestionIDs }
  } catch {
    return null
  }
}

export function clearBaselineCalibrationDraft(storage: CalibrationDraftStorage, userID: string): void {
  if (userID.trim()) storage.removeItem(draftKey(userID))
}

export const emptyBaselineCalibrationAnswers = (): BaselineCalibrationAnswers => ({
  cardiorespiratory: ['not_tested', 'not_tested', 'not_tested'],
  upper_strength: ['not_tested', 'not_tested', 'not_tested'],
  lower_strength: ['not_tested', 'not_tested', 'not_tested'],
  mobility: ['not_tested', 'not_tested', 'not_tested'],
})

export function normalizedCalibrationEvidence(
  drafts: FitnessEvidenceDraft[],
  referenceNow: string,
): NormalizedFitnessEvidence[] {
  return drafts.flatMap((draft) => {
    const result = normalizeFitnessEvidence(draft, 'user', referenceNow)
    return result.status === 'accepted' ? [result.evidence] : []
  })
}
