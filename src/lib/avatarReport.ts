// A standalone document: the downloaded report needs neither a login nor a network connection.
import { datedChartAxis } from './datedChartAxis.ts'
import type { RpgSnapshot } from './types'
import type { StatBlock } from './rpg'

type ReportPoint = { date: string; value: number; reps?: number | null }
type ReportFamily = { name: string; sessionCount: number; variants: {
  name: string; sessionCount: number; points: { date: string; topWeight: number; topReps: number | null }[]
}[] }
type Score = keyof StatBlock | 'overall' | 'strength'

const scoreLabels: Record<Score, string> = {
  overall: 'Overall Fitness Level', health: 'Health', joint: 'Joint Health Balance',
  flexibility: 'Body Flexibility', endurance: 'Endurance', strength: 'Strength',
  strength_lower: 'Lower Body Strength', strength_upper: 'Upper Body Strength',
}

function escape(value: string) {
  return value.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))
}

export function avatarReportHTML(options: {
  name: string; locale: string; today: string; snapshots: RpgSnapshot[];
  observed: Partial<StatBlock>; families: ReportFamily[]; translate: (text: string) => string
}) {
  const { name, locale, snapshots, observed, families, today, translate } = options
  const t = (s: string) => escape(translate(s))
  const fmt = new Intl.NumberFormat(locale, { maximumFractionDigits: 1 })
  const dates = new Intl.DateTimeFormat(locale, { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' })
  const stamp = (d: string) => dates.format(new Date(d + 'T12:00:00Z'))
  const metric = (p: ReportPoint, unit: string) => fmt.format(p.value) + unit + (p.reps != null && p.reps > 0 ? ' × ' + fmt.format(p.reps) : '')
  const chart = (series: ReportPoint[], unit: string, label: string) => {
    if (!series.length) return ''
    const first = series[0], last = series[series.length - 1]
    const max = unit ? series.reduce((peak, p) => Math.max(peak, p.value), 0) : 100
    const axis = datedChartAxis(series.map(point => point.date), locale)
    const plotX = (fraction: number) => 48 + 406 * fraction
    const xy = series.map((p, i) => [
      plotX(axis.positions[i]),
      max ? 55 - 45 * p.value / max : 55,
    ].map(v => v.toFixed(1)))

    return `<svg role="img" aria-label="${label}" viewBox="0 0 490 82">
      <path d="M48 10H468 M48 32H468 M48 55H468" fill="none" stroke="#ddd9ec" stroke-dasharray="3 5"/>
      <g font-size="11" fill="#584d69"><text x="0" y="13">${fmt.format(max)}${unit}</text><text x="0" y="58">0</text></g>
      <polyline points="${xy.map(pair => pair.join(',')).join(' ')}" fill="none" stroke="#733fc1" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"/>
      ${xy.map(([x,y],i) => `<circle cx="${x}" cy="${y}" r="${i === xy.length - 1 ? 3.8 : 2.6}" fill="#512790"><title>${stamp(series[i].date)} · ${metric(series[i],unit)}</title></circle>`).join('')}
      ${axis.ticks.map(tick => `<text x="${plotX(tick.fraction)}" y="77" text-anchor="middle" font-size="11" fill="#584d69">${tick.label}</text>`).join('')}</svg>
      <div class="ends"><span>${stamp(first.date)} · ${metric(first, unit)}</span>${series.length > 1 ? `<span>${stamp(last.date)} · ${metric(last,unit)}</span>` : ''}</div>`
  }
  const latest = snapshots.at(-1)
  const tiles = Object.entries(scoreLabels).map(([key, label]) => {
    const value = latest?.[key as Score] ?? observed[key as keyof StatBlock]
    const points = snapshots.map(s => ({ date: s.date, value: s[key as Score] }))
    return `<article><h3>${t(label)}</h3><b class="score">${value != null ? fmt.format(value) + '<small> / 100</small>' : t('No data')}</b>${chart(points,'',t(label))}</article>`
  })
  const lifts = families.flatMap(family => family.variants.filter(variant => variant.points.length)).slice(0,5)
    .map(variant => ({ name: variant.name, points: variant.points.map(p => ({ date: p.date, value: p.topWeight, reps: p.topReps })) }))
  const rankings = families.map((family,i) => {
    const variants = family.variants.length > 1 || family.variants[0]?.name !== family.name
      ? `<small class="variants">${family.variants.map(v => `${t(v.name)} · ${fmt.format(v.sessionCount)}`).join('<br>')}</small>` : ''
    return `<tr><td>${fmt.format(i+1)}</td><th scope="row">${t(family.name)}${variants}</th><td>${fmt.format(family.sessionCount)}</td></tr>`
  })
  const empty = `<p>${t('No data')}</p>`
  return `<!doctype html><html lang="${escape(locale)}"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${t('Avatar report')} · FITR MAX</title><style>
*{box-sizing:border-box}body{margin:0;background:#f7f5fc;color:#271942;font:16px/1.5 system-ui,sans-serif}main{max-width:920px;margin:auto;padding:clamp(16px,4vw,52px)}header{padding:clamp(18px,5vw,54px);border-radius:26px;background:#e9dfff;border-top:8px solid #7442be}header b{letter-spacing:.22em;color:#563280}h1{font-size:clamp(32px,7vw,64px);line-height:1.05;margin:.25em 0}h2{margin:1.6em 0 .45em}h3,p{margin:.25em 0}p,.ends,small{color:#584d69}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,290px),1fr));gap:12px}article,table{background:white;border:1px solid #ded8e9;border-radius:16px}article{padding:18px;break-inside:avoid}h1,h2,h3,th,p{overflow-wrap:anywhere}.variants{display:block;margin-top:.3em;font-weight:400}.score{font-size:1.7em}.score small{font-size:.5em}svg{display:block;width:100%;margin-top:14px}.ends{display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;font-size:.78em;font-variant-numeric:tabular-nums}.lifts article{border-left:5px solid #ab82dc;margin-bottom:10px}.lifts svg{max-height:130px}table{border-spacing:0;width:100%;margin-top:.75em}td,th{padding:8px 14px;border-bottom:1px solid #eee9f3;text-align:left}td:last-child,th:last-child{text-align:right}thead{background:#f7efca}tr{break-inside:avoid}@page{margin:14mm}@media print{body{background:white;font-size:11pt}main{padding:0}.grid{display:block;columns:2}.grid article{margin-bottom:10px}.lifts{break-before:page}h2,h3{break-after:avoid}header{padding:16px}*{print-color-adjust:exact}}
</style><main><header><b>FITR MAX</b><h1>${t('Avatar report')}</h1><p>${escape(name)} · ${stamp(today)}</p></header>
<section><h2>${t('Stats')}</h2><p>${t('Legacy game scores. Not medical measurements.')}</p><div class="grid">${tiles.join('')}</div></section>
<section class="lifts"><h2>${t('Recorded load')}</h2><p>${t('Heaviest recorded set per session, in kilograms.')}</p>${lifts.map(e => `<article><h3>${t(e.name)}</h3><div>${t('Personal best')} · ${fmt.format(e.points.reduce((m,p) => Math.max(m,p.value),0))} kg</div>${chart(e.points,' kg',t(e.name))}</article>`).join('') || empty}</section>
<section><h2>${t('Most trained exercises')}</h2><p>${t('Each completed workout counts once per exercise family.')}</p>${rankings.length ? `<table><thead><tr><th>#</th><th>${t('Exercise')}</th><th>${t('Sessions')}</th></tr></thead><tbody>${rankings.join('')}</tbody></table>` : empty}</section></main></html>`
}
