import { useEffect, useId, useMemo, useState } from 'react'
import { motion } from 'framer-motion'
import { ACCENTS } from '../../lib/theme'
import { GlassCard } from '../ui'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import { useStore } from '../../store/AppStore'
import { todayIso } from '../../lib/plan'
import {
  assessJointCheckin,
  buildStrengthSeries,
  checkinDue,
  type DeloadState,
  type JointRegion,
  type StrengthPoint,
} from '../../lib/strengthProgress'
import type { IntroLanguage } from '../../lib/introLanguage'
import type { JointCheckin } from '../../lib/types'

type RangeChoice = 30 | 60 | 90 | 'months'

const COPY = {
  en: {
    eyebrow: 'STRENGTH HISTORY', title: 'Progress you can actually see', subtitle: 'Every curve comes from the loads and reps logged during your workouts.',
    exercise: 'Exercise', noData: 'Your first weighted workout will create this curve automatically.', bestLoad: 'Best working load', estimated: 'Estimated strength', change: 'Range change', sessions: 'Sessions',
    months: 'Months', window: 'History window', weekly: 'WEEKLY LOAD-TOLERANCE CHECK', weeklyTitle: 'How are your joints this week?', weeklyBody: 'Rate fatigue or pain—not normal muscle soreness. One minute now can prevent a bad load decision later.',
    arms: 'Arms', armsDetail: 'shoulders · elbows · wrists', core: 'Core', coreDetail: 'lower/middle back · hips', legs: 'Legs', legsDetail: 'knees · ankles',
    save: 'Save weekly check-in', due: 'Due now', current: 'Current guidance', update: 'Update now', nextWeek: 'Recorded this week', method: 'APEX combines your trend with the actual training load. This is training guidance, not a diagnosis.',
  },
  ro: {
    eyebrow: 'ISTORICUL FORȚEI', title: 'Progres pe care chiar îl poți vedea', subtitle: 'Fiecare curbă provine din greutățile și repetările înregistrate în antrenamente.',
    exercise: 'Exercițiu', noData: 'Primul antrenament cu greutăți va crea automat această curbă.', bestLoad: 'Cea mai bună greutate de lucru', estimated: 'Forță estimată', change: 'Schimbare în interval', sessions: 'Sesiuni',
    months: 'Luni', window: 'Interval istoric', weekly: 'VERIFICARE SĂPTĂMÂNALĂ A TOLERANȚEI', weeklyTitle: 'Cum se simt articulațiile săptămâna aceasta?', weeklyBody: 'Evaluează oboseala sau durerea, nu febra musculară normală. Un minut acum poate preveni o decizie proastă de încărcare.',
    arms: 'Brațe', armsDetail: 'umeri · coate · încheieturi', core: 'Trunchi', coreDetail: 'spate inferior/mediu · șolduri', legs: 'Picioare', legsDetail: 'genunchi · glezne',
    save: 'Salvează verificarea săptămânală', due: 'De completat acum', current: 'Recomandarea actuală', update: 'Actualizează acum', nextWeek: 'Înregistrat săptămâna aceasta', method: 'APEX combină tendința ta cu încărcarea reală. Este ghidaj de antrenament, nu un diagnostic.',
  },
  th: {
    eyebrow: 'ประวัติความแข็งแรง', title: 'เห็นพัฒนาการได้จริง', subtitle: 'ทุกเส้นโค้งมาจากน้ำหนักและจำนวนครั้งที่บันทึกระหว่างการฝึก',
    exercise: 'ท่าออกกำลังกาย', noData: 'การฝึกด้วยน้ำหนักครั้งแรกจะสร้างเส้นโค้งนี้ให้อัตโนมัติ', bestLoad: 'น้ำหนักฝึกที่ดีที่สุด', estimated: 'ความแข็งแรงโดยประมาณ', change: 'การเปลี่ยนแปลงในช่วง', sessions: 'เซสชัน',
    months: 'เดือน', window: 'ช่วงประวัติ', weekly: 'ตรวจความทนต่อโหลดประจำสัปดาห์', weeklyTitle: 'สัปดาห์นี้ข้อต่อเป็นอย่างไร?', weeklyBody: 'ให้คะแนนความล้าหรือความเจ็บ ไม่ใช่อาการปวดกล้ามเนื้อปกติ ใช้เวลาเพียงหนึ่งนาทีเพื่อช่วยเลี่ยงการเพิ่มโหลดที่ไม่เหมาะสม',
    arms: 'แขน', armsDetail: 'ไหล่ · ศอก · ข้อมือ', core: 'แกนกลาง', coreDetail: 'หลังล่าง/กลาง · สะโพก', legs: 'ขา', legsDetail: 'เข่า · ข้อเท้า',
    save: 'บันทึกการตรวจประจำสัปดาห์', due: 'ถึงเวลาตรวจ', current: 'คำแนะนำปัจจุบัน', update: 'อัปเดตตอนนี้', nextWeek: 'บันทึกแล้วในสัปดาห์นี้', method: 'APEX ใช้ทั้งแนวโน้มของคุณและโหลดการฝึกจริง นี่คือคำแนะนำการฝึก ไม่ใช่การวินิจฉัยโรค',
  },
} satisfies Record<IntroLanguage, Record<string, string>>

const ASSESSMENT_COPY: Record<IntroLanguage, Record<DeloadState, { title: string; body: string }>> = {
  en: {
    clear: { title: 'Green light · train as planned', body: 'Your scores are stable. Progress only when technique, completed reps and RIR all support it.' },
    watch: { title: 'Hold the load · watch the trend', body: 'Keep 2–3 reps in reserve and remove one working set from movements that stress the flagged area this week.' },
    regional_deload: { title: 'Regional deload recommended', body: 'Avoid failure and reduce work for the affected area for 5–7 days. Unaffected areas may train if movement stays pain-free and uncompensated.' },
    whole_deload: { title: 'Whole-body deload recommended', body: 'Multiple regions are elevated. For 5–7 days, reduce working sets, avoid failure and keep every repetition comfortably controlled.' },
    stop_and_review: { title: 'Stop loading the affected area today', body: 'Do not train through a severe signal. Sudden or persistent pain, swelling, instability, numbness or weakness needs assessment by a qualified clinician.' },
  },
  ro: {
    clear: { title: 'Semnal verde · urmează planul', body: 'Scorurile sunt stabile. Crește doar când tehnica, repetările și RIR-ul susțin progresia.' },
    watch: { title: 'Păstrează greutatea · urmărește tendința', body: 'Păstrează 2–3 repetări în rezervă și elimină un set de lucru din mișcările care solicită zona semnalată în această săptămână.' },
    regional_deload: { title: 'Deload regional recomandat', body: 'Evită eșecul și redu lucrul pentru zona afectată timp de 5–7 zile. Zonele neafectate pot fi antrenate doar fără durere și fără compensări.' },
    whole_deload: { title: 'Deload pentru tot corpul recomandat', body: 'Mai multe zone sunt solicitate. Timp de 5–7 zile, redu seturile de lucru, evită eșecul și păstrează fiecare repetare confortabil controlată.' },
    stop_and_review: { title: 'Oprește astăzi încărcarea zonei afectate', body: 'Nu te antrena peste un semnal sever. Durerea bruscă sau persistentă, umflarea, instabilitatea, amorțeala ori slăbiciunea necesită evaluarea unui clinician calificat.' },
  },
  th: {
    clear: { title: 'ไฟเขียว · ฝึกตามแผน', body: 'คะแนนคงที่ เพิ่มระดับเมื่อเทคนิค จำนวนครั้ง และ RIR สนับสนุนเท่านั้น' },
    watch: { title: 'คงน้ำหนักไว้ · ดูแนวโน้ม', body: 'เหลือแรง 2–3 ครั้ง และลดหนึ่งเซตจากท่าที่กดดันบริเวณที่ถูกแจ้งเตือนในสัปดาห์นี้' },
    regional_deload: { title: 'แนะนำให้ลดโหลดเฉพาะบริเวณ', body: 'งดฝึกจนหมดแรงและลดงานของบริเวณที่มีปัญหา 5–7 วัน ส่วนอื่นฝึกได้เมื่อไม่เจ็บและไม่มีการชดเชยท่าทาง' },
    whole_deload: { title: 'แนะนำให้ลดโหลดทั้งร่างกาย', body: 'มีหลายบริเวณที่คะแนนสูง เป็นเวลา 5–7 วันให้ลดเซตทำงาน งดฝึกจนหมดแรง และควบคุมทุกครั้งอย่างสบาย' },
    stop_and_review: { title: 'หยุดลงน้ำหนักบริเวณนี้วันนี้', body: 'อย่าฝืนสัญญาณรุนแรง อาการปวดฉับพลันหรือต่อเนื่อง บวม ไม่มั่นคง ชา หรืออ่อนแรง ควรได้รับการประเมินจากผู้เชี่ยวชาญ' },
  },
}

function toTimestamp(date: string): number {
  return Date.parse(`${date}T12:00:00Z`)
}

function filteredPoints(points: StrengthPoint[], days: number): StrengthPoint[] {
  const now = Date.now()
  const threshold = now - days * 86_400_000
  return points.filter((point) => toTimestamp(point.date) >= threshold)
}

function curveGeometry(points: StrengthPoint[]) {
  const width = 640
  const height = 230
  const padX = 34
  const padY = 34
  const values = points.map((point) => point.topWeight)
  const min = Math.min(...values)
  const max = Math.max(...values)
  const spread = Math.max(2.5, max - min)
  const low = Math.max(0, min - spread * 0.24)
  const high = max + spread * 0.24
  const firstTime = toTimestamp(points[0]?.date ?? todayIso())
  const lastTime = toTimestamp(points.at(-1)?.date ?? todayIso())
  const timeSpread = Math.max(1, lastTime - firstTime)
  const coords = points.map((point, index) => ({
    x: points.length === 1 ? width / 2 : padX + ((toTimestamp(point.date) - firstTime) / timeSpread) * (width - padX * 2),
    y: height - padY - ((point.topWeight - low) / Math.max(1, high - low)) * (height - padY * 2),
    point,
    index,
  }))
  if (coords.length === 0) return { width, height, coords, line: '', area: '' }
  if (coords.length === 1) {
    const line = `M ${coords[0].x} ${coords[0].y}`
    return { width, height, coords, line, area: `${line} L ${coords[0].x} ${height - padY} Z` }
  }
  let line = `M ${coords[0].x} ${coords[0].y}`
  for (let i = 0; i < coords.length - 1; i++) {
    const p0 = coords[Math.max(0, i - 1)]
    const p1 = coords[i]
    const p2 = coords[i + 1]
    const p3 = coords[Math.min(coords.length - 1, i + 2)]
    const c1x = p1.x + (p2.x - p0.x) / 6
    const c1y = p1.y + (p2.y - p0.y) / 6
    const c2x = p2.x - (p3.x - p1.x) / 6
    const c2y = p2.y - (p3.y - p1.y) / 6
    line += ` C ${c1x} ${c1y}, ${c2x} ${c2y}, ${p2.x} ${p2.y}`
  }
  return { width, height, coords, line, area: `${line} L ${coords.at(-1)!.x} ${height - padY} L ${coords[0].x} ${height - padY} Z` }
}

function StrengthCurve({ points }: { points: StrengthPoint[] }) {
  const id = useId().replace(/:/g, '')
  const graph = curveGeometry(points)
  return (
    <svg viewBox={`0 0 ${graph.width} ${graph.height}`} className="h-auto w-full overflow-visible" role="img" aria-label="Strength progress curve">
      <defs>
        <linearGradient id={`strength-line-${id}`} x1="0" y1="0" x2="1" y2="0"><stop stopColor="#8b5cf6" /><stop offset=".48" stopColor="#22d3ee" /><stop offset="1" stopColor="#34d399" /></linearGradient>
        <linearGradient id={`strength-area-${id}`} x1="0" y1="0" x2="0" y2="1"><stop stopColor="#8b5cf6" stopOpacity=".34" /><stop offset="1" stopColor="#22d3ee" stopOpacity="0" /></linearGradient>
        <filter id={`strength-glow-${id}`} x="-30%" y="-60%" width="160%" height="220%"><feGaussianBlur stdDeviation="5" result="blur" /><feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
      </defs>
      {[0.22, 0.5, 0.78].map((ratio) => <line key={ratio} x1="28" x2={graph.width - 28} y1={graph.height * ratio} y2={graph.height * ratio} stroke="rgba(26,26,34,.075)" strokeDasharray="4 9" />)}
      {graph.area && <motion.path initial={{ opacity: 0 }} animate={{ opacity: 1 }} d={graph.area} fill={`url(#strength-area-${id})`} />}
      {graph.line && <motion.path key={graph.line} initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 1.1, ease: [0.16, 1, 0.3, 1] }} d={graph.line} fill="none" stroke={`url(#strength-line-${id})`} strokeWidth="6" strokeLinecap="round" strokeLinejoin="round" filter={`url(#strength-glow-${id})`} />}
      {graph.coords.map(({ x, y, point, index }) => <g key={`${point.sessionId}:${index}`}><circle cx={x} cy={y} r="8" fill="rgba(255,255,255,.92)" stroke={index === graph.coords.length - 1 ? '#10b981' : '#8b5cf6'} strokeWidth="4"><title>{point.date}: {point.topWeight} kg</title></circle></g>)}
      {graph.coords.length > 0 && <><text x="30" y={graph.height - 7} className="fill-ink-faint font-mono text-[12px]">{graph.coords[0].point.date.slice(5)}</text><text x={graph.width - 30} y={graph.height - 7} textAnchor="end" className="fill-ink-faint font-mono text-[12px]">{graph.coords.at(-1)!.point.date.slice(5)}</text></>}
    </svg>
  )
}

function regionLabel(region: JointRegion, language: IntroLanguage): string {
  const copy = COPY[language]
  return region === 'arms' ? copy.arms : region === 'core' ? copy.core : copy.legs
}

export function StrengthProgressPanel() {
  const { data, setSettings } = useStore()
  const { language } = useLanguage()
  const copy = COPY[language]
  const t = (value: string): string => translateInterfaceText(value, language)
  const series = useMemo(() => buildStrengthSeries(data), [data])
  const [selectedKey, setSelectedKey] = useState(series[0]?.key ?? '')
  const [range, setRange] = useState<RangeChoice>(90)
  const [months, setMonths] = useState(6)
  const checkins = data.settings?.addons.joint_checkins ?? []
  const latest = [...checkins].sort((a, b) => b.date.localeCompare(a.date))[0] ?? null
  const previous = [...checkins].sort((a, b) => b.date.localeCompare(a.date))[1] ?? null
  const due = checkinDue(checkins, todayIso())
  const [showCheckin, setShowCheckin] = useState(due)
  const [scores, setScores] = useState(() => latest
    ? { arms: latest.arms, core: latest.core, legs: latest.legs }
    : { arms: 3, core: 3, legs: 3 })

  useEffect(() => {
    if (!series.some((item) => item.key === selectedKey)) setSelectedKey(series[0]?.key ?? '')
  }, [selectedKey, series])
  useEffect(() => { if (due) setShowCheckin(true) }, [due])

  const active = series.find((item) => item.key === selectedKey) ?? series[0] ?? null
  const windowDays = range === 'months' ? months * 30 : range
  const points = active ? filteredPoints(active.points, windowDays) : []
  const visible = points.length > 0 ? points : active?.points.slice(-1) ?? []
  const start = visible[0]
  const end = visible.at(-1)
  const change = start && end ? Math.round((end.topWeight - start.topWeight) * 10) / 10 : 0
  const assessment = latest ? assessJointCheckin(latest, previous) : null

  const saveCheckin = () => {
    if (!data.settings) return
    const entry: JointCheckin = { id: crypto.randomUUID(), date: todayIso(), ...scores }
    const next = [...checkins.filter((checkin) => checkin.date !== entry.date), entry]
      .sort((a, b) => a.date.localeCompare(b.date))
      .slice(-104)
    setSettings({ addons: { ...data.settings.addons, joint_checkins: next } })
    setShowCheckin(false)
  }

  return (
    <GlassCard accent={ACCENTS.violet} className="overflow-hidden p-0">
      <div className="relative bg-[radial-gradient(circle_at_85%_0%,rgba(139,92,246,.18),transparent_32%),radial-gradient(circle_at_5%_80%,rgba(34,211,238,.14),transparent_32%)] p-5 sm:p-6">
        <p className="font-mono text-[9px] font-black tracking-[0.2em] text-violet-700 uppercase">{copy.eyebrow}</p>
        <div className="mt-1 flex flex-col justify-between gap-3 sm:flex-row sm:items-end">
          <div><h2 className="font-display text-xl font-black text-ink">{copy.title}</h2><p className="mt-1 max-w-xl text-xs leading-relaxed font-medium text-ink-soft">{copy.subtitle}</p></div>
          {series.length > 0 && <label className="shrink-0"><span className="sr-only">{copy.exercise}</span><select value={active?.key ?? ''} onChange={(event) => setSelectedKey(event.target.value)} className="max-w-full rounded-2xl border border-white/80 bg-white/75 px-3 py-2.5 text-xs font-bold text-ink shadow-sm outline-none"><option value="" disabled>{copy.exercise}</option>{series.map((item) => <option key={item.key} value={item.key}>{t(item.name)}</option>)}</select></label>}
        </div>

        {active && visible.length > 0 ? <>
          <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
            <Metric label={copy.bestLoad} value={`${Math.max(...visible.map((point) => point.topWeight))} kg`} />
            <Metric label={copy.estimated} value={`${Math.max(...visible.map((point) => point.estimated1rm)).toFixed(1)} kg`} />
            <Metric label={copy.change} value={`${change > 0 ? '+' : ''}${change} kg`} positive={change > 0} />
            <Metric label={copy.sessions} value={String(visible.length)} />
          </div>
          <div className="mt-3 rounded-[1.75rem] border border-white/85 bg-white/58 px-2 pt-4 pb-1 shadow-[inset_0_1px_0_rgba(255,255,255,.9)]"><StrengthCurve points={visible} /></div>
          <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
            <div className="flex rounded-full bg-white/65 p-1 shadow-sm">{([30, 60, 90] as const).map((days) => <button key={days} type="button" onClick={() => setRange(days)} className={`rounded-full px-3 py-1.5 font-mono text-[9px] font-black transition ${range === days ? 'bg-violet-600 text-white shadow' : 'text-ink-soft'}`}>{days}D</button>)}<button type="button" onClick={() => setRange('months')} className={`rounded-full px-3 py-1.5 font-mono text-[9px] font-black transition ${range === 'months' ? 'bg-violet-600 text-white shadow' : 'text-ink-soft'}`}>{copy.months}</button></div>
            {range === 'months' && <label className="flex min-w-[180px] flex-1 items-center gap-3 sm:max-w-xs"><span className="whitespace-nowrap font-mono text-[9px] font-black text-ink-soft">{copy.window}</span><input type="range" min="3" max="12" step="1" value={months} onChange={(event) => setMonths(Number(event.target.value))} className="min-w-0 flex-1 accent-violet-600" /><span className="w-10 rounded-full bg-white/75 px-2 py-1 text-center font-mono text-[9px] font-black text-violet-700">{months}M</span></label>}
          </div>
        </> : <div className="mt-4 rounded-[1.75rem] border border-dashed border-violet-200 bg-white/55 px-5 py-9 text-center"><p className="text-sm font-bold text-ink">{copy.noData}</p><p className="mt-1 text-[11px] text-ink-soft">{copy.subtitle}</p></div>}

        <div className="mt-5 rounded-[1.75rem] border border-white/85 bg-[#08111d] p-4 text-white shadow-[0_24px_50px_-32px_rgba(76,29,149,.9)] sm:p-5">
          <div className="flex items-start justify-between gap-3"><div><p className="font-mono text-[8px] font-black tracking-[0.18em] text-cyan-200/70 uppercase">{copy.weekly}</p><h3 className="mt-1 font-display text-base font-black">{copy.weeklyTitle}</h3><p className="mt-1 max-w-xl text-[11px] leading-relaxed text-white/55">{copy.weeklyBody}</p></div><span className={`shrink-0 rounded-full px-2.5 py-1 font-mono text-[8px] font-black ${due ? 'bg-amber-300 text-amber-950' : 'bg-emerald-300/15 text-emerald-200'}`}>{due ? copy.due : copy.nextWeek}</span></div>

          {showCheckin ? <div className="mt-4 space-y-3">{(['arms', 'core', 'legs'] as const).map((region) => <label key={region} className="grid grid-cols-[minmax(0,1fr)_2.7rem] items-center gap-x-3 rounded-2xl bg-white/[.065] px-3.5 py-3"><span><span className="block text-xs font-black">{copy[region]}</span><span className="block text-[9px] text-white/42">{copy[`${region}Detail` as keyof typeof copy]}</span></span><span className="row-span-2 grid h-9 w-9 place-items-center rounded-full font-mono text-sm font-black" style={{ background: scores[region] >= 7 ? '#fb7185' : scores[region] >= 5 ? '#fbbf24' : '#34d399', color: '#061019', boxShadow: `0 0 18px ${scores[region] >= 7 ? 'rgba(251,113,133,.35)' : scores[region] >= 5 ? 'rgba(251,191,36,.3)' : 'rgba(52,211,153,.28)'}` }}>{scores[region]}</span><input aria-label={`${copy[region]} 1 to 10`} type="range" min="1" max="10" step="1" value={scores[region]} onChange={(event) => setScores((current) => ({ ...current, [region]: Number(event.target.value) }))} className="mt-2 w-full accent-cyan-300" /></label>)}<button type="button" onClick={saveCheckin} className="w-full rounded-2xl bg-gradient-to-r from-violet-500 via-cyan-400 to-emerald-400 px-4 py-3.5 text-sm font-black text-[#061019] shadow-[0_14px_32px_-18px_rgba(34,211,238,.8)]">{copy.save}</button></div> : assessment && <div className="mt-4 rounded-2xl border border-white/8 bg-white/[.055] p-3.5"><div className="flex items-start justify-between gap-3"><div><p className="font-mono text-[8px] font-black tracking-widest text-white/40 uppercase">{copy.current}</p><p className="mt-1 text-sm font-black" style={{ color: assessment.state === 'clear' ? '#6ee7b7' : assessment.state === 'watch' ? '#fde68a' : '#fda4af' }}>{ASSESSMENT_COPY[language][assessment.state].title}</p></div><button type="button" onClick={() => { if (latest) setScores({ arms: latest.arms, core: latest.core, legs: latest.legs }); setShowCheckin(true) }} className="shrink-0 rounded-full bg-white/10 px-3 py-1.5 text-[9px] font-black text-white/70">{copy.update}</button></div><p className="mt-2 text-[11px] leading-relaxed text-white/58">{ASSESSMENT_COPY[language][assessment.state].body}</p>{assessment.affected.length > 0 && <p className="mt-2 font-mono text-[9px] font-bold text-cyan-100/70">{assessment.affected.map((region) => regionLabel(region, language)).join(' · ')}</p>}</div>}
          <p className="mt-3 text-[9px] leading-relaxed text-white/32">{copy.method}</p>
        </div>
      </div>
    </GlassCard>
  )
}

function Metric({ label, value, positive = false }: { label: string; value: string; positive?: boolean }) {
  return <div className="rounded-2xl border border-white/85 bg-white/68 px-3 py-3 shadow-sm"><p className="text-[9px] leading-tight font-bold text-ink-faint">{label}</p><p className={`mt-1 font-mono text-base font-black ${positive ? 'text-emerald-700' : 'text-ink'}`}>{value}</p></div>
}
