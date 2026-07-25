import { useMemo, useState } from 'react'
import { motion } from 'framer-motion'
import type { IntroLanguage } from '../../lib/introLanguage'
import { analyzeMealTiming, timeZoneFromSettings, zonedClock } from '../../lib/mealTiming'
import { ACCENTS } from '../../lib/theme'
import { useLanguage } from '../../lib/i18n'
import { useStore } from '../../store/AppStore'
import { useFoodStore } from '../../store/FoodStore'
import { GlassCard } from '../ui'

const COPY = {
  en: {
    eyebrow: 'AVATAR INPUT SIGNAL',
    title: 'Metabolic rhythm',
    subtitle: 'APEX now reads meal completion, consistency and the real gap before training.',
    rhythm: 'Rhythm',
    variation: 'Typical variation',
    context: 'Timed workouts',
    comfortable: 'Comfort-window starts',
    average: 'Average meal-to-training gap',
    recovery: 'Post-workout timing',
    recoveryAverage: 'Average workout-to-food gap',
    exactStarts: 'Exact recovery starts',
    meals: 'recorded meals',
    meal: 'recorded meal',
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
    rhythm: 'Ritm',
    variation: 'Variație tipică',
    context: 'Antrenamente corelate',
    comfortable: 'Porniri în fereastra confortabilă',
    average: 'Interval mediu masă-antrenament',
    recovery: 'Timing după antrenament',
    recoveryAverage: 'Interval mediu antrenament-masă',
    exactStarts: 'Începuturi exacte',
    meals: 'mese înregistrate',
    meal: 'masă înregistrată',
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
    rhythm: 'จังหวะ',
    variation: 'ความคลาดเคลื่อนโดยทั่วไป',
    context: 'การฝึกที่มีข้อมูลเวลา',
    comfortable: 'เริ่มฝึกในช่วงที่สบายขึ้น',
    average: 'ช่วงเฉลี่ยจากมื้ออาหารถึงการฝึก',
    recovery: 'เวลาหลังฝึก',
    recoveryAverage: 'ช่วงเฉลี่ยจากฝึกถึงกิน',
    exactStarts: 'เวลาเริ่มกินที่บันทึกจริง',
    meals: 'มื้อที่บันทึกเวลา',
    meal: 'มื้อที่บันทึกเวลา',
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
    recoveryNutrition: data.settings?.addons.recovery_nutrition,
    mealStartTimes: data.settings?.addons.meal_start_times,
  }), [data.settings?.addons.meal_start_times, data.settings?.addons.recovery_nutrition, entries, meals, sessions, timeZone])
  const score = analysis.rhythmScore
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
              <p className="font-mono text-[8px] font-black tracking-[.2em] text-cyan-200/65 uppercase">{copy.eyebrow}</p>
              <h2 className="mt-1 font-display text-xl font-black">{copy.title}</h2>
              <p className="mt-1 max-w-lg text-[11px] leading-relaxed text-white/45">{copy.subtitle}</p>
            </div>
            <div className="flex shrink-0 rounded-full bg-white/8 p-1">
              {([30, 90] as const).map((days) => <button key={days} type="button" onClick={() => setRange(days)} className={`rounded-full px-2.5 py-1.5 font-mono text-[8px] font-black transition ${range === days ? 'bg-emerald-300 text-emerald-950 shadow' : 'text-white/45'}`}>{days}{copy.dayUnit}</button>)}
            </div>
          </div>

          <div className="relative mt-4 grid gap-2 sm:grid-cols-[9.5rem_minmax(0,1fr)]">
            <div className="grid place-items-center rounded-[1.6rem] border border-white/8 bg-white/[.055] p-4">
              <div className="relative grid h-28 w-28 place-items-center rounded-full" style={{ background: `conic-gradient(#34d399 ${score ?? 0}%,rgba(255,255,255,.08) 0)` }}>
                <div className="grid h-[90px] w-[90px] place-items-center rounded-full bg-[#0a1d1d] text-center">
                  <div><p className="font-mono text-3xl font-black text-white">{score ?? '·'}</p><p className="font-mono text-[7px] font-black tracking-wider text-emerald-200/55 uppercase">{copy.rhythm}</p></div>
                </div>
                {score != null && <motion.span initial={{ scale: 0 }} animate={{ scale: 1 }} className="absolute -right-1 bottom-2 h-4 w-4 rounded-full border-4 border-[#0a1d1d] bg-cyan-300 shadow-[0_0_18px_rgba(103,232,249,.8)]" />}
              </div>
              <p className="mt-2 font-mono text-[8px] font-bold text-white/34">{zonedClock(new Date(), timeZone).time} · {timeZone.replace(/_/g, ' ')}</p>
            </div>

            <div className="grid grid-cols-2 gap-2">
              <Metric label={copy.variation} value={analysis.typicalVariationMinutes == null ? '·' : `${analysis.typicalVariationMinutes} ${copy.minutes}`} />
              <Metric label={copy.context} value={String(analysis.workoutsWithContext)} />
              <Metric label={copy.comfortable} value={readyShare == null ? '·' : `${readyShare}%`} positive={readyShare != null && readyShare >= 70} />
              <Metric label={copy.average} value={analysis.averageWaitMinutes == null ? '·' : `${analysis.averageWaitMinutes} ${copy.minutes}`} />
              <Metric label={copy.recovery} value={analysis.recoveryTimingScore == null ? '·' : `${analysis.recoveryTimingScore}/100`} positive={analysis.recoveryTimingScore != null && analysis.recoveryTimingScore >= 85} />
              <Metric label={copy.recoveryAverage} value={analysis.averageRecoveryGapMinutes == null ? '·' : `${analysis.averageRecoveryGapMinutes} ${copy.minutes}`} />
              <Metric label={copy.exactStarts} value={`${analysis.recoveryMealsRecorded}/${analysis.completedWorkouts}`} />
            </div>
          </div>

          <div className="relative mt-3 rounded-2xl border border-white/8 bg-white/[.05] px-3.5 py-3">
            <p className="text-[11px] font-black text-white">{statement}</p>
            <p className="mt-1 font-mono text-[8px] font-bold text-cyan-100/42">{analysis.recordedMeals} {analysis.recordedMeals === 1 ? copy.meal : copy.meals}</p>
          </div>
          <p className="relative mt-3 text-[8px] leading-relaxed font-medium text-white/25">{copy.note}</p>
        </div>
      </GlassCard>
    </div>
  )
}

function Metric({ label, value, positive = false }: { label: string; value: string; positive?: boolean }) {
  return (
    <div className="rounded-2xl border border-white/8 bg-white/[.055] px-3 py-3">
      <p className="text-[8px] leading-tight font-bold text-white/35">{label}</p>
      <p className={`mt-1 font-mono text-base font-black ${positive ? 'text-emerald-300' : 'text-white'}`}>{value}</p>
    </div>
  )
}
