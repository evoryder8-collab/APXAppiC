import { useEffect, useMemo, useState } from 'react'
import { GlassCard } from './ui'
import { ACCENTS } from '../lib/theme'
import type { RecoveryCheckin, RecoveryDataSource, Settings } from '../lib/types'
import { assessRecovery, normalizeRecoveryHistory } from '../lib/personalProtocol'
import { useLanguage } from '../lib/i18n'

interface Props {
  date: string
  settings: Settings
  onSettingsChange: (patch: Partial<Settings>) => void
}

const copy = {
  en: {
    apple: 'Apple Sleep Score',
    appleHelp: 'Sleep quality context, not an HRV measurement.',
    athlytic: 'Athlytic morning check',
    athlyticHelp: 'Recovery is readiness. Sleep supports the context.',
    sleepScore: 'Sleep Score',
    sleep: 'Sleep',
    recovery: 'Recovery',
    states: { strong: 'Ready', normal: 'Normal', low: 'Protect load', very_low: 'Recovery first' },
    guidance: {
      strong: 'Follow the planned session normally.',
      normal: 'Follow the plan and keep the prescribed repetitions in reserve.',
      low: 'Keep the priority strength work, reduce optional volume and prefer Stretch over optional conditioning.',
      very_low: 'Use reduced volume, Stretch or rest. Avoid adding extra training.',
    },
  },
  ro: {
    apple: 'Scor de somn Apple',
    appleHelp: 'Context pentru calitatea somnului, nu o măsurătoare HRV.',
    athlytic: 'Verificare Athlytic de dimineață',
    athlyticHelp: 'Recuperarea indică pregătirea. Somnul completează contextul.',
    sleepScore: 'Scor de somn',
    sleep: 'Somn',
    recovery: 'Recuperare',
    states: { strong: 'Pregătit', normal: 'Normal', low: 'Protejează efortul', very_low: 'Recuperare întâi' },
    guidance: {
      strong: 'Urmează normal sesiunea planificată.',
      normal: 'Urmează planul și păstrează repetările prescrise în rezervă.',
      low: 'Păstrează exercițiile prioritare, redu volumul opțional și alege Stretch în locul condiționării opționale.',
      very_low: 'Alege volum redus, Stretch sau odihnă. Nu adăuga antrenament suplimentar.',
    },
  },
  th: {
    apple: 'คะแนนการนอน Apple',
    appleHelp: 'ใช้เป็นบริบทคุณภาพการนอน ไม่ใช่การวัด HRV',
    athlytic: 'เช็ก Athlytic ตอนเช้า',
    athlyticHelp: 'Recovery คือความพร้อม ส่วน Sleep เป็นบริบทเสริม',
    sleepScore: 'คะแนนการนอน',
    sleep: 'การนอน',
    recovery: 'การฟื้นตัว',
    states: { strong: 'พร้อม', normal: 'ปกติ', low: 'ลดภาระ', very_low: 'ฟื้นตัวก่อน' },
    guidance: {
      strong: 'ทำเซสชันที่วางแผนไว้ตามปกติ',
      normal: 'ทำตามแผนและเหลือจำนวนครั้งสำรองตามที่กำหนด',
      low: 'คงงานเวทหลัก ลดปริมาณเสริม และเลือก Stretch แทนคาร์ดิโอเสริม',
      very_low: 'ลดปริมาณ เลือก Stretch หรือพัก และไม่เพิ่มการฝึก',
    },
  },
} as const

function percentDraft(value: number | null | undefined): string {
  return value == null ? '' : String(value)
}

function boundedPercent(value: string): number | null {
  if (value.trim() === '') return null
  const parsed = Number(value)
  if (!Number.isFinite(parsed)) return null
  return Math.max(0, Math.min(100, Math.round(parsed)))
}

function previousIsoDate(value: string): string {
  const date = new Date(`${value}T12:00:00Z`)
  date.setUTCDate(date.getUTCDate() - 1)
  return date.toISOString().slice(0, 10)
}

function consecutiveLowMornings(
  history: RecoveryCheckin[],
  date: string,
  source: RecoveryDataSource,
): number {
  const byDate = new Map(history.filter((entry) => entry.source === source && entry.date <= date).map((entry) => [entry.date, entry]))
  let cursor = date
  let count = 0
  while (count < 14) {
    const entry = byDate.get(cursor)
    if (!entry) break
    const score = source === 'apple' ? entry.sleep_score : entry.recovery_pct
    if (score == null || score > (source === 'apple' ? 60 : 33)) break
    count += 1
    cursor = previousIsoDate(cursor)
  }
  return count
}

export function RecoveryCheckinCard({ date, settings, onSettingsChange }: Props) {
  const { language } = useLanguage()
  const words = copy[language]
  const source: RecoveryDataSource = settings.addons.recovery_data_source === 'athlytic' ? 'athlytic' : 'apple'
  const history = useMemo(() => normalizeRecoveryHistory(settings.addons.recovery_history), [settings.addons.recovery_history])
  const existing = history.find((entry) => entry.date === date && entry.source === source)
  const [sleepScore, setSleepScore] = useState(() => percentDraft(existing?.sleep_score))
  const [sleep, setSleep] = useState(() => percentDraft(existing?.sleep_pct))
  const [recovery, setRecovery] = useState(() => percentDraft(existing?.recovery_pct))

  useEffect(() => {
    setSleepScore(percentDraft(existing?.sleep_score))
    setSleep(percentDraft(existing?.sleep_pct))
    setRecovery(percentDraft(existing?.recovery_pct))
  }, [date, existing?.sleep_pct, existing?.sleep_score, existing?.recovery_pct, source])

  const persist = (): void => {
    const now = new Date().toISOString()
    const next: RecoveryCheckin | null = source === 'apple'
      ? boundedPercent(sleepScore) == null
        ? null
        : {
            date, source, sleep_score: boundedPercent(sleepScore), sleep_pct: null,
            recovery_pct: null, updated_at: now,
          }
      : boundedPercent(sleep) == null || boundedPercent(recovery) == null
        ? null
        : {
            date, source, sleep_score: null, sleep_pct: boundedPercent(sleep),
            recovery_pct: boundedPercent(recovery), updated_at: now,
          }
    if (!next) return
    const nextHistory = [next, ...history.filter((entry) => !(entry.date === date && entry.source === source))]
      .sort((left, right) => right.date.localeCompare(left.date))
      .slice(0, 730)
    onSettingsChange({ addons: { ...settings.addons, recovery_history: nextHistory } })
  }

  const assessment = existing ? assessRecovery(existing, {
    consecutiveLowMornings: consecutiveLowMornings(history, date, source),
  }) : null

  const inputClass = 'w-full rounded-2xl border border-white/90 bg-white/82 px-3 py-2.5 text-center font-mono text-xl font-black text-ink outline-none shadow-sm focus:border-violet-300'
  return (
    <GlassCard accent={ACCENTS.violet} className="p-3.5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="font-display text-sm font-black text-ink">{source === 'apple' ? words.apple : words.athlytic}</p>
          <p className="mt-0.5 text-[9px] font-semibold text-ink-faint">{source === 'apple' ? words.appleHelp : words.athlyticHelp}</p>
        </div>
        {assessment && (
          <span className={`shrink-0 rounded-full px-2 py-1 font-mono text-[8px] font-black uppercase ${
            assessment.state === 'strong' ? 'bg-emerald-100 text-emerald-800'
              : assessment.state === 'normal' ? 'bg-amber-100 text-amber-800'
                : 'bg-rose-100 text-rose-700'
          }`}>{words.states[assessment.state]}</span>
        )}
      </div>
      <div className={`mt-3 grid gap-2 ${source === 'athlytic' ? 'grid-cols-2' : 'grid-cols-1'}`}>
        {source === 'apple' ? (
          <label>
            <span className="mb-1 block text-[9px] font-black text-ink-soft">{words.sleepScore}</span>
            <div className="relative">
              <input aria-label={words.sleepScore} type="number" inputMode="numeric" min="0" max="100" value={sleepScore} onChange={(event) => setSleepScore(event.target.value)} onBlur={persist} onKeyDown={(event) => event.key === 'Enter' && event.currentTarget.blur()} className={inputClass} />
              <span className="pointer-events-none absolute top-1/2 right-3 -translate-y-1/2 font-mono text-[10px] font-bold text-ink-faint">/100</span>
            </div>
          </label>
        ) : (
          <>
            <label>
              <span className="mb-1 block text-[9px] font-black text-ink-soft">{words.sleep}</span>
              <div className="relative">
                <input aria-label={words.sleep} type="number" inputMode="numeric" min="0" max="100" value={sleep} onChange={(event) => setSleep(event.target.value)} onBlur={persist} onKeyDown={(event) => event.key === 'Enter' && event.currentTarget.blur()} className={inputClass} />
                <span className="pointer-events-none absolute top-1/2 right-3 -translate-y-1/2 font-mono text-[10px] font-bold text-ink-faint">%</span>
              </div>
            </label>
            <label>
              <span className="mb-1 block text-[9px] font-black text-ink-soft">{words.recovery}</span>
              <div className="relative">
                <input aria-label={words.recovery} type="number" inputMode="numeric" min="0" max="100" value={recovery} onChange={(event) => setRecovery(event.target.value)} onBlur={persist} onKeyDown={(event) => event.key === 'Enter' && event.currentTarget.blur()} className={inputClass} />
                <span className="pointer-events-none absolute top-1/2 right-3 -translate-y-1/2 font-mono text-[10px] font-bold text-ink-faint">%</span>
              </div>
            </label>
          </>
        )}
      </div>
      {assessment && (
        <p className="mt-2.5 rounded-2xl bg-white/55 px-3 py-2 text-[10px] font-bold leading-relaxed text-ink-soft">{words.guidance[assessment.state]}</p>
      )}
    </GlassCard>
  )
}
