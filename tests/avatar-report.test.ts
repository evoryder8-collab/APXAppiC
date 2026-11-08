import assert from 'node:assert/strict'
import { test } from 'node:test'
import { avatarReportHTML } from '../src/lib/avatarReport.ts'

const input = { name: 'A <B>', locale: 'en', today: '2026-11-08', snapshots: [],
  observed: { flexibility: 0 }, exercises: [], translate: (s: string) => s }

test('report preserves partial scores and only charts recorded data', () => {
  const html = avatarReportHTML(input)
  assert.match(html, /Body Flexibility<\/h3><b class="score">0</)
  assert.match(html, /Overall Fitness Level<\/h3><b class="score">No data</)
  assert.doesNotMatch(html, /<svg/)
  assert.match(html, /A &lt;B&gt;/)
})

test('report exports every frequency rank, graphs only loaded exercises and escapes names', () => {
  const exercises = Array.from({ length: 11 }, (_,i) => ({ name: 'Lift '+i+' <test>', sessionCount: 20-i,
    points: i ? [{date:'2026-10-01',value:50,reps:8}, {date:'2026-11-06',value:52.5,reps:6}] : [] }))
  const html = avatarReportHTML({ ...input, exercises })
  assert.equal((html.match(/scope="row"/g) || []).length, 11)
  assert.equal((html.match(/<svg/g) || []).length, 5)
  assert.match(html, /52.5 kg × 6/)
  assert.match(html, /Lift 10 &lt;test&gt;/)
  assert.doesNotMatch(html, /<test>|NaN|Infinity/)
})
