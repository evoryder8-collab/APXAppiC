import assert from 'node:assert/strict'
import { test } from 'node:test'
import { avatarReportHTML } from '../src/lib/avatarReport.ts'

const input = { name: 'A <B>', locale: 'en', today: '2026-11-08', snapshots: [],
  observed: { flexibility: 0 }, families: [], translate: (s: string) => s }

test('report preserves partial scores and only charts recorded data', () => {
  const html = avatarReportHTML(input)
  assert.match(html, /Body Flexibility<\/h3><b class="score">0</)
  assert.match(html, /Overall Fitness Level<\/h3><b class="score">No data</)
  assert.doesNotMatch(html, /<svg/)
  assert.match(html, /A &lt;B&gt;/)
})

test('report exports every frequency rank, graphs only loaded exercises and escapes names', () => {
  const families = Array.from({ length: 11 }, (_,i) => ({
    name: 'Lift '+i+' <test>', sessionCount: 20-i, variants: [{
      name: 'Variation '+i, sessionCount: 20-i,
      points: i ? [{date:'2026-10-01',topWeight:50,topReps:8}, {date:'2026-11-06',topWeight:52.5,topReps:6}] : [],
    }],
  }))
  const html = avatarReportHTML({ ...input, families })
  assert.equal((html.match(/scope="row"/g) || []).length, 11)
  assert.equal((html.match(/<svg/g) || []).length, 5)
  assert.match(html, /52.5 kg × 6/)
  assert.match(html, /Lift 10 &lt;test&gt;/)
  assert.doesNotMatch(html, /<test>|NaN|Infinity/)
})

test('family frequency uses one total while the report plots each loaded variation separately', () => {
  const html = avatarReportHTML({ ...input, families: [{
    name: 'Hip Thrust', sessionCount: 3, variants: [
      { name: 'Dumbbell Hip Thrust', sessionCount: 2, points: [{date:'2026-09-01',topWeight:24,topReps:8}] },
      { name: 'Single-Leg Hip Thrust', sessionCount: 2, points: [{date:'2026-09-01',topWeight:8,topReps:10}] },
    ],
  }] })
  assert.equal((html.match(/scope="row"/g) ?? []).length, 1)
  assert.match(html, /Hip Thrust<small class="variants">Dumbbell Hip Thrust · 2<br>Single-Leg Hip Thrust · 2<\/small><\/th><td>3<\/td>/)
  assert.match(html, /<h3>Dumbbell Hip Thrust<\/h3>/)
  assert.match(html, /<h3>Single-Leg Hip Thrust<\/h3>/)
})
