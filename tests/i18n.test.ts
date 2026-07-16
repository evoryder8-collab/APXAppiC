import assert from 'node:assert/strict'
import test from 'node:test'
import { isSelectableIntroLanguage, LANGUAGE_OPTIONS, localizedLoginError } from '../src/lib/introLanguage.ts'
import { ACTIVITY_TRANSLATIONS, UI_TRANSLATIONS } from '../src/lib/translations.ts'
import { translateAvatarAssessmentSummary } from '../src/lib/avatarLocalization.ts'
import { replaceInterfaceSegment } from '../src/lib/translationSegments.ts'

test('language selector always exposes English, Thai, and Romanian', () => {
  assert.deepEqual(LANGUAGE_OPTIONS.map((option) => option.value), ['en', 'th', 'ro'])
  assert.equal(isSelectableIntroLanguage('en'), true)
  assert.equal(isSelectableIntroLanguage('th'), true)
  assert.equal(isSelectableIntroLanguage('ro'), true)
})

test('critical app surfaces have complete Romanian and Thai copy', () => {
  const critical = [
    'Nutrition',
    "Today's Activities",
    'Daily targets',
    'Food tracker',
    'Visual Progress',
    'Settings',
    'What your body needs',
    'Include stats',
    'No APEX stats for this date',
    'Interface mode',
    'Today’s checklist',
    'APEX Body Index',
    'Upper Body Strength',
    'Lower Body Strength',
    'Muscle target map',
    'Holographic body',
    'You’re about to log out. Are you sure?',
    'Language',
    'Replace meal',
    'adaptive',
    'lock',
    'fixed',
    "Today's record",
    'Activity mode',
    'Estimated TDEE',
    'Eaten ✓',
    'Not checked',
    'Create your own workout',
    'Voice coach',
    'Measured BMR (optional)',
    'protein / 100 g',
    'Built naturally. Refined intelligently.',
    'Your next run, already reasoned through',
    'Athletic Base',
    'Living profile',
    'LIFELONG ATHLETE',
    'ENDURANCE ATHLETE',
    'BALANCED PERFORMANCE',
    'Workout stats at a glance',
    'Log the weight used for this set.',
    'Four calm checks make every future comparison more meaningful.',
    'Shareable progress card',
    'Export PNG',
    'Camera & comparison',
    'Comparison export stats',
    'Minimal exports show only APEX, Before/After, and each photo’s date and time.',
    'Detailed exports add elapsed days, completed workouts, and strength/load stats.',
    '12-Week Home Foundation',
    'Home Full Body B',
    'Natural Bodybuilding',
    'Reduced-volume gym re-entry',
    'This food could not be added. Please try again.',
    'This provider record is incomplete. Review the missing values before saving your private corrected copy.',
    'Product not found. Add it manually and keep it private.',
    'Nutrition is incomplete. Review it manually before logging.',
    'Barcode lookup is temporarily unavailable. Search by name or create a private food instead.',
    'This result is incomplete. Review all per-100 g values before saving it privately.',
    'Name and all four per-100 g nutrition values are required.',
    'Planned meal',
  ]
  for (const english of critical) {
    assert.ok(UI_TRANSLATIONS[english]?.ro, `missing Romanian: ${english}`)
    assert.ok(UI_TRANSLATIONS[english]?.th, `missing Thai: ${english}`)
  }
})

test('login errors are localized without translating June as a month', () => {
  assert.equal(localizedLoginError('Invalid login credentials', 'ro'), 'Adresa de e-mail sau parola sunt incorecte.')
  assert.equal(localizedLoginError('Invalid login credentials', 'th'), 'อีเมลหรือรหัสผ่านไม่ถูกต้อง')
  assert.match(localizedLoginError('Those credentials belong to June. Choose that profile to continue.', 'ro'), /June/)
})

test('shared activity catalog names, categories and guidance are translated without per-user copies', () => {
  const byName = new Map(ACTIVITY_TRANSLATIONS.map(([english, ro, th]) => [english, { ro, th }]))
  for (const activity of [
    'Massage session given',
    'Handheld or gimbal filming',
    'Full gym session',
    'Steps not already covered by the blocks above.',
    'Moving while filming with handheld or stabilized camera equipment.',
  ]) {
    assert.ok(byName.get(activity)?.ro, `missing Romanian activity: ${activity}`)
    assert.ok(byName.get(activity)?.th, `missing Thai activity: ${activity}`)
  }
  for (const category of ['Hands-on therapy', 'Camera work', 'General work', 'Errands and life']) {
    assert.ok(UI_TRANSLATIONS[category]?.ro, `missing Romanian activity category: ${category}`)
    assert.ok(UI_TRANSLATIONS[category]?.th, `missing Thai activity category: ${category}`)
  }
})

test('camera framing and quick activity presets use exact native-language labels', () => {
  assert.equal(UI_TRANSLATIONS['Torso only']?.ro, 'Doar trunchi')
  assert.equal(replaceInterfaceSegment('Doar trunchi', 'run', 'alergare'), 'Doar trunchi')
  assert.equal(replaceInterfaceSegment('Morning run', 'run', 'alergare'), 'Morning alergare')
  const byName = new Map(ACTIVITY_TRANSLATIONS.map(([english, ro, th]) => [english, { ro, th }]))
  assert.deepEqual(byName.get('4h standing'), { ro: '4 h în picioare', th: 'ยืน 4 ชม.' })
  assert.deepEqual(byName.get('1h childcare'), { ro: '1 h îngrijire copii', th: 'ดูแลเด็ก 1 ชม.' })
})

test('advanced nutrition calendar copy and clear actions are fully localized', () => {
  for (const label of [
    'Previous month',
    'Next month',
    'Choose where to paste',
    'Calendar day actions',
    'Copy or clear this day’s meals and snacks.',
    'Paste copied day',
    'Select meals or snacks',
    'Choose individual meals or snacks',
    'All selected meals and snacks',
    'Clearing…',
    'Pasting…',
    'Paste selected',
    'Meal and snack selections cleared',
    'Could not clear this day.',
    'Could not paste this day.',
  ]) {
    assert.ok(UI_TRANSLATIONS[label]?.ro, `missing Romanian calendar action: ${label}`)
    assert.ok(UI_TRANSLATIONS[label]?.th, `missing Thai calendar action: ${label}`)
  }
})

test('Avatar runtime titles and recommendation copy are available in both localized languages', () => {
  const avatarCopy = [
    'Endurance & VO2max',
    'Solid base with a clear next unlock',
    'Strong foundation. Refine the weak link',
    'Foundation phase. Make the basics repeatable',
    'Aerobic adaptations fade fastest, on a half-life of roughly 12 days without a stimulus.',
    'Make hydration, protein and a complete evening log the daily floor; those are the fastest controllable inputs to your Health score.',
  ]
  for (const english of avatarCopy) {
    assert.ok(UI_TRANSLATIONS[english]?.ro, `missing Romanian Avatar copy: ${english}`)
    assert.ok(UI_TRANSLATIONS[english]?.th, `missing Thai Avatar copy: ${english}`)
  }
})

test('Avatar assessment localizes every weakest-stat and trend sentence combination', () => {
  const trends = [
    'Your Overall score is broadly stable, so the next improvement will come from consistently feeding the weakest quality.',
    'Your Overall score has risen 1.7 points over the comparison window, so the current direction is productive.',
    'Your Overall score has fallen 2.1 points over the comparison window, which points to an underfed training or recovery input.',
  ]
  for (const trend of trends) {
    const english = `Joint health is the clearest limiter at 57, while Endurance currently leads at 72. ${trend}`
    const thai = translateAvatarAssessmentSummary(english, 'th')
    const romanian = translateAvatarAssessmentSummary(english, 'ro')
    assert.ok(thai?.includes('สุขภาพข้อต่อ เป็นข้อจำกัดหลักที่ 57'))
    assert.ok(thai?.includes('ความอดทน นำที่ 72'))
    assert.ok(romanian?.includes('Sănătatea articulațiilor este limita principală la 57'))
    assert.ok(romanian?.includes('Anduranță conduce la 72'))
    assert.equal(thai?.includes('clearest limiter'), false)
    assert.equal(romanian?.includes('clearest limiter'), false)
  }
})
