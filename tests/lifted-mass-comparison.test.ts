import assert from 'node:assert/strict'
import { test } from 'node:test'
import { readFileSync } from 'node:fs'
import objects from '../shared/lifted-mass-landmarks.json' with { type: 'json' }
import heroes from '../shared/hero-lift-landmarks.json' with { type: 'json' }
import { formattedMass, liftedMassCaption, heroLiftCaption } from '../src/lib/liftedMassComparison.ts'

test('each comparison catalog has at least 100 distinct, sourced mass benchmarks in ascending order', () => {
  assert.equal(new Set(objects.map(object => object.artwork)).size, objects.length)
  for (const object of objects) {
    assert.match(object.artwork, /^[a-z0-9-]+\.webp$/)
    const image = readFileSync(new URL('../public/award-objects/' + object.artwork, import.meta.url))
    assert.equal(image.toString('ascii', 0, 4), 'RIFF')
    assert.equal(image.toString('ascii', 8, 12), 'WEBP')
    assert.ok(object.fact.trim().length > 15)
    for (const locale of ['de','de-CH','it','es','pt','ja','ro','th'] as const) {
      const words = object.translations[locale]
      assert.equal(words.length, 2)
      assert.ok(words.every(word => word.trim().length > 0))
    }
    if ('factSource' in object) assert.equal(new URL(String(object.factSource)).protocol, 'https:')
  }
  for (const catalog of [objects, heroes]) {
    assert.ok(catalog.length >= 100)
    assert.equal(new Set(catalog.map(row => row.name.toLowerCase())).size, catalog.length)
    catalog.forEach((row, i) => {
      assert.ok(row.name.trim() && Number.isFinite(row.kg) && row.kg > 0)
      assert.equal(new URL(row.source).protocol, 'https:')
      if (i > 0) assert.ok(row.kg >= catalog[i - 1].kg)
    })
  }
})

test('reported hero can cover the full training volume in one lift and links to its evidence', () => {
  assert.equal(heroLiftCaption(0, 'en'), undefined)
  assert.equal(liftedMassCaption(NaN, 'en'), undefined)
  for (const kg of [500, 20_000, 100_000]) {
    const match = heroLiftCaption(kg, 'en')
    assert.ok(match)
    assert.ok(heroes.some(hero => hero.source === match.source && match.caption.includes(' · ' + hero.name + ' · ') && hero.kg >= kg))
    const object = liftedMassCaption(kg, 'en')
    assert.ok(object?.caption.startsWith('≈ '))
    assert.ok(objects.some(row => row.fact === object.fact && row.source === object.source))
    assert.deepEqual(heroLiftCaption(kg, 'en'), match)
  }
  assert.equal(heroLiftCaption(heroes.at(-1)!.kg * 2, 'en'), undefined)
})

test('the printed object fact follows the chosen report language', () => {
  const en = liftedMassCaption(37_833, 'en')!
  const de = liftedMassCaption(37_833, 'de-CH')!
  const entry = objects.find(row => row.fact === en.fact)!
  assert.equal(de.source, en.source)
  assert.equal(de.fact, entry.translations['de-CH'][1])
  assert.ok(de.caption.includes(entry.translations['de-CH'][0]))
})

test('large comparisons use metric mass units, with physical references throughout the scale', () => {
  const scales = [[1e9, 'Mt'], [1e12, 'Gt'], [1e15, 'Tt'], [1e18, 'Pt'], [1e21, 'Et'], [1e24, 'Zt'], [1e27, 'Yt'], [1e30, 'Rt']] as const
  for (const [kg, symbol] of scales) {
    assert.equal(formattedMass(kg, 'en'), '1 ' + symbol)
    assert.ok(objects.some(row => row.kg >= kg && row.kg < kg * 1000))
    assert.ok(liftedMassCaption(kg, 'en')?.fact)
  }
  for (const kg of [1e9, 1e12, 1e15, 1e18, 1e21]) {
    const selected = heroLiftCaption(kg, 'en')!
    assert.ok(heroes.some(row => row.kg >= kg && selected.caption.includes(' · ' + row.name + ' · ')))
  }
})
