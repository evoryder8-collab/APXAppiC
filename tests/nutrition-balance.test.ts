import test from 'node:test'
import assert from 'node:assert/strict'
import { resolveNutritionCalorieBalance } from '../src/lib/nutritionBalance.ts'

test('an over-target day reports the actual excess instead of zero remaining', () => {
  assert.deepEqual(resolveNutritionCalorieBalance(1_685, 2_119), {
    label: 'Exceeding by',
    amount: 434,
    isOverTarget: true,
  })
})

test('an under-target day still reports calories remaining', () => {
  assert.deepEqual(resolveNutritionCalorieBalance(1_685, 1_200), {
    label: 'Remaining',
    amount: 485,
    isOverTarget: false,
  })
})
