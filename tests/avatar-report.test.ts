import assert from 'node:assert/strict'
import { test } from 'node:test'
import { avatarReportHTML, downloadableAvatarReport } from '../src/lib/avatarReport.ts'
import { liftedMassCaption } from '../src/lib/liftedMassComparison.ts'

const noWork = { sets: 0, recordedReps: null, liftedKg: null, loadedReps: 0, missingReps: false, missingVolume: false }
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
    key: 'lift-' + i, sessions: [], name: 'Lift '+i+' <test>', work: noWork, sessionCount: 20-i, variants: [{
      name: 'Variation '+i, work: noWork, sessionCount: 20-i,
      points: i ? [{date:'2026-10-01',topWeight:50,topReps:8}, {date:'2026-11-06',topWeight:52.5,topReps:6}] : [],
    }],
  }))
  const html = avatarReportHTML({ ...input, families })
  assert.equal((html.match(/<tr class="family">/g) || []).length, 11)
  assert.equal((html.match(/<svg/g) || []).length, 10)
  assert.match(html, /52.5 kg × 6/)
  assert.match(html, /Lift 10 &lt;test&gt;/)
  assert.doesNotMatch(html, /<test>|NaN|Infinity/)
})

test('family frequency uses one total while the report plots each loaded variation separately', () => {
  const html = avatarReportHTML({ ...input, families: [{
    key: 'family:hip_thrust', sessions: [], name: 'Hip Thrust', work: { ...noWork, recordedReps: 123, liftedKg: 1500, loadedReps: 100, missingVolume: true }, sessionCount: 3, variants: [
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

test('report shows lifetime work once and plots measured session reps and unilateral volume', () => {
  const morning = { sessionId:'am', date:'2026-11-07', work:{ ...noWork, sets:2, recordedReps:16, liftedKg:160, loadedReps:16 } }
  const evening = { sessionId:'pm', date:'2026-11-07', work:{ ...noWork, sets:1, recordedReps:12, missingVolume:true } }
  const total = { ...morning.work, sets:3, recordedReps:28, missingVolume:true }
  const family = { key:'family:split_squat', name:'Split Squat', work:total, sessionCount:2,
    sessions:[morning,evening], variants:[{ name:'Bulgarian Split Squat', work:total, sessionCount:2, points:[] }] }
  const html = avatarReportHTML({ ...input, families:[family] })
  assert.match(html, /Performed sets<\/h3><b class="score">3<\/b>/)
  assert.match(html, /Recorded reps<\/h3><b class="score">28<\/b>/)
  assert.match(html, /Lifted volume<\/h3><b class="score">160 kg\*<\/b>/)
  assert.doesNotMatch(html, /≈| × [\w ]+ \([\d.,]+ kg\)/)
  assert.ok(html.includes(liftedMassCaption(160, 'en')!.caption))
  const reps = html.split('<h2>Reps per session</h2>')[1].split('</section>')[0]
  assert.match(reps, /#1 · Nov 7, 2026 · 16 reps/)
  assert.match(reps, /#2 · Nov 7, 2026 · 12 reps/)
  assert.equal(new Set([...reps.matchAll(/<circle cx="([^"]+)"/g)].map(match => match[1])).size,2)
  const volume = html.split('<h2>Recorded volume per session</h2>')[1].split('</section>')[0]
  assert.match(volume, /160 kg/)
  assert.equal((volume.match(/<circle /g) ?? []).length,1)
})

test('download fetches only the selected object and embeds its WebP next to the localized fact', async t => {
  const family = { key:'squat', name:'Squat', sessionCount:1, variants:[], sessions:[],
    work:{ ...noWork, sets:1, recordedReps:10, liftedKg:200, loadedReps:10 } }
  const options = { ...input, locale:'de', families:[family] }
  const object = liftedMassCaption(200, 'de')!
  const webp = 'UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEAAUAmJaQAA3AA/v89WAAAAA=='
  const fetchImage = t.mock.method(globalThis, 'fetch', async () => new Response(Buffer.from(webp, 'base64')))
  const html = await downloadableAvatarReport(options, '/APXAppiC/')
  assert.equal(fetchImage.mock.callCount(),1)
  assert.equal(fetchImage.mock.calls[0].arguments[0], '/APXAppiC/award-objects/' + object.artwork)
  assert.deepEqual([...html.matchAll(/<img[^>]+src="([^"]+)"/g)].map(match => match[1]), ['data:image/webp;base64,' + webp])
  assert.ok(html.includes(object.fact.replaceAll('&', '&amp;').replaceAll("'", '&#39;')))

  const textOnly = avatarReportHTML(options)
  fetchImage.mock.mockImplementation(async () => new Response('<html>missing</html>'))
  assert.equal(await downloadableAvatarReport(options, '/APXAppiC/'),textOnly)
  fetchImage.mock.mockImplementation(async () => { throw new TypeError('Offline') })
  assert.equal(await downloadableAvatarReport(options, '/APXAppiC/'),textOnly)
  const before = fetchImage.mock.callCount()
  assert.equal(await downloadableAvatarReport(input, '/APXAppiC/'),avatarReportHTML(input))
  assert.equal(fetchImage.mock.callCount(),before)
})
