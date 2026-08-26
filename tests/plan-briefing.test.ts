import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
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
  assert.match(briefing.slides[0].title, /12-week strength/i)
  assert.match(briefing.slides[0].title, /4 sessions\/week/i)
  assert.equal(briefing.slides[0].assetName, 'plan-briefing-overview')
  assert.match(briefing.slides[0].eyebrow, /why this plan fits/i)
  assert.deepEqual(
    briefing.slides[0].energyPresets?.map((preset) => preset.label),
    ['Strength recomp', 'Strength base', 'Power surplus'],
  )
  assert.equal(briefing.slides[0].recommendedGoal, 'maintain')
  assert.match(briefing.slides[0].body, /answers|goal/i)
})

test('six-month plans are described as six months rather than twenty-six weeks', () => {
  const briefing = buildPlanBriefing({ ...input, planWeeks: 26 })
  assert.match(briefing.slides[0].title, /6-month strength/i)
  assert.doesNotMatch(briefing.slides[0].title, /26-week/i)
})

test('hydration briefing uses the shared personalized target and chosen unit', () => {
  const liters = buildPlanBriefing(input)
  const gallons = buildPlanBriefing({ ...input, displayUnit: 'gallons' })

  assert.equal(liters.hydrationTargetML, 3_250)
  assert.match(liters.slides[2].title, /3\.25 L/)
  assert.match(gallons.slides[2].title, /0\.86 US gal/)
  assert.match(liters.slides[2].body, /drinks and water in food/i)
  assert.match(liters.slides[2].bullets.map((bullet) => bullet.text).join(' '), /long, hot, or very sweaty/i)
  assert.match(liters.slides[2].bullets.map((bullet) => bullet.text).join(' '), /sodium-restricted/i)
  assert.doesNotMatch(liters.slides[2].bullets.map((bullet) => bullet.text).join(' '), /pinch of salt/i)
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
  const safetyText = safety.bullets.map((bullet) => bullet.text).join(' ')
  const supplementsText = supplements.bullets.map((bullet) => bullet.text).join(' ')
  assert.match(safetyText, /chest pressure|chest pain/i)
  assert.match(safetyText, /emergency/i)
  assert.match(safetyText, /144/)
  assert.match(safetyText, /persistent|return/i)
  assert.match(supplements.body, /food/i)
  assert.match(supplementsText, /protein/i)
  assert.match(supplementsText, /creatine monohydrate/i)
  assert.match(supplementsText, /algae/i)
})

test('briefing copy is scannable, semantic and cites primary Swiss guidance', () => {
  const briefing = buildPlanBriefing(input)

  for (const slide of briefing.slides) {
    assert.ok(slide.body.trim().split(/\s+/).length <= 24, `${slide.kind} body is too dense`)
    assert.ok(slide.bullets.length <= 3, `${slide.kind} has too many takeaways`)
    assert.equal(new Set(slide.bullets.map((bullet) => bullet.icon)).size, slide.bullets.length)
    for (const bullet of slide.bullets) {
      assert.ok(bullet.text.trim().split(/\s+/).length <= 20, `${slide.kind} bullet is too dense`)
      assert.doesNotMatch(bullet.icon, /sparkle/i)
    }
  }

  const [, safety, hydration, sleep, supplements] = briefing.slides
  assert.match(safety.evidenceLabel, /Swiss Heart Foundation/i)
  assert.match(safety.evidenceURL, /^https:\/\/swissheart\.ch\//)
  assert.match(hydration.evidenceLabel, /Swiss FSVO/i)
  assert.match(hydration.evidenceURL, /^https:\/\/www\.blv\.admin\.ch\//)
  assert.match(sleep.evidenceLabel, /Swiss Society for Sleep Research/i)
  assert.match(sleep.evidenceURL, /^https:\/\/swiss-sleep\.ch\//)
  assert.match(supplements.evidenceLabel, /Swiss Sports Nutrition Society/i)
  assert.match(supplements.evidenceURL, /^https:\/\/www\.ssns\.ch\//)
  assert.doesNotMatch(briefing.slides.map((slide) => slide.evidenceLabel).join(' '), /CDC|American Heart|NIH/i)
})

test('the owner-approved safety illustration is shared unchanged by both clients', () => {
  const nativeAsset = readFileSync(join(process.cwd(), 'ios/APEXNative/APEX/Resources/Assets.xcassets/plan-briefing-safety.imageset/plan-briefing-safety.png'))
  const webAsset = readFileSync(join(process.cwd(), 'public/plan-briefing/plan-briefing-safety.png'))
  const approvedHash = 'b28b785dafb6d58d8e1abd72b8d7cafb9c13dd671b8bc83e876984832ea79b83'

  assert.deepEqual(webAsset, nativeAsset)
  assert.equal(createHash('sha256').update(nativeAsset).digest('hex'), approvedHash)
  assert.equal(nativeAsset[25], 6, 'PNG must use RGBA color type instead of a baked checkerboard')
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
  assert.match(web, /BriefingBulletIcon/)
  assert.match(web, /slide\.energyPresets/)
  assert.match(web, /recommendedGoalForTrainingGoal/)
  assert.doesNotMatch(web, />✦</)
  assert.match(web, /text-sm leading-relaxed font-semibold/)
  assert.match(web, /activeSlide === briefing\.slides\.length - 1/)
  assert.match(web, /snap-mandatory/)
  assert.match(web, /useReducedMotion/)
  const webInstall = web.slice(web.indexOf('const install ='), web.indexOf('const cautionTitle'))
  assert.ok(webInstall.indexOf('commitTrainingPlanAddons') < webInstall.indexOf('setBriefingOpen(true)'))

  assert.match(native, /PlanBriefingDeck/)
  assert.match(native, /Image\(systemName: bullet\.icon\.rawValue\)/)
  assert.match(native, /slide\.energyPresets/)
  assert.match(native, /slide\.recommendedGoal/)
  assert.doesNotMatch(native, /systemName: "sparkle"/)
  assert.match(native, /APEXFont\.body\(14, weight: \.semibold\)/)
  assert.match(native, /page == briefing\.slides\.count - 1/)
  assert.match(native, /PageTabViewStyle/)
  assert.match(native, /accessibilityReduceMotion/)
  const nativeInstall = native.slice(native.indexOf('private func install()'))
  assert.ok(nativeInstall.indexOf('await session.installInductionPlan') < nativeInstall.indexOf('showBriefing = true'))
})
