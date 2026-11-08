import assert from 'node:assert/strict'
import { test } from 'node:test'
import { avatarReportHTML, downloadableAvatarReport, reportBodyweight, reportExerciseRecords, reportSessionBodyweights } from '../src/lib/avatarReport.ts'
import { avatarReportRange } from '../src/lib/avatarReportRange.ts'
import { buildExerciseFamilies, exerciseChartTitle } from '../src/lib/strengthProgress.ts'
import { EMPTY_DATA } from '../src/lib/types.ts'
import { seedProfile } from '../src/data/seed.ts'
import { liftedMassCaption } from '../src/lib/liftedMassComparison.ts'

const noWork = { sets: 0, recordedReps: null, liftedKg: null, loadedReps: 0, missingReps: false, missingVolume: false }
const input = { name: 'A <B>', locale: 'en', today: '2026-11-08', snapshots: [],
  observed: { flexibility: 0 }, training: { focus: 'Limited history' as const, workouts: 0,
    counts: { Resistance: 0, Cardio: 0, Mobility: 0 }, running: 0, medianReps: null, comparison: null }, families: [], translate: (s: string) => s }

test('report preserves partial scores and only charts recorded data', () => {
  const html = avatarReportHTML(input)
  assert.match(html, /Body Flexibility<\/h3><b class="score">0</)
  assert.doesNotMatch(html, /Overall Fitness Level|All-time training totals|Most trained exercises|No data/)
  assert.doesNotMatch(avatarReportHTML({ ...input, observed: {} }), /<section>/)
  assert.doesNotMatch(html, /<svg/)
  assert.match(html, /A &lt;B&gt;/)
  assert.match(html, /<h1>Building your baseline<\/h1>/)
  assert.doesNotMatch(html, /Classified workouts 0/)
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
  assert.match(html, /Personal best · <strong>6 reps × 52.5 kg/)
  assert.match(html, /Lift 10 &lt;test&gt;/)
  assert.doesNotMatch(html, /<test>|NaN|Infinity/)
})

test('family frequency keeps each variation while charts require comparable sessions of the same variation', () => {
  const html = avatarReportHTML({ ...input, families: [{
    key: 'family:hip_thrust', sessions: [], name: 'Hip Thrust', work: { ...noWork, recordedReps: 123, liftedKg: 1500, loadedReps: 100, missingVolume: true }, sessionCount: 3, variants: [
      { name: 'Dumbbell Hip Thrust', work: { ...noWork, recordedReps: 83, liftedKg: 1200, loadedReps: 80 }, sessionCount: 2, points: [{date:'2026-09-01',topWeight:24,topReps:8},{date:'2026-09-12',topWeight:28,topReps:6}] },
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
  assert.match(html, /<h3>Hip Thrust<\/h3><p class="variation">Dumbbell<\/p>/)
  assert.doesNotMatch(html, /<h3>Single-Leg Hip Thrust<\/h3>/)
  assert.match(html, /<dt>Recorded reps<\/dt><dd>83<\/dd>/)
  assert.match(html, /<dt>Lifted volume<\/dt><dd>1.2 t<\/dd>/)
})

test('report leads with the athlete category, totals and comparison before secondary detail or charts', () => {
  const work = { ...noWork, sets:4, recordedReps:28, liftedKg:160, loadedReps:16, missingReps:true, missingVolume:true }
  const points = [{ date:'2026-11-07', topWeight:10, topReps:8 }, { date:'2026-11-07', topWeight:14, topReps:null }]
  const family = { name:'Split Squat', work, sessionCount:2,
    variants:[{ name:'Bulgarian Split Squat', work, sessionCount:2, points }] }
  const training = { ...input.training, focus:'Resistance-focused' as const, workouts:3, counts:{ Resistance:3, Cardio:0, Mobility:0 }, comparison:{name:'Split Squat', reps:8, previous:10, recent:14} }
  const html = avatarReportHTML({ ...input, training, families:[family] })
  assert.match(html, /<header class="profile">.*<h1>Strength athlete<\/h1>.*<\/header>/)
  const order = ['</header>', '<h2>All-time training totals</h2>', '<h3>Lifted volume</h3>', '<div class="comparison">', 'Fictional one-lift benchmark', '<h3>Performed sets</h3>', '<h3>Recorded reps</h3>', 'Classified workouts 3', '<h2>Recorded load</h2>'].map(value => html.indexOf(value))
  assert.ok(order.every((position, i) => position >= 0 && (!i || position > order[i - 1])))
  assert.doesNotMatch(html,/Matched working load|Median session-best|Known external load|Volume sums each/)
  assert.match(html,/\* Incomplete records/)
  assert.ok(html.indexOf('<h2>Recorded load</h2>') < html.indexOf('<h2>Most trained exercises</h2>'))
  assert.match(html, /Performed sets<\/h3><b class="score">4<\/b>/)
  assert.match(html, /Recorded reps<\/h3><b class="score">28\*<\/b>/)
  assert.match(html, /Lifted volume<\/h3><b class="score">160 kg\*<\/b>/)
  assert.doesNotMatch(html, /<h2>Reps per session|<h2>Recorded volume per session|≈/)
  assert.ok(html.includes(liftedMassCaption(160, 'en')!.caption))
  assert.match(html, /#1 · Nov 7, 2026 · 8 reps × 10 kg/)
  assert.match(html, /#2 · Nov 7, 2026 · 14 kg/)
  assert.equal(new Set([...html.matchAll(/<circle cx="([^"]+)"/g)].map(match => match[1])).size,2)
  assert.match(html, /<\/svg>[\s\S]*?<dl><div><dt>Recorded reps<\/dt><dd>28\*<\/dd><\/div><div><dt>Lifted volume<\/dt><dd>160 kg\*<\/dd>/)
})

test('the cover distinguishes zero volume from unrecorded volume', () => {
  const cover = (liftedKg: number | null) => avatarReportHTML({ ...input, families:[{
    name:'Squat', work:{ ...noWork, sets:1, liftedKg }, sessionCount:1, variants:[],
  }] }).split('<section class="totals-section">')[1].split('</section>')[0]
  assert.match(cover(0), /Lifted volume<\/h3><b class="score">0 kg<\/b>/)
  assert.doesNotMatch(cover(0), /class="comparison"/)
  assert.doesNotMatch(cover(null), /Lifted volume/)
  assert.match(cover(null), /Performed sets/)
})

test('one observed score snapshot shows its values without drawing any trend', () => {
  const snapshot = { id:'sample', user_id:'u', date:'2026-11-05', overall:42, health:40, joint:50,
    flexibility:60, endurance:55, strength:50, strength_lower:36, strength_upper:64 }
  const html = avatarReportHTML({ ...input, snapshots:[snapshot] })
  assert.match(html, /Overall Fitness Level<\/h3><b class="score">42</)
  assert.doesNotMatch(html, /<svg/)
  assert.equal((avatarReportHTML({ ...input, snapshots:[snapshot,{ ...snapshot, date:'2026-11-06' }] }).match(/<svg /g) ?? []).length,8)
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
  assert.match(html, /<article class="volume-panel"><h3>Lifted volume<\/h3><b class="score">200 kg<\/b><div class="comparison"><img class="award-art"/)
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

test('an unconfirmed default profile mass cannot supply bodyweight in a report', () => {
  const profile = seedProfile('user')
  profile.weight_kg = 70
  const data = { ...EMPTY_DATA, profile, health_metrics: [
    { id:'future',user_id:'user',date:'2027-01-01',weight_kg:70,vo2max:null,resting_hr:null },
    { id:'other',user_id:'other',date:'2026-11-07',weight_kg:70,vo2max:null,resting_hr:null },
  ] }
  assert.equal(reportBodyweight(data, input.today),null)
  data.health_metrics.push({ ...data.health_metrics[0], id:'known', date:'2026-11-07' })
  assert.equal(reportBodyweight(data, input.today),70)
})

function recordedHistory() {
  const profile = seedProfile('user')
  const session = (id, date) => ({id, date, user_id:'user', completed:true})
  const log = (session_id, exercise_name, movement_id, set_no, weight_kg, reps, changes = {}) => ({
    id:[session_id,movement_id,set_no].join('-'), user_id:'user', exercise_id:null, exercise_name, movement_id,
    session_id, set_no, weight_kg, reps, skipped:false, ...changes,
  })
  const lunge = (day, set, weight, reps, changes = {}) => log(day,'Reverse Lunge','reverse_lunge',set,weight,reps,changes)
  return {...EMPTY_DATA,profile,workout_sessions:[session('s0','2026-01-01'),session('s1','2026-11-01'),session('s2','2026-11-02'),session('s3','2026-11-07')],
    workout_logs:[lunge('s0',1,0,8),lunge('s0',2,10,8),lunge('s1',2,24,1),lunge('s1',1,25,6),lunge('s1',3,26,null),lunge('s2',1,12,10),
      lunge('s3',1,100,1),lunge('s2',2,1000,1,{skipped:true}), log('s2','Bench Press','barbell_bench_press',1,35,1),
      log('s2','Bench Press','barbell_bench_press',2,40,3),
      log('s2','Bench Press','barbell_bench_press',3,1000,1,{user_id:'another'})]}
}

const period = {from:'2026-11-01',to:'2026-11-06',allTime:false}
function exampleReport() {
  const data = recordedHistory()
  const exerciseRecords = reportExerciseRecords(data, period)
  const key = 'movement:reverse_lunge'
  const points = exerciseRecords.get(key).sets.filter(set => set.sessionId === 's2' || set.weight === 26).map(set => ({
    sessionId:set.sessionId,date:set.date,topWeight:set.weight,topReps:set.reps,
  }))
  return {...input,joined:'2025-08-05',range:period,currentBodyweight:88,exerciseRecords,
    sessionBodyweights:new Map([['s0',39],['s1',42],['s2',41]]),
    families:[{key:'family:lunge',name:'Lunge',work:noWork,sessionCount:2,variants:[{key,name:'Reverse Lunge',points,work:noWork,sessionCount:2}]},
      {name:'Bench Press',work:noWork,sessionCount:1,variants:[{key:'movement:barbell_bench_press',name:'Bench Press',points:[],work:noWork,sessionCount:1}]}]}
}
test('split records keep lifetime first, current in-range work, mid-period best and a lighter real single', () => {
  const html = avatarReportHTML(exampleReport())
  assert.match(html, /<h5>Before<\/h5>[\s\S]*?Jan 1, 2026<\/time>[\s\S]*?Joined FITR MAX · Aug 5, 2025[\s\S]*?Added weight<\/dt><dd>0 kg[\s\S]*?Body \+ load<\/dt><dd>39 kg/)
  assert.match(html, /<h5>After<\/h5>[\s\S]*?Nov 2, 2026<\/time>[\s\S]*?Added weight<\/dt><dd>12 kg[\s\S]*?Body \+ load<\/dt><dd>53 kg/)
  assert.match(html, /class="personal-record"><h4>Personal record<\/h4><p>6 reps · Nov 1, 2026 · Best in range<\/p>\s*<dl><div><dt>Added weight<\/dt><dd>25 kg<\/dd><\/div><div><dt>Body \+ load<\/dt><dd>67 kg<\/dd>/)
  assert.match(html, /class="personal-record"><h4>Personal record<\/h4><p>3 reps · Nov 2, 2026 · Best in range<\/p>\s*<dl><div><dt>Added weight<\/dt><dd>40 kg<\/dd>/)
  assert.match(html, /Best single<\/b> · 1 rep × 24 kg · Nov 1, 2026/)
  assert.match(html, /Best single<\/b> · 1 rep × 35 kg · Nov 2, 2026/)
  assert.doesNotMatch(html,/1RM|1000 kg|Nov 7, 2026/)
})

test('an ordinary exercise performed once needs an actual single for a record card', () => {
  const data = recordedHistory()
  data.workout_logs = data.workout_logs.filter(log => log.reps !== 1)
  const report = exampleReport()
  const bench = buildExerciseFamilies(data, period).filter(family => family.variants.some(v => v.key === 'movement:barbell_bench_press'))
  const html = avatarReportHTML({...report, families: bench, exerciseRecords: reportExerciseRecords(data, period)})
  assert.doesNotMatch(html, /<section class="lifts">/)
})

test('an unrecorded starting weight stays unknown and old sessions do not borrow current profile mass', () => {
  const data = recordedHistory()
  data.workout_logs[0].weight_kg = null
  const exerciseRecords = reportExerciseRecords(data,period)
  assert.equal(exerciseRecords.get('movement:reverse_lunge').before.weight,null)
  const html=avatarReportHTML({...exampleReport(),exerciseRecords,joined:undefined,sessionBodyweights:new Map()})
  assert.match(html,/Jan 1, 2026<\/time>[\s\S]*?Added weight<\/dt><dd>&ndash;<\/dd>[\s\S]*?Body \+ load<\/dt><dd>&ndash;<\/dd>/)
  assert.match(html,/Personal record<\/h4><p>6 reps · Nov 1, 2026 · Best in range<\/p>\s*<dl><div><dt>Added weight<\/dt><dd>25 kg<\/dd><\/div><div><dt>Body \+ load<\/dt><dd>&ndash;<\/dd>/)
  assert.doesNotMatch(html,/Joined FITR MAX|88 kg/)
})

test('a mixed-era hip thrust history keeps the earliest reps, chart and actual record for its owner', () => {
  const profile = seedProfile('user')
  const name = 'B-Stance or Single-Leg Hip Thrust'
  const days = [
    { date: '2026-08-07', count: 2, weight: null, movementId: null },
    { date: '2026-08-14', count: 3, weight: 8, movementId: null },
    { date: '2026-11-06', count: 3, weight: 36, movementId: 'b_stance_hip_thrust' },
  ]
  const data = { ...EMPTY_DATA, profile,
    workout_sessions: days.map(({date}) => ({ id: date, date, completed: true, user_id: profile.user_id })),
    workout_logs: days.flatMap(({date, count, weight, movementId}) => Array.from({length: count}, (_, i) => ({
      id: date + '-' + i, user_id: profile.user_id, session_id: date, set_no: i+1,
      reps: 10, weight_kg: weight, exercise_name: name, movement_id: movementId, exercise_id: null, skipped: false,
    }))),
  }
  const range = {from: days[0].date, to: input.today, allTime: true}
  const families = buildExerciseFamilies(data, range)
  assert.equal(families.length, 1)
  assert.equal(families[0].variants.length, 1)
  const variant = families[0].variants[0]
  assert.equal(variant.sessionCount, 3)
  assert.deepEqual(variant.points.map(p => [p.date,p.topWeight]), [['2026-08-14',8],['2026-11-06',36]])
  assert.deepEqual(variant.work, {sets:8, recordedReps:80, liftedKg:1320, loadedReps:60, missingReps:false, missingVolume:true})
  const exerciseRecords = reportExerciseRecords(data, range)
  const html = avatarReportHTML({...input, range, families, exerciseRecords})
  assert.match(html, /<h5>Before<\/h5>\s*<time datetime="2026-08-07">Aug 7, 2026<\/time><span>Recorded reps · 20<\/span>[\s\S]*?Added weight<\/dt><dd>&ndash;<\/dd>/)
  assert.match(html, /#1 · Aug 14, 2026 · 10 reps × 8 kg/)
  assert.match(html, /<h4>Personal record<\/h4><p>10 reps · Nov 6, 2026<\/p>\s*<dl><div><dt>Added weight<\/dt><dd>36 kg<\/dd>/)
  assert.doesNotMatch(html, /<dt>Body \+ load|Best single|1RM/)
})

test('strength headings show variant modifiers once and keep custom names intact', () => {
  const family = { key:'family:hip_thrust', name:'Hip Thrust' }
  assert.deepEqual(exerciseChartTitle(family, 'Weighted Dumbbell Hip Thrusts', s => s),
    { title:'Hip Thrust', subtitle:'Weighted Dumbbell' })
  assert.deepEqual(exerciseChartTitle(family, 'Hip Thrust', s => s), { title:'Hip Thrust', subtitle:'' })
  assert.deepEqual(exerciseChartTitle({ key:'name:custom', name:'Personal lift' }, 'My Lift', s => s),
    { title:'My Lift', subtitle:'' })
  assert.deepEqual(exerciseChartTitle(family, 'Cable Setup', s => s), { title:'Hip Thrust', subtitle:'Cable Setup' })
})

test('report periods use inclusive calendar boundaries, clamped months, and reject invalid custom dates', () => {
  const start = (period, end) => avatarReportRange(period, end, '2020-01-01','','')?.from
  assert.equal(start('month','2024-03-31'),'2024-03-01')
  assert.equal(start('month','2026-11-08'),'2026-10-09')
  assert.equal(start('quarter','2026-11-08'),'2026-08-09')
  assert.equal(start('half','2026-11-08'),'2026-05-09')
  assert.equal(start('year','2024-02-29'),'2023-03-01')
  assert.equal(start('all','2026-11-08'),'2020-01-01')
  const custom = (from,to) => avatarReportRange('custom','2026-11-08','2020-01-01',from,to)
  assert.deepEqual(custom('2026-07-01','2026-07-01'),{from:'2026-07-01',to:'2026-07-01',allTime:false})
  for (const dates of [['2026-02-30','2026-03-01'],['2026-05-03','2026-05-02'],['2026-10-01','2026-11-09']]) assert.equal(custom(...dates),null)
})
test('download embeds the same exercise illustration in both columns and keeps values when offline', async t => {
  const webp = 'UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEAAUAmJaQAA3AA/v89WAAAAA=='
  const fetchImage = t.mock.method(globalThis,'fetch',async () => new Response(Buffer.from(webp,'base64')))
  const html = await downloadableAvatarReport(exampleReport(),'/app/')
  assert.deepEqual(fetchImage.mock.calls.map(call=>call.arguments[0]),['/app/leg-anatomy/reverse_lunge.webp'])
  assert.equal((html.match(/<img alt="" src="data:image\/webp;base64,/g) ?? []).length,2)
  fetchImage.mock.mockImplementation(async () => new Response('missing',{status:404}))
  const offline = await downloadableAvatarReport(exampleReport(),'/app/')
  assert.doesNotMatch(offline,/<img/)
  assert.match(offline,/53 kg/)
})

test('session bodyweights exclude other accounts, superseded data, unsupported values and later weigh-ins', () => {
  const profile = seedProfile('user')
  const health = (id,date,kg,owner='user')=>({ id,date,user_id:owner,weight_kg:kg })
  const ev = (id,date,kg,changes={})=>({id,user_id:'user',metric:'body_mass',unit:'kg',measured_at:date,imported_at:date,value:kg,...changes})
  const session = (id,date,started)=>({id,date,user_id:'user',completed:true,started_at:started,completed_at:null})
  const masses=reportSessionBodyweights({...EMPTY_DATA,profile,
    daily_logs:[health('d1','2026-10-30',68),health('d2','2026-10-31',70)],
    health_metrics:[health('hk','2026-10-31',72),health('bad','2026-11-01',700),health('other','2026-11-01',99,'else')],
    fitness_evidence:[ev('old','2026-11-01T10:00:00Z',77),ev('correction','2026-11-01T11:00:00Z',69,{supersedes_id:'old'}),
      ev('later','2026-11-01T20:00:00Z',74),ev('future','2026-12-01T20:00:00Z',90)],
    workout_sessions:[session('early','2026-10-29',null),session('am','2026-11-01','2026-11-01T10:30:00Z'),
      session('pm','2026-11-01','2026-11-01T12:00:00Z'),session('next','2026-11-02',null)]},'2026-11-02')
  assert.deepEqual([...masses],[['am',72],['pm',69],['next',74]])
})
