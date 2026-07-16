import assert from 'node:assert/strict'
import test from 'node:test'
import { buildWeightTrend, weightTrendChange } from '../src/lib/weightTrend.ts'

test('weight trend uses valid persisted weigh-ins inside the requested range', () => {
  const rows = [
    { date: '2026-05-01', weight_kg: 90 },
    { date: '2026-07-01', weight_kg: 80 },
    { date: '2026-07-10', weight_kg: null },
    { date: '2026-07-12', weight_kg: 79.4 },
    { date: '2026-07-15', weight_kg: 79.1 },
    { date: '2026-07-17', weight_kg: 78.9 },
  ]
  assert.deepEqual(buildWeightTrend(rows, '2026-07-15', 30), [
    { date: '2026-07-01', weightKg: 80 },
    { date: '2026-07-12', weightKg: 79.4 },
    { date: '2026-07-15', weightKg: 79.1 },
  ])
})

test('weight trend is chronological, deduplicated and computes the range change', () => {
  const points = buildWeightTrend([
    { date: '2026-07-15', weight_kg: 79.3 },
    { date: '2026-07-01', weight_kg: 80 },
    { date: '2026-07-15', weight_kg: 79.1 },
    { date: '2026-07-11', weight_kg: 500 },
  ], '2026-07-15', 30)
  assert.deepEqual(points, [
    { date: '2026-07-01', weightKg: 80 },
    { date: '2026-07-15', weightKg: 79.1 },
  ])
  assert.equal(weightTrendChange(points), -0.9)
  assert.equal(weightTrendChange(points.slice(0, 1)), null)
})
