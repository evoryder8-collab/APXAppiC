import assert from 'node:assert/strict'
import test from 'node:test'
import { isSelectableIntroLanguage, LANGUAGE_OPTIONS } from '../src/lib/introLanguage.ts'
import { ACTIVITY_TRANSLATIONS, UI_TRANSLATIONS } from '../src/lib/translations.ts'

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
