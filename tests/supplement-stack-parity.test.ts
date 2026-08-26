import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { orderedSupplementCatalogue } from '../src/data/supplementCatalogue.ts'

test('supplement browse order leads with protein and creatine, then stays alphabetical', () => {
  const entries = orderedSupplementCatalogue()
  assert.deepEqual(entries.slice(0, 2).map((entry) => entry.id), ['whey_protein', 'creatine_monohydrate'])

  const remainder = entries.slice(2).map((entry) => entry.name)
  assert.deepEqual(remainder, [...remainder].sort((left, right) => left.localeCompare(right)))
  assert.equal(new Set(entries.map((entry) => entry.id)).size, entries.length)
})

test('simple and nutrition surfaces use one shared supplement-stack editor', () => {
  const simple = readFileSync('src/pages/SimpleHome.tsx', 'utf8')
  const nutrition = readFileSync('src/pages/Nutrition.tsx', 'utf8')
  const nativeSimple = readFileSync('ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift', 'utf8')
  const nativeNutrition = readFileSync('ios/APEXNative/APEX/Features/Nutrition/NutritionView.swift', 'utf8')

  assert.match(simple, /SupplementStackEditor/)
  assert.match(nutrition, /SupplementStackEditor/)
  assert.match(nativeSimple, /SupplementStackEditor/)
  assert.match(nativeNutrition, /SupplementStackEditor/)
  assert.doesNotMatch(nativeNutrition, /SupplementTimeline\(date:/)
})

test('retiring a supplement preserves its historical logs', () => {
  const migration = readFileSync('supabase/migrations/031_archive_supplements.sql', 'utf8')
  assert.match(migration, /add column if not exists archived boolean not null default false/i)
  assert.doesNotMatch(migration, /delete\s+from\s+supplements/i)
})
