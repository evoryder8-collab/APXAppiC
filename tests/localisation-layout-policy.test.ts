import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { globSync } from 'node:fs'
import { test } from 'node:test'

const swiftFiles = globSync('ios/APEXNative/APEX/**/*.swift')
const swiftSource = swiftFiles.map((path) => readFileSync(path, 'utf8')).join('\n')

test('localized layout never defeats Dynamic Type by scaling text down', () => {
  assert.doesNotMatch(swiftSource, /\.minimumScaleFactor\s*\(/)
})

test('hard-width controls use authored compact labels and preserve Thai height', () => {
  const localization = readFileSync(
    'ios/APEXNative/APEX/Core/DesignSystem/APEXLocalization.swift',
    'utf8',
  )
  const modeSelector = readFileSync(
    'ios/APEXNative/APEX/Features/Portal/PortalUIMode.swift',
    'utf8',
  )

  assert.match(localization, /func shortText\(_ value: String\) -> String/)
  assert.match(modeSelector, /language\.shortText\(mode == \.simple/)
  assert.match(modeSelector, /fixedSize\(horizontal: false, vertical: true\)/)
  assert.match(modeSelector, /frame\(minHeight:/)
})
