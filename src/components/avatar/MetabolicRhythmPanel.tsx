import { useMemo, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import type { IntroLanguage } from '../../lib/introLanguage'
import { analyzeMealTiming, timeZoneFromSettings, zonedClock } from '../../lib/mealTiming'
import { ACCENTS } from '../../lib/theme'
import { useLanguage } from '../../lib/i18n'
import { useStore } from '../../store/AppStore'
import { useFoodStore } from '../../store/FoodStore'
import { GlassCard } from '../ui'
import { averageClosedMealRhythm, normalizeMealRhythmHistory } from '../../lib/mealRhythm'

const COPY = {
  en: {
    eyebrow: 'AVATAR INPUT SIGNAL',
    title: 'Metabolic rhythm',
    subtitle: 'APEX now reads meal completion, consistency and the real gap before training.',
    rhythm: 'Rhythm score',
    infoLabel: 'Explain rhythm score',
    infoTitle: 'What does this score mean?',
    infoBody: 'This is a 0–100 consistency score, not a metabolism-speed or health grade. It mainly reflects how many scheduled meals were logged and how closely meal-finished times matched your plan. While history is building, repeatability of recorded finish times supplies the signal.',
    infoScale: 'Higher means more consistent: 0–39 flexible, 40–69 developing, 70–84 steady, 85–100 highly repeatable.',
    close: 'Close',
    variation: 'Typical variation',
    context: 'Timed workouts',
    comfortable: 'Comfort-window starts',
    average: 'Average meal-to-training gap',
    recovery: 'Post-workout timing',
    recoveryAverage: 'Average workout-to-food gap',
    exactStarts: 'Recovery meal finishes',
    meals: 'recorded meals',
    meal: 'recorded meal',
    closedDays: 'Closed days',
    completeDays: 'Complete meal days',
    dayUnit: 'D',
    minutes: 'min',
    noData: 'Record finish times across several meals and start a workout. Your rhythm signal will build without guessing.',
    strong: 'Your meal rhythm is highly repeatable.',
    steady: 'Your meal rhythm is becoming predictable.',
    flexible: 'Your timing is flexible. More recorded finish times will sharpen the signal.',
    note: 'This signal informs Avatar explanations and AI exports. It does not diagnose digestion or decide whether exercise is medically safe.',
  },
  ro: {
    eyebrow: 'SEMNAL PENTRU AVATAR',
    title: 'Ritm metabolic',
    subtitle: 'APEX citește acum ora încheierii meselor, consecvența și intervalul real până la antrenament.',
    rhythm: 'Scor de ritm',
    infoLabel: 'Explică scorul de ritm',
    infoTitle: 'Ce înseamnă acest scor?',
    infoBody: 'Este un scor de consecvență de la 0 la 100, nu o evaluare a vitezei metabolismului sau a sănătății. Reflectă în principal câte mese programate au fost înregistrate și cât de apropiate au fost orele de final față de plan. Cât timp istoricul este în formare, semnalul folosește repetabilitatea orelor de final înregistrate.',
    infoScale: 'Un scor mai mare înseamnă mai multă consecvență: 0–39 flexibil, 40–69 în dezvoltare, 70–84 constant, 85–100 foarte repetabil.',
    close: 'Închide',
    variation: 'Variație tipică',
    context: 'Antrenamente corelate',
    comfortable: 'Porniri în fereastra confortabilă',
    average: 'Interval mediu masă-antrenament',
    recovery: 'Timing după antrenament',
    recoveryAverage: 'Interval mediu antrenament-masă',
    exactStarts: 'Finaluri ale meselor de recuperare',
    meals: 'mese înregistrate',
    meal: 'masă înregistrată',
    closedDays: 'Zile încheiate',
    completeDays: 'Zile cu toate mesele',
    dayUnit: 'Z',
    minutes: 'min',
    noData: 'Înregistrează ora de final pentru mai multe mese și pornește un antrenament. Semnalul se va construi fără presupuneri.',
    strong: 'Ritmul meselor tale este foarte constant.',
    steady: 'Ritmul meselor tale devine previzibil.',
    flexible: 'Orele sunt flexibile. Mai multe înregistrări vor rafina semnalul.',
    note: 'Semnalul intră în explicațiile Avatarului și în exporturile AI. Nu diagnostichează digestia și nu stabilește siguranța medicală a efortului.',
  },
  th: {
    eyebrow: 'สัญญาณสำหรับอวตาร',
    title: 'จังหวะเมตาบอลิซึม',
    subtitle: 'APEX อ่านเวลาที่กินเสร็จ ความสม่ำเสมอ และช่วงเวลาจริงก่อนเริ่มฝึก',
    rhythm: 'คะแนนจังหวะ',
    infoLabel: 'อธิบายคะแนนจังหวะ',
    infoTitle: 'คะแนนนี้หมายถึงอะไร',
    infoBody: 'นี่คือคะแนนความสม่ำเสมอ 0–100 ไม่ใช่คะแนนความเร็วการเผาผลาญหรือสุขภาพ โดยดูเป็นหลักว่าบันทึกมื้อตามแผนครบเพียงใด และเวลากินเสร็จใกล้กับเวลาที่ตั้งไว้แค่ไหน ระหว่างที่ข้อมูลยังสะสม ระบบจะใช้ความสม่ำเสมอของเวลากินเสร็จที่บันทึกไว้',
    infoScale: 'คะแนนสูงหมายถึงสม่ำเสมอกว่า: 0–39 ยืดหยุ่น, 40–69 กำลังพัฒนา, 70–84 สม่ำเสมอ, 85–100 สม่ำเสมอมาก',
    close: 'ปิด',
    variation: 'ความคลาดเคลื่อนโดยทั่วไป',
    context: 'การฝึกที่มีข้อมูลเวลา',
    comfortable: 'เริ่มฝึกในช่วงที่สบายขึ้น',
    average: 'ช่วงเฉลี่ยจากมื้ออาหารถึงการฝึก',
    recovery: 'เวลาหลังฝึก',
    recoveryAverage: 'ช่วงเฉลี่ยจากฝึกถึงกิน',
    exactStarts: 'เวลากินมื้อฟื้นตัวเสร็จ',
    meals: 'มื้อที่บันทึกเวลา',
    meal: 'มื้อที่บันทึกเวลา',
    closedDays: 'วันที่ปิดแล้ว',
    completeDays: 'วันที่บันทึกมื้อครบ',
    dayUnit: 'วัน',
    minutes: 'นาที',
    noData: 'บันทึกเวลาที่กินเสร็จหลายมื้อและเริ่มการฝึก ระบบจะสร้างสัญญาณจากข้อมูลจริง',
    strong: 'จังหวะมื้ออาหารของคุณสม่ำเสมอมาก',
    steady: 'จังหวะมื้ออาหารของคุณเริ่มคาดการณ์ได้',
    flexible: 'เวลาอาหารยังยืดหยุ่น บันทึกเพิ่มเพื่อให้สัญญาณแม่นยำขึ้น',
    note: 'สัญญาณนี้ใช้ในคำอธิบายของอวตารและไฟล์ส่งออก AI ไม่ใช่การวินิจฉัยการย่อยอาหารหรือการรับรองความปลอดภัยทางการแพทย์',
  },
} satisfies Record<IntroLanguage, Record<string, string>>

function cutoffDate(days: number, timeZone: string): string {
  const [year, month, day] = zonedClock(new Date(), timeZone).date.split('-').map(Number)
  return new Date(Date.UTC(year, month - 1, day - (days - 1))).toISOString().slice(0, 10)
}

export function MetabolicRhythmPanel() {
  const { data } = useStore()
  const food = useFoodStore()
  const { language } = useLanguage()
  const copy = COPY[language]
  const [range, setRange] = useState<30 | 90>(30)
  const [showScoreInfo, setShowScoreInfo] = useState(false)
  const timeZone = timeZoneFromSettings(data.settings)
  const cutoff = cutoffDate(range, timeZone)
  const meals = useMemo(() => food.meals.filter((meal) => meal.local_date >= cutoff), [cutoff, food.meals])
  const mealIds = useMemo(() => new Set(meals.map((meal) => meal.id)), [meals])
  const entries = useMemo(() => food.entries.filter((entry) => mealIds.has(entry.meal_id)), [food.entries, mealIds])
  const sessions = useMemo(() => data.workout_sessions.filter((session) => session.date >= cutoff && session.started_at), [cutoff, data.workout_sessions])
  const analysis = useMemo(() => analyzeMealTiming({
    meals,
    entries,
    sessions,
    timeZone,
  }), [entries, meals, sessions, timeZone])
  const historyDays = useMemo(
    () => Object.values(normalizeMealRhythmHistory(data.settings?.addons.meal_rhythm_history))
      .filter((day) => day.finalized && day.date >= cutoff),
    [cutoff, data.settings?.addons.meal_rhythm_history],
  )
  const closedRhythmScore = averageClosedMealRhythm(data.settings?.addons.meal_rhythm_history, cutoff)
  const score = closedRhythmScore ?? analysis.rhythmScore
  const completeDays = historyDays.filter((day) => day.verdict === 'complete_on_time' || day.verdict === 'complete_irregular').length
  const readyShare = analysis.workoutsWithContext
    ? Math.round((analysis.readyStarts / analysis.workoutsWithContext) * 100)
    : null
  const statement = score == null ? copy.noData : score >= 82 ? copy.strong : score >= 60 ? copy.steady : copy.flexible

  return (
    <div data-no-translate>
      <GlassCard accent={ACCENTS.emerald} className="overflow-hidden p-0">
        <div className="relative overflow-hidden bg-[radial-gradient(circle_at_90%_0%,rgba(16,185,129,.2),transparent_32%),radial-gradient(circle_at_8%_88%,rgba(34,211,238,.15),transparent_34%),linear-gradient(145deg,#07151a,#0a2020)] p-5 text-white sm:p-6">
          <div className="pointer-events-none absolute inset-0 opacity-30 [background-image:linear-gradient(rgba(255,255,255,.035)_1px,transparent_1px)] [background-size:100%_26px]" />
          <div className="relative flex items-start justify-between gap-3">
            <div>
              <p className="font-mono text-[9px] font-black tracking-[.2em] text-cyan-200/70 uppercase">{copy.eyebrow}</p>
              <h2 className="mt-1 font-display text-2xl font-black">{copy.title}</h2>
              <p className="mt-1 max-w-lg text-[13px] leading-relaxed text-white/60">{copy.subtitle}</p>
            </div>
            <div className="flex shrink-0 rounded-full bg-white/8 p-1">
              {([30, 90] as const).map((days) => <button key={days} type="button" onClick={() => setRange(days)} className={`rounded-full px-2.5 py-1.5 font-mono text-[9px] font-black transition ${range === days ? 'bg-emerald-300 text-emerald-950 shadow' : 'text-white/55'}`}>{days}{copy.dayUnit}</button>)}
            </div>
          </div>

          <div className="relative mt-4 grid gap-2 sm:grid-cols-[9.5rem_minmax(0,1fr)]">
            <div className="relative grid place-items-center rounded-[1.6rem] border border-white/8 bg-white/[.055] p-4">
              <button
                type="button"
                aria-label={copy.infoLabel}
                aria-expanded={showScoreInfo}
                aria-controls="metabolic-rhythm-score-info"
                onClick={() => setShowScoreInfo((open) => !open)}
                className="absolute top-3 right-3 grid h-8 w-8 place-items-center rounded-full border border-cyan-100/20 bg-cyan-200/10 font-serif text-sm font-black text-cyan-100 transition hover:bg-cyan-200/15 active:scale-95"
              >
                i
              </button>
              <div className="relative grid h-28 w-28 place-items-center rounded-full" style={{ background: `conic-gradient(#34d399 ${score ?? 0}%,rgba(255,255,255,.08) 0)` }}>
                <div className="grid h-[90px] w-[90px] place-items-center rounded-full bg-[#0a1d1d] text-center">
                  <div>
                    <p className="font-mono font-black text-white">
                      <span className="text-3xl">{score ?? '·'}</span>
                      {score != null && <span className="ml-0.5 text-[11px] text-white/48">/100</span>}
                    </p>
                    <p className="mt-0.5 font-mono text-[9px] font-black tracking-wide text-emerald-200/65 uppercase">{copy.rhythm}</p>
                  </div>
                </div>
                {score != null && <motion.span initial={{ scale: 0 }} animate={{ scale: 1 }} className="absolute -right-1 bottom-2 h-4 w-4 rounded-full border-4 border-[#0a1d1d] bg-cyan-300 shadow-[0_0_18px_rgba(103,232,249,.8)]" />}
              </div>
              <p className="mt-2 font-mono text-[9px] font-bold text-white/45">{zonedClock(new Date(), timeZone).time} · {timeZone.replace(/_/g, ' ')}</p>
            </div>

            <div className="grid grid-cols-2 gap-2">
              <Metric label={copy.variation} value={analysis.typicalVariationMinutes == null ? '·' : `${analysis.typicalVariationMinutes} ${copy.minutes}`} />
              <Metric label={copy.context} value={String(analysis.workoutsWithContext)} />
              <Metric label={copy.comfortable} value={readyShare == null ? '·' : `${readyShare}%`} positive={readyShare != null && readyShare >= 70} />
              <Metric label={copy.average} value={analysis.averageWaitMinutes == null ? '·' : `${analysis.averageWaitMinutes} ${copy.minutes}`} />
              <Metric label={copy.recovery} value={analysis.recoveryTimingScore == null ? '·' : `${analysis.recoveryTimingScore}/100`} positive={analysis.recoveryTimingScore != null && analysis.recoveryTimingScore >= 85} />
              <Metric label={copy.recoveryAverage} value={analysis.averageRecoveryGapMinutes == null ? '·' : `${analysis.averageRecoveryGapMinutes} ${copy.minutes}`} />
              <Metric label={copy.exactStarts} value={`${analysis.recoveryMealsRecorded}/${analysis.completedWorkouts}`} />
              <Metric label={copy.closedDays} value={String(historyDays.length)} />
              <Metric label={copy.completeDays} value={`${completeDays}/${historyDays.length}`} positive={historyDays.length > 0 && completeDays === historyDays.length} />
            </div>
          </div>

          <AnimatePresence initial={false}>
            {showScoreInfo && (
              <motion.div
                id="metabolic-rhythm-score-info"
                role="note"
                initial={{ opacity: 0, height: 0, marginTop: 0 }}
                animate={{ opacity: 1, height: 'auto', marginTop: 12 }}
                exit={{ opacity: 0, height: 0, marginTop: 0 }}
                className="relative overflow-hidden rounded-2xl border border-cyan-100/14 bg-cyan-100/[.075]"
              >
                <div className="p-4">
                  <div className="flex items-start justify-between gap-3">
                    <p className="text-[13px] font-black text-cyan-50">{copy.infoTitle}</p>
                    <button type="button" onClick={() => setShowScoreInfo(false)} aria-label={copy.close} className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-white/8 text-sm font-black text-white/65">×</button>
                  </div>
                  <p className="mt-2 text-[12px] leading-relaxed font-semibold text-white/65">{copy.infoBody}</p>
                  <p className="mt-2 text-[11px] leading-relaxed font-bold text-emerald-200/75">{copy.infoScale}</p>
                </div>
              </motion.div>
            )}
          </AnimatePresence>

          <div className="relative mt-3 rounded-2xl border border-white/8 bg-white/[.05] px-3.5 py-3">
            <p className="text-[13px] font-black text-white">{statement}</p>
            <p className="mt-1 font-mono text-[10px] font-bold text-cyan-100/52">{analysis.recordedMeals} {analysis.recordedMeals === 1 ? copy.meal : copy.meals}</p>
          </div>
          <p className="relative mt-3 text-[10px] leading-relaxed font-medium text-white/38">{copy.note}</p>
        </div>
      </GlassCard>
    </div>
  )
}

function Metric({ label, value, positive = false }: { label: string; value: string; positive?: boolean }) {
  return (
    <div className="min-h-[74px] rounded-2xl border border-white/8 bg-white/[.055] px-3 py-3">
      <p className="text-[11px] leading-snug font-bold text-white/58">{label}</p>
      <p className={`mt-1.5 font-mono text-lg font-black ${positive ? 'text-emerald-300' : 'text-white'}`}>{value}</p>
    </div>
  )
}
