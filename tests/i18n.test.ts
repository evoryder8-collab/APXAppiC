import assert from 'node:assert/strict'
import test from 'node:test'
import { isSelectableIntroLanguage, LANGUAGE_OPTIONS } from '../src/lib/introLanguage.ts'
import { ACTIVITY_TRANSLATIONS, UI_TRANSLATIONS } from '../src/lib/translations.ts'
import { translateAvatarAssessmentSummary } from '../src/lib/avatarLocalization.ts'

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
    'You’re about to log out. Are you sure?',
    'Language',
  ]
  for (const english of critical) {
    assert.ok(UI_TRANSLATIONS[english]?.ro, `missing Romanian: ${english}`)
    assert.ok(UI_TRANSLATIONS[english]?.th, `missing Thai: ${english}`)
  }
})

test('shared activity catalog names are translated without per-user copies', () => {
  const byName = new Map(ACTIVITY_TRANSLATIONS.map(([english, ro, th]) => [english, { ro, th }]))
  for (const activity of ['Massage session given', 'Handheld or gimbal filming', 'Full gym session', 'Steps not already covered by the blocks above.']) {
    assert.ok(byName.get(activity)?.ro, `missing Romanian activity: ${activity}`)
    assert.ok(byName.get(activity)?.th, `missing Thai activity: ${activity}`)
  }
})

test('Avatar runtime titles and recommendation copy are available in both localized languages', () => {
  const avatarCopy = [
    'Endurance & VO2max',
    'Solid base with a clear next unlock',
    'Strong foundation — refine the weak link',
    'Foundation phase — make the basics repeatable',
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
