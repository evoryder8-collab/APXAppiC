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

test('supplement routine editing exposes labelled removal and preserves the archival path', () => {
  const native = readFileSync('ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift', 'utf8')
  const editor = native.slice(native.indexOf('struct SupplementStackEditor'), native.indexOf('private struct StatsQuickSheet'))
  const web = readFileSync('src/components/supplements/SupplementStackEditor.tsx', 'utf8')
  assert.ok(editor.includes('supplement-edit-defaults'))
  assert.ok(editor.indexOf('supplement-remove-') < editor.indexOf('.swipeActions'), 'Removal is visible in Edit, not swipe-only')
  assert.ok(editor.includes('language.text("Remove from your daily routine?")'))
  assert.ok(editor.includes('session.archiveSupplement('))
  assert.ok(web.includes('supplement-edit-defaults') && web.includes('supplement-remove-'))
  assert.ok(web.includes("archived: true") && web.includes("pendingArchive.user_id === ownerID"))
  const session = readFileSync('ios/APEXNative/APEX/App/AppSession.swift', 'utf8')
  const archive = session.slice(session.indexOf('    func archiveSupplement('), session.indexOf('    /// Puts an archived supplement'))
  assert.ok(archive.includes('archived = true'))
  assert.ok(archive.includes('publishHydrationState()') && archive.includes('refreshNudges(operation: operation)'))
  assert.ok(!archive.includes('supplementLogs.remove') && !archive.includes('persistDelete'))
  assert.ok(session.includes('.filter { $0.userID == ownerID && !$0.archived }'))
  assert.ok(session.includes('let items = activeSupplements.map'))
})

test('Nutrition exposes the supplement routine as its own section', () => {
  const native = readFileSync('ios/APEXNative/APEX/Features/Nutrition/NutritionView.swift', 'utf8')
  const web = readFileSync('src/pages/Nutrition.tsx', 'utf8')
  assert.ok(native.includes('Text(language.text("Supplements"))'))
  assert.ok(native.includes('SupplementStackEditor(date: selectedDate, showsHeader: false)'))
  assert.ok(!native.includes('id: "supplements",'))
  assert.ok(web.includes('<section id="nutrition-supplements"'))
})
