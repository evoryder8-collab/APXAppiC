import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import {
  MEAL_UNDO_WINDOW_MS,
  mealUndoSecondsRemaining,
  removeMealItemWithUndo,
  restoreMealItemFromUndo,
} from '../src/lib/mealUndo.ts'

test('a removed meal item can be restored at its exact position for five seconds only', () => {
  const items = [
    { id: 'milk', name: 'Milk' },
    { id: 'oats', name: 'Oats' },
    { id: 'walnuts', name: 'Walnuts' },
  ]
  const removed = removeMealItemWithUndo(items, 'oats', 10_000)

  assert.equal(MEAL_UNDO_WINDOW_MS, 5_000)
  assert.deepEqual(removed.items.map((item) => item.id), ['milk', 'walnuts'])
  assert.equal(removed.undo?.item.name, 'Oats')
  assert.equal(mealUndoSecondsRemaining(removed.undo, 10_000), 5)
  assert.equal(mealUndoSecondsRemaining(removed.undo, 14_001), 1)

  const restored = restoreMealItemFromUndo(removed.items, removed.undo, 14_999)
  assert.equal(restored.restored, true)
  assert.deepEqual(restored.items.map((item) => item.id), ['milk', 'oats', 'walnuts'])

  const expired = restoreMealItemFromUndo(removed.items, removed.undo, 15_000)
  assert.equal(expired.restored, false)
  assert.deepEqual(expired.items.map((item) => item.id), ['milk', 'walnuts'])
})

test('every web meal composer removal exposes the same expiring countdown action', () => {
  const source = readFileSync(new URL('../src/components/food/MealComposer.tsx', import.meta.url), 'utf8')

  assert.match(source, /removeMealItemWithUndo/)
  assert.match(source, /mealUndoSecondsRemaining/)
  assert.match(source, /window\.setTimeout/)
  assert.match(source, /\{t\('Undo'\)\} · \{undoSecondsRemaining\}s/)
})
