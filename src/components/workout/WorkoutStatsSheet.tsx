import { useEffect, useMemo, useState } from 'react'
import { ACCENTS, type Accent } from '../../lib/theme'
import type { IntroLanguage } from '../../lib/introLanguage'
import type { WorkoutLog } from '../../lib/types'
import { distinctInsightTexts, sessionStrengthInsights, type SessionStrengthInsight } from '../../lib/strengthProgress'
import { useStore } from '../../store/AppStore'
import { AccentChip, Sheet } from '../ui'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import { isFocusT25Name } from '../../lib/focusT25'
import { workoutLogsInPerformedOrder } from '../../lib/workoutLogOrder'
import {
  descriptorForExercise,
  isValidExerciseFacts,
  loadedStrengthVolume,
  normalizeExerciseFacts,
  workoutLogFactSummary,
} from '../../lib/exerciseLogging'
import type { SetEntry } from '../../lib/workoutSession'
import { ExerciseFactFields } from './ExerciseFactFields'
import { progressForWorkoutLog, type ExerciseProgress } from '../../lib/progression'

const COPY = {
  en: { eyebrow: 'WORKOUT RECEIPT', title: 'Stats at a glance', subtitle: 'Every strength set is editable. Secondary sessions keep their own completion details.', volume: 'Loaded volume', sets: 'Working sets', movements: 'Movements', signal: 'APEX strength signal', first: 'First clean baseline recorded. This becomes the comparison point for your next session.', saved: 'Corrections save automatically', close: 'Done', weight: 'Weight', reps: 'Reps', rir: 'RIR', secondary: 'Secondary session', full: 'Full version', modifier: 'Used modifier', incomplete: 'Not completed' },
  ro: { eyebrow: 'REZUMATUL ANTRENAMENTULUI', title: 'Statistici dintr-o privire', subtitle: 'Fiecare set de forță poate fi corectat. Sesiunile secundare păstrează detaliile lor proprii.', volume: 'Volum încărcat', sets: 'Seturi de lucru', movements: 'Mișcări', signal: 'Semnalul de forță APEX', first: 'Primul reper curat a fost înregistrat. Acesta devine comparația pentru următoarea sesiune.', saved: 'Corecțiile se salvează automat', close: 'Gata', weight: 'Greutate', reps: 'Repetări', rir: 'RIR', secondary: 'Sesiune secundară', full: 'Versiunea completă', modifier: 'Cu modificator', incomplete: 'Neefectuat' },
  th: { eyebrow: 'ใบสรุปการฝึก', title: 'สถิติโดยสรุป', subtitle: 'แก้ไขได้ทุกเซตเวท ส่วนเซสชันเสริมจะเก็บรายละเอียดการทำของตัวเอง', volume: 'ปริมาณน้ำหนักรวม', sets: 'เซตทำงาน', movements: 'ท่า', signal: 'สัญญาณความแข็งแรง APEX', first: 'บันทึกค่าฐานครั้งแรกแล้ว ค่านี้จะใช้เทียบกับการฝึกครั้งถัดไป', saved: 'บันทึกการแก้ไขอัตโนมัติ', close: 'เสร็จ', weight: 'น้ำหนัก', reps: 'ครั้ง', rir: 'RIR', secondary: 'เซสชันเสริม', full: 'เวอร์ชันเต็ม', modifier: 'ใช้ท่าปรับง่าย', incomplete: 'ไม่ได้ทำ' },
} satisfies Record<IntroLanguage, Record<string, string>>

function entryFromLog(log: WorkoutLog): SetEntry {
  return {
    weight: log.weight_kg,
    reps: log.reps,
    rir: log.rir,
    durationSeconds: log.duration_seconds,
    distanceMeters: log.distance_meters,
    contacts: log.contacts,
    rounds: log.rounds,
    workSeconds: log.work_seconds,
    recoverySeconds: log.recovery_seconds,
  }
}

function logPatchFromEntry(patch: Partial<SetEntry>): Partial<WorkoutLog> {
  const result: Partial<WorkoutLog> = {}
  if ('weight' in patch) result.weight_kg = patch.weight ?? null
  if ('reps' in patch) result.reps = patch.reps ?? null
  if ('rir' in patch) result.rir = patch.rir ?? null
  if ('durationSeconds' in patch) result.duration_seconds = patch.durationSeconds ?? null
  if ('distanceMeters' in patch) result.distance_meters = patch.distanceMeters ?? null
  if ('contacts' in patch) result.contacts = patch.contacts ?? null
  if ('rounds' in patch) result.rounds = patch.rounds ?? null
  if ('workSeconds' in patch) result.work_seconds = patch.workSeconds ?? null
  if ('recoverySeconds' in patch) result.recovery_seconds = patch.recoverySeconds ?? null
  return result
}

function progressLabel(progress: ExerciseProgress): string {
  switch (progress) {
    case 'improved': return 'Improved from last time'
    case 'maintained': return 'Matched last time'
    case 'regressed': return 'Below last time'
    case 'adherence': return 'Completed'
    case 'incomparable': return 'Needs matching facts to compare'
  }
}

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
  const sourceLogs = useMemo(
    () => sessionId ? workoutLogsInPerformedOrder(data, sessionId) : [],
    [data.exercises, data.workout_logs, data.workout_sessions, sessionId],
  )
  const [logs, setLogs] = useState<WorkoutLog[]>(sourceLogs)

  useEffect(() => { if (open) setLogs(sourceLogs) }, [open, sourceLogs])

  const groups = useMemo(() => {
    const map = new Map<string, WorkoutLog[]>()
    for (const log of logs) map.set(log.exercise_name, [...(map.get(log.exercise_name) ?? []), log])
    return [...map.entries()]
  }, [logs])
  const insights = sessionId ? sessionStrengthInsights(data, sessionId) : []
  const insightLines = distinctInsightTexts(insights.map((insight) => insightText(insight, language)))
  const workingLogs = logs.filter((log) => !isFocusT25Name(log.exercise_name))
  const volume = loadedStrengthVolume(workingLogs)
  const workingSets = workingLogs.filter((log) => !log.skipped).length

  const persistPatch = (id: string, patch: Partial<WorkoutLog>) => {
    const current = logs.find((candidate) => candidate.id === id)
    if (!current) return
    const candidate = { ...current, ...patch }
    setLogs((rows) => rows.map((row) => row.id === id ? candidate : row))
    const descriptor = descriptorForExercise({ name: candidate.exercise_name, movement_id: candidate.movement_id })
    const entry = entryFromLog(candidate)
    if (!candidate.skipped && !isValidExerciseFacts(entry, descriptor)) return
    const facts = normalizeExerciseFacts(entry, descriptor, candidate.skipped)
    const next = { ...candidate, ...logPatchFromEntry(facts) }
    setLogs((rows) => rows.map((row) => row.id === id ? next : row))
    upsert('workout_logs', next)
  }

  return (
    <Sheet open={open} onClose={onClose} wide>
      <div className="flex items-start justify-between gap-3"><div><p className="font-mono text-[9px] font-black tracking-[0.18em] uppercase" style={{ color: accent.deep }}>{copy.eyebrow}</p><h2 className="mt-1 font-display text-2xl font-black text-ink">{copy.title}</h2><p className="mt-1 max-w-xl text-xs leading-relaxed font-medium text-ink-soft">{copy.subtitle}</p></div><button type="button" onClick={onClose} className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-ink/6 text-lg font-black text-ink-soft" aria-label={copy.close}>×</button></div>

      <div className="mt-4 grid grid-cols-3 gap-2"><Metric label={copy.volume} value={`${Math.round(volume).toLocaleString()} kg`} /><Metric label={copy.sets} value={String(workingSets)} /><Metric label={copy.movements} value={String(groups.length)} /></div>

      {insightLines.length > 0 && <div className="mt-4 rounded-[1.6rem] bg-[#08111d] p-4 text-white shadow-[0_22px_45px_-30px_rgba(139,92,246,.9)]"><div className="flex items-center gap-2"><span className="h-2 w-2 rounded-full bg-emerald-300 shadow-[0_0_14px_rgba(110,231,183,.8)]" /><p className="font-mono text-[8px] font-black tracking-[0.16em] text-cyan-100/65 uppercase">{copy.signal}</p></div><div className="mt-3 space-y-2">{insightLines.map((text) => <p key={text} className="text-[11px] leading-relaxed font-semibold text-white/72">{text}</p>)}</div></div>}

      <div className="mt-4 space-y-3">{groups.map(([name, exerciseLogs]) => {
        const focusT25 = isFocusT25Name(name)
        const focusLog = exerciseLogs[0]
        return (
          <section key={name} className="rounded-[1.5rem] border border-white/80 bg-white/55 p-3 shadow-sm">
            <div className="flex items-center justify-between gap-2">
              <h3 className="min-w-0 truncate text-sm font-black text-ink">{t(name)}</h3>
              <AccentChip accent={focusT25 ? ACCENTS.teal : ACCENTS.violet}>{focusT25 ? copy.secondary : `${exerciseLogs.length} ${t('sets')}`}</AccentChip>
            </div>
            {focusT25 && focusLog ? (
              <div className="mt-3 grid gap-2 sm:grid-cols-3">
                {([
                  { label: copy.full, skipped: false, modifier: false },
                  { label: copy.modifier, skipped: false, modifier: true },
                  { label: copy.incomplete, skipped: true, modifier: false },
                ] as const).map((option) => {
                  const active = focusLog.skipped === option.skipped && (option.skipped || focusLog.override_flag === option.modifier)
                  return (
                    <button
                      key={option.label}
                      type="button"
                      aria-pressed={active}
                      onClick={() => persistPatch(focusLog.id, {
                        skipped: option.skipped,
                        override_flag: option.modifier,
                        weight_kg: null,
                        reps: option.skipped ? null : 1,
                        rir: null,
                      })}
                      className={`rounded-xl border px-3 py-2.5 text-[10px] font-black transition ${active ? 'border-teal-300 bg-teal-50 text-teal-800 shadow-sm' : 'border-white/80 bg-white/65 text-ink-soft'}`}
                    >
                      {active ? '✓ ' : ''}{option.label}
                    </button>
                  )
                })}
              </div>
            ) : (
              <div className="mt-2 space-y-2">{exerciseLogs.map((log) => {
                const pace = workoutLogFactSummary(log).find((fact) => fact.includes('/km'))
                const progress = progressForWorkoutLog(data, log)
                return <div key={log.id} className="grid grid-cols-[2.7rem_minmax(0,1fr)] items-start gap-1.5 rounded-xl bg-white/70 p-2">
                  <span className="pt-7 text-center font-mono text-[9px] font-black text-ink-faint">S{log.set_no}</span>
                  <div>
                    <ExerciseFactFields
                      descriptor={descriptorForExercise({ name: log.exercise_name, movement_id: log.movement_id })}
                      value={entryFromLog(log)}
                      disabled={log.skipped}
                      onChange={(patch) => persistPatch(log.id, logPatchFromEntry(patch))}
                    />
                    {(pace || progress) && <p className="mt-1 text-right font-mono text-[9px] font-black text-cyan-800">
                      {[pace, progress ? t(progressLabel(progress)) : null].filter(Boolean).join(' · ')}
                    </p>}
                  </div>
                </div>
              })}</div>
            )}
          </section>
        )
      })}</div>
      <div className="mt-4 flex items-center justify-between gap-3"><p className="text-[10px] font-semibold text-emerald-700">✓ {copy.saved}</p><button type="button" onClick={onClose} className="rounded-2xl px-5 py-3 text-sm font-black text-white" style={{ background: accent.gradient }}>{copy.close}</button></div>
    </Sheet>
  )
}

function Metric({ label, value }: { label: string; value: string }) {
  return <div className="rounded-2xl border border-white/80 bg-white/65 px-2 py-3 text-center"><p className="text-[8px] leading-tight font-bold text-ink-faint">{label}</p><p className="mt-1 font-mono text-sm font-black text-ink">{value}</p></div>
}
