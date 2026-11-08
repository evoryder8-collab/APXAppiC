import assert from 'node:assert/strict'
import { test } from 'node:test'
import { avatarReportHTML, downloadableAvatarReport, reportBodyweight, reportSessionBodyweights } from '../src/lib/avatarReport.ts'
import { avatarReportRange } from '../src/lib/avatarReportRange.ts'
import { exerciseChartTitle } from '../src/lib/strengthProgress.ts'
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
  assert.match(html, /6 reps × 52.5 kg/)
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
  const order = ['</header>', '<h2>All-time training totals</h2>', '<aside class="comparison">', 'Fictional one-lift benchmark', 'Classified workouts 3', '<h2>Recorded load</h2>'].map(value => html.indexOf(value))
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

test('unilateral estimates distinguish recorded load, combined mass and support for the actual variation', () => {
  const profile = seedProfile('user')
  profile.weight_kg = 70
  const data = { ...EMPTY_DATA, profile, health_metrics: [
    { id:'future',user_id:'user',date:'2027-01-01',weight_kg:70,vo2max:null,resting_hr:null },
    { id:'other',user_id:'other',date:'2026-11-07',weight_kg:70,vo2max:null,resting_hr:null },
  ] }
  assert.equal(reportBodyweight(data, input.today),null)
  data.health_metrics.push({ ...data.health_metrics[0], id:'known', date:'2026-11-07' })
  assert.equal(reportBodyweight(data, input.today),70)
  const make = (key: string, name: string, currentBodyweight: number | null = 70) => {
    const points = [{date:'2026-11-01',topWeight:20,topReps:5},{date:'2026-11-02',topWeight:20,topReps:8}]
    return avatarReportHTML({ ...input, currentBodyweight, families:[{ key:'family:split_squat', name:'Split Squat',
      work:noWork, sessionCount:2, variants:[{ key, name, points, work:noWork, sessionCount:2 }] }] })
  }
  const rfess = make('movement:bulgarian_split_squat','Bulgarian Split Squat')
  assert.match(rfess, /<h3>Split Squat<\/h3><p class="variation">Bulgarian<\/p>/)
  assert.match(rfess, /<title>#1 · Nov 1, 2026 · 5 reps × 20 kg<\/title>/)
  assert.match(rfess, /<title>#2 · Nov 2, 2026 · 8 reps × 20 kg<\/title>/)
  assert.match(rfess, /Personal best · <strong>8 reps × 20 kg/)
  assert.match(rfess, /<span>Front foot · estimated<\/span><strong>≈ 76 kg/)
  assert.match(rfess, /Current bodyweight 70 \+ 20 kg/)
  assert.match(make('name:bulgarian split squat','Bulgarian Split Squat'), /Front foot · estimated/)
  assert.match(make('movement:single_leg_romanian_deadlift','Single-Leg Romanian Deadlift'), /Standing foot · estimated/)
  const lunge = make('movement:reverse_lunge','Reverse Lunge',41)
  assert.match(lunge, /<span>Added weight<\/span><strong>20 kg/)
  assert.match(lunge, /<span>Body \+ load<\/span><strong>61 kg/)
  assert.doesNotMatch(lunge,/≈/)
  for (const html of [make('movement:smith_split_squat','Smith Split Squat'),
    make('movement:bulgarian_split_squat','Bulgarian Split Squat (hand-supported)'),
    make('movement:bulgarian_split_squat','Bulgarian Split Squat',null)]) {
    assert.match(html, /<span>Added weight<\/span><strong>20 kg/)
    assert.doesNotMatch(html,/Body \+ load|≈/)
  }
  assert.doesNotMatch(make('name:custom','Custom split squat variation'), /Working leg/)
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
test('download embeds each chart anatomy once per movement fetch and retains the tiles when offline', async t => {
  const webp = 'UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEAAUAmJaQAA3AA/v89WAAAAA=='
  const points = [{date:'2026-11-01', topWeight:10,topReps:5},{date:'2026-11-02',topWeight:20,topReps:10}]
  const variant = { key:'movement:bulgarian_split_squat',name:'Bulgarian Split Squat',points,work:noWork,sessionCount:2 }
  const options = { ...input, currentBodyweight:70, families:[{name:'Split Squat',work:noWork,sessionCount:2,variants:[variant,variant]}] }
  const fetchImage = t.mock.method(globalThis,'fetch',async () => new Response(Buffer.from(webp,'base64')))
  const html = await downloadableAvatarReport(options,'/app/')
  assert.deepEqual(fetchImage.mock.calls.map(call=>call.arguments[0]),['/app/leg-anatomy/bulgarian_split_squat.webp'])
  assert.equal((html.match(/<img alt="" src="data:image\/webp;base64,/g) ?? []).length,2)
  fetchImage.mock.mockImplementation(async () => new Response('missing',{status:404}))
  const offline = await downloadableAvatarReport(options,'/app/')
  assert.doesNotMatch(offline,/<img/)
  assert.match(offline,/Front foot · estimated/)
})

test('the latest single-leg card uses that session’s dated bodyweight and keeps unknown mass out of historical reports', () => {
  const points = [[16,1],[20,2],[30,3]].map(([weight,i])=>({sessionId:'s'+i,date:'2026-11-0'+i,topWeight:weight,topReps:8}))
  const variant = { key:'movement:bulgarian_split_squat',name:'Bulgarian Split Squat',points,work:noWork,sessionCount:3 }
  const options = {...input,currentBodyweight:80,families:[{key:'family:split_squat',name:'Split Squat',work:noWork,sessionCount:3,variants:[variant]}]}
  const masses = new Map([['s1',70],['s2',80],['s3',60]])
  const html = avatarReportHTML({...options,sessionBodyweights:masses})
  assert.match(html,/<span>Front foot · estimated<\/span><strong>≈ 76 kg/)
  assert.match(html,/<span>Body \+ load<\/span><strong>90 kg<\/strong><small>60 \+ 30 kg/)
  assert.match(html,/Personal best · <strong>8 reps × 30 kg/)
  assert.doesNotMatch(html,/Current bodyweight|Peak<\/span>/)
  const incomplete = avatarReportHTML({...options,sessionBodyweights:new Map([['s2',100]])})
  assert.match(incomplete, /<span>Added weight<\/span><strong>30 kg/)
  assert.doesNotMatch(incomplete,/Body \+ load|≈/)
  const historical = avatarReportHTML({...options,range:{from:'2026-11-01',to:'2026-11-03',allTime:false}})
  assert.doesNotMatch(historical,/Current bodyweight used as a reference|≈/)
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
