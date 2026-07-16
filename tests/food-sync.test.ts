import test from 'node:test'
import assert from 'node:assert/strict'
import { replayFoodOutbox } from '../src/lib/foodSync.ts'

test('food hydration keeps queued meal replacements and deletions authoritative', () => {
  const base = {
    foods: [], preferences: [], presets: [], presetItems: [],
    meals: [
      { id: 'old', user_id: 'user', local_date: '2026-07-16' },
      { id: 'deleted', user_id: 'user', local_date: '2026-07-16' },
    ],
    entries: [
      { id: 'old-entry', user_id: 'user', meal_id: 'old' },
      { id: 'deleted-entry', user_id: 'user', meal_id: 'deleted' },
    ],
  }
  const result = replayFoodOutbox(base as never, [
    {
      operation: 'log_meal', entity_id: 'new',
      payload: {
        meal: { id: 'new', user_id: 'user', local_date: '2026-07-16', replace_meal_id: 'old' },
        entries: [{ id: 'new-entry', user_id: 'user', meal_id: 'new' }],
      },
    },
    { operation: 'delete_meal', entity_id: 'deleted', payload: null },
  ])

  assert.deepEqual(result.meals.map((meal) => meal.id), ['new'])
  assert.deepEqual(result.entries.map((entry) => entry.id), ['new-entry'])
})
