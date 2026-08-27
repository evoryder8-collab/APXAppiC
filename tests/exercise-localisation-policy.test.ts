import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'

const catalogPath = 'ios/APEXNative/APEX/Resources/exercise-catalog.json'
const policyRoot = 'docs/localisation/policies'
const locales = ['en', 'de', 'de-CH', 'it', 'es', 'pt', 'ja', 'ro', 'th'] as const
const classifications = new Set(['english', 'native', 'hybrid', 'transliterated'])

const catalog = JSON.parse(readFileSync(catalogPath, 'utf8'))
const exercises = catalog.exercises as Array<{
  id: string
  name: string
  names: Record<string, string>
}>
const exerciseIDs = exercises.map((exercise) => exercise.id).sort()

test('every offered language has a sourced exercise-name policy', () => {
  assert.equal(exercises.length, 549)

  for (const locale of locales) {
    const policy = JSON.parse(readFileSync(`${policyRoot}/${locale}.json`, 'utf8'))
    assert.equal(policy.language, locale)
    assert.equal(policy.market, locale === 'pt' ? 'pt-PT' : locale)
    assert.ok(policy.sources.length >= 1, `${locale} has no recorded sources`)
    assert.ok(policy.shortForms.length >= 20, `${locale} has no authored short-form set`)

    const sourceIDs = new Set(policy.sources.map((source: { id: string }) => source.id))
    const terms = policy.exerciseTerms as Array<{
      id: string
      english: string
      display: string
      classification: string
      source: string
    }>
    assert.equal(terms.length, exercises.length, `${locale} term count drifted`)
    assert.deepEqual(terms.map((term) => term.id).sort(), exerciseIDs)

    for (const term of terms) {
      assert.ok(term.display.trim(), `${locale}/${term.id} has an empty display name`)
      assert.ok(classifications.has(term.classification), `${locale}/${term.id} has an invalid classification`)
      assert.ok(sourceIDs.has(term.source), `${locale}/${term.id} cites an unknown source`)
      if (term.classification === 'english') assert.equal(term.display, term.english)
      if (locale === 'ja' && term.classification !== 'english') {
        assert.match(term.display, /[\u3040-\u30ff\u3400-\u9fff]/)
      }
      if (locale === 'de-CH') assert.doesNotMatch(term.display, /ß/)
    }

    for (const shortForm of policy.shortForms as Array<{ key: string; value: string; maxCharacters: number }>) {
      assert.ok(shortForm.key)
      assert.ok(shortForm.value)
      assert.ok(shortForm.maxCharacters >= shortForm.value.length)
    }
  }
})

test('the native catalogue resolves every policy display name without English fallback', () => {
  for (const exercise of exercises) {
    for (const locale of locales) {
      assert.ok(exercise.names[locale]?.trim(), `${exercise.id} lacks ${locale}`)
    }
  }
})
