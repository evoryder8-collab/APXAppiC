// A standalone document: the downloaded report needs neither a login nor a network connection.
import { trainingProfileLines, type TrainingProfile } from './trainingProfile.ts'
import { datedChartAxis, distinctSessionPositions } from './datedChartAxis.ts'
import { totalRecordedWork, type ExerciseFrequencyFamily, type RankedExerciseHistory } from './strengthProgress.ts'
import { formattedMass, heroLiftCaption, liftedMassCaption } from './liftedMassComparison.ts'
import type { RpgSnapshot } from './types'
import type { StatBlock } from './rpg'

type ReportPoint = { date: string; value: number; reps?: number | null; partial?: boolean }
type ReportWorkRow = Pick<ExerciseFrequencyFamily, 'name' | 'sessionCount' | 'work'>
type ReportFamily = ReportWorkRow & Pick<ExerciseFrequencyFamily, 'key' | 'sessions'> & {
  variants: Array<ReportWorkRow & Pick<RankedExerciseHistory, 'points'>>
}
type ReportInput = {
  name: string; locale: string; today: string; snapshots: RpgSnapshot[]
  observed: Partial<StatBlock>; training: TrainingProfile; families: ReportFamily[]; translate: (text: string) => string
}
type Illustration = { filename: string; dataURL: string }
type Score = keyof StatBlock | 'overall' | 'strength'

const scoreLabels: Record<Score, string> = {
  overall: 'Overall Fitness Level', health: 'Health', joint: 'Joint Health Balance',
  flexibility: 'Body Flexibility', endurance: 'Endurance', strength: 'Strength',
  strength_lower: 'Lower Body Strength', strength_upper: 'Upper Body Strength',
}

function escape(value: string) {
  return value.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))
}

export function avatarReportHTML(options: ReportInput, illustration?: Illustration) {
  const { name, locale, snapshots, observed, families, training, today, translate } = options
  const t = (s: string) => escape(translate(s))
  const fmt = new Intl.NumberFormat(locale, { maximumFractionDigits: 1 })
  const dates = new Intl.DateTimeFormat(locale, { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' })
  const stamp = (d: string) => dates.format(new Date(d + 'T12:00:00Z'))
  const metric = (p: ReportPoint, unit: string) => fmt.format(p.value) + unit + (p.reps != null && p.reps > 0 ? ' × ' + fmt.format(p.reps) : '') + (p.partial ? '*' : '')
  const chart = (series: ReportPoint[], unit: string, label: string, perSession = false) => {
    if (!series.length) return ''
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
  const latest = snapshots.at(-1)
  const tiles = Object.entries(scoreLabels).map(([key, label]) => {
    const value = latest?.[key as Score] ?? observed[key as keyof StatBlock]
    const points = snapshots.map(s => ({ date: s.date, value: s[key as Score] }))
    return `<article><h3>${t(label)}</h3><b class="score">${value != null ? fmt.format(value) + '<small> / 100</small>' : t('No data')}</b>${chart(points,'',t(label))}</article>`
  })
  const lifts = families.flatMap(family => family.variants.filter(variant => variant.points.length))
    .map(variant => ({ name: variant.name, points: variant.points.map(p => ({ date: p.date, value: p.topWeight, reps: p.topReps })) }))
  const total = totalRecordedWork(families)
  const object = liftedMassCaption(total.liftedKg ?? 0, locale, translate)
  const hero = heroLiftCaption(total.liftedKg ?? 0, locale, translate)
  const picture = object && illustration?.filename === object.artwork && illustration.dataURL.startsWith('data:image/webp;base64,')
    ? `<img class="award-art" alt="" src="${escape(illustration.dataURL)}">` : ''
  const comparisons = [
    object && `<figure>${picture}<figcaption><p><a href="${escape(object.source)}">${escape(object.caption)}</a></p><p class="fact"><a href="${escape(object.factSource)}">${escape(object.fact)}</a></p></figcaption></figure>`,
    hero && `<p><a href="${escape(hero.source)}">${escape(hero.caption)}</a></p>`,
  ].join('')
  const totals = [
    ['Performed sets', fmt.format(total.sets)],
    ['Recorded reps', total.recordedReps == null ? '–' : fmt.format(total.recordedReps) + (total.missingReps ? '*' : '')],
    ['Lifted volume', total.liftedKg == null ? '–' : formattedMass(total.liftedKg, locale) + (total.missingVolume ? '*' : '')],
  ]
  function sessionCharts(metricKey: 'recordedReps' | 'liftedKg') {
    const volume = metricKey === 'liftedKg'
    return families.flatMap(family => {
      if (volume && family.key !== 'family:split_squat' && family.key !== 'family:lunge') return []
      const points = family.sessions.flatMap(({ date, work }) => {
        const value = work[metricKey]
        return value == null ? [] : [{ date, value, partial: volume ? work.missingVolume : work.missingReps }]
      })
      if (!points.length) return []
      return [`<article><h3>${t(family.name)}</h3>${chart(points, volume ? ' kg' : ' ' + t('reps'), t(family.name), true)}</article>`]
    }).join('')
  }
  const repCharts = sessionCharts('recordedReps')
  const volumeCharts = sessionCharts('liftedKg')
  const headers = ['Sessions', 'Recorded reps', 'Lifted volume', 'Load per rep'].map(t)
  function workRow(row: ReportWorkRow, rank?: number) {
    const { recordedReps, liftedKg, loadedReps, missingReps, missingVolume } = row.work
    const partial = missingVolume ? '*' : ''
    const volume = liftedKg == null ? '–'
      : formattedMass(liftedKg, locale) + partial
    const mean = liftedKg != null && loadedReps > 0 ? fmt.format(liftedKg / loadedReps) + ' kg' + partial : '–'
    const values = [fmt.format(row.sessionCount), recordedReps == null ? '–' : fmt.format(recordedReps) + (missingReps ? '*' : ''), volume, mean]
    return `<tr class="${rank == null ? 'variant' : 'family'}"><th scope="row">${rank == null ? '' : fmt.format(rank) + '. '}${t(row.name)}</th>${values.map((value,i) =>
      `<td data-label="${headers[i]}"${i === 2 && liftedKg != null ? ` title="${fmt.format(liftedKg)} kg"` : ''}>${value}</td>`).join('')}</tr>`
  }
  const rankings = families.map((family,i) => {
    const showVariants = family.variants.length > 1 || family.variants[0]?.name !== family.name
    return `<tbody>${workRow(family, i + 1)}${showVariants ? family.variants.map(v => workRow(v)).join('') : ''}</tbody>`
  })
  const empty = `<p>${t('No data')}</p>`
  return `<!doctype html><html lang="${escape(locale)}"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${t('Avatar report')} · FITR MAX</title><style>
*{box-sizing:border-box}body{margin:0;background:#f7f5fc;color:#271942;font:16px/1.5 system-ui,sans-serif}main{max-width:920px;margin:auto;padding:clamp(16px,4vw,52px)}header{padding:clamp(18px,5vw,54px);border-radius:26px;background:#e9dfff;border-top:8px solid #7442be}header b{letter-spacing:.22em;color:#563280}h1{font-size:clamp(32px,7vw,64px);line-height:1.05;margin:.25em 0}h2{margin:1.6em 0 .45em}h3,p{margin:.25em 0}p,.ends,small{color:#584d69}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,290px),1fr));gap:12px}article,table{background:white;border:1px solid #ded8e9;border-radius:16px}article{padding:18px;break-inside:avoid}h1,h2,h3,th,p{overflow-wrap:anywhere}.work .family{background:#f8f5fd;font-weight:650}.work .variant th{padding-inline-start:26px;font-weight:400}.work .variant{color:#584d69;font-size:.88em}.work td{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}.work th:not(:first-child){text-align:right}.work-note{margin-top:.65em;font-size:.85em}@media screen and (max-width:600px){.work,.work tbody{display:block}.work thead{position:absolute;clip-path:inset(50%);width:1px;height:1px;overflow:hidden}.work tr{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));padding:9px 12px;gap:6px}.work tr>th{grid-column:1/-1}.work th,.work td,.work .variant th{padding:0;border:0;text-align:left}.work td:before{display:block;content:attr(data-label);color:#62576b;font-size:.74em;font-weight:400;white-space:normal}.work .variant{padding-inline-start:24px;border-top:1px solid #eee9f3}.work .family{border-top:1px solid #ded8e9}}.score{font-size:1.7em}.score small{font-size:.5em}svg{display:block;width:100%;margin-top:14px}.ends{display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;font-size:.78em;font-variant-numeric:tabular-nums}.lifts article{border-left:5px solid #ab82dc;margin-bottom:10px}.lifts svg{max-height:130px}table{border-spacing:0;width:100%;margin-top:.75em}td,th{padding:8px 14px;border-bottom:1px solid #eee9f3;text-align:left}td:last-child,th:last-child{text-align:right}thead{background:#f7efca}tr{break-inside:avoid}@page{margin:14mm}@media print{body{background:white;font-size:11pt}main{padding:0}.grid{display:block;columns:2}.grid article{margin-bottom:10px}.lifts>p,h2,h3{break-after:avoid}header{padding:16px}*{print-color-adjust:exact}}
.totals{grid-template-columns:repeat(auto-fit,minmax(min(100%,200px),1fr))}.totals figure{margin:.6em 0;break-inside:avoid}.award-art{display:block;max-width:100%;width:100%;height:150px;object-fit:contain;margin-bottom:.6em}@media print{.award-art{height:32mm}}
</style><main><header><b>FITR MAX</b><h1>${t('Avatar report')}</h1><p>${escape(name)} · ${stamp(today)}</p></header>
<section><h2>${t('All-time training totals')}</h2><div class="grid totals">${totals.map(([label,value]) => `<article><h3>${t(label)}</h3><b class="score">${value}</b>${label === 'Lifted volume' ? comparisons : ''}</article>`).join('')}</div><p class="work-note">${t('Known external load × recorded reps. Body mass, assistance and timed work are excluded from volume. Skipped sets are excluded from all totals.')} ${t('Volume sums each recorded load × reps. An asterisk marks incomplete records.')} </p></section>
<section><h2>${t('Stats')}</h2><p>${t('Legacy game scores. Not medical measurements.')}</p><div class="grid">${tiles.join('')}</div></section>
<section><h2>${t('90-day training profile')}</h2><h3>${t(training.focus)}</h3>${trainingProfileLines(training, locale, translate).map(line => `<p>${escape(line)}</p>`).join('')}</section>
${repCharts ? `<section class="lifts"><h2>${t('Reps per session')}</h2><p>${t('Each point sums recorded reps across all variations in one completed workout.')}</p>${repCharts}</section>` : ''}
${volumeCharts ? `<section class="lifts"><h2>${t('Recorded volume per session')}</h2><p>${t('Split squats and lunges use the load and reps entered for each set once. Left and right sides are not recorded separately.')}</p>${volumeCharts}</section>` : ''}
${lifts.length ? `<section class="lifts"><h2>${t('Recorded load')}</h2><p>${t('Heaviest recorded set per session, in kilograms.')}</p>${lifts.map(e => `<article><h3>${t(e.name)}</h3><div>${t('Personal best')} · ${fmt.format(e.points.reduce((m,p) => Math.max(m,p.value),0))} kg</div>${chart(e.points,' kg',t(e.name),true)}</article>`).join('')}</section>` : ''}
<section><h2>${t('Most trained exercises')}</h2><p>${t('Each completed workout counts once per exercise family.')}</p>${rankings.length ? `<table class="work"><thead><tr><th>${t('Exercise')}</th>${headers.map(label => `<th>${label}</th>`).join('')}</tr></thead>${rankings.join('')}</table><p class="work-note">${t('Volume sums each recorded load × reps. An asterisk marks incomplete records.')} ${t('Load per rep averages only reps with a measured load.')}</p>` : empty}</section></main></html>`
}

export async function downloadableAvatarReport(options: ReportInput, baseURL: string) {
  const kg = totalRecordedWork(options.families).liftedKg
  const filename = kg == null ? undefined : liftedMassCaption(kg, options.locale, options.translate)?.artwork
  let illustration: Illustration | undefined
  if (filename && /^[a-z0-9-]+\.webp$/.test(filename)) {
    try {
      const response = await fetch(baseURL + 'award-objects/' + filename, { signal: AbortSignal.timeout(8000) })
      if (response.ok) {
        const bytes = new Uint8Array(await response.arrayBuffer())
        const tag = (from: number) => String.fromCharCode(...bytes.subarray(from, from + 4))
        if (tag(0) === 'RIFF' && tag(8) === 'WEBP') {
          const data = btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join(''))
          illustration = { filename, dataURL: 'data:image/webp;base64,' + data }
        }
      }
    } catch {
      // A missing or offline illustration still leaves a complete text report.
    }
  }
  return avatarReportHTML(options, illustration)
}
