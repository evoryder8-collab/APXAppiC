import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const simple = readFileSync(
  'ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift',
  'utf8',
)
const mealComposer = readFileSync(
  'ios/APEXNative/APEX/Features/Nutrition/MealComposerView.swift',
  'utf8',
)
const foodLogging = readFileSync(
  'ios/APEXNative/APEX/Features/Nutrition/FoodLoggingViews.swift',
  'utf8',
)

test('native hydration presets and supplement header use runtime localisation', () => {
  const presetButton = simple.slice(
    simple.indexOf('private func presetButton'),
    simple.indexOf('private func quickButton'),
  )
  assert.match(presetButton, /language\.hydrationPresetName\(preset\.name\)/)
  assert.doesNotMatch(presetButton, /Text\(preset\.name\)/)
  assert.match(simple, /title: language\.text\("Supplement stack"\)/)
  assert.match(simple, /language\.format\(\s*"%d of %d taken"/)
  assert.match(simple, /language\.text\(event\.kind\.rawValue\.capitalized\)/)
  assert.match(simple, /language\.text\(value\.rawValue\.capitalized\)/)
})

test('food amount configuration explicitly hands focus off from search', () => {
  assert.match(foodLogging, /@FocusState\.Binding var isFocused: Bool/)
  assert.match(foodLogging, /\.focused\(\$isFocused\)/)
  assert.match(mealComposer, /@FocusState private var searchFocused: Bool/)
  assert.match(mealComposer, /searchFocused = false[\s\S]{0,180}configuring = food/)
})
