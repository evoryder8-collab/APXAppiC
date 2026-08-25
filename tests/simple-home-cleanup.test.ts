import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const nativeSimple = readFileSync(
  new URL('../ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift', import.meta.url),
  'utf8',
)
const nativeGlance = readFileSync(
  new URL('../ios/APEXNative/APEX/Features/Nutrition/NutritionParityViews.swift', import.meta.url),
  'utf8',
).split('struct GlanceMacroCard')[0]
const webSimple = readFileSync(new URL('../src/pages/SimpleHome.tsx', import.meta.url), 'utf8')
const webGlance = readFileSync(
  new URL('../src/components/food/NutritionGlance.tsx', import.meta.url),
  'utf8',
)

test('Simple Mode removes the redundant greeting and manual checklist', () => {
  assert.doesNotMatch(nativeSimple, /private var simpleHeader|private var checklist|SimpleChecklistRow/)
  assert.doesNotMatch(nativeSimple, /Today, %@\./)
  assert.doesNotMatch(webSimple, /Today, \$\{firstName\}/)
})

test('daily completion lives inside the Simple Mode nutrition card', () => {
  assert.match(nativeSimple, /NutritionGlanceCard\([\s\S]*?completion: completion/)
  assert.match(webSimple, /<NutritionGlance[\s\S]*?completion=\{completion\}/)
  assert.match(nativeGlance, /CompletionRing\(value: completion\)/)
  assert.match(webGlance, /aria-label=\{t\('Daily completion'\)\}/)
})

test('nutrition glance reports resolved burned energy instead of meal count', () => {
  assert.doesNotMatch(nativeGlance, /configuredMealCount|language\.text\("Meals"\)/)
  assert.match(nativeGlance, /resolvedActiveCalories/)
  assert.match(nativeGlance, /language\.text\("Burned"\)/)
  assert.doesNotMatch(webGlance, /mealsDone|mealsTotal|t\('Meals'\)/)
  assert.match(webGlance, /burnedKcal/)
  assert.match(webGlance, /t\('Burned'\)/)
})

test('collapsed native wearable activity exposes every detected fact', () => {
  const card = nativeSimple.slice(nativeSimple.indexOf('private struct WearableActivityCard'))
  const headerStart = card.indexOf('Button {')
  const collapsedHeader = card.slice(headerStart, card.indexOf('.buttonStyle(.plain)', headerStart))

  assert.match(collapsedHeader, /record\.steps|\$0\.steps/)
  assert.match(collapsedHeader, /record\.activeCalories|\$0\.activeCalories/)
  assert.match(collapsedHeader, /record\.exerciseMinutes|\$0\.exerciseMinutes/)
})
