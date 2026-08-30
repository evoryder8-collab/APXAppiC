import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import {
  collapsedFitnessPlanDisclosure,
  recordFitnessPlanIntroPresentation,
  selectFitnessPlanInfo,
  toggleFitnessPlanDisclosure,
} from '../src/lib/fitnessPlanDisclosure.ts'
import { UI_TRANSLATIONS } from '../src/lib/translations.ts'
import { showsPersonaLabel } from '../src/lib/profileIdentity.ts'

test('first Fitness Plan expansion persists only after both subtitles arrive', () => {
  let state = toggleFitnessPlanDisclosure(collapsedFitnessPlanDisclosure(), false)

  assert.equal(state.expanded, true)
  assert.equal(state.showsIntroduction, true)
  assert.deepEqual(state.presentedIntroductionPhases, [])
  assert.equal(state.activeInfo, null)

  const transition = recordFitnessPlanIntroPresentation(state, 'transition')
  assert.equal(transition.shouldPersist, false)
  assert.deepEqual(transition.state.presentedIntroductionPhases, ['transition'])

  const main = recordFitnessPlanIntroPresentation(transition.state, 'main')
  assert.equal(main.shouldPersist, true)
  assert.deepEqual(main.state.presentedIntroductionPhases, ['transition', 'main'])

  const repeated = recordFitnessPlanIntroPresentation(main.state, 'main')
  assert.equal(repeated.shouldPersist, false)
  assert.deepEqual(repeated.state, main.state)
})

test('recurring Fitness Plan expansion shows one info tooltip at a time', () => {
  let state = toggleFitnessPlanDisclosure(collapsedFitnessPlanDisclosure(), true)

  assert.equal(state.expanded, true)
  assert.equal(state.showsIntroduction, false)
  assert.deepEqual(state.presentedIntroductionPhases, [])

  state = selectFitnessPlanInfo(state, 'transition')
  assert.equal(state.activeInfo, 'transition')
  state = selectFitnessPlanInfo(state, 'main')
  assert.equal(state.activeInfo, 'main')
  state = selectFitnessPlanInfo(state, 'main')
  assert.equal(state.activeInfo, null)

  state = toggleFitnessPlanDisclosure(state, true)
  assert.deepEqual(state, collapsedFitnessPlanDisclosure())
})

test('introduction copy and recurring info controls are mutually exclusive', () => {
  const introduction = toggleFitnessPlanDisclosure(collapsedFitnessPlanDisclosure(), false)
  const attemptedInfo = selectFitnessPlanInfo(introduction, 'transition')

  assert.equal(attemptedInfo.showsIntroduction, true)
  assert.equal(attemptedInfo.activeInfo, null)
})

test('Advanced surfaces put identity first and expand Fitness Plan in place', () => {
  const native = readFileSync(new URL('../ios/APEXNative/APEX/Features/Portal/PortalHomeView.swift', import.meta.url), 'utf8')
  const web = readFileSync(new URL('../src/pages/Portal.tsx', import.meta.url), 'utf8')
  const webDisclosure = readFileSync(new URL('../src/components/FitnessPlanDisclosure.tsx', import.meta.url), 'utf8')

  assert.ok(native.indexOf('ProfilePortalTile()') < native.indexOf('title: language.text(.nutrition)'))
  assert.ok(native.indexOf('title: language.text(.nutrition)') < native.indexOf('FitnessPlanDisclosure('))
  assert.match(native, /FitnessPlanDisclosure\([\s\S]*if session\.data\.programs\.contains\(where: \{ \$0\.slug == "custom" \}\)/)

  assert.ok(web.indexOf('to="/avatar"') < web.indexOf('to="/nutrition"'))
  assert.ok(web.indexOf('to="/nutrition"') < web.indexOf('<FitnessPlanDisclosure'))
  assert.match(web, /<FitnessPlanDisclosure[\s\S]*slug === 'custom'[\s\S]*to="\/custom-workouts"[\s\S]*to="\/orbit"/)
  assert.match(webDisclosure, /data-testid="portal\.fitness-plan"/)
  assert.match(webDisclosure, /aria-expanded=\{state\.expanded\}/)
  assert.match(webDisclosure, /role="tooltip"/)
})

test('first-use Fitness Plan completion persists through each platform settings outbox', () => {
  const native = readFileSync(new URL('../ios/APEXNative/APEX/Features/Portal/PortalHomeView.swift', import.meta.url), 'utf8')
  const web = readFileSync(new URL('../src/pages/Portal.tsx', import.meta.url), 'utf8')

  assert.match(native, /fitness_plan_intro_seen/)
  assert.match(native, /session\.updateSettings/)
  assert.match(web, /fitness_plan_intro_seen: true/)
  assert.match(web, /setSettings\(\{/)
})

test('Fitness Plan keeps first-use subtitles separate from recurring explanations', () => {
  const native = readFileSync(new URL('../ios/APEXNative/APEX/Features/Portal/PortalHomeView.swift', import.meta.url), 'utf8')
  const webDisclosure = readFileSync(new URL('../src/components/FitnessPlanDisclosure.tsx', import.meta.url), 'utf8')
  const requiredCopy = [
    "If you haven't trained in a long time.",
    'Fit enough to start the main journey.',
    'Return here after a long break to rebuild consistency, movement quality and training tolerance.',
    "Choose this when regular training feels manageable and you're ready to build strength, muscle and performance.",
  ]

  for (const copy of requiredCopy) {
    assert.ok(native.includes(copy), `native is missing: ${copy}`)
    assert.ok(webDisclosure.includes(copy), `web is missing: ${copy}`)
  }
})

test('native Fitness Plan keeps compact visible copy and full VoiceOver explanations', () => {
  const native = readFileSync(new URL('../ios/APEXNative/APEX/Features/Portal/PortalHomeView.swift', import.meta.url), 'utf8')

  assert.match(native, /accessibilityLabel\(language\.text\("Fitness Plan"\)\)/)
  assert.match(native, /titleAccessibility: language\.text\("Transition Phase"\)/)
  assert.match(native, /introductionAccessibility: language\.text\("If you haven't trained in a long time\."\)/)
  assert.match(native, /information: language\.text\("Return here after a long break to rebuild consistency, movement quality and training tolerance\."\)/)
  assert.match(native, /titleAccessibility: language\.text\("Main Phase"\)/)
  assert.match(native, /introductionAccessibility: language\.text\("Fit enough to start the main journey\."\)/)
  assert.match(native, /information: language\.text\("Choose this when regular training feels manageable and you're ready to build strength, muscle and performance\."\)/)
})

test('web Fitness Plan copy is authored for every offered non-English language', () => {
  const expected: Record<string, { ro: string; th: string }> = {
    'Fitness Plan': { ro: 'Plan de antrenament', th: 'แผนการฝึก' },
    "If you haven't trained in a long time.": {
      ro: 'Revii la antrenamente după o pauză lungă.',
      th: 'กลับมาฝึกหลังหยุดไปนาน',
    },
    'Fit enough to start the main journey.': {
      ro: 'Ai baza necesară pentru etapa principală.',
      th: 'ฟิตพอที่จะเริ่มช่วงหลัก',
    },
    'Return here after a long break to rebuild consistency, movement quality and training tolerance.': {
      ro: 'Revino aici după o pauză lungă ca să-ți refaci ritmul, tehnica și toleranța la efort.',
      th: 'ถ้าหยุดฝึกไปนาน ให้เริ่มตรงนี้เพื่อเรียกความสม่ำเสมอ ฟอร์มการเคลื่อนไหว และความพร้อมรับการฝึกกลับมา',
    },
    "Choose this when regular training feels manageable and you're ready to build strength, muscle and performance.": {
      ro: 'Alege etapa asta când te antrenezi deja constant și ești gata să crești în forță, masă musculară și performanță.',
      th: 'เลือกช่วงนี้เมื่อฝึกเป็นประจำได้สบายแล้ว และพร้อมพัฒนาความแข็งแรง กล้ามเนื้อ และสมรรถนะ',
    },
    'Back after a long break?': { ro: 'Revii după o pauză lungă.', th: 'กลับมาฝึกหลังพักนาน' },
    'Ready for the main phase.': { ro: 'Ești gata pentru etapa principală.', th: 'พร้อมเริ่มช่วงหลัก' },
    'Sessions you built yourself': { ro: 'Sesiuni create de tine', th: 'เซสชันที่คุณสร้างเอง' },
  }

  for (const [key, translations] of Object.entries(expected)) {
    assert.deepEqual(UI_TRANSLATIONS[key], translations, `missing authored web copy for ${key}`)
  }
})

test('Fitness Plan exposes stable accessible controls and a vertical phase hierarchy', () => {
  const native = readFileSync(new URL('../ios/APEXNative/APEX/Features/Portal/PortalHomeView.swift', import.meta.url), 'utf8')
  const web = readFileSync(new URL('../src/components/FitnessPlanDisclosure.tsx', import.meta.url), 'utf8')

  for (const identifier of [
    'portal.fitness-plan',
    'portal.transition',
    'portal.main',
    'fitness-plan.info.transition',
    'fitness-plan.info.main',
  ]) {
    assert.ok(native.includes(identifier), `native is missing ${identifier}`)
    assert.ok(web.includes(identifier), `web is missing ${identifier}`)
  }
  assert.match(native, /accessibilityValue[\s\S]*(Expanded|Collapsed)/)
  assert.doesNotMatch(web, /sm:grid-cols-2/)
  assert.match(web, /initial=\{\{ opacity: 0, y: reducedMotion \? 0 : 26 \}\}/)
})

test('Settings hides only a persona label that repeats the display name', () => {
  assert.equal(showsPersonaLabel('Constantine', 'CONSTANTINE'), false)
  assert.equal(showsPersonaLabel('Iulian', 'IULIÁN'), false)
  assert.equal(showsPersonaLabel('Iulian-Andrei', 'Iulian'), true)
})

test('Settings gives the name its own non-hyphenating row on native and web', () => {
  const native = readFileSync(new URL('../ios/APEXNative/APEX/Features/Settings/SettingsView.swift', import.meta.url), 'utf8')
  const web = readFileSync(new URL('../src/pages/Settings.tsx', import.meta.url), 'utf8')

  assert.match(native, /Text\(profile\?\.displayName \?\? "APEX"\)[\s\S]*\.lineLimit\(1\)[\s\S]*\.allowsTightening\(true\)/)
  assert.doesNotMatch(native, /minimumScaleFactor/)
  assert.match(web, /whitespace-nowrap/)
  assert.match(web, /\[hyphens:none\]/)
  assert.match(native, /ProfileIdentityPresentation\.showsPersona/)
  assert.match(web, /showsPersonaLabel/)
})
