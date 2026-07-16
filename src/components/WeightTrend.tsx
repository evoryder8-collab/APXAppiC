import { motion } from 'framer-motion'
import { useId, useMemo, useState } from 'react'
import { useLanguage } from '../lib/i18n'
import type { IntroLanguage } from '../lib/introLanguage'
import { weightFromKg, type WeightUnit } from '../lib/simpleMode'
import type { DailyLog } from '../lib/types'
import { buildWeightTrend, weightTrendChange, type WeightTrendRange } from '../lib/weightTrend'

const COPY = {
  en: {
    title: 'Weight trend', subtitle: 'Built from your saved morning weigh-ins.', latest: 'Latest', change: 'Range change', entries: 'Check-ins', empty: 'Add two morning weigh-ins to reveal your curve.', graph: 'Weight progress curve',
  },
  ro: {
    title: 'Evoluția greutății', subtitle: 'Creată din cântăririle de dimineață salvate.', latest: 'Ultima valoare', change: 'Schimbare', entries: 'Cântăriri', empty: 'Adaugă două cântăriri de dimineață pentru a vedea curba.', graph: 'Curba evoluției greutății',
  },
  th: {
    title: 'แนวโน้มน้ำหนัก', subtitle: 'สร้างจากน้ำหนักตอนเช้าที่บันทึกไว้', latest: 'ล่าสุด', change: 'การเปลี่ยนแปลง', entries: 'ครั้งที่บันทึก', empty: 'บันทึกน้ำหนักตอนเช้าสองครั้งเพื่อดูเส้นแนวโน้ม', graph: 'กราฟแนวโน้มน้ำหนัก',
  },
} satisfies Record<IntroLanguage, Record<string, string>>

const RANGES: Array<{ days: WeightTrendRange; label: string }> = [
  { days: 7, label: '1W' },
  { days: 30, label: '1M' },
  { days: 90, label: '3M' },
  { days: 365, label: '12M' },
]

function graphGeometry(points: Array<{ date: string; value: number }>) {
  const width = 520
  const height = 190
  const padX = 28
  const padY = 28
  const values = points.map((point) => point.value)
  const min = values.length ? Math.min(...values) : 0
  const max = values.length ? Math.max(...values) : 0
  const spread = Math.max(1, max - min)
  const low = min - spread * 0.35
  const high = max + spread * 0.35
  const first = Date.parse(`${points[0]?.date ?? '1970-01-01'}T12:00:00Z`)
  const last = Date.parse(`${points.at(-1)?.date ?? '1970-01-01'}T12:00:00Z`)
  const timeSpread = Math.max(1, last - first)
  const coords = points.map((point) => ({
    x: points.length === 1 ? width / 2 : padX + ((Date.parse(`${point.date}T12:00:00Z`) - first) / timeSpread) * (width - padX * 2),
    y: height - padY - ((point.value - low) / Math.max(1, high - low)) * (height - padY * 2),
    point,
  }))
  if (coords.length === 0) return { width, height, coords, line: '', area: '' }
  if (coords.length === 1) return { width, height, coords, line: '', area: '' }
  let line = `M ${coords[0].x} ${coords[0].y}`
  for (let index = 0; index < coords.length - 1; index += 1) {
    const p0 = coords[Math.max(0, index - 1)]
    const p1 = coords[index]
    const p2 = coords[index + 1]
    const p3 = coords[Math.min(coords.length - 1, index + 2)]
    line += ` C ${p1.x + (p2.x - p0.x) / 6} ${p1.y + (p2.y - p0.y) / 6}, ${p2.x - (p3.x - p1.x) / 6} ${p2.y - (p3.y - p1.y) / 6}, ${p2.x} ${p2.y}`
  }
  return {
    width,
    height,
    coords,
    line,
    area: `${line} L ${coords.at(-1)!.x} ${height - padY} L ${coords[0].x} ${height - padY} Z`,
  }
}

export function WeightTrend({ logs, anchorDate, unit }: { logs: DailyLog[]; anchorDate: string; unit: WeightUnit }) {
  const { language } = useLanguage()
  const copy = COPY[language]
  const [range, setRange] = useState<WeightTrendRange>(30)
  const points = useMemo(() => buildWeightTrend(logs, anchorDate, range), [anchorDate, logs, range])
  const displayPoints = useMemo(() => points.map((point) => ({ date: point.date, value: Number(weightFromKg(point.weightKg, unit).toFixed(1)) })), [points, unit])
  const graph = graphGeometry(displayPoints)
  const id = useId().replace(/:/g, '')
  const changeKg = weightTrendChange(points)
  const change = changeKg == null ? null : Number(weightFromKg(changeKg, unit).toFixed(1))
  const latest = displayPoints.at(-1)?.value ?? null

  return (
    <div data-no-translate>
      <div className="grid grid-cols-3 gap-1.5">
        <Metric label={copy.latest} value={latest == null ? '–' : `${latest} ${unit}`} />
        <Metric label={copy.change} value={change == null ? '–' : `${change > 0 ? '+' : ''}${change} ${unit}`} positive={change != null && change < 0} />
        <Metric label={copy.entries} value={String(points.length)} />
      </div>
      <div className="mt-3 overflow-hidden rounded-[22px] border border-white/90 bg-[radial-gradient(circle_at_75%_10%,rgba(34,211,238,.14),transparent_42%),rgba(248,250,252,.82)] px-1.5 pt-3 pb-1 shadow-inner">
        {displayPoints.length > 0 ? (
          <svg viewBox={`0 0 ${graph.width} ${graph.height}`} className="h-auto w-full overflow-visible" role="img" aria-label={copy.graph}>
            <defs>
              <linearGradient id={`weight-line-${id}`} x1="0" y1="0" x2="1" y2="0"><stop stopColor="#8b5cf6" /><stop offset=".55" stopColor="#22d3ee" /><stop offset="1" stopColor="#10b981" /></linearGradient>
              <linearGradient id={`weight-area-${id}`} x1="0" y1="0" x2="0" y2="1"><stop stopColor="#22d3ee" stopOpacity=".28" /><stop offset="1" stopColor="#22d3ee" stopOpacity="0" /></linearGradient>
              <filter id={`weight-glow-${id}`} x="-30%" y="-70%" width="160%" height="240%"><feGaussianBlur stdDeviation="4" result="blur" /><feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
            </defs>
            {[0.3, 0.55, 0.8].map((ratio) => <line key={ratio} x1="24" x2={graph.width - 24} y1={graph.height * ratio} y2={graph.height * ratio} stroke="rgba(15,23,42,.08)" strokeDasharray="4 9" />)}
            {graph.area && <motion.path initial={{ opacity: 0 }} animate={{ opacity: 1 }} d={graph.area} fill={`url(#weight-area-${id})`} />}
            {graph.line && <motion.path key={graph.line} initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 0.9, ease: [0.16, 1, 0.3, 1] }} d={graph.line} fill="none" stroke={`url(#weight-line-${id})`} strokeWidth="6" strokeLinecap="round" strokeLinejoin="round" filter={`url(#weight-glow-${id})`} />}
            {graph.coords.map(({ x, y, point }, index) => <circle key={`${point.date}:${index}`} cx={x} cy={y} r="7" fill="white" stroke={index === graph.coords.length - 1 ? '#10b981' : '#8b5cf6'} strokeWidth="4"><title>{point.date}: {point.value} {unit}</title></circle>)}
            <text x="26" y={graph.height - 6} className="fill-ink-faint font-mono text-[12px]">{displayPoints[0]?.date.slice(5)}</text>
            <text x={graph.width - 26} y={graph.height - 6} textAnchor="end" className="fill-ink-faint font-mono text-[12px]">{displayPoints.at(-1)?.date.slice(5)}</text>
          </svg>
        ) : <div className="grid min-h-32 place-items-center px-5 text-center text-[11px] font-semibold leading-relaxed text-ink-faint">{copy.empty}</div>}
      </div>
      <div className="mt-3 grid grid-cols-4 gap-1 rounded-full bg-ink/5 p-1" role="group" aria-label={copy.title}>
        {RANGES.map((choice) => <button key={choice.days} type="button" aria-pressed={range === choice.days} onClick={() => setRange(choice.days)} className={`rounded-full px-2 py-1.5 font-mono text-[9px] font-black transition ${range === choice.days ? 'bg-violet-600 text-white shadow-sm' : 'text-ink-soft'}`}>{choice.label}</button>)}
      </div>
      <p className="mt-2 text-center text-[9px] font-semibold text-ink-faint">{copy.subtitle}</p>
    </div>
  )
}

function Metric({ label, value, positive = false }: { label: string; value: string; positive?: boolean }) {
  return <div className="rounded-2xl border border-white/90 bg-white/76 px-2.5 py-2.5 shadow-sm"><p className="truncate text-[8px] font-bold text-ink-faint">{label}</p><p className={`mt-1 truncate font-mono text-[11px] font-black ${positive ? 'text-emerald-700' : 'text-ink'}`}>{value}</p></div>
}
