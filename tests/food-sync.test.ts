import test from 'node:test'
import assert from 'node:assert/strict'
import {
  detachedLoggedMealPayload,
  foodSyncFailureCanYield,
  foodMutationBelongsToActiveUser,
  foodOperationBelongsToUser,
  isMealReferenceError,
  isStaleFoodPreferenceReferenceError,
  replayFoodOutbox,
  foodSessionBelongsToExpectedUser,
} from '../src/lib/foodSync.ts'

test('meal snapshots can detach optional catalogue links without changing nutrition', () => {
  const payload = {
    meal: {
      id: 'meal-1',
      source_preset_id: 'preset-1',
      source_planned_meal_id: 'planned-1',
    },
    entries: [{ id: 'entry-1', food_id: 'client-food', kcal: 321, quantity: 175, unit: 'g' }],
  }
  const detached = detachedLoggedMealPayload(payload as never)
  assert.equal(detached.meal.source_preset_id, null)
  assert.equal(detached.meal.source_planned_meal_id, null)
  assert.equal(detached.entries[0].food_id, null)
  assert.equal(detached.entries[0].kcal, 321)
  assert.equal(detached.entries[0].quantity, 175)
  assert.equal(payload.entries[0].food_id, 'client-food', 'the durable queued payload remains immutable')
})

test('only reference failures detach a meal and optional catalogue failures yield', () => {
  assert.equal(isMealReferenceError({ code: '23503', message: 'foreign key violation' }), true)
  assert.equal(isMealReferenceError({ code: '22P02', message: 'invalid input syntax for type uuid' }), true)
  assert.equal(isMealReferenceError({ code: '42501', message: 'permission denied' }), false)
  assert.equal(foodSyncFailureCanYield('save_preference'), true)
  assert.equal(foodSyncFailureCanYield('save_usage_preference'), true)
  assert.equal(foodSyncFailureCanYield('save_food'), true)
  assert.equal(foodSyncFailureCanYield('log_meal'), false)
  assert.equal(foodSyncFailureCanYield('delete_meal'), false)
})

test('only a missing food reference is safe to skip for preference writes', () => {
  const staleFoodId = '0b88a5f2-6ee0-46a6-bf46-e433fd79610d'
  assert.equal(isStaleFoodPreferenceReferenceError({
    code: '23503',
    message: 'insert or update on table "food_preferences" violates foreign key constraint "food_preferences_food_id_fkey"',
    details: `Key (food_id)=(${staleFoodId}) is not present in table "foods".`,
  }, staleFoodId), true)
  assert.equal(isStaleFoodPreferenceReferenceError({
    status: 409,
    message: 'insert or update on table "food_preferences" violates foreign key constraint "food_preferences_food_id_fkey"',
  }, staleFoodId), true)
  assert.equal(isStaleFoodPreferenceReferenceError({
    code: '22P02', message: `invalid input syntax for type uuid: "${staleFoodId}"`,
  }, staleFoodId), true)

  assert.equal(isStaleFoodPreferenceReferenceError({
    code: '23503',
    message: 'insert or update on table "food_preferences" violates foreign key constraint "food_preferences_user_id_fkey"',
    details: 'Key (user_id) is not present in table "users".',
  }, staleFoodId), false)
  assert.equal(isStaleFoodPreferenceReferenceError({ code: '23514', message: 'new row violates a check constraint' }, staleFoodId), false)
  assert.equal(isStaleFoodPreferenceReferenceError({ code: '42501', message: 'permission denied for table food_preferences' }, staleFoodId), false)
  assert.equal(isStaleFoodPreferenceReferenceError({ status: 409, message: 'Conflict while saving an unrelated preference field' }, staleFoodId), false)
  assert.equal(isStaleFoodPreferenceReferenceError({ code: '22P02', message: 'invalid input syntax for type uuid: "a-different-field"' }, staleFoodId), false)
})

test('food mutations only update the account that started them', () => {
  assert.equal(foodMutationBelongsToActiveUser('account-a', 'account-a'), true)
  assert.equal(foodMutationBelongsToActiveUser('account-a', 'account-b'), false)
  assert.equal(foodMutationBelongsToActiveUser('account-a', null), false)
})

test('food hydration accepts only a session owned by its expected account', () => {
  assert.equal(foodSessionBelongsToExpectedUser('account-a', 'account-a'), true)
  assert.equal(foodSessionBelongsToExpectedUser('account-b', 'account-a'), false)
  assert.equal(foodSessionBelongsToExpectedUser(null, 'account-a'), false)
  assert.equal(foodSessionBelongsToExpectedUser(undefined, 'account-a'), false)
})

test('food outbox ownership stays bound to the captured sync account', () => {
  assert.equal(foodOperationBelongsToUser({ user_id: 'account-a' }, 'account-a'), true)
  assert.equal(foodOperationBelongsToUser({ user_id: 'account-b' }, 'account-a'), false)
})

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

test('food replay follows durable creation order instead of IndexedDB key order', () => {
  const base = { foods: [], preferences: [], presets: [], presetItems: [], meals: [], entries: [] }
  const result = replayFoodOutbox(base, [
    {
      operation: 'delete_meal', entity_id: 'meal', payload: null,
      created_at: '2026-07-16T10:00:00.002Z',
    },
    {
      operation: 'log_meal', entity_id: 'meal',
      payload: { meal: { id: 'meal' }, entries: [] },
      created_at: '2026-07-16T10:00:00.001Z',
    },
  ])

  assert.deepEqual(result.meals, [])
})

test('food replay retains preferences when an incomplete food snapshot omits their food', () => {
  const base = {
    foods: [{ id: 'food-live' }],
    preferences: [{ id: 'preference-live', food_id: 'food-live' }, { id: 'preference-deleted', food_id: 'food-deleted' }],
    presets: [], presetItems: [], meals: [], entries: [],
  }
  const result = replayFoodOutbox(base as never, [{
    operation: 'save_preference', entity_id: 'preference-missing',
    payload: { id: 'preference-missing', food_id: 'food-missing' },
    created_at: '2026-08-21T05:00:00.000Z',
  }])

  assert.deepEqual(result.preferences.map((preference) => preference.id), [
    'preference-live',
    'preference-deleted',
    'preference-missing',
  ])
})

test('food replay retains a preference when its queued food is created first', () => {
  const base = { foods: [], preferences: [], presets: [], presetItems: [], meals: [], entries: [] }
  const result = replayFoodOutbox(base, [
    { operation: 'save_food', entity_id: 'food-new', payload: { id: 'food-new' }, created_at: '2026-08-21T05:00:00.000Z' },
    { operation: 'save_preference', entity_id: 'preference-new', payload: { id: 'preference-new', food_id: 'food-new' }, created_at: '2026-08-21T05:00:00.001Z' },
  ])

  assert.deepEqual(result.preferences.map((preference) => preference.id), ['preference-new'])
})
