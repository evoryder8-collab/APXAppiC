import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import {
  ONBOARDING_MOVEMENT_DOMAINS,
  evaluateOnboardingBaseline,
  summarizeOnboardingBaseline,
  type OnboardingBaselineFixture,
} from '../src/lib/onboardingBaseline.ts'
import {
  assessTrainingInput,
  generateTrainingPlan,
  trainingInputFromProfile,
  type TrainingInductionInput,
} from '../src/lib/trainingInduction.ts'

const fixture = JSON.parse(readFileSync(
  new URL('./fixtures/onboarding-baseline.json', import.meta.url),
  'utf8',
)) as OnboardingBaselineFixture

test('distilled onboarding matches the shared broad-band fixture', () => {
  for (const scenario of fixture.scenarios) {
    const result = evaluateOnboardingBaseline({
      user_id: fixture.user_id,
      measured_at: fixture.measured_at,
      imported_at: fixture.imported_at,
      answers: scenario.input,
    })
    assert.deepEqual(summarizeOnboardingBaseline(result), scenario.expected, scenario.name)
  }
})

test('onboarding evidence is low-confidence, band-only, and deterministic', () => {
  const scenario = fixture.scenarios[1]
  const input = {
    user_id: fixture.user_id,
    measured_at: fixture.measured_at,
    imported_at: fixture.imported_at,
    answers: scenario.input,
  }
  const first = evaluateOnboardingBaseline(input)
  const second = evaluateOnboardingBaseline(input)
  assert.equal(first.status, 'accepted')
  assert.equal(second.status, 'accepted')
  if (first.status !== 'accepted' || second.status !== 'accepted') return

  assert.deepEqual(first.evidence, second.evidence)
  assert.equal(first.bands.overall_fitness, 'building_baseline')
  for (const evidence of first.evidence) {
    assert.equal(evidence.source, 'structured_self_report')
    assert.equal(evidence.requested_confidence, 'low')
    assert.equal((evidence.metadata as Record<string, unknown>).display_precision, 'band_only')
    assert.match(evidence.client_idempotency_key, /^onboarding-v1:/)
  }
})

test('the mandatory movement pulse stays four-domain and uncertainty-safe', () => {
  assert.deepEqual(ONBOARDING_MOVEMENT_DOMAINS, [
    'cardiorespiratory',
    'upper_strength',
    'lower_strength',
    'mobility',
  ])

  const native = readFileSync(new URL(
    '../ios/APEXNative/APEX/Features/Onboarding/InductionView.swift',
    import.meta.url,
  ), 'utf8')
  assert.match(native, /private let stepCount = 8/)
  assert.match(native, /I haven't tested this/)
  assert.match(native, /How APEX estimated this/)
  assert.match(native, /Building your baseline/)
  assert.match(native, /induction-movement-(?:cardiorespiratory|upper-strength|lower-strength|mobility)/)
})

test('plan metadata preserves the distilled assessment and safety routing', () => {
  const input: TrainingInductionInput = {
    start_date: '2026-08-30',
    inactivity: 'under_three_months',
    venue: 'home',
    equipment: [],
    pain_areas: [],
    recent_operation: false,
    chronic_lower_back_pain: false,
    acute_symptoms: true,
    sessions_per_week: 4,
    plan_weeks: 12,
    available_minutes: 45,
    goal: 'rebuild',
    baseline_assessment: {
      version: 1,
      activity_pattern: 'mixed_day',
      movement: {
        cardiorespiratory: 'developing',
        upper_strength: 'capable',
        lower_strength: 'developing',
        mobility: 'not_tested',
      },
    },
  }
  assert.equal(assessTrainingInput(input).caution, 'clearance')
  const generated = generateTrainingPlan(fixture.user_id, input, [], 0, fixture.imported_at)
  assert.equal(generated.induction.available_minutes, 45)
  assert.deepEqual(generated.induction.baseline_assessment, input.baseline_assessment)
  assert.equal(generated.induction.acute_symptoms, true)

  const restored = trainingInputFromProfile(generated.induction, input.start_date)
  assert.equal(restored.available_minutes, 45)
  assert.deepEqual(restored.baseline_assessment, input.baseline_assessment)
  assert.equal(restored.acute_symptoms, true)
})

test('native submission stores activity and evidence through the guarded ledger', () => {
  const session = readFileSync(new URL(
    '../ios/APEXNative/APEX/App/AppSession.swift',
    import.meta.url,
  ), 'utf8')
  const service = readFileSync(new URL(
    '../ios/APEXNative/APEX/Core/Networking/SupabaseService.swift',
    import.meta.url,
  ), 'utf8')
  assert.match(session, /submission\.profileActivityLevel/)
  assert.match(session, /persistInductionEvidence\(submission/)
  assert.match(session, /recordFitnessEvidence\(evidence\)/)
  assert.match(service, /case activityLevel = "activity_level"/)
})

const onboardingFullKeys = [
  'Your normal week', 'Your movement pulse', 'Your setup', 'Train safely', 'Your starting map',
  'Choose the week you usually live, not your most active one.',
  'Four quick, observable signals give APEX a broad starting range. There is no penalty for not knowing.',
  'Pick what you can reliably use on a busy week. You can change it later.',
  'This decides what gets adapted or paused. Nothing here is shared with anyone.',
  'Broad early bands, never invented precision. You can sharpen them later from your Avatar.',
  'Most days, I am…', 'Mostly seated, with short walks', 'A mix of sitting and moving',
  'On my feet for much of the day', 'Doing physically demanding work', 'Not sure',
  'Swipe between the four movement questions.', 'Stamina', 'Upper body', 'Lower body', 'Mobility',
  'Which feels most like your stamina today?',
  'Which feels most like your upper-body strength today?',
  'Which feels most like your lower-body strength today?',
  'Which feels most like your comfortable range today?',
  'I need a pause after a few minutes of brisk movement.',
  'I can walk briskly for about 20 minutes without stopping.',
  'I can jog, cycle or row steadily for about 20 minutes.',
  'I train sustained or interval cardio comfortably.',
  'Pushing or pulling my body weight feels difficult.',
  'I can do wall or raised push-ups with control.',
  'I can do several floor push-ups or comparable rows.',
  'I regularly train challenging presses, pulls or pull-ups.',
  'Repeated chair stands or stairs tire my legs quickly.',
  'I can squat to a chair and climb stairs comfortably.',
  'I can do controlled deep squats or lunges.',
  'I regularly train challenging squats, hinges or split squats.',
  'Everyday movement feels restricted.', 'I move comfortably through normal daily ranges.',
  'I comfortably reach deep squat and hip-hinge positions.',
  'I train deep ranges such as full splits or advanced mobility work.',
  "I haven't tested this", 'How many training days fit a normal week?',
  'How much time fits most sessions?', 'About 30 minutes', 'About 45 minutes',
  'About 60 minutes', '75 minutes or more', 'Choose equipment (optional)', 'Plan horizon',
  'No equipment', 'Exercise has caused chest pain, faintness or unusual breathlessness',
  'Building your baseline', 'Foundation', 'Developing', 'Capable', 'Strong signal',
  'How APEX estimated this',
  'These are broad early bands from your answers, not measured test results. Self-report stays low confidence. Overall Fitness remains Building your baseline until APEX has enough region-specific evidence.',
  'Your plan will stay in clearance mode until a qualified clinician says loaded training is appropriate.',
] as const

const onboardingCompactKeys = [
  'Stamina', 'Upper body', 'Lower body', 'Mobility', 'Building your baseline',
  'Foundation', 'Developing', 'Capable', 'Strong signal',
] as const

function stringTableKeys(source: string): Set<string> {
  return new Set(Array.from(source.matchAll(/^"((?:[^"\\]|\\.)+)"\s*=/gm), (match) => match[1]))
}

test('every offered native locale authors the distilled onboarding copy', () => {
  const resources = new URL('../ios/APEXNative/APEX/Resources/', import.meta.url)
  const fullLocales = ['de-CH', 'de', 'es', 'it', 'ja', 'pt', 'ro', 'th']
  const compactLocales = ['en', ...fullLocales]
  for (const locale of fullLocales) {
    const keys = stringTableKeys(readFileSync(new URL(`${locale}.lproj/Localizable.strings`, resources), 'utf8'))
    const missing = onboardingFullKeys.filter((key) => !keys.has(key))
    assert.deepEqual(missing, [], `${locale} missing full onboarding keys`)
  }
  for (const locale of compactLocales) {
    const keys = stringTableKeys(readFileSync(new URL(`${locale}.lproj/LocalizableShort.strings`, resources), 'utf8'))
    const missing = onboardingCompactKeys.filter((key) => !keys.has(key))
    assert.deepEqual(missing, [], `${locale} missing compact onboarding keys`)
  }
})
