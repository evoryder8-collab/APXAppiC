import { useMemo, useState } from 'react'
import { motion } from 'framer-motion'
import { useLanguage } from '../../lib/i18n'
import { normalizeRecoveryHistory } from '../../lib/personalProtocol'
import { ACCENTS } from '../../lib/theme'
import { useStore } from '../../store/AppStore'
import type { RecoveryDataSource } from '../../lib/types'
import { GlassCard } from '../ui'

const COPY = {
  en: {
    eyebrow: 'SOURCE-AWARE AVATAR SIGNAL',
    title: 'Sleep & recovery trend',
    subtitle: 'Apple Sleep Score and Recovery score retain their original meaning when you change source.',
    apple: 'Apple Sleep Score',
    other: 'Recovery score',
    sleep: 'Other Sleep',
    noData: 'Enter a morning score in Simple Mode to begin the trend.',
    latest: 'Latest',
  },
  ro: {
    eyebrow: 'SEMNAL AVATAR CU SURSĂ PĂSTRATĂ',
    title: 'Evoluția somnului și recuperării',
    subtitle: 'Scorul de somn Apple și recuperarea Other își păstrează sensul original când schimbi sursa.',
    apple: 'Scor de somn Apple',
    other: 'Recuperare Other',
    sleep: 'Somn Other',
    noData: 'Introdu un scor de dimineață în Modul Simplu pentru a porni evoluția.',
    latest: 'Ultimul',
  },
  th: {
    eyebrow: 'สัญญาณอวตารที่คงแหล่งข้อมูล',
    title: 'แนวโน้มการนอนและการฟื้นตัว',
    subtitle: 'คะแนนการนอน Apple และ Recovery ของ Other ยังคงความหมายเดิมเมื่อเปลี่ยนแหล่งข้อมูล',
    apple: 'คะแนนการนอน Apple',
    other: 'การฟื้นตัว Other',
    sleep: 'การนอน Other',
    noData: 'กรอกคะแนนตอนเช้าในโหมดเรียบง่ายเพื่อเริ่มดูแนวโน้ม',
    latest: 'ล่าสุด',
  },
} as const

type Point = { date: string; value: number; supporting: number | null; source: RecoveryDataSource }

function pointsPath(points: Point[], valueOf: (point: Point) => number | null): string {
  if (!points.length) return ''
  return points.map((point, index) => {
    const value = valueOf(point)
    if (value == null) return ''
    const x = points.length === 1 ? 50 : (index / (points.length - 1)) * 100
    const y = 96 - Math.max(0, Math.min(100, value)) * 0.88
    const previousExists = points.slice(0, index).some((candidate) => valueOf(candidate) != null)
    return `${previousExists ? 'L' : 'M'} ${x.toFixed(2)} ${y.toFixed(2)}`
  }).filter(Boolean).join(' ')
}

export function RecoveryTrendPanel() {
  const { data } = useStore()
  const { language } = useLanguage()
  const words = COPY[language]
  const [range, setRange] = useState<30 | 90>(30)
  const history = useMemo(
    () => normalizeRecoveryHistory(data.settings?.addons?.recovery_history),
    [data.settings?.addons?.recovery_history],
  )
  const points = useMemo<Point[]>(() => history
    .slice()
    .sort((left, right) => left.date.localeCompare(right.date))
    .slice(-range)
    .map((entry) => ({
      date: entry.date,
      value: entry.source === 'apple' ? entry.sleep_score ?? 0 : entry.recovery_pct ?? 0,
      supporting: entry.source === 'other' ? entry.sleep_pct : null,
      source: entry.source,
    })), [history, range])
  const latest = points.at(-1)
  const primaryPath = pointsPath(points, (point) => point.value)
  const sleepPath = pointsPath(points, (point) => point.supporting)

  return (
    <GlassCard accent={ACCENTS.violet} className="overflow-hidden p-0">
      <div className="relative overflow-hidden bg-[radial-gradient(circle_at_90%_0%,rgba(139,92,246,.2),transparent_35%),linear-gradient(145deg,#111128,#121b32)] p-5 text-white sm:p-6">
        <div className="relative flex items-start justify-between gap-3">
          <div>
            <p className="font-mono text-[8px] font-black tracking-[.2em] text-violet-200/65 uppercase">{words.eyebrow}</p>
            <h2 className="mt-1 font-display text-xl font-black">{words.title}</h2>
            <p className="mt-1 max-w-xl text-[11px] leading-relaxed text-white/48">{words.subtitle}</p>
          </div>
          <div className="flex shrink-0 rounded-full bg-white/8 p-1">
            {([30, 90] as const).map((days) => (
              <button key={days} type="button" onClick={() => setRange(days)} className={`rounded-full px-2.5 py-1.5 font-mono text-[8px] font-black transition ${range === days ? 'bg-violet-300 text-violet-950' : 'text-white/45'}`}>
                {days}D
              </button>
            ))}
          </div>
        </div>

        {points.length ? (
          <>
            <div className="relative mt-4 overflow-hidden rounded-[1.5rem] border border-white/8 bg-white/[.045] p-3">
              <div className="absolute inset-x-3 top-[22%] border-t border-dashed border-white/8" />
              <div className="absolute inset-x-3 top-1/2 border-t border-dashed border-white/8" />
              <div className="absolute inset-x-3 top-[78%] border-t border-dashed border-white/8" />
              <svg viewBox="0 0 100 100" preserveAspectRatio="none" className="relative h-36 w-full overflow-visible" aria-label={words.title}>
                {sleepPath && <path d={sleepPath} fill="none" stroke="#67e8f9" strokeWidth="1.2" strokeDasharray="2.5 2.5" vectorEffect="non-scaling-stroke" opacity=".55" />}
                <motion.path d={primaryPath} fill="none" stroke="url(#recovery-gradient)" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" vectorEffect="non-scaling-stroke" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: .8 }} />
                <defs>
                  <linearGradient id="recovery-gradient" x1="0" x2="1">
                    <stop offset="0" stopColor="#67e8f9" />
                    <stop offset="1" stopColor="#c4b5fd" />
                  </linearGradient>
                </defs>
              </svg>
              <div className="mt-1 flex items-center justify-between font-mono text-[8px] font-bold text-white/35">
                <span>{points[0]?.date.slice(5)}</span><span>{points.at(-1)?.date.slice(5)}</span>
              </div>
            </div>
            <div className="mt-3 flex flex-wrap items-center gap-2 text-[9px] font-bold">
              <span className="rounded-full bg-white/8 px-2.5 py-1 text-violet-100">
                {words.latest}: {latest?.value ?? '·'} · {latest?.source === 'apple' ? words.apple : words.other}
              </span>
              {points.some((point) => point.supporting != null) && <span className="rounded-full bg-cyan-300/10 px-2.5 py-1 text-cyan-100">{words.sleep}</span>}
            </div>
          </>
        ) : (
          <div className="mt-4 rounded-[1.5rem] border border-dashed border-white/12 bg-white/[.035] px-4 py-8 text-center text-[11px] font-semibold text-white/44">{words.noData}</div>
        )}
      </div>
    </GlassCard>
  )
}
