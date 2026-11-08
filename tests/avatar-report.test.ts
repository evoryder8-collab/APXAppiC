import assert from 'node:assert/strict'
import { test } from 'node:test'
import { avatarReportHTML } from '../src/lib/avatarReport.ts'

const noWork = { recordedReps: null, liftedKg: null, loadedReps: 0, missingReps: false, missingVolume: false }
const input = { name: 'A <B>', locale: 'en', today: '2026-11-08', snapshots: [],
  observed: { flexibility: 0 }, training: { focus: 'Limited history' as const, workouts: 0,
    counts: { Resistance: 0, Cardio: 0, Mobility: 0 }, running: 0, medianReps: null, comparison: null }, families: [], translate: (s: string) => s }

test('report preserves partial scores and only charts recorded data', () => {
  const html = avatarReportHTML(input)
  assert.match(html, /Body Flexibility<\/h3><b class="score">0</)
  assert.match(html, /Overall Fitness Level<\/h3><b class="score">No data</)
  assert.doesNotMatch(html, /<svg/)
  assert.match(html, /A &lt;B&gt;/)
})

test('report exports every frequency rank, graphs only loaded exercises and escapes names', () => {
  const families = Array.from({ length: 11 }, (_,i) => ({
    name: 'Lift '+i+' <test>', work: noWork, sessionCount: 20-i, variants: [{
      name: 'Variation '+i, work: noWork, sessionCount: 20-i,
      points: i ? [{date:'2026-10-01',topWeight:50,topReps:8}, {date:'2026-11-06',topWeight:52.5,topReps:6}] : [],
    }],
  }))
  const html = avatarReportHTML({ ...input, families })
  assert.equal((html.match(/<tr class="family">/g) || []).length, 11)
  assert.equal((html.match(/<svg/g) || []).length, 5)
  assert.match(html, /52.5 kg × 6/)
  assert.match(html, /Lift 10 &lt;test&gt;/)
  assert.doesNotMatch(html, /<test>|NaN|Infinity/)
})

test('family frequency uses one total while the report plots each loaded variation separately', () => {
  const html = avatarReportHTML({ ...input, families: [{
    name: 'Hip Thrust', work: { ...noWork, recordedReps: 123, liftedKg: 1500, loadedReps: 100, missingVolume: true }, sessionCount: 3, variants: [
      { name: 'Dumbbell Hip Thrust', work: { ...noWork, recordedReps: 83, liftedKg: 1200, loadedReps: 80 }, sessionCount: 2, points: [{date:'2026-09-01',topWeight:24,topReps:8}] },
      { name: 'Single-Leg Hip Thrust', work: { ...noWork, recordedReps: 40, liftedKg: 300, loadedReps: 20, missingVolume: true }, sessionCount: 2, points: [{date:'2026-09-01',topWeight:8,topReps:10}] },
    ],
  }] })
  assert.equal((html.match(/<tr class="family">/g) ?? []).length, 1)
  assert.match(html, /1\. Hip Thrust<\/th><td data-label="Sessions">3<\/td>/)
  assert.match(html, /data-label="Recorded reps">123</)
  assert.match(html, /data-label="Lifted volume" title="1,500 kg">1.5 t\*</)
  assert.match(html, /data-label="Load per rep">15 kg\*</)
  assert.match(html, /data-label="Lifted volume" title="300 kg">300 kg\*</)
  assert.equal((html.match(/<tr class="variant">/g) ?? []).length, 2)
  assert.match(html, /<h3>Dumbbell Hip Thrust<\/h3>/)
  assert.match(html, /<h3>Single-Leg Hip Thrust<\/h3>/)
})
