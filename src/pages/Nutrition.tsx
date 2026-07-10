import { useMemo, useState } from 'react'
import { motion } from 'framer-motion'
import { format, subDays } from 'date-fns'
import { useStore } from '../store/AppStore'
import { ACCENTS } from '../lib/theme'
import {
  AccentChip,
  EASE,
  GlassCard,
  SectionHeader,
  Sparkline,
  Stepper,
  Toggle,
} from '../components/ui'
import { computeTargets, ACTIVITY_MULTIPLIERS, GOALS } from '../lib/nutrition'
import { todayIso } from '../lib/plan'
import type { ActivityLevel, DailyLog, Goal, Supplement } from '../lib/types'
import { ensurePermission } from '../lib/notify'

const amber = ACCENTS.amber

export function dailyLogId(date: string): string {
  return `33333333-0000-4000-8000-${date.replaceAll('-', '').padStart(12, '0')}`
}

function minutesOf(hm: string): number {
  const [h, m] = hm.split(':').map(Number)
  return h * 60 + m
}

function hmOf(minutes: number): string {
  const m = ((minutes % 1440) + 1440) % 1440
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`
}

export function resolveSupplementTime(s: Supplement, trainingTime: string): number {
  if (s.timing === 'clock' && s.clock_time) return minutesOf(s.clock_time)
  return minutesOf(trainingTime) + (s.offset_min ?? 0)
}

export function Nutrition() {
  const { data, upsert, remove, setProfile, setSettings, toast } = useStore()
  const today = todayIso()
  const profile = data.profile
  const targets = useMemo(() => (profile ? computeTargets(profile) : null), [profile])
  const [showBmrInfo, setShowBmrInfo] = useState(false)

  const todayLog: DailyLog =
    data.daily_logs.find((d) => d.date === today) ?? {
      id: dailyLogId(today),
      user_id: profile?.user_id ?? '',
      date: today,
      kcal: null,
      protein_g: null,
      fat_g: null,
      carbs_g: null,
      water_l: 0,
    }

  const patchLog = (patch: Partial<DailyLog>): void => {
    upsert('daily_logs', { ...todayLog, ...patch })
  }

  /* Sparkline data: last 7 days including today */
  const week = useMemo(() => {
    const days = [...Array(7)].map((_, i) => format(subDays(new Date(), 6 - i), 'yyyy-MM-dd'))
    const byDate = new Map(data.daily_logs.map((d) => [d.date, d]))
    return {
      kcal: days.map((d) => byDate.get(d)?.kcal ?? null),
      protein: days.map((d) => byDate.get(d)?.protein_g ?? null),
      fat: days.map((d) => byDate.get(d)?.fat_g ?? null),
      carbs: days.map((d) => byDate.get(d)?.carbs_g ?? null),
      water: days.map((d) => byDate.get(d)?.water_l ?? null),
    }
  }, [data.daily_logs])

  /* Meal check-offs for today */
  const mealDone = (mealId: string): boolean =>
    data.meal_logs.some((l) => l.date === today && l.meal_id === mealId)
  const toggleMeal = (mealId: string): void => {
    const existing = data.meal_logs.find((l) => l.date === today && l.meal_id === mealId)
    if (existing) remove('meal_logs', existing.id)
    else
      upsert('meal_logs', {
        id: crypto.randomUUID(),
        user_id: profile?.user_id ?? '',
        date: today,
        meal_id: mealId,
        checked_at: new Date().toISOString(),
      })
  }

  /* Supplements resolved to today's clock and grouped */
  const trainingTime = profile?.training_time ?? '19:00'
  const nowMin = new Date().getHours() * 60 + new Date().getMinutes()
  const isTrainingDay = true // every weekday has a session in these programs
  const groups = useMemo(() => {
    const map = new Map<string, { time: number; items: Supplement[] }>()
    for (const s of [...data.supplements].sort((a, b) => a.sort_order - b.sort_order)) {
      if (s.training_days_only && !isTrainingDay) continue
      const t = resolveSupplementTime(s, trainingTime)
      const g = map.get(s.group_label) ?? { time: t, items: [] }
      g.items.push(s)
      map.set(s.group_label, g)
    }
    return [...map.entries()]
      .map(([label, g]) => ({ label, ...g }))
      .sort((a, b) => a.time - b.time)
  }, [data.supplements, trainingTime, isTrainingDay])

  const supDone = (id: string): boolean =>
    data.supplement_logs.some((l) => l.date === today && l.supplement_id === id)
  const toggleSup = (id: string): void => {
    const existing = data.supplement_logs.find((l) => l.date === today && l.supplement_id === id)
    if (existing) remove('supplement_logs', existing.id)
    else
      upsert('supplement_logs', {
        id: crypto.randomUUID(),
        user_id: profile?.user_id ?? '',
        date: today,
        supplement_id: id,
        checked_at: new Date().toISOString(),
      })
  }

  const enableNotifications = async (): Promise<void> => {
    const ok = await ensurePermission()
    if (ok) {
      setSettings({ notifications_on: true })
      toast('Meal and supplement reminders on', 'ok')
    } else {
      toast('Notifications blocked by the browser')
    }
  }

  if (!profile || !targets) return null

  const num = 'font-mono font-bold text-ink'

  return (
    <div className="mx-auto w-full max-w-3xl">
      <SectionHeader
        accent={amber}
        title="Nutrition"
        subtitle="Targets, meals, stack and the evening log"
        right={
          !data.settings?.notifications_on ? (
            <button
              type="button"
              onClick={() => void enableNotifications()}
              className="glass rounded-full px-3 py-1.5 text-xs font-bold text-ink-soft"
            >
              Enable reminders
            </button>
          ) : undefined
        }
      />

      <div className="space-y-5">
        {/* -------- Targets -------- */}
        <GlassCard accent={amber} className="p-5 sm:p-6">
          <div className="flex items-start justify-between">
            <h2 className="font-display text-lg font-bold text-ink">Daily targets</h2>
            <AccentChip accent={amber}>{GOALS[profile.goal].label.toUpperCase()}</AccentChip>
          </div>

          <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div>
              <p className="text-[11px] font-semibold tracking-wide text-ink-soft uppercase">Calories</p>
              <p className={`${num} text-3xl`} style={{ color: amber.deep }}>
                {targets.kcal}
              </p>
            </div>
            <div>
              <p className="text-[11px] font-semibold tracking-wide text-ink-soft uppercase">Protein</p>
              <p className={`${num} text-3xl`}>{targets.protein_g}g</p>
            </div>
            <div>
              <p className="text-[11px] font-semibold tracking-wide text-ink-soft uppercase">Fat</p>
              <p className={`${num} text-3xl`}>{targets.fat_g}g</p>
            </div>
            <div>
              <p className="text-[11px] font-semibold tracking-wide text-ink-soft uppercase">Carbs</p>
              <p className={`${num} text-3xl`}>{targets.carbs_g}g</p>
            </div>
          </div>

          <div className="mt-4 flex flex-wrap items-center gap-x-5 gap-y-2 border-t border-ink/8 pt-4 text-sm">
            <p className="font-medium text-ink-soft">
              BMR Mifflin-St Jeor: <span className={num}>{targets.bmrMifflin}</span>
            </p>
            <p className="font-medium text-ink-soft">
              Katch-McArdle: <span className={num}>{targets.bmrKatch}</span>
              <button
                type="button"
                onClick={() => setShowBmrInfo((v) => !v)}
                className="ml-1.5 inline-flex h-4.5 w-4.5 items-center justify-center rounded-full text-[10px] font-bold text-white align-middle"
                style={{ background: amber.gradient }}
                aria-label="Why Katch-McArdle"
              >
                i
              </button>
            </p>
            <p className="font-medium text-ink-soft">
              TDEE: <span className={num}>{targets.tdee}</span>
            </p>
          </div>
          {showBmrInfo && (
            <motion.p
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: 'auto' }}
              className="mt-2 rounded-xl px-3 py-2 text-[13px] leading-relaxed font-medium text-ink-soft"
              style={{ background: amber.wash }}
            >
              Katch-McArdle computes from lean body mass instead of total weight, so when body fat
              is measured it stops fat mass from inflating the estimate. With 23% body fat on
              record, APEX builds your calorie target on it.
            </motion.p>
          )}

          <div className="mt-4 flex flex-wrap gap-2">
            {Object.entries(ACTIVITY_MULTIPLIERS).map(([key, v]) => (
              <button
                key={key}
                type="button"
                onClick={() => setProfile({ activity_level: key as ActivityLevel })}
                className="rounded-full px-3 py-1.5 text-xs font-bold transition-all"
                style={
                  profile.activity_level === key
                    ? { background: amber.gradient, color: '#fff' }
                    : { background: 'rgba(255,255,255,0.6)', color: '#55555f', border: '1px solid rgba(26,26,34,0.08)' }
                }
              >
                {v.label}
              </button>
            ))}
          </div>
          <div className="mt-2 flex flex-wrap gap-2">
            {Object.entries(GOALS).map(([key, v]) => (
              <button
                key={key}
                type="button"
                onClick={() => setProfile({ goal: key as Goal })}
                className="rounded-full px-3 py-1.5 text-xs font-bold transition-all"
                style={
                  profile.goal === key
                    ? { background: amber.gradient, color: '#fff' }
                    : { background: 'rgba(255,255,255,0.6)', color: '#55555f', border: '1px solid rgba(26,26,34,0.08)' }
                }
              >
                {v.label}
              </button>
            ))}
          </div>
        </GlassCard>

        {/* -------- Meal timeline -------- */}
        <div>
          <h2 className="mb-3 font-display text-lg font-bold text-ink">Meal timeline</h2>
          <div className="space-y-3">
            {[...data.meals]
              .sort((a, b) => a.time.localeCompare(b.time))
              .map((meal, i) => {
                const done = mealDone(meal.id)
                const t = minutesOf(meal.time)
                const isNext = !done && t >= nowMin - 45 && t <= nowMin + 120
                return (
                  <motion.div
                    key={meal.id}
                    initial={{ opacity: 0, y: 14 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: i * 0.05, duration: 0.4, ease: EASE }}
                  >
                    <GlassCard
                      accent={amber}
                      breathe={isNext}
                      className={`p-4 transition-opacity ${done ? 'opacity-60' : ''}`}
                    >
                      <div className="flex items-start gap-3">
                        <button
                          type="button"
                          onClick={() => toggleMeal(meal.id)}
                          aria-label={`Mark ${meal.name} ${done ? 'not eaten' : 'eaten'}`}
                          className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full border-2 transition-all active:scale-90"
                          style={
                            done
                              ? { background: amber.gradient, borderColor: 'transparent', color: '#fff' }
                              : { borderColor: amber.bright, color: 'transparent' }
                          }
                        >
                          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" className="h-4 w-4">
                            <path d="m5 13 4 4L19 7" strokeLinecap="round" strokeLinejoin="round" />
                          </svg>
                        </button>
                        <div className="min-w-0 flex-1">
                          <div className="flex flex-wrap items-center gap-2">
                            <span className="font-mono text-sm font-bold" style={{ color: amber.deep }}>
                              {meal.time}
                            </span>
                            <h3 className="font-display text-[15px] font-bold text-ink">{meal.name}</h3>
                            {meal.full_days_only && <AccentChip accent={amber}>FULL DAYS ONLY</AccentChip>}
                          </div>
                          <p className="mt-1 text-[13px] leading-snug font-medium text-ink-soft">{meal.foods}</p>
                          <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 font-mono text-xs font-semibold text-ink-soft">
                            <span>{meal.kcal} kcal</span>
                            <span>P {meal.protein_g}</span>
                            <span>F {meal.fat_g}</span>
                            <span>C {meal.carbs_g}</span>
                          </div>
                          <div
                            className="mt-2 inline-block rounded-full px-2.5 py-1 text-[11px] font-semibold"
                            style={{ background: amber.wash, color: amber.deep }}
                          >
                            Minimum effective: 1 fist carbs + 1 palm protein + 1 scoop isolate
                          </div>
                        </div>
                      </div>
                    </GlassCard>
                  </motion.div>
                )
              })}
          </div>
        </div>

        {/* -------- Supplement timeline -------- */}
        <div>
          <div className="mb-3 flex items-center justify-between">
            <h2 className="font-display text-lg font-bold text-ink">Supplement stack</h2>
            <div className="flex items-center gap-2 text-xs font-semibold text-ink-soft">
              Training at
              <input
                type="time"
                value={trainingTime}
                onChange={(e) => setProfile({ training_time: e.target.value })}
                className="glass rounded-lg px-2 py-1 font-mono text-xs font-bold text-ink"
              />
            </div>
          </div>
          <div className="relative space-y-3 pl-6">
            <div
              className="absolute top-2 bottom-2 left-[9px] w-0.5 rounded-full"
              style={{ background: `linear-gradient(180deg, ${amber.soft}, ${amber.bright})`, opacity: 0.4 }}
              aria-hidden
            />
            {groups.map((group) => {
              const active = nowMin >= group.time - 10 && nowMin <= group.time + 50
              const allDone = group.items.every((s) => supDone(s.id))
              return (
                <div key={group.label} className="relative">
                  <span
                    className="absolute top-4 -left-6 h-3 w-3 rounded-full border-2 border-white"
                    style={{ background: allDone ? amber.gradient : 'rgba(26,26,34,0.15)' }}
                    aria-hidden
                  />
                  <GlassCard accent={amber} breathe={active} className="p-4">
                    <div className="flex items-center justify-between">
                      <p className="font-display text-sm font-bold text-ink">{group.label}</p>
                      <span className="font-mono text-xs font-bold" style={{ color: amber.deep }}>
                        {hmOf(group.time)}
                        {active && ' · now'}
                      </span>
                    </div>
                    <div className="mt-2.5 flex flex-wrap gap-2">
                      {group.items.map((s) => {
                        const done = supDone(s.id)
                        return (
                          <button
                            key={s.id}
                            type="button"
                            onClick={() => toggleSup(s.id)}
                            className="rounded-full px-3 py-1.5 text-xs font-bold transition-all active:scale-95"
                            style={
                              done
                                ? { background: amber.gradient, color: '#fff' }
                                : {
                                    background: 'rgba(255,255,255,0.65)',
                                    color: '#3f3f48',
                                    border: `1px solid ${amber.glowSoft}`,
                                  }
                            }
                          >
                            {s.name}
                            {s.dose ? ` ${s.dose}` : ''}
                            {s.training_days_only ? ' (training days)' : ''}
                          </button>
                        )
                      })}
                    </div>
                  </GlassCard>
                </div>
              )
            })}
          </div>
        </div>

        {/* -------- Evening daily log -------- */}
        <GlassCard accent={amber} className="p-5 sm:p-6">
          <div className="flex items-center justify-between">
            <h2 className="font-display text-lg font-bold text-ink">Daily log</h2>
            <span className="font-mono text-xs font-bold text-ink-faint">{today}</span>
          </div>
          <p className="mt-1 text-[13px] font-medium text-ink-soft">
            Twenty seconds before bed. This feeds the Health stat.
          </p>
          <div className="mt-4 space-y-4">
            {(
              [
                { label: 'Calories', key: 'kcal', step: 50, unit: 'kcal', values: week.kcal },
                { label: 'Protein', key: 'protein_g', step: 5, unit: 'g', values: week.protein },
                { label: 'Fat', key: 'fat_g', step: 5, unit: 'g', values: week.fat },
                { label: 'Carbs', key: 'carbs_g', step: 10, unit: 'g', values: week.carbs },
              ] as const
            ).map((row) => (
              <div key={row.key} className="flex items-center justify-between gap-3">
                <div className="w-20">
                  <p className="text-sm font-bold text-ink">{row.label}</p>
                  <Sparkline values={row.values} accent={amber} width={72} height={22} />
                </div>
                <Stepper
                  accent={amber}
                  value={(todayLog[row.key] as number | null) ?? 0}
                  step={row.step}
                  unit={row.unit}
                  onChange={(v) => patchLog({ [row.key]: v })}
                />
              </div>
            ))}
            <div className="flex items-center justify-between gap-3">
              <div className="w-20">
                <p className="text-sm font-bold text-ink">Water</p>
                <Sparkline values={week.water} accent={amber} width={72} height={22} />
              </div>
              <Stepper
                accent={amber}
                value={todayLog.water_l}
                step={0.25}
                unit="L"
                onChange={(v) => patchLog({ water_l: v })}
              />
            </div>
          </div>
          <div className="mt-4 border-t border-ink/8 pt-3 text-xs font-medium text-ink-soft">
            Water is shared with the workout calendars. Log it wherever you are.
          </div>
        </GlassCard>

        {/* Reminders toggle */}
        {data.settings && (
          <GlassCard accent={amber} className="flex items-center justify-between p-4">
            <div>
              <p className="text-sm font-bold text-ink">Meal + stack reminders</p>
              <p className="text-xs font-medium text-ink-soft">Fires while APEX is open in a tab</p>
            </div>
            <Toggle
              accent={amber}
              on={data.settings.notifications_on}
              onChange={(v) => {
                if (v) void enableNotifications()
                else setSettings({ notifications_on: false })
              }}
            />
          </GlassCard>
        )}
      </div>
    </div>
  )
}
