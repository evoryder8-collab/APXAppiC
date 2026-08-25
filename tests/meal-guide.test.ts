import assert from 'node:assert/strict'
import test from 'node:test'
import { defaultMealGuideSections } from '../src/lib/mealGuide.ts'

test('main meals offer three labelled groups with five practical examples each', () => {
  for (const slot of ['breakfast', 'lunch', 'dinner'] as const) {
    const sections = defaultMealGuideSections(slot)
    assert.deepEqual(sections.map((section) => section.title), [
      'CARBOHYDRATES',
      'PROTEIN SOURCES',
      'FATS',
    ])
    assert.deepEqual(sections.map((section) => section.items.length), [5, 5, 5])
    assert.equal(sections[0]?.items[0], 'Bulgur, cooked')
    assert.equal(sections[2]?.items[0], 'Extra virgin olive oil')
  }
})

test('snacks offer five quick examples without pretending they are a prescription', () => {
  const sections = defaultMealGuideSections('snack')
  assert.equal(sections.length, 1)
  assert.equal(sections[0]?.title, 'QUICK PICKS')
  assert.equal(sections[0]?.items.length, 5)
  assert.deepEqual(sections[0]?.items.slice(0, 2), ['Banana', 'Berries or apple'])
})
