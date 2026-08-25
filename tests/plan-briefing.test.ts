import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import test from 'node:test'
import {
  buildPlanBriefing,
  type PlanBriefingInput,
} from '../src/lib/planBriefing.ts'

const input: PlanBriefingInput = {
  language: 'en',
  planWeeks: 12,
  sessionsPerWeek: 4,
  goal: 'strength',
  venue: 'gym',
  caution: 'standard',
  sex: 'male',
  weightKg: 80,
  plannedExerciseMinutes: 60,
  hydrationMode: 'automatic',
  customHydrationTargetML: null,
  displayUnit: 'liters',
}

test('generated plan briefing is ordered and begins with the installed plan facts', () => {
  const briefing = buildPlanBriefing(input)

  assert.deepEqual(
    briefing.slides.map((slide) => slide.kind),
    ['overview', 'safety', 'hydration', 'sleep', 'supplements'],
  )
  assert.match(briefing.slides[0].title, /12-week strength plan/i)
  assert.match(briefing.slides[0].body, /4 sessions per week/i)
  assert.equal(briefing.slides[0].assetName, 'plan-briefing-overview')
})

test('six-month plans are described as six months rather than twenty-six weeks', () => {
  const briefing = buildPlanBriefing({ ...input, planWeeks: 26 })
  assert.match(briefing.slides[0].title, /6-month strength plan/i)
  assert.doesNotMatch(briefing.slides[0].title, /26-week/i)
})

test('hydration briefing uses the shared personalized target and chosen unit', () => {
  const liters = buildPlanBriefing(input)
  const gallons = buildPlanBriefing({ ...input, displayUnit: 'gallons' })

  assert.equal(liters.hydrationTargetML, 3_250)
  assert.match(liters.slides[2].title, /3\.25 L/)
  assert.match(gallons.slides[2].title, /0\.86 US gal/)
  assert.match(liters.slides[2].body, /drinks and food/i)
  assert.match(liters.slides[2].bullets.join(' '), /long, hot, or very sweaty/i)
  assert.match(liters.slides[2].bullets.join(' '), /sodium-restricted/i)
  assert.doesNotMatch(liters.slides[2].bullets.join(' '), /pinch of salt/i)
})

test('custom hydration targets remain exact in the generated briefing', () => {
  const briefing = buildPlanBriefing({
    ...input,
    hydrationMode: 'custom',
    customHydrationTargetML: 3_800,
  })

  assert.equal(briefing.hydrationTargetML, 3_800)
  assert.match(briefing.slides[2].title, /3\.80 L/)
})

test('safety and supplements slides distinguish stop rules, emergencies, and optional aids', () => {
  const briefing = buildPlanBriefing(input)
  const safety = briefing.slides[1]
  const supplements = briefing.slides[4]

  assert.match(safety.body, /stop/i)
  assert.match(safety.bullets.join(' '), /chest pressure|chest pain/i)
  assert.match(safety.bullets.join(' '), /emergency/i)
  assert.match(safety.bullets.join(' '), /persistent|worsening/i)
  assert.match(supplements.body, /optional/i)
  assert.match(supplements.bullets.join(' '), /protein/i)
  assert.match(supplements.bullets.join(' '), /creatine monohydrate/i)
  assert.match(supplements.bullets.join(' '), /algae/i)
  assert.match(supplements.bullets.join(' '), /clinician|dietitian/i)
})

test('web and native completion paths present a swipeable, reduce-motion-aware deck only after install', () => {
  const web = readFileSync(
    join(process.cwd(), 'src/components/workout/TrainingInductionPanel.tsx'),
    'utf8',
  )
  const native = readFileSync(
    join(process.cwd(), 'ios/APEXNative/APEX/Features/Training/TrainingInductionPanel.swift'),
    'utf8',
  )

  assert.match(web, /PlanBriefingDeck/)
  assert.match(web, /snap-mandatory/)
  assert.match(web, /useReducedMotion/)
  const webInstall = web.slice(web.indexOf('const install ='), web.indexOf('const cautionTitle'))
  assert.ok(webInstall.indexOf('commitTrainingPlanAddons') < webInstall.indexOf('setBriefingOpen(true)'))

  assert.match(native, /PlanBriefingDeck/)
  assert.match(native, /PageTabViewStyle/)
  assert.match(native, /accessibilityReduceMotion/)
  const nativeInstall = native.slice(native.indexOf('private func install()'))
  assert.ok(nativeInstall.indexOf('await session.installInductionPlan') < nativeInstall.indexOf('showBriefing = true'))
})
