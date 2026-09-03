import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { UI_TRANSLATIONS } from '../src/lib/translations.ts'
import * as baselineCalibration from '../src/lib/baselineCalibration.ts'

import {
  baselineCalibrationQuestions,
  baselineCalibrationAuthority,
  buildDxaCalibrationEvidence,
  buildManualCalibrationEvidence,
  evaluateBaselineCalibration,
  isBaselineCalibrationQuestionAnswered,
  loadBaselineCalibrationDraft,
  saveBaselineCalibrationDraft,
  summarizeBaselineCalibration,
  type BaselineCalibrationFixture,
  type CalibrationDraftStorage,
} from '../src/lib/baselineCalibration.ts'

const fixture = JSON.parse(readFileSync(
  new URL('./fixtures/baseline-calibration.json', import.meta.url),
  'utf8',
)) as BaselineCalibrationFixture

test('long-form calibration matches the shared uncertainty-aware fixture', () => {
  for (const scenario of fixture.scenarios) {
    const result = evaluateBaselineCalibration({
      user_id: fixture.user_id,
      measured_at: fixture.measured_at,
      imported_at: fixture.imported_at,
      answers: scenario.input,
    })
    assert.deepEqual(summarizeBaselineCalibration(result), scenario.expected, scenario.name)
  }
})

test('calibration evidence remains low-confidence, band-only, and never creates Overall', () => {
  const result = evaluateBaselineCalibration({
    user_id: fixture.user_id,
    measured_at: fixture.measured_at,
    imported_at: fixture.imported_at,
    answers: fixture.scenarios[1].input,
  })
  assert.equal(result.status, 'accepted')
  if (result.status !== 'accepted') return
  assert.equal(result.bands.overall_fitness, 'building_baseline')
  assert.equal(result.evidence.some((item) => item.metric === 'overall_fitness'), false)
  for (const item of result.evidence) {
    assert.equal(item.source, 'structured_self_report')
    assert.equal(item.requested_confidence, 'low')
    assert.equal((item.metadata as Record<string, unknown>).display_precision, 'band_only')
    assert.match(item.client_idempotency_key, /^calibration-v1:/)
  }
})

test('recent external results are validated and never promoted beyond user evidence', () => {
  const accepted = buildManualCalibrationEvidence({
    user_id: fixture.user_id,
    metric: 'resting_metabolic_rate',
    value: 1683,
    unit: 'kcal_per_day',
    declared_source: 'DEXA report',
    measured_at: fixture.measured_at,
    imported_at: fixture.imported_at,
  })
  assert.equal(accepted.status, 'accepted')
  if (accepted.status === 'accepted') {
    assert.equal(accepted.evidence.source, 'user_entered_external_result')
    assert.equal(accepted.evidence.confidence, 'low')
    assert.equal(accepted.evidence.metadata.declared_source, 'DEXA report')
  }
  assert.deepEqual(buildManualCalibrationEvidence({
    user_id: fixture.user_id,
    metric: 'vo2_max',
    value: 999,
    unit: 'ml_per_kg_min',
    declared_source: 'Lab result',
    measured_at: fixture.measured_at,
    imported_at: fixture.imported_at,
  }), { status: 'rejected', reason: 'invalid_unit_or_range' })
})

test('recent-result dates fail closed when empty, malformed, or impossible', () => {
  const measuredAt = (baselineCalibration as typeof baselineCalibration & {
    calibrationResultMeasuredAt?: (date: string) => string | null
  }).calibrationResultMeasuredAt
  assert.equal(typeof measuredAt, 'function')
  if (!measuredAt) return

  assert.equal(measuredAt(''), null)
  assert.equal(measuredAt('not-a-date'), null)
  assert.equal(measuredAt('2026-02-30'), null)
  assert.equal(measuredAt('2026-09-03'), '2026-09-03T12:00:00.000Z')
})

test('calibration presents one direct question with question-specific answers', () => {
  assert.equal(baselineCalibrationQuestions.length, 12)
  assert.deepEqual(
    [...new Set(baselineCalibrationQuestions.map((question) => question.id))].length,
    12,
  )
  for (const question of baselineCalibrationQuestions) {
    assert.equal(question.options.length, 4, question.id)
    assert.deepEqual(question.options.map((option) => option.value), [
      'foundation', 'developing', 'capable', 'strong',
    ])
    assert.equal(new Set(question.options.map((option) => option.label)).size, 4, question.id)
    assert.equal(question.options.some((option) => [
      'Foundation', 'Developing', 'Capable', 'Strong signal',
    ].includes(option.label)), false, question.id)
  }
})

test('Continue requires an explicit response while Not sure remains a valid choice', () => {
  const unanswered = {
    step: 1,
    answers: fixture.scenarios[0].input,
    answered_question_ids: [],
  }
  const firstQuestion = baselineCalibrationQuestions[0]
  assert.equal(isBaselineCalibrationQuestionAnswered(unanswered, firstQuestion.id), false)
  const explicitNotSure = { ...unanswered, answered_question_ids: [firstQuestion.id] }
  assert.equal(isBaselineCalibrationQuestionAnswered(explicitNotSure, firstQuestion.id), true)
})

test('a DEXA report can save body fat and its printed resting-energy estimate together', () => {
  const result = buildDxaCalibrationEvidence({
    user_id: fixture.user_id,
    body_fat_percentage: 18.4,
    resting_metabolic_rate: 1683,
    declared_source: 'DEXA report · clinic copy',
    measured_at: fixture.measured_at,
    imported_at: fixture.imported_at,
  })
  assert.equal(result.status, 'accepted')
  if (result.status !== 'accepted') return
  assert.deepEqual(result.evidence.map((item) => item.metric), [
    'body_fat_percentage',
    'resting_metabolic_rate',
  ])
  assert.ok(result.evidence.every((item) => item.confidence === 'low'))
  assert.ok(result.evidence.every((item) => item.metadata.declared_source === 'DEXA report · clinic copy'))
  assert.deepEqual(result.persistence, {
    owner_id: fixture.user_id,
    profile_patch: {
      body_fat_pct: 18.4,
      body_fat_source: 'dexa',
      body_fat_measured_at: fixture.measured_at,
    },
    settings_addons_patch: {
      custom_bmr: 1683,
      custom_bmr_source: 'dexa_report_estimate',
    },
  })
  assert.deepEqual(buildDxaCalibrationEvidence({
    user_id: fixture.user_id,
    body_fat_percentage: null,
    resting_metabolic_rate: null,
    declared_source: 'DEXA report',
    measured_at: fixture.measured_at,
    imported_at: fixture.imported_at,
  }), { status: 'rejected', reason: 'missing_value' })
})

test('a DEXA report value outside the target-safe resting-energy range remains evidence only', () => {
  const result = buildDxaCalibrationEvidence({
    user_id: fixture.user_id,
    body_fat_percentage: null,
    resting_metabolic_rate: 700,
    declared_source: 'DEXA report',
    measured_at: fixture.measured_at,
    imported_at: fixture.imported_at,
  })

  assert.equal(result.status, 'accepted')
  if (result.status !== 'accepted') return
  assert.deepEqual(result.evidence.map((item) => item.value), [700])
  assert.deepEqual(result.persistence, {
    owner_id: fixture.user_id,
    profile_patch: null,
    settings_addons_patch: null,
  })
})

test('a DEXA report keeps stronger indirect-calorimetry resting energy authoritative', () => {
  const result = buildDxaCalibrationEvidence({
    user_id: fixture.user_id,
    body_fat_percentage: 18.4,
    resting_metabolic_rate: 1_600,
    declared_source: 'DEXA report',
    measured_at: fixture.measured_at,
    imported_at: fixture.imported_at,
    existing_custom_bmr: 1_720,
    existing_custom_bmr_source: 'indirect_calorimetry',
  })

  assert.equal(result.status, 'accepted')
  if (result.status !== 'accepted') return
  assert.deepEqual(result.evidence.map((item) => item.value), [18.4, 1_600])
  assert.deepEqual(result.persistence.profile_patch, {
    body_fat_pct: 18.4,
    body_fat_source: 'dexa',
    body_fat_measured_at: fixture.measured_at,
  })
  assert.equal(result.persistence.settings_addons_patch, null)
})

test('resume drafts are account scoped and cleared only for their owner', () => {
  const values = new Map<string, string>()
  const storage: CalibrationDraftStorage = {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => { values.set(key, value) },
    removeItem: (key) => { values.delete(key) },
  }
  const draft = {
    step: 7,
    answers: fixture.scenarios[1].input,
    answered_question_ids: baselineCalibrationQuestions.slice(0, 6).map((question) => question.id),
  }
  saveBaselineCalibrationDraft(storage, fixture.user_id, draft)
  assert.deepEqual(loadBaselineCalibrationDraft(storage, fixture.user_id), draft)
  assert.equal(loadBaselineCalibrationDraft(storage, 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'), null)
})

test('legacy owner-scoped drafts migrate to explicit question completion', () => {
  const values = new Map<string, string>()
  const storage: CalibrationDraftStorage = {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => { values.set(key, value) },
    removeItem: (key) => { values.delete(key) },
  }
  const legacy = {
    step: 2,
    answers: fixture.scenarios[1].input,
  }
  saveBaselineCalibrationDraft(storage, fixture.user_id, legacy)
  const migrated = loadBaselineCalibrationDraft(storage, fixture.user_id)
  assert.ok(migrated)
  assert.ok(migrated.answered_question_ids.length > 0)
  assert.ok(migrated.step >= 1 && migrated.step <= 13)
})

test('calibration can refine evidence but has no programme authority', () => {
  assert.deepEqual(baselineCalibrationAuthority('standard'), {
    can_refine_evidence: true,
    can_replace_programme: false,
    can_authorize_bespoke: false,
  })
  assert.deepEqual(baselineCalibrationAuthority('bespoke'), {
    can_refine_evidence: true,
    can_replace_programme: false,
    can_authorize_bespoke: false,
  })
})

test('Avatar places the accessible calibration control immediately above Stats on both clients', () => {
  const native = readFileSync(new URL(
    '../ios/APEXNative/APEX/Features/Avatar/AvatarView.swift',
    import.meta.url,
  ), 'utf8')
  const nativePortalShell = readFileSync(new URL(
    '../ios/APEXNative/APEX/Features/Portal/PortalShellView.swift',
    import.meta.url,
  ), 'utf8')
  const web = readFileSync(new URL('../src/pages/AvatarPage.tsx', import.meta.url), 'utf8')
  assert.ok(native.indexOf('calibrationControl') < native.indexOf('statsCard'))
  assert.match(native, /avatar\.calibrate-baseline/)
  assert.match(native, /Calibrate my baseline/)
  assert.match(native, /onCalibrateBaseline\(\)/)
  assert.match(nativePortalShell, /@State private var showBaselineCalibration/)
  assert.match(nativePortalShell, /BaselineCalibrationSheet\(\)/)
  assert.ok(web.indexOf('data-testid="avatar-calibrate-baseline"') < web.indexOf('{\/\* Stat bars \*\/}'))
  assert.match(web, /aria-label=\{t\('Calibrate my baseline'\)\}/)
  assert.match(web, /BaselineCalibrationDialog/)
})

const redesignedCalibrationKeys = [
  ...baselineCalibrationQuestions.flatMap((question) => [
    question.prompt,
    ...question.options.map((option) => option.label),
  ]),
  'A clearer starting point', '12 clear questions · about 3 minutes',
  'Lab & DEXA results · about 1 minute', 'Question',
  'Choose what has felt true recently. Never test through pain.', 'Choose one answer',
  "I'm not sure or haven't done this recently", 'Choose one answer before continuing.',
  'Calibration complete', 'Not enough recent answers to change a band yet. Your existing baseline stays safe.',
  'Keep my existing baseline', 'Evidence, not guesswork', 'What are you adding?',
  'Choose the report you have. APEX will only ask for values that belong to it.',
  'DEXA body composition report', 'Save body fat and any resting-energy estimate printed on the same report.',
  'Other health or fitness result', 'Add VO₂ max, resting heart rate, waist or a metabolic test.',
  'DEXA REPORT', 'Add your DEXA results',
  'Enter either value or both. Leave a field blank when it is not printed on your report.',
  'DEXA measures body composition. Some reports also print an estimated BMR or RMR; APEX stores that number as report-supplied, not as a direct metabolic measurement.',
  'Body fat (optional)', 'Resting metabolism printed on the report (optional)', 'kcal/day',
  'Save DEXA results', 'Enter at least one valid value and name the report or clinic.',
  'DEXA results saved', 'RECENT RESULT', 'Add another result',
  'Manual entries stay low-confidence until a supported source confirms them.',
  'Report or clinic', 'You can close this screen. These values are now part of your private evidence history.',
  'Add another',
] as const

const calibrationFullKeys = [...new Set([
  'Calibrate my baseline', 'Opens a resumable baseline questionnaire.', 'Sharpen your map',
  'Add better evidence without turning fitness into a test you can fail.',
  'Your bespoke plan stays protected. Calibration only refines your evidence.',
  'Calibration refines your evidence. It never rewrites your training or nutrition plan.',
  'Sharpen with questions', 'Twelve observable prompts in four short sections.',
  'Connect what you track', 'Import the Apple Health categories you choose.',
  'Add a recent result', 'Keep a DEXA, metabolic, VO₂, heart-rate or waist result with its source.',
  'Your question progress is saved privately on this device.', 'Calibration progress',
  'Answer from recent, pain-free experience. Do not test a movement now. Choose Not tested if pain or uncertainty is involved.',
  'Read each line left to right: Foundation, Developing, Capable, Strong signal.',
  'Sustained effort: a few minutes · brisk 20 minutes · steady cardio 20 minutes · trained intervals',
  'Stairs: frequent pause · one flight comfortable · several flights controlled · repeated climbs trained',
  'Conditioning week: none · one easy session · two steady sessions · three or more purposeful sessions',
  'Pressing: body weight difficult · raised push-ups · floor push-ups · challenging presses',
  'Pulling: little recent work · light supported rows · controlled rows · pull-ups or challenging pulls',
  'Upper-body training: none · occasional · weekly progressive work · multiple challenging sessions',
  'Chair and stairs: tiring · comfortable · repeated with control · high work capacity',
  'Squat and lunge: restricted · chair-depth control · deep controlled reps · challenging full-range work',
  'Lower-body training: none · occasional · weekly progressive work · multiple challenging sessions',
  'Hips and posterior chain: daily restriction · functional reach · deep hinge or squat · advanced range practice',
  'Ankles: heels lift early · daily range comfortable · knee-over-toe range controlled · deep loaded range trained',
  'Shoulders: overhead reach restricted · daily reach comfortable · full overhead control · advanced range trained',
  'Review my baseline', 'Your sharper starting map',
  'These remain broad bands, not laboratory measurements. Overall Fitness stays Building your baseline until enough independent evidence exists.',
  'Answer at least two prompts in a section to sharpen that band.', 'Saved to your evidence',
  'Save baseline', 'Your baseline could not be saved yet. Your answers remain on this device.',
  'Back to questions', 'APEX keeps a value you enter as unverified until a supported source confirms it.',
  'Result type', 'Where did this result come from?', 'For example, DEXA report or laboratory test',
  'Measured on', 'Result saved', 'Save result', 'Check the value and source, then try again.',
  'You choose what APEX can read. Denial or missing data never lowers your baseline, and manual calibration always remains available.',
  'Apple Health synced the categories you allowed.',
  'No new permitted data was available. You can keep calibrating manually.', 'Connect Apple Health',
  'Apple Health connects through the APEX iPhone app, where iOS lets you choose each category. Denial or missing data never lowers your baseline.',
  'Open Avatar on your iPhone and choose Edit, then Connect what you track. Your manual routes remain available here.',
  'Resting energy (BMR/RMR)', 'Waist circumference', 'Value', 'VO₂ max',
  'Resting heart rate', 'Not tested', 'Saving…',
  ...redesignedCalibrationKeys,
])]

const calibrationCompactKeys = [
  'Edit', 'Back', 'Continue', 'Review my baseline', 'Save baseline', 'Save result',
  'Connect Apple Health', 'Not tested', 'Save DEXA results', 'Add another',
  "I'm not sure or haven't done this recently",
] as const

function stringTableKeys(source: string): Set<string> {
  return new Set(Array.from(source.matchAll(/^"((?:[^"\\]|\\.)+)"\s*=/gm), (match) => match[1]))
}

test('every offered locale authors the full and constrained calibration copy', () => {
  for (const key of calibrationFullKeys) {
    assert.ok(UI_TRANSLATIONS[key]?.ro, `missing Romanian web calibration copy: ${key}`)
    assert.ok(UI_TRANSLATIONS[key]?.th, `missing Thai web calibration copy: ${key}`)
  }

  const resources = new URL('../ios/APEXNative/APEX/Resources/', import.meta.url)
  const fullLocales = ['de-CH', 'de', 'es', 'it', 'ja', 'pt', 'ro', 'th']
  const compactLocales = ['en', ...fullLocales]
  for (const locale of fullLocales) {
    const keys = stringTableKeys(readFileSync(new URL(`${locale}.lproj/Localizable.strings`, resources), 'utf8'))
    assert.deepEqual(calibrationFullKeys.filter((key) => !keys.has(key)), [], `${locale} missing full calibration keys`)
  }
  for (const locale of compactLocales) {
    const keys = stringTableKeys(readFileSync(new URL(`${locale}.lproj/LocalizableShort.strings`, resources), 'utf8'))
    assert.deepEqual(calibrationCompactKeys.filter((key) => !keys.has(key)), [], `${locale} missing compact calibration keys`)
  }
})
