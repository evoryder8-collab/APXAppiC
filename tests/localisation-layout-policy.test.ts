import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { globSync } from 'node:fs'
import { test } from 'node:test'

const swiftFiles = globSync('ios/APEXNative/APEX/**/*.swift')
test('localized layout never defeats Dynamic Type by scaling text down', () => {
  for (const path of swiftFiles) {
    const source = readFileSync(path, 'utf8').replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, '')
    for (const match of source.matchAll(/\.minimumScaleFactor\s*\(/g)) {
      // Only a FITR MAX wordmark, optionally inside its shimmer mask, may shrink.
      assert.match(source.slice(0, match.index), /Text\(verbatim: (?:AppBrand\.name|"FITR MAX")\)(?:\s*\.(?:font\(APEXFont\.display\(\d+\)\)|tracking\(\d+\)|lineLimit\(1\)))*\s*$/, path)
    }
  }
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

  assert.match(localization, /func shortText\(_ \w+: String\) -> String/)
  assert.match(modeSelector, /language\.shortText\(mode == \.simple/)
  assert.match(modeSelector, /fixedSize\(horizontal: false, vertical: true\)/)
  assert.match(modeSelector, /frame\(minHeight:/)
})
