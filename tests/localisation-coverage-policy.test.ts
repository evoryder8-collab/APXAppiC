import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'

const audit = 'ios/APEXNative/Tools/audit-translation-coverage.mjs'
const auditSource = readFileSync(audit, 'utf8')
const offeredLanguages = ['en', 'de', 'de-CH', 'it', 'es', 'pt', 'ja', 'ro', 'th']

test('translation coverage reports every offered language against the same source set', () => {
  const result = spawnSync(process.execPath, [audit], { encoding: 'utf8' })

  const corpusCount = result.stdout.match(/^(\d+) distinct user-facing strings in runtime corpus$/m)
  assert.ok(corpusCount, 'coverage output omitted its runtime denominator')
  assert.ok(Number(corpusCount[1]) > 3_000, 'the audit silently discarded most runtime copy')
  for (const language of offeredLanguages) {
    assert.match(
      result.stdout,
      new RegExp(`^\\s+${language.replace('-', '\\-')}: ${corpusCount[1]}/${corpusCount[1]} translated \\(100\\.0%\\)$`, 'm'),
      `coverage output omitted ${language}`,
    )
  }
  assert.equal(result.status, 0, result.stderr || result.stdout)
})

test('the runtime audit uses the sourced exercise policy as its only exercise allowlist', () => {
  const result = spawnSync(process.execPath, [audit, '--json'], { encoding: 'utf8' })
  const report = JSON.parse(result.stdout)

  assert.equal(report.excludedExerciseCount, 549)
  assert.ok(report.corpusCount > report.sourceLiteralCount)
  assert.deepEqual(report.gaps, [])
  assert.equal(result.status, 0)
})

test('translation coverage excludes storage identifiers, debug fixtures and translated values', () => {
  const result = spawnSync(process.execPath, [audit, '--list'], { encoding: 'utf8' })

  assert.doesNotMatch(result.stdout, /B72E51D1-5D0B-4585-B361-9AF511F98964/)
  assert.doesNotMatch(result.stdout, /UI fixture: server rejected this write/)
  assert.doesNotMatch(result.stdout, /"Alege limba"/)
  assert.doesNotMatch(result.stdout, /"yyyy-MM-dd HH:mm"/)
  assert.doesNotMatch(result.stdout, /FoodRegion\.swift\s+"AUT"/)
  assert.doesNotMatch(result.stdout, /APEX_MANUAL_V1/)
  assert.doesNotMatch(result.stdout, /__APEX_AUTOMATIC_TITLE__/)
  assert.doesNotMatch(result.stdout, /safeName\)\.gpx/)
  assert.doesNotMatch(result.stdout, /photo\.note\)/)
  assert.doesNotMatch(result.stdout, /lowercased\(with:/)
  assert.doesNotMatch(result.stdout, /\)\) kcal/)
  assert.doesNotMatch(result.stdout, /OrbitGPXService\.swift\s+" \.gpx"/)
  assert.doesNotMatch(result.stdout, /MuscleMap\.(?:facing|spin|xray)\(/)
  assert.doesNotMatch(result.stdout, /\(\^\|\[\^a-z\]\)/)
  assert.doesNotMatch(result.stdout, /<trkpt\s/)
  assert.doesNotMatch(result.stdout, /PortalHomeView\.swift\s+" ,/)
  assert.doesNotMatch(result.stdout, /FoodHydration\.swift\s+"(?:VITC|FASAT|CHOAVL)"/)
  assert.doesNotMatch(result.stdout, /FoodHydration\.swift\s+"mg α-TE"/)
})

test('translation coverage preserves the canonical alpha-tocopherol unit verbatim', () => {
  assert.match(auditSource, /'mg α-TE'/)
})

test('the Portuguese table consistently uses the documented pt-PT market vocabulary', () => {
  const table = readFileSync(
    'ios/APEXNative/APEX/Resources/pt.lproj/Localizable.strings',
    'utf8',
  )
  const values = table
    .split('\n')
    .filter((line) => line.includes(' = '))
    .map((line) => line.slice(line.indexOf(' = ') + 3))
    .join('\n')

  assert.doesNotMatch(
    values,
    /\b(?:usuári[oa]s?|aplicativos?|telas?|salvar|salvando|planejamento|planejad[oa]s?|equipes?|sucos?|gerenciar|compartilh(?:ar|ad[oa]s?|ável)|carboidratos?|controle|registros?|treinamentos?)\b/i,
  )
})
