import { useEffect, useMemo, useState } from 'react'
import { ACCENTS, type Accent } from '../../lib/theme'
import type { IntroLanguage } from '../../lib/introLanguage'
import type { WorkoutLog } from '../../lib/types'
import { sessionStrengthInsights, type SessionStrengthInsight } from '../../lib/strengthProgress'
import { useStore } from '../../store/AppStore'
import { AccentChip, Sheet } from '../ui'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'

const COPY = {
  en: { eyebrow: 'WORKOUT RECEIPT', title: 'Stats at a glance', subtitle: 'Every set is editable. Corrections update your private strength history immediately.', volume: 'Loaded volume', sets: 'Working sets', movements: 'Movements', signal: 'APEX strength signal', first: 'First clean baseline recorded. This becomes the comparison point for your next session.', saved: 'Corrections save automatically', close: 'Done', weight: 'Weight', reps: 'Reps', rir: 'RIR' },
  ro: { eyebrow: 'REZUMATUL ANTRENAMENTULUI', title: 'Statistici dintr-o privire', subtitle: 'Fiecare set poate fi corectat. Modificările actualizează imediat istoricul privat de forță.', volume: 'Volum încărcat', sets: 'Seturi de lucru', movements: 'Mișcări', signal: 'Semnalul de forță APEX', first: 'Primul reper curat a fost înregistrat. Acesta devine comparația pentru următoarea sesiune.', saved: 'Corecțiile se salvează automat', close: 'Gata', weight: 'Greutate', reps: 'Repetări', rir: 'RIR' },
  th: { eyebrow: 'ใบสรุปการฝึก', title: 'สถิติโดยสรุป', subtitle: 'แก้ไขได้ทุกเซต การแก้ไขจะอัปเดตประวัติความแข็งแรงส่วนตัวทันที', volume: 'ปริมาณน้ำหนักรวม', sets: 'เซตทำงาน', movements: 'ท่า', signal: 'สัญญาณความแข็งแรง APEX', first: 'บันทึกค่าฐานครั้งแรกแล้ว ค่านี้จะใช้เทียบกับการฝึกครั้งถัดไป', saved: 'บันทึกการแก้ไขอัตโนมัติ', close: 'เสร็จ', weight: 'น้ำหนัก', reps: 'ครั้ง', rir: 'RIR' },
} satisfies Record<IntroLanguage, Record<string, string>>

function insightText(insight: SessionStrengthInsight, language: IntroLanguage): string {
  if (insight.reference == null || insight.loadDelta == null || insight.daysCompared == null) return COPY[language].first
  const delta = Math.abs(insight.loadDelta)
  const e1rm = Math.abs(insight.estimated1rmDelta ?? 0)
  if (language === 'ro') {
    if (insight.loadDelta > 0) return `Ai crescut greutatea de lucru pentru ${insight.name} cu ${delta} kg în ${insight.daysCompared} zile. Forța estimată a urcat cu ${e1rm.toFixed(1)} kg.`
    if (insight.loadDelta < 0) return `${insight.name} a fost cu ${delta} kg sub reperul de acum ${insight.daysCompared} zile. Contextul de deload, repetările și RIR-ul contează înainte de următoarea creștere.`
    return `${insight.name} a rămas stabil timp de ${insight.daysCompared} zile. Următoarea creștere se câștigă prin repetări curate și RIR controlat.`
  }
  if (language === 'th') {
    if (insight.loadDelta > 0) return `น้ำหนักฝึก ${insight.name} เพิ่มขึ้น ${delta} กก. ใน ${insight.daysCompared} วัน ความแข็งแรงโดยประมาณเพิ่ม ${e1rm.toFixed(1)} กก.`
    if (insight.loadDelta < 0) return `${insight.name} ต่ำกว่าค่าอ้างอิงเมื่อ ${insight.daysCompared} วันก่อน ${delta} กก. ควรดูช่วงลดโหลด จำนวนครั้ง และ RIR ก่อนเพิ่มครั้งถัดไป`
    return `${insight.name} คงที่ตลอด ${insight.daysCompared} วัน เพิ่มระดับเมื่อทำซ้ำได้คมชัดและควบคุม RIR ได้`
  }
  if (insight.loadDelta > 0) return `You increased ${insight.name} by ${delta} kg across ${insight.daysCompared} days. Estimated strength rose ${e1rm.toFixed(1)} kg.`
  if (insight.loadDelta < 0) return `${insight.name} was ${delta} kg below the ${insight.daysCompared}-day reference. Deload context, reps and RIR matter before the next increase.`
  return `${insight.name} held steady across ${insight.daysCompared} days. The next increase is earned through clean reps and controlled RIR.`
}

export function WorkoutStatsSheet({ open, onClose, sessionId, accent }: { open: boolean; onClose: () => void; sessionId: string | null; accent: Accent }) {
  const { data, upsert } = useStore()
  const { language } = useLanguage()
  const copy = COPY[language]
  const t = (value: string): string => translateInterfaceText(value, language)
  const sourceLogs = useMemo(() => data.workout_logs.filter((log) => log.session_id === sessionId).sort((a, b) => a.exercise_name.localeCompare(b.exercise_name) || a.set_no - b.set_no), [data.workout_logs, sessionId])
  const [logs, setLogs] = useState<WorkoutLog[]>(sourceLogs)

  useEffect(() => { if (open) setLogs(sourceLogs) }, [open, sourceLogs])

  const groups = useMemo(() => {
    const map = new Map<string, WorkoutLog[]>()
    for (const log of logs) map.set(log.exercise_name, [...(map.get(log.exercise_name) ?? []), log])
    return [...map.entries()]
  }, [logs])
  const insights = sessionId ? sessionStrengthInsights(data, sessionId) : []
  const volume = logs.reduce((sum, log) => sum + (log.skipped ? 0 : (log.weight_kg ?? 0) * (log.reps ?? 0)), 0)
  const workingSets = logs.filter((log) => !log.skipped).length

  const change = (id: string, patch: Partial<WorkoutLog>) => setLogs((current) => current.map((log) => log.id === id ? { ...log, ...patch } : log))
  const commit = (id: string) => {
    const log = logs.find((candidate) => candidate.id === id)
    if (log) upsert('workout_logs', log)
  }

  return (
    <Sheet open={open} onClose={onClose} wide>
      <div className="flex items-start justify-between gap-3"><div><p className="font-mono text-[9px] font-black tracking-[0.18em] uppercase" style={{ color: accent.deep }}>{copy.eyebrow}</p><h2 className="mt-1 font-display text-2xl font-black text-ink">{copy.title}</h2><p className="mt-1 max-w-xl text-xs leading-relaxed font-medium text-ink-soft">{copy.subtitle}</p></div><button type="button" onClick={onClose} className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-ink/6 text-lg font-black text-ink-soft" aria-label={copy.close}>×</button></div>

      <div className="mt-4 grid grid-cols-3 gap-2"><Metric label={copy.volume} value={`${Math.round(volume).toLocaleString()} kg`} /><Metric label={copy.sets} value={String(workingSets)} /><Metric label={copy.movements} value={String(groups.length)} /></div>

      {insights.length > 0 && <div className="mt-4 rounded-[1.6rem] bg-[#08111d] p-4 text-white shadow-[0_22px_45px_-30px_rgba(139,92,246,.9)]"><div className="flex items-center gap-2"><span className="h-2 w-2 rounded-full bg-emerald-300 shadow-[0_0_14px_rgba(110,231,183,.8)]" /><p className="font-mono text-[8px] font-black tracking-[0.16em] text-cyan-100/65 uppercase">{copy.signal}</p></div><div className="mt-3 space-y-2">{insights.slice(0, 3).map((insight) => <p key={insight.key} className="text-[11px] leading-relaxed font-semibold text-white/72">{insightText(insight, language)}</p>)}</div></div>}

      <div className="mt-4 space-y-3">{groups.map(([name, exerciseLogs]) => <section key={name} className="rounded-[1.5rem] border border-white/80 bg-white/55 p-3 shadow-sm"><div className="flex items-center justify-between gap-2"><h3 className="min-w-0 truncate text-sm font-black text-ink">{t(name)}</h3><AccentChip accent={ACCENTS.violet}>{exerciseLogs.length} {t('sets')}</AccentChip></div><div className="mt-2 space-y-2">{exerciseLogs.map((log) => <div key={log.id} className="grid grid-cols-[2.7rem_repeat(3,minmax(0,1fr))] items-end gap-1.5 rounded-xl bg-white/70 p-2"><span className="pb-2 text-center font-mono text-[9px] font-black text-ink-faint">S{log.set_no}</span><EditableNumber label={copy.weight} suffix="kg" value={log.weight_kg} step="0.5" onChange={(value) => change(log.id, { weight_kg: value })} onCommit={() => commit(log.id)} /><EditableNumber label={copy.reps} value={log.reps} step="1" onChange={(value) => change(log.id, { reps: value == null ? null : Math.round(value) })} onCommit={() => commit(log.id)} /><EditableNumber label={copy.rir} value={log.rir} step="1" max="10" onChange={(value) => change(log.id, { rir: value == null ? null : Math.round(value) })} onCommit={() => commit(log.id)} /></div>)}</div></section>)}</div>
      <div className="mt-4 flex items-center justify-between gap-3"><p className="text-[10px] font-semibold text-emerald-700">✓ {copy.saved}</p><button type="button" onClick={onClose} className="rounded-2xl px-5 py-3 text-sm font-black text-white" style={{ background: accent.gradient }}>{copy.close}</button></div>
    </Sheet>
  )
}

function Metric({ label, value }: { label: string; value: string }) {
  return <div className="rounded-2xl border border-white/80 bg-white/65 px-2 py-3 text-center"><p className="text-[8px] leading-tight font-bold text-ink-faint">{label}</p><p className="mt-1 font-mono text-sm font-black text-ink">{value}</p></div>
}

function EditableNumber({ label, suffix, value, step, max, onChange, onCommit }: { label: string; suffix?: string; value: number | null; step: string; max?: string; onChange: (value: number | null) => void; onCommit: () => void }) {
  return <label className="min-w-0"><span className="block truncate text-[7px] font-black tracking-wide text-ink-faint uppercase">{label}</span><span className="relative mt-1 block"><input type="number" inputMode="decimal" min="0" max={max} step={step} value={value ?? ''} onChange={(event) => onChange(event.target.value === '' ? null : Number(event.target.value))} onBlur={onCommit} onKeyDown={(event) => { if (event.key === 'Enter') event.currentTarget.blur() }} className={`w-full rounded-lg border border-ink/6 bg-white px-1.5 py-2 text-center font-mono text-xs font-black text-ink outline-none focus:ring-2 focus:ring-violet-300 ${suffix ? 'pr-5' : ''}`} />{suffix && <span className="pointer-events-none absolute inset-y-0 right-1 flex items-center text-[6px] font-black text-ink-faint">{suffix}</span>}</span></label>
}
