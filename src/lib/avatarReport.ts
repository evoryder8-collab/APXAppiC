// A standalone document: the downloaded report needs neither a login nor a network connection.
import { athleteTitle, type TrainingProfile } from './trainingProfile.ts'
import { datedChartAxis, distinctSessionPositions } from './datedChartAxis.ts'
import { exerciseChartTitle, performedWorkoutObservations, totalRecordedWork, type ExerciseFrequencyFamily, type RecordedWork, type RankedExerciseHistory } from './strengthProgress.ts'
import { formattedMass, heroLiftCaption, liftedMassCaption } from './liftedMassComparison.ts'
import guide from '../../shared/unilateral-load-guide.json' with { type: 'json' }
import { MOVEMENT_ALIASES, MOVEMENTS } from '../data/movements.ts'
import { bespokeProtocolFor } from './profilePolicy.ts'
import { isIsoDate } from './activeDate.ts'
import type { AppData, RpgSnapshot } from './types'
import type { AvatarReportRange } from './avatarReportRange'
import type { StatBlock } from './rpg'

type ReportPoint = { date: string; value: number; reps?: number | null }
type ReportWorkRow = Pick<ExerciseFrequencyFamily, 'name' | 'sessionCount' | 'work'>
type ReportFamily = ReportWorkRow & {
  key?: string
  variants: Array<ReportWorkRow & { key?: string } & Pick<RankedExerciseHistory, 'points'>>
}
type WorkingSet = { sessionId: string; date: string; weight: number | null; reps: number | null }
type ExerciseRecord = { before: WorkingSet; firstSessionReps: number | null; sets: WorkingSet[]; bestSingle?: WorkingSet }
type ReportInput = {
  name: string; locale: string; today: string; snapshots: RpgSnapshot[]; currentBodyweight?: number | null; range?: AvatarReportRange
  sessionBodyweights?: ReadonlyMap<string, number>; exerciseRecords?: ReadonlyMap<string, ExerciseRecord>; joined?: string
  observed: Partial<StatBlock>; training: TrainingProfile; families: ReportFamily[]; translate: (text: string) => string
}
type Illustration = { filename: string; dataURL: string }
type Score = keyof StatBlock | 'overall' | 'strength'

const loadGuides = new Map(Object.entries(guide))
const normalizedName = (name: string) => name.toLocaleLowerCase('en').replace(/[^\p{L}\p{N}]/gu, '')
const exactMovementNames = new Map<string, string | null>()
for (const [name, id] of [...MOVEMENTS.map(m => [m.name, m.id]), ...Object.entries(MOVEMENT_ALIASES)]) {
  const key = normalizedName(name)
  exactMovementNames.set(key, !exactMovementNames.has(key) || exactMovementNames.get(key) === id ? id : null)
}

function loadGuide(variant: ReportFamily['variants'][number]) {
  const key = variant.key
  const name = variant.points.at(-1)?.topSetName ?? variant.name
  const id = key?.startsWith('movement:') ? key.slice('movement:'.length) : exactMovementNames.get(normalizedName(name))
  const kind = id ? loadGuides.get(id) : undefined
  if (!id || !kind) return null
  const supportQualifier = /[+/]|\b(?:or|support(?:ed)?|assisted|smith|cable|machine|counterweight(?:ed)?)\b/i
  const supported = variant.points.some(point => supportQualifier.test(point.topSetName ?? variant.name))
  return { id, kind: supported ? 'externalOnly' : kind }
}

function validMass(kg: unknown): kg is number {
  return typeof kg === 'number' && Number.isFinite(kg) && kg >= 10 && kg <= 500
}

export function reportSessionBodyweights(data: AppData, through: string): Map<string, number> {
  const owner = data.profile?.user_id
  type Weight = { kg: number; priority: number; time: number; imported: string; id: string }
  const days = new Map<string, Weight[]>()
  function add(date: string, record: Weight) {
    if (!isIsoDate(date) || date > through || !validMass(record.kg)) return
    const values = days.get(date) ?? []
    values.push(record)
    days.set(date, values)
  }
  for (const [priority, rows] of [data.daily_logs, data.health_metrics].entries()) {
    for (const row of rows) {
      if (row.user_id === owner && validMass(row.weight_kg)) add(row.date, {
        kg: row.weight_kg, priority: priority + 1, time: -Infinity, imported: '', id: row.id,
      })
    }
  }
  const evidence = data.fitness_evidence.filter(row => row.user_id === owner)
  const superseded = new Set(evidence.map(row => row.supersedes_id))
  for (const row of evidence) {
    const time = Date.parse(row.measured_at)
    if (row.metric === 'body_mass' && row.unit === 'kg' && !superseded.has(row.id) && Number.isFinite(time)) {
      add(row.measured_at.slice(0,10), { kg: row.value, priority: 0, time, imported: row.imported_at, id: row.id })
    }
  }
  for (const values of days.values()) values.sort((a,b) => b.priority - a.priority || b.time - a.time
    || b.imported.localeCompare(a.imported) || b.id.localeCompare(a.id))

  const dates = [...days.keys()].sort()
  const result = new Map<string, number>()
  const sessions = data.workout_sessions.filter(s => s.user_id === owner && s.completed && s.date <= through && isIsoDate(s.date))
    .sort((a,b) => a.date.localeCompare(b.date))
  let day = 0
  let previous: number | undefined
  for (const session of sessions) {
    while (day < dates.length && dates[day] < session.date) previous = days.get(dates[day++])![0].kg
    const start = Date.parse(session.started_at ?? session.completed_at ?? '')
    const sameDay = days.get(session.date)?.find(weight => weight.time === -Infinity || weight.time <= start)
    const kg = sameDay?.kg ?? previous
    if (kg != null) result.set(session.id, kg)
  }
  return result
}

export function reportExerciseRecords(data: AppData, range: { from: string; to: string }): Map<string, ExerciseRecord> {
  const observations = [...performedWorkoutObservations(data, { from: '0001-01-01', to: range.to })]
    .filter(o => o.repBased && o.movement.measuresExternalWeight)
    .sort((a,b) => a.session.date.localeCompare(b.session.date)
      || (a.session.started_at ?? a.session.completed_at ?? '').localeCompare(b.session.started_at ?? b.session.completed_at ?? '')
      || a.session.id.localeCompare(b.session.id) || a.log.set_no - b.log.set_no || a.log.id.localeCompare(b.log.id))
  const records = new Map<string, ExerciseRecord>()
  for (const { movement, session, log, reps } of observations) {
    const weight = log.weight_kg
    const set: WorkingSet = { sessionId: session.id, date: session.date, reps,
      weight: weight != null && Number.isFinite(weight) && weight >= 0 ? weight : null }
    const record: ExerciseRecord = records.get(movement.key) ?? { before: set, firstSessionReps: null, sets: [] }
    records.set(movement.key, record)
    if (session.id === record.before.sessionId && reps != null) record.firstSessionReps = (record.firstSessionReps ?? 0) + reps
    if (session.date < range.from) continue
    record.sets.push(set)
    if (reps === 1 && set.weight != null && set.weight > (record.bestSingle?.weight ?? 0)) record.bestSingle = set
  }
  return records
}

export function reportBodyweight(data: AppData, today: string): number | null {
  const profile = data.profile
  if (!profile || !validMass(profile.weight_kg)) return null
  if (profile.weight_kg !== 70 || bespokeProtocolFor(profile)) return profile.weight_kg
  // A new database profile defaults to 70 kg even when nobody has entered a weight.
  const recorded = (row: { user_id: string; date: string; weight_kg: number | null }) =>
    row.user_id === profile.user_id && isIsoDate(row.date) && row.date <= today && row.weight_kg === profile.weight_kg
  if (data.daily_logs.some(recorded) || data.health_metrics.some(recorded)) return profile.weight_kg
  const owned = data.fitness_evidence.filter(row => row.user_id === profile.user_id)
  const superseded = new Set(owned.map(row => row.supersedes_id))
  return owned.some(row => row.metric === 'body_mass' && row.unit === 'kg' && row.value === profile.weight_kg
    && !superseded.has(row.id) && isIsoDate(row.measured_at.slice(0,10)) && row.measured_at.slice(0,10) <= today) ? profile.weight_kg : null
}

const scoreLabels: Record<Score, string> = {
  overall: 'Overall Fitness Level', health: 'Health', joint: 'Joint Health Balance',
  flexibility: 'Body Flexibility', endurance: 'Endurance', strength: 'Strength',
  strength_lower: 'Lower Body Strength', strength_upper: 'Upper Body Strength',
}

function escape(value: string) {
  return value.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))
}

export function avatarReportHTML(options: ReportInput, illustration?: Illustration, legArt: ReadonlyMap<string, string> = new Map()) {
  const { name, locale, snapshots, observed, families, training, today, translate } = options
  const t = (s: string) => escape(translate(s))
  const fmt = new Intl.NumberFormat(locale, { maximumFractionDigits: 1 })
  const dates = new Intl.DateTimeFormat(locale, { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' })
  const stamp = (d: string) => dates.format(new Date(d + 'T12:00:00Z'))
  const repCount = (n: number) => fmt.format(n) + ' ' + t(n === 1 ? 'rep' : 'reps')
  const metric = (p: ReportPoint, unit: string) => (p.reps != null && p.reps > 0 ? repCount(p.reps) + ' × ' : '') + fmt.format(p.value) + unit
  const chart = (series: ReportPoint[], unit: string, label: string, perSession = false) => {
    if (series.length < 2) return ''
    const max = unit ? series.reduce((peak, p) => Math.max(peak, p.value), 0) : 100
    const axis = datedChartAxis(series.map(point => point.date), locale)
    const positions = perSession ? distinctSessionPositions(axis.positions) : axis.positions
    const pointLabel = (index: number) => (perSession ? '#' + fmt.format(index + 1) + ' · ' : '')
      + stamp(series[index].date) + ' · ' + metric(series[index], unit)
    const plotX = (fraction: number) => 48 + 406 * fraction
    const xy = series.map((p, i) => [
      plotX(positions[i]),
      max ? 55 - 45 * p.value / max : 55,
    ].map(v => v.toFixed(1)))

    return `<svg role="img" aria-label="${label}" viewBox="0 0 490 82">
      <path d="M48 10H468 M48 32H468 M48 55H468" fill="none" stroke="#ddd9ec" stroke-dasharray="3 5"/>
      <g font-size="11" fill="#584d69"><text x="0" y="13">${fmt.format(max)}</text><text x="0" y="58">0</text></g>
      <polyline points="${xy.map(pair => pair.join(',')).join(' ')}" fill="none" stroke="#733fc1" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"/>
      ${xy.map(([x,y],i) => `<circle cx="${x}" cy="${y}" r="${i === xy.length - 1 ? 3.8 : 2.6}" fill="#512790"><title>${pointLabel(i)}</title></circle>`).join('')}
      ${axis.ticks.map(tick => `<text x="${plotX(tick.fraction)}" y="77" text-anchor="middle" font-size="11" fill="#584d69">${tick.label}</text>`).join('')}</svg>
      <div class="ends"><span>${pointLabel(0)}</span>${series.length > 1 ? `<span>${pointLabel(series.length - 1)}</span>` : ''}</div>`
  }
  const tiles = Object.entries(scoreLabels).flatMap(([key, label]) => {
    const points = snapshots.flatMap(s => Number.isFinite(s[key as Score]) ? [{ date: s.date, value: s[key as Score] }] : [])
    const value = points.at(-1)?.value ?? observed[key as keyof StatBlock]
    if (value == null || !Number.isFinite(value)) return []
    return [`<article><h3>${t(label)}</h3><b class="score">${fmt.format(value)}<small> / 100</small></b>${chart(points,'',t(label))}</article>`]
  })
  function repsTotal(work: RecordedWork) {
    return work.recordedReps == null ? null : fmt.format(work.recordedReps) + (work.missingReps ? '*' : '')
  }
  function volumeTotal(work: RecordedWork) {
    return work.liftedKg == null ? null : formattedMass(work.liftedKg, locale) + (work.missingVolume ? '*' : '')
  }
  function setLabel(set: WorkingSet) {
    return [set.reps != null && repCount(set.reps), set.weight != null && fmt.format(set.weight) + ' kg'].filter(Boolean).join(' × ')
  }
  function heaviestSet(sets: WorkingSet[], load: (set: WorkingSet) => number | null) {
    let best: WorkingSet | undefined
    let peak = -Infinity
    for (const set of sets) {
      const kg = load(set)
      if (kg == null || set.reps == null) continue
      if (!best || kg > peak || (kg === peak && set.reps > (best.reps ?? 0))) {
        best = set
        peak = kg
      }
    }
    return best
  }
  function personalRecord(set: WorkingSet, combinedKg?: number | null, single?: WorkingSet) {
    const value = (label: string, kg: number | null) => `<div><dt>${t(label)}</dt><dd>${kg == null ? '&ndash;' : fmt.format(kg) + ' kg'}</dd></div>`
    const detail = [set.reps != null && repCount(set.reps), stamp(set.date),
      options.range && !options.range.allTime && t('Best in range')].filter(Boolean).join(' · ')
    return `<section class="personal-record"><h4>${t('Personal record')}</h4><p>${detail}</p>
      <dl>${value('Added weight', set.weight)}${combinedKg !== undefined ? value('Body + load', combinedKg) : ''}</dl>
      ${single && single !== set
        ? `<p class="single-record"><b>${t('Best single')}</b> · ${setLabel(single)} · ${stamp(single.date)}</p>` : ''}</section>`
  }
  function workingLeg(variant: ReportFamily['variants'][number], record: ExerciseRecord) {
    const load = loadGuide(variant)
    const last = record.sets.at(-1)
    if (!load || !last) return ''
    const latest = record.sets.reduce((best,set) => {
      if (set.sessionId !== last.sessionId) return best
      if ((set.weight ?? -1) > (best.weight ?? -1)) return set
      return set.weight === best.weight && (set.reps ?? 0) > (best.reps ?? 0) ? set : best
    }, last)
    const kind = load.kind
    function bodyFor(set: WorkingSet) {
      const mass = options.sessionBodyweights?.get(set.sessionId)
      if (validMass(mass)) return mass
      return set.date === today && validMass(options.currentBodyweight) ? options.currentBodyweight : null
    }
    function combined(set: WorkingSet) {
      const body = bodyFor(set)
      return kind !== 'externalOnly' && body != null && set.weight != null ? body + set.weight : null
    }
    const best = heaviestSet(record.sets, combined) ?? heaviestSet(record.sets, set => set.weight)
    const art = legArt.get(load.id)
    const image = art?.startsWith('data:image/webp;base64,') ? `<img alt="" src="${escape(art)}">` : ''
    function stage(label: 'Before' | 'After', set: WorkingSet) {
      const total = combined(set)
      const body = bodyFor(set)
      const added = set.weight
      const values: [string,number | null,string?][] = [['Added weight', added]]
      if (kind !== 'externalOnly') {
        const breakdown = total != null && body != null && added != null ? fmt.format(body) + ' + ' + fmt.format(added) + ' kg' : undefined
        values.push(['Body + load', total, breakdown])
      }
      const reps = label === 'Before' && added == null && record.firstSessionReps != null
        ? t('Recorded reps') + ' · ' + fmt.format(record.firstSessionReps)
        : set.reps != null ? repCount(set.reps) : ''
      return `<div class="leg-stage"><div class="leg-dates"><h5>${t(label)}</h5>
        <time datetime="${escape(set.date)}">${stamp(set.date)}</time>${reps ? `<span>${reps}</span>` : ''}
        ${label === 'Before' && isIsoDate(options.joined) ? `<small>${t('Joined FITR MAX')} · ${stamp(options.joined)}</small>` : ''}</div>
        ${image}<dl>${values.map(([key,value,detail]) =>
          `<div><dt>${t(key)}</dt><dd>${value == null ? '&ndash;' : fmt.format(value) + ' kg'}</dd>${detail ? `<small>${detail}</small>` : ''}</div>`).join('')}</dl></div>`
    }
    return `<aside class="leg-load"><h4>${t('Working leg')}</h4><div class="leg-stages">${stage('Before',record.before)}${stage('After',latest)}</div>
      ${load.kind === 'sharedSupport' ? `<p class="leg-note">${t('The share on each foot varies with stance and support.')}</p>` : ''}
      ${best ? personalRecord(best, kind === 'externalOnly' ? undefined : combined(best), record.bestSingle) : ''}</aside>`
  }
  const lifts = families.flatMap(family => family.variants.flatMap(variant => {
    const points = variant.points.map(p => ({ date: p.date, value: p.topWeight, reps: p.topReps }))
    const record = options.exerciseRecords?.get(variant.key ?? '')
    const leg = record ? workingLeg(variant, record) : ''
    if (points.length < 2 && !leg && !record?.bestSingle) return []
    const best = !leg && record && heaviestSet(record.sets, set => set.weight != null && set.weight > 0 ? set.weight : null)
    const card = leg || (best ? personalRecord(best, undefined, record?.bestSingle) : '')
    const chartBest = !card && points.reduce<ReportPoint | undefined>((peak, p) =>
      !peak || p.value > peak.value || (p.value === peak.value && (p.reps ?? 0) > (peak.reps ?? 0)) ? p : peak, undefined)
    const { title, subtitle } = exerciseChartTitle(family, variant.name, t)
    const reps = repsTotal(variant.work)
    const volume = volumeTotal(variant.work)
    const stats = [
      reps && `<div><dt>${t('Recorded reps')}</dt><dd>${reps}</dd></div>`,
      volume && `<div><dt>${t('Lifted volume')}</dt><dd>${volume}</dd></div>`,
    ].join('')
    return [`<article><h3>${title}</h3>${subtitle ? `<p class="variation">${subtitle}</p>` : ''}
      ${chart(points, ' kg', t(variant.name), true)}
      ${chartBest ? `<p>${t(options.range && !options.range.allTime ? 'Best in range' : 'Personal best')} · <strong>${metric(chartBest, ' kg')}</strong></p>` : ''}
      ${stats ? `<dl>${stats}</dl>` : ''}${card}</article>`]
  }))
  const total = totalRecordedWork(families)
  const object = liftedMassCaption(total.liftedKg ?? 0, locale, translate)
  const hero = heroLiftCaption(total.liftedKg ?? 0, locale, translate)
  const picture = object && illustration?.filename === object.artwork && illustration.dataURL.startsWith('data:image/webp;base64,')
    ? `<img class="award-art" alt="" src="${escape(illustration.dataURL)}">` : ''
  const analogy = object || hero ? `<div class="comparison">${picture}<div>
    ${object ? `<h4><a href="${escape(object.source)}">${escape(object.caption)}</a></h4><p class="fact"><a href="${escape(object.factSource)}">${escape(object.fact)}</a></p>` : ''}
    ${hero ? `<p class="hero"><a href="${escape(hero.source)}">${escape(hero.caption)}</a></p>` : ''}</div></div>` : ''
  const volume = volumeTotal(total)
  const volumePanel = volume == null ? '' : `<article class="volume-panel"><h3>${t('Lifted volume')}</h3><b class="score">${volume}</b>${analogy}</article>`
  const totals: Array<[string, string | null]> = [
    ['Performed sets', total.sets ? fmt.format(total.sets) : null],
    ['Recorded reps', repsTotal(total)],
  ]
  const totalTiles = totals.flatMap(([label, value]) => value == null ? [] : [
    `<article><h3>${t(label)}</h3><b class="score">${value}</b></article>`,
  ])
  const headers = ['Sessions', 'Recorded reps', 'Lifted volume', 'Load per rep'].map(t)
  function workRow(row: ReportWorkRow, rank?: number) {
    const { liftedKg, loadedReps, missingVolume } = row.work
    const partial = missingVolume ? '*' : ''
    const mean = liftedKg != null && loadedReps > 0 ? fmt.format(liftedKg / loadedReps) + ' kg' + partial : '–'
    const values = [fmt.format(row.sessionCount), repsTotal(row.work) ?? '–', volumeTotal(row.work) ?? '–', mean]
    return `<tr class="${rank == null ? 'variant' : 'family'}"><th scope="row">${rank == null ? '' : fmt.format(rank) + '. '}${t(row.name)}</th>${values.map((value,i) =>
      `<td data-label="${headers[i]}"${i === 2 && liftedKg != null ? ` title="${fmt.format(liftedKg)} kg"` : ''}>${value}</td>`).join('')}</tr>`
  }
  const rankings = families.map((family,i) => {
    const showVariants = family.variants.length > 1 || family.variants[0]?.name !== family.name
    return `<tbody>${workRow(family, i + 1)}${showVariants ? family.variants.map(v => workRow(v)).join('') : ''}</tbody>`
  })
  const range = options.range
  const bounds = (from: string, to: string) => stamp(from) + ' – ' + stamp(to)
  const profileStart = training.period?.from ?? new Date(Date.parse((range?.to ?? today) + 'T12:00:00Z') - 89 * 86400000).toISOString().slice(0,10)
  const profileDetails = training.workouts ? [
    t('Classified workouts') + ' ' + fmt.format(training.workouts),
    t('Workouts per week') + ' ' + fmt.format(training.workouts * 7 / (training.period?.days ?? 90)),
    ...Object.entries(training.counts).filter(([,count]) => count > 0).map(([label,count]) => t(label) + ' ' + fmt.format(count)),
  ].join(' · ') : ''
  return `<!doctype html><html lang="${escape(locale)}"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${t('Avatar report')} · FITR MAX</title><style>
*{box-sizing:border-box}body{margin:0;background:#f7f5fc;color:#271942;font:16px/1.5 system-ui,sans-serif}main{max-width:920px;margin:auto;padding:clamp(16px,4vw,52px)}h1{font-size:clamp(32px,7vw,64px);line-height:1.05;margin:.25em 0}h2{margin:1.6em 0 .45em}h3,p{margin:.25em 0}p,.ends,small{color:#584d69}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,290px),1fr));gap:12px}article,table{background:white;border:1px solid #ded8e9;border-radius:16px}article{padding:18px;break-inside:avoid}h1,h2,h3,th,p{overflow-wrap:anywhere}.work .family{background:#f8f5fd;font-weight:650}.work .variant th{padding-inline-start:26px;font-weight:400}.work .variant{color:#584d69;font-size:.88em}.work td{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}.work th:not(:first-child){text-align:right}.work-note{margin-top:.65em;font-size:.85em}@media screen and (max-width:600px){.work,.work tbody{display:block}.work thead{position:absolute;clip-path:inset(50%);width:1px;height:1px;overflow:hidden}.work tr{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));padding:9px 12px;gap:6px}.work tr>th{grid-column:1/-1}.work th,.work td,.work .variant th{padding:0;border:0;text-align:left}.work td:before{display:block;content:attr(data-label);color:#62576b;font-size:.74em;font-weight:400;white-space:normal}.work .variant{padding-inline-start:24px;border-top:1px solid #eee9f3}.work .family{border-top:1px solid #ded8e9}}.score{font-size:1.7em}.score small{font-size:.5em}svg{display:block;width:100%;margin-top:14px}.ends{display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;font-size:.78em;font-variant-numeric:tabular-nums}.lifts article{border-left:5px solid #ab82dc;margin-bottom:10px}.lifts svg{max-height:130px}table{border-spacing:0;width:100%;margin-top:.75em}td,th{padding:8px 14px;border-bottom:1px solid #eee9f3;text-align:left}td:last-child,th:last-child{text-align:right}thead{background:#f7efca}tr{break-inside:avoid}@page{margin:14mm}@media print{body{background:white;font-size:11pt}main{padding:0}.grid{display:block;columns:2}.grid article{margin-bottom:10px}.lifts>p,h2,h3{break-after:avoid}*{print-color-adjust:exact}}
.totals{grid-template-columns:repeat(auto-fit,minmax(min(100%,135px),1fr))}.totals article{padding:12px 16px}.totals h3{margin:0;font-size:1em}.totals .score{font-size:1.5em}
.volume-panel{background:#eef6f1;border-color:#d1e4da;color:#145442;margin-bottom:12px}.volume-panel h3{margin:0}.volume-panel>.score{display:block;font-size:clamp(2.25em,6vw,3em);line-height:1.1;overflow-wrap:anywhere}
.comparison{display:flex;align-items:flex-start;gap:clamp(12px,3vw,26px);margin-top:10px}.comparison h4{margin:0;font-size:1.2em;overflow-wrap:anywhere}.comparison a{color:inherit;text-decoration:none}.comparison .fact{font-size:.9em}.comparison .hero{font-weight:650;color:#3e3566;margin-top:.55em}.award-art{width:clamp(88px,28%,150px);height:auto;flex:none}.profile-details{font-size:.86em;margin:16px 0}.totals-section{break-inside:avoid}
.profile{background:linear-gradient(115deg,#f1eafa,#e2d7f7);border-left:6px solid #7442be;border-radius:0 18px 18px 0;padding:clamp(18px,4vw,32px);break-inside:avoid}
.profile h1{color:#41246b;font-size:clamp(32px,6.8vw,58px);margin:.16em 0 .25em}
.report-range{margin:0 0 8px;font-weight:600}.profile .period{font-size:.82em;font-weight:700;color:#563280}
.profile p{margin:.15em 0}
.masthead{display:flex;align-items:baseline;justify-content:space-between;flex-wrap:wrap;gap:4px 16px;margin-bottom:12px}
.masthead strong{letter-spacing:.12em}.masthead p{font-size:.88em}
.lifts dl{display:flex;flex-wrap:wrap;gap:4px 22px;margin:10px 0 0;padding-top:8px;border-top:1px solid #e6e0ed}
.lifts dl div{display:flex;gap:6px;align-items:baseline}.lifts dt{color:#584d69;font-size:.82em}.lifts dd{font-weight:700;margin:0}
.lifts>p{margin-bottom:8px}.variation{font-weight:600}.lifts dl{margin:14px 0 0;padding:12px 0 0;gap:8px 28px}
.leg-load{background:#edf5f1;border-radius:14px;margin-top:16px;padding:12px}.leg-load h4{margin:4px 0 18px;font-size:1.8rem;line-height:1.2;font-weight:800}.leg-stages{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.leg-stage{display:grid;grid-template-rows:subgrid;grid-row:span 3;row-gap:0;border-radius:12px;background:#fff;padding:12px}.leg-stage .leg-dates{grid-row:1}.leg-stage img{grid-row:2}.leg-stage dl{grid-row:3}.leg-stage+.leg-stage{background:#d9efe6}.leg-dates{min-height:4.3em}.leg-stage h5{margin:0 0 8px;font-size:1.45rem;line-height:1.1;font-weight:850;text-transform:uppercase;letter-spacing:.04em}.leg-dates time{display:block;font-size:1.1rem;line-height:1.3;font-weight:650;margin-bottom:6px;color:#122729}.leg-stage small{display:block;font-size:.76em;color:#425e55}.leg-stage img{display:block;width:100%;height:116px;object-fit:contain;margin:8px 0}.leg-stage dl{display:grid;align-content:start;margin:8px 0 0;border:0;padding:0;gap:12px}.leg-stage dl div{display:block}.leg-stage dt{font-size:1rem;line-height:1.25;font-weight:650;color:#183633}.leg-stage dd{font-size:1.25rem;font-weight:700}.leg-stage dl div:nth-child(2) dd{font-size:1.5rem;color:#00695c}.leg-note{font-size:.8em;margin:8px 0}
.personal-record{margin-top:14px;padding:clamp(14px,3vw,24px);background:#ecf7f2;color:#183633;border-radius:12px;break-inside:avoid;overflow-wrap:anywhere}
.personal-record h4{margin:0;font-size:clamp(1.5rem,4vw,2.2rem);line-height:1.1;letter-spacing:.025em;text-transform:uppercase}.personal-record p,.personal-record dt{color:#35584e}
.personal-record dl{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,140px),1fr));border-color:#c7dfd4;margin:12px 0 0;padding:10px 0 0;gap:10px}
.personal-record dl div{display:block}.personal-record dt{font-size:.9em}.personal-record dd{color:#145442;font-size:clamp(1.5rem,4vw,2.2rem);line-height:1.15}.single-record{margin-top:12px}
@media print{.award-art{width:27mm}.leg-stage img{height:24mm}}
@media screen and (max-width:600px){svg text{font-size:17px}.profile p:not(.period){font-size:.9em}.lifts article{padding:14px}.ends{gap:2px 10px}}
@media print{.profile{padding:14px 20px}.profile h1{font-size:29pt}.totals{display:flex;columns:auto;align-items:flex-start}.totals article{flex:1;min-width:0}}
</style><main><div class="masthead"><strong>FITR MAX · ${t('Avatar report')}</strong><p>${escape(name)} · ${stamp(today)}</p></div>
${range && (range.allTime || profileStart !== range.from) ? `<p class="report-range">${t(range.allTime ? 'All time' : 'Date range')} · ${bounds(range.from, range.to)}</p>` : ''}
<header class="profile"><p class="period">${t(training.period ? 'Training profile' : '90-day training profile')}${range ? ' · ' + bounds(profileStart, range.to) : ''}</p><h1>${t(athleteTitle(training))}</h1></header>
${volumePanel || totalTiles.length ? `<section class="totals-section"><h2>${t(range && !range.allTime ? 'Training totals' : 'All-time training totals')}</h2>${volumePanel}${totalTiles.length ? `<div class="grid totals">${totalTiles.join('')}</div>` : ''}</section>` : ''}
${profileDetails ? `<p class="profile-details">${profileDetails}</p>` : ''}
${total.missingReps || total.missingVolume ? `<p class="work-note">* ${t('Incomplete records')}</p>` : ''}
${lifts.length ? `<section class="lifts"><h2>${t('Recorded load')}</h2><p>${t('Heaviest recorded set per session, in kilograms.')}</p>${lifts.join('')}</section>` : ''}
${tiles.length ? `<section><h2>${t('Stats')}</h2><p>${t('Legacy game scores. Not medical measurements.')}</p><div class="grid">${tiles.join('')}</div></section>` : ''}
${rankings.length ? `<section><h2>${t('Most trained exercises')}</h2><p>${t('Each completed workout counts once per exercise family.')}</p><table class="work"><thead><tr><th>${t('Exercise')}</th>${headers.map(label => `<th>${label}</th>`).join('')}</tr></thead>${rankings.join('')}</table></section>` : ''}</main></html>`
}

async function embeddedWebP(url: string) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(8000) })
    if (!response.ok) return
    const bytes = new Uint8Array(await response.arrayBuffer())
    const tag = (from: number) => String.fromCharCode(...bytes.subarray(from, from + 4))
    if (tag(0) === 'RIFF' && tag(8) === 'WEBP') {
      return 'data:image/webp;base64,' + btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join(''))
    }
  } catch {
    // An unavailable illustration leaves a complete text report.
  }
}

export async function downloadableAvatarReport(options: ReportInput, baseURL: string) {
  const kg = totalRecordedWork(options.families).liftedKg
  const filename = kg == null ? undefined : liftedMassCaption(kg, options.locale, options.translate)?.artwork
  const ids = new Set(options.families.flatMap(family => family.variants.flatMap(variant => {
    const load = options.exerciseRecords?.get(variant.key ?? '')?.sets.length ? loadGuide(variant) : null
    return load ? [load.id] : []
  })))
  const [award, anatomy] = await Promise.all([
    filename && /^[a-z0-9-]+\.webp$/.test(filename) ? embeddedWebP(baseURL + 'award-objects/' + filename) : undefined,
    Promise.all([...ids].map(async id => [id, await embeddedWebP(baseURL + 'leg-anatomy/' + id + '.webp')] as const)),
  ])
  return avatarReportHTML(options, filename && award ? { filename, dataURL: award } : undefined,
    new Map(anatomy.filter((entry): entry is readonly [string, string] => entry[1] != null)))
}
