/*
 * RPG Avatar dashboard: level HUD, hexagonal radar, six animated stat bars
 * with Upper/Lower strength sub-bars, per-stat history, baseline reasoning
 * and the "What your body needs" recommendation cards.
 */
import { useMemo, useState } from 'react'
import { motion } from 'framer-motion'
import { useNavigate } from 'react-router-dom'
import { useStore } from '../store/AppStore'
import { ACCENTS } from '../lib/theme'
import { AccentChip, EASE, GlassCard, GradientButton, SectionHeader } from '../components/ui'
import { assessBodyState, baselineForProfile, overallOf, whatYourBodyNeeds } from '../lib/rpg'
import type { SynergyEvent, SynergyKind } from '../lib/rpg'
import type { Profile, RpgSnapshot } from '../lib/types'
import { format as fmtDate } from 'date-fns'
import { ageFrom } from '../lib/nutrition'
import { translateInterfaceText, useLanguage } from '../lib/i18n'
import { CameraIcon } from '../components/Icons'
import { AvatarPortraitHero } from '../components/avatar/AvatarPortraitHero'
import { StrengthProgressPanel } from '../components/avatar/StrengthProgressPanel'

const emerald = ACCENTS.emerald

interface StatDef {
  key: keyof Pick<RpgSnapshot, 'overall' | 'health' | 'joint' | 'flexibility' | 'endurance' | 'strength'>
  label: string
  color: string
  colorSoft: string
  glow: string
}

const STATS: StatDef[] = [
  { key: 'overall', label: 'Overall Fitness Level', color: '#059669', colorSoft: '#34d399', glow: 'rgba(16,185,129,0.45)' },
  { key: 'health', label: 'Health', color: '#f59e0b', colorSoft: '#fbbf24', glow: 'rgba(245,158,11,0.45)' },
  { key: 'joint', label: 'Joint Health Balance', color: '#0284c7', colorSoft: '#7dd3fc', glow: 'rgba(56,189,248,0.45)' },
  { key: 'flexibility', label: 'Body Flexibility', color: '#0d9488', colorSoft: '#2dd4bf', glow: 'rgba(20,184,166,0.45)' },
  { key: 'endurance', label: 'Endurance & VO2max', color: '#7c3aed', colorSoft: '#a78bfa', glow: 'rgba(139,92,246,0.45)' },
  { key: 'strength', label: 'Strength', color: '#dc2626', colorSoft: '#fb923c', glow: 'rgba(220,38,38,0.4)' },
]

function baselineNotes(profile: Profile) {
  const baseline = baselineForProfile(profile)
  if (profile.persona === 'june') {
    return [
      { label: `Strength-Upper ${baseline.strength_upper}`, text: 'manual therapy, visible muscularity and calisthenics work support a strong upper-body starting point.' },
      { label: `Strength-Lower ${baseline.strength_lower}`, text: 'a lifetime of field work, strong legs and direct glute training make lower-body strength the leading quality.' },
      { label: `Endurance ${baseline.endurance}`, text: 'high occupational work capacity and an active lifestyle create an above-average base.' },
      { label: `Flexibility ${baseline.flexibility}`, text: 'movement skill is solid, while short corrective exposures protect range under repetitive massage work.' },
      { label: `Joint Health ${baseline.joint}`, text: 'the score respects both her durability and the recovery cost of repeated hand, shoulder and chest-wall loading.' },
      { label: `Health ${baseline.health}`, text: 'lean athletic function starts high, with energy availability, cycle changes and recovery treated as watchpoints.' },
    ]
  }
  if (profile.persona === 'matthew') {
    return [
      { label: `Strength-Upper ${baseline.strength_upper}`, text: 'pull-ups, push-ups, muscle-ups and hammer work support a strong calisthenics base.' },
      { label: `Strength-Lower ${baseline.strength_lower}`, text: 'marathon history and weighted squats provide a capable base with room for progressive strength work.' },
      { label: `Endurance ${baseline.endurance}`, text: 'the barefoot marathon history and regular SkiErg work make aerobic capacity the standout starting quality.' },
      { label: `Flexibility ${baseline.flexibility}`, text: 'a functional base is assumed, while daily mobility protects quality as training volume accumulates.' },
      { label: `Joint Health ${baseline.joint}`, text: 'experience is balanced against age-aware tendon and recovery management; crisp submaximal reps are rewarded.' },
      { label: `Health ${baseline.health}`, text: 'high activity and recovery-tool access create a strong base, while body-fat reduction depends on repeatable nutrition and sleep.' },
    ]
  }
  return [
    { label: `Strength-Upper ${baseline.strength_upper}`, text: 'childhood upper-body training keeps the top half moderately ahead.' },
    { label: `Strength-Lower ${baseline.strength_lower}`, text: 'legs started behind and receive extra XP until upper and lower strength converge.' },
    { label: `Endurance ${baseline.endurance}`, text: 'the starting point is modest and layoff-adjusted because aerobic adaptations fade quickly.' },
    { label: `Flexibility ${baseline.flexibility}`, text: 'the base prices in long desk and editing hours.' },
    { label: `Joint Health ${baseline.joint}`, text: 'deloads, honest tempo and sensible load jumps are the main levers.' },
    { label: `Health ${baseline.health}`, text: 'the starting score reflects current logging and recovery habits.' },
  ]
}

export function AvatarPage() {
  const { data, snapshots, synergies } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const navigate = useNavigate()
  const [showBaseline, setShowBaseline] = useState(false)
  const [range, setRange] = useState<30 | 90>(30)
  const [expanded, setExpanded] = useState<string | null>(null)

  const now = snapshots[snapshots.length - 1] ?? null
  const before = snapshots[Math.max(0, snapshots.length - 15)] ?? now
  const advice = useMemo(() => whatYourBodyNeeds(data, snapshots), [data, snapshots])
  const assessment = useMemo(() => assessBodyState(data, snapshots), [data, snapshots])

  if (!now) return null

  const profile = data.profile
  const baseline = baselineForProfile(profile)
  const notes = profile ? baselineNotes(profile) : []
  const score = Math.floor(now.overall)
  const overallDelta = now.overall - before.overall
  const personalBest = Math.max(...snapshots.map((snapshot) => snapshot.overall))
  const nextMilestone = Math.min(100, Math.max(5, (Math.floor(now.overall / 5) + 1) * 5))
  const milestoneStart = Math.max(0, nextMilestone - 5)
  const milestoneProgress = nextMilestone === 100 && now.overall >= 100
    ? 100
    : Math.max(0, Math.min(100, ((now.overall - milestoneStart) / Math.max(1, nextMilestone - milestoneStart)) * 100))
  const strongestStat = STATS.slice(1).reduce((best, stat) => now[stat.key] > now[best.key] ? stat : best)
  const identityTitle = now.overall >= 80
    ? 'Elite foundation'
    : now.overall >= 65
      ? 'Power becoming visible'
      : now.overall >= 50
        ? 'Momentum is taking shape'
        : 'Foundation under construction'

  /* the stat moving the most over 14 days breathes */
  const trending = STATS.slice(1).reduce(
    (best, s) => {
      const delta = Math.abs(now[s.key] - before[s.key])
      return delta > best.delta ? { key: s.key, delta } : best
    },
    { key: '' as string, delta: 0.4 },
  ).key

  const history = (key: StatDef['key']): number[] =>
    snapshots.slice(-range).map((s) => s[key])

  return (
    <div className="mx-auto w-full max-w-3xl">
      <SectionHeader accent={emerald} title="Avatar" subtitle="Your body, as a living stat sheet" />

      <div className="space-y-5">
        {profile && <AvatarPortraitHero profile={profile} />}

        <button type="button" onClick={() => navigate('/progress', { state: { from: '/avatar' } })} className="w-full text-left">
          <GlassCard accent={ACCENTS.violet} className="p-4 sm:p-5">
            <div className="flex items-center justify-between gap-4">
              <div className="flex items-center gap-3">
                <div className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl text-white" style={{ background: ACCENTS.violet.gradient }}><CameraIcon className="h-6 w-6" /></div>
                <div><p className="font-display text-base font-bold text-ink">Visual Progress</p><p className="mt-0.5 text-xs font-medium text-ink-soft">Private guided photos and honest side-by-side comparison</p></div>
              </div>
              <span className="text-2xl text-ink">›</span>
            </div>
          </GlassCard>
        </button>

        {/* Performance identity + radar */}
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="relative overflow-hidden rounded-3xl border border-emerald-300/20 bg-[#07130f] p-5 text-white shadow-[0_26px_70px_-32px_rgba(16,185,129,0.8)]">
            <div className="pointer-events-none absolute -top-20 -right-16 h-48 w-48 rounded-full bg-emerald-400/25 blur-3xl" />
            <div className="pointer-events-none absolute -bottom-24 -left-16 h-48 w-48 rounded-full bg-cyan-400/15 blur-3xl" />
            <div className="relative">
              <div className="flex items-center justify-between gap-2"><p className="font-mono text-[9px] font-bold tracking-[0.22em] text-emerald-200/70 uppercase">APEX Body Index</p><span className="rounded-full border border-emerald-300/20 bg-emerald-300/10 px-2 py-1 font-mono text-[7px] font-bold tracking-widest text-emerald-100 uppercase">Live profile</span></div>
              <div className="mt-3 flex items-end gap-3"><p className="font-mono text-7xl leading-none font-bold tracking-[-0.08em] text-white" style={{ textShadow: '0 0 28px rgba(52,211,153,0.42)' }}>{score}</p><div className="pb-1"><p className="font-display text-base font-bold text-emerald-100">{t(identityTitle)}</p><p className="mt-0.5 text-[10px] font-medium text-white/55">{t(`Your strongest signal is ${strongestStat.label} at ${now[strongestStat.key].toFixed(0)}.`)}</p></div></div>
              <div className="mt-5"><div className="flex items-center justify-between font-mono text-[8px] font-bold tracking-wide text-white/45 uppercase"><span>{t('Progress to next unlock')}</span><span className="text-emerald-200">{nextMilestone}</span></div><div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-white/10"><motion.div initial={{ width: 0 }} animate={{ width: `${milestoneProgress}%` }} transition={{ duration: 1, ease: EASE }} className="h-full rounded-full bg-gradient-to-r from-emerald-400 to-cyan-300 shadow-[0_0_12px_rgba(52,211,153,0.7)]" /></div></div>
              <div className="mt-4 grid grid-cols-3 gap-2 border-t border-white/8 pt-3">
                <IdentityMetric label="14-day change" value={`${overallDelta >= 0 ? '+' : ''}${overallDelta.toFixed(1)}`} positive={overallDelta >= 0} />
                <IdentityMetric label="Personal best" value={personalBest.toFixed(0)} positive={now.overall >= personalBest} />
                <IdentityMetric label="Next unlock" value={String(nextMilestone)} positive />
              </div>
            </div>
          </div>

          <GlassCard accent={emerald} className="p-1.5">
            <Radar snapshot={now} />
          </GlassCard>
        </div>

        {/* The engine: how nutrition, training and recovery talk */}
        <EngineCard synergies={synergies} />

        {/* What your body needs */}
        {advice.length > 0 && (
          <div>
            <h2 className="mb-3 font-display text-lg font-bold text-ink">What your body needs</h2>
            <div className="space-y-3">
              {advice.map((a, i) => (
                <motion.div
                  key={a.stat}
                  initial={{ opacity: 0, y: 14 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: i * 0.07, duration: 0.4, ease: EASE }}
                >
                  <GlassCard accent={emerald} className="p-4">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <AccentChip accent={emerald}>{t(a.stat).toUpperCase()}</AccentChip>
                        <p className="mt-2 text-[15px] leading-snug font-bold text-ink">{t(a.headline)}</p>
                        <p className="mt-1 text-[13px] leading-relaxed font-medium text-ink-soft">
                          {t(a.detail)} {t(a.prescription)}
                        </p>
                      </div>
                      {a.dayType && (
                        <GradientButton
                          accent={emerald}
                          className="shrink-0 !px-3.5 !py-2 text-xs"
                          onClick={() => navigate('/transition')}
                        >
                          Plan it
                        </GradientButton>
                      )}
                    </div>
                  </GlassCard>
                </motion.div>
              ))}
            </div>
          </div>
        )}

        {/* Stat bars */}
        <GlassCard accent={emerald} className="p-5">
          <div className="flex items-center justify-between">
            <h2 className="font-display text-lg font-bold text-ink">Stats</h2>
            <div className="flex gap-1.5">
              {([30, 90] as const).map((r) => (
                <button
                  key={r}
                  type="button"
                  onClick={() => setRange(r)}
                  className="rounded-full px-3 py-1 font-mono text-[11px] font-bold transition-all"
                  style={
                    range === r
                      ? { background: emerald.gradient, color: '#fff' }
                      : { background: 'rgba(255,255,255,0.6)', color: '#55555f', border: '1px solid rgba(26,26,34,0.08)' }
                  }
                >
                  {r}D
                </button>
              ))}
            </div>
          </div>

          <div className="mt-4 space-y-4">
            {STATS.map((s) => {
              const value = now[s.key]
              const delta = value - before[s.key]
              const isTrending = s.key === trending
              const isOpen = expanded === s.key
              return (
                <div key={s.key}>
                  <button
                    type="button"
                    className="w-full text-left"
                    onClick={() => setExpanded(isOpen ? null : s.key)}
                    aria-expanded={isOpen}
                  >
                    <div className="flex items-baseline justify-between">
                      <p className="text-sm font-bold text-ink">{t(s.label)}</p>
                      <p className="font-mono text-lg font-bold" style={{ color: s.color }}>
                        {value.toFixed(0)}
                        <span className={`ml-1.5 text-[11px] ${delta >= 0 ? 'text-emerald' : 'text-crimson'}`}>
                          {delta >= 0 ? '▲' : '▼'} {Math.abs(delta).toFixed(1)}
                        </span>
                      </p>
                    </div>
                    <div
                      className="mt-1.5 h-3 overflow-hidden rounded-full bg-ink/8"
                      style={isTrending ? { boxShadow: `0 0 18px -2px ${s.glow}`, animation: 'breathe 3.6s ease-in-out infinite' } : undefined}
                    >
                      <motion.div
                        className="h-full rounded-full"
                        style={{ background: `linear-gradient(90deg, ${s.color}, ${s.colorSoft})`, boxShadow: `0 0 12px ${s.glow}` }}
                        initial={{ width: 0 }}
                        animate={{ width: `${value}%` }}
                        transition={{ duration: 0.9, ease: EASE }}
                      />
                    </div>
                  </button>

                  {/* Upper / Lower sub-bars */}
                  {s.key === 'strength' && (
                    <div className="mt-2 grid grid-cols-2 gap-3 pl-3">
                      {(
                        [
                          ['Upper Body Strength', now.strength_upper],
                          ['Lower Body Strength', now.strength_lower],
                        ] as const
                      ).map(([label, v]) => (
                        <div key={label}>
                          <div className="flex justify-between font-mono text-[11px] font-bold text-ink-soft">
                            <span>{label}</span>
                            <span>{v.toFixed(0)}</span>
                          </div>
                          <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-ink/8">
                            <motion.div
                              className="h-full rounded-full"
                              style={{ background: `linear-gradient(90deg, ${s.color}, ${s.colorSoft})` }}
                              initial={{ width: 0 }}
                              animate={{ width: `${v}%` }}
                              transition={{ duration: 0.9, ease: EASE }}
                            />
                          </div>
                        </div>
                      ))}
                      {now.strength_lower < now.strength_upper - 3 && (
                        <p className="col-span-2 text-[11px] font-semibold text-ink-faint">
                          Leg XP boosted 1.25x until the bars converge.
                        </p>
                      )}
                    </div>
                  )}

                  {isOpen && (
                    <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} className="mt-2">
                      <HistoryChart values={history(s.key)} color={s.color} colorSoft={s.colorSoft} />
                    </motion.div>
                  )}
                </div>
              )
            })}
          </div>

          {assessment && (
            <motion.div
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.15, duration: 0.45, ease: EASE }}
              className="mt-6 border-t border-ink/8 pt-5"
            >
              <div className="flex flex-wrap items-start justify-between gap-2">
                <div>
                  <p className="font-mono text-[10px] font-bold tracking-[0.18em] text-ink-faint uppercase">APEX assessment</p>
                  <h3 className="mt-1 font-display text-base font-bold text-ink">{t(assessment.title)}</h3>
                </div>
                <AccentChip accent={emerald}>{t(assessment.confidence).toUpperCase()}</AccentChip>
              </div>
              <p className="mt-2 text-[13.5px] leading-relaxed font-medium text-ink-soft">
                {t(assessment.summary)}
              </p>
              <div className="mt-4 grid gap-3 sm:grid-cols-2">
                <div className="rounded-2xl p-3.5" style={{ background: 'rgba(16,185,129,0.07)' }}>
                  <p className="text-[11px] font-bold tracking-wide text-emerald uppercase">What is working</p>
                  <ul className="mt-2 space-y-1.5 text-[12.5px] leading-relaxed font-medium text-ink-soft">
                    {assessment.strengths.map((item) => <li key={item}>✓ {t(item)}</li>)}
                  </ul>
                </div>
                <div className="rounded-2xl p-3.5" style={{ background: 'rgba(245,158,11,0.08)' }}>
                  <p className="text-[11px] font-bold tracking-wide text-amber uppercase">Highest-return improvements</p>
                  <ol className="mt-2 space-y-1.5 text-[12.5px] leading-relaxed font-medium text-ink-soft">
                    {assessment.priorities.map((item, index) => <li key={item}>{index + 1}. {t(item)}</li>)}
                  </ol>
                </div>
              </div>
              <p className="mt-3 text-[10.5px] leading-relaxed font-medium text-ink-faint">
                Performance guidance generated from your APEX logs and trends; it is not a medical diagnosis.
              </p>
            </motion.div>
          )}
        </GlassCard>

        {/* Load history follows the at-a-glance body index and fitness scores. */}
        <StrengthProgressPanel />

        {/* Baseline reasoning */}
        <GlassCard accent={emerald} className="p-5">
          <button
            type="button"
            className="flex w-full items-center justify-between"
            onClick={() => setShowBaseline((v) => !v)}
            aria-expanded={showBaseline}
          >
            <h2 className="font-display text-lg font-bold text-ink">How your baseline was set</h2>
            <span className="font-mono text-lg text-ink-soft">{showBaseline ? '−' : '+'}</span>
          </button>
          {showBaseline && (
            <motion.ul
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="mt-3 space-y-2.5 text-[13.5px] leading-relaxed font-medium text-ink-soft"
            >
              <li>
                {profile
                  ? t(`Calibrated for ${profile.display_name}: age ${ageFrom(profile.birthdate)}, ${profile.weight_kg} kg, ${profile.body_fat_pct}% body fat and ${profile.height_cm} cm. ${profile.profile_note}`)
                  : 'Calibrated from the current body profile and available performance history.'}
              </li>
              {notes.map((note) => (
                <li key={note.label}>
                  <strong className="text-ink">{t(note.label)}:</strong> {t(note.text)}
                </li>
              ))}
              <li>
                {t(`Overall computes from the weights (Strength 25%, Endurance 20%, Joint 20%, Health 20%, Flexibility 15%), starting at ${overallOf(baseline).toFixed(1)}.`)}
              </li>
            </motion.ul>
          )}
        </GlassCard>
      </div>
    </div>
  )
}

function IdentityMetric({ label, value, positive }: { label: string; value: string; positive: boolean }) {
  return (
    <div className="min-w-0">
      <p className="truncate font-mono text-[7px] font-bold tracking-[0.1em] text-white/38 uppercase">{label}</p>
      <p className={`mt-1 font-mono text-sm font-bold ${positive ? 'text-emerald-200' : 'text-amber-200'}`}>{value}</p>
    </div>
  )
}

/* ---------------- the engine: explainable synergy feed ---------------- */

const SYNERGY_DOT: Record<SynergyKind, string> = {
  protein_strength: 'linear-gradient(135deg, #f59e0b, #fb7185)',
  deficit_strength: 'linear-gradient(135deg, #dc2626, #f59e0b)',
  hydration_endurance: 'linear-gradient(135deg, #38bdf8, #a78bfa)',
  mobility_after_legs: 'linear-gradient(135deg, #0ea5e9, #34d399)',
  vo2_anchor: 'linear-gradient(135deg, #7c3aed, #22d3ee)',
  import_feed: 'conic-gradient(from 0deg, #f59e0b, #8b5cf6, #10b981, #f59e0b)',
  deload_honored: 'linear-gradient(135deg, #0ea5e9, #7dd3fc)',
}

function EngineCard({ synergies }: { synergies: SynergyEvent[] }) {
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const recent = [...synergies].sort((a, b) => b.date.localeCompare(a.date)).slice(0, 8)
  return (
    <GlassCard accent={emerald} className="p-5">
      <div className="flex items-center justify-between">
        <h2 className="font-display text-lg font-bold text-ink">The engine</h2>
        <AccentChip accent={emerald}>NUTRITION × TRAINING × RECOVERY</AccentChip>
      </div>
      {recent.length === 0 ? (
        <p className="mt-2 text-[13.5px] leading-relaxed font-medium text-ink-soft">
          Everything here talks to everything else. Protein at target amplifies strength days by
          15%. Hydration fuels cardio XP. Mobility within 48 hours of a leg day pays a joint
          bonus. A measured VO2max from your watch anchors Endurance to reality, and imported
          Apple Health workouts feed the stats at reduced credit. When a rule fires, it shows up
          here with its receipt.
        </p>
      ) : (
        <div className="mt-3 space-y-2">
          {recent.map((e, i) => (
            <motion.div
              key={`${e.date}-${e.kind}-${i}`}
              initial={{ opacity: 0, x: -8 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: i * 0.05, duration: 0.35, ease: EASE }}
              className="flex items-center gap-2.5 rounded-2xl px-3 py-2"
              style={{ background: 'rgba(255,255,255,0.5)' }}
            >
              <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: SYNERGY_DOT[e.kind] }} />
              <p className="min-w-0 flex-1 text-[12.5px] leading-snug font-semibold text-ink">{t(e.label)}</p>
              <span className="shrink-0 font-mono text-[10px] font-bold text-ink-faint">
                {fmtDate(new Date(e.date + 'T12:00:00'), 'd MMM')}
              </span>
            </motion.div>
          ))}
        </div>
      )}
    </GlassCard>
  )
}

/* ---------------- hexagonal radar, jewel-box treatment ---------------- */

function Radar({ snapshot }: { snapshot: RpgSnapshot }) {
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const axes = [
    { label: 'HEALTH', lines: ['HEALTH'], value: snapshot.health },
    { label: 'JOINT', lines: ['JOINT'], value: snapshot.joint },
    { label: 'FLEX', lines: ['FLEX'], value: snapshot.flexibility },
    { label: 'ENDUR', lines: ['ENDUR'], value: snapshot.endurance },
    { label: 'UPPER BODY STRENGTH', lines: ['UPPER BODY', 'STRENGTH'], value: snapshot.strength_upper },
    { label: 'LOWER BODY STRENGTH', lines: ['LOWER BODY', 'STRENGTH'], value: snapshot.strength_lower },
  ]
  const cx = 130
  const cy = 118
  const R = 76

  const point = (i: number, v: number): [number, number] => {
    const angle = (Math.PI / 3) * i - Math.PI / 2
    const r = (v / 100) * R
    return [cx + r * Math.cos(angle), cy + r * Math.sin(angle)]
  }
  const pathFor = (vals: number[]): string =>
    vals.map((v, i) => `${i === 0 ? 'M' : 'L'}${point(i, v)[0].toFixed(1)},${point(i, v)[1].toFixed(1)}`).join(' ') + ' Z'

  const d = pathFor(axes.map((a) => a.value))
  const grid = 'rgba(126, 232, 255, 0.13)'

  return (
    <div
      className="relative overflow-hidden rounded-[20px]"
      style={{
        background: 'radial-gradient(130% 130% at 50% 18%, #232a54 0%, #12163a 48%, #05060f 100%)',
        boxShadow: 'inset 0 0 0 1px rgba(16,185,129,0.22), inset 0 0 55px rgba(3,4,12,0.7)',
      }}
    >
      <svg viewBox="0 0 260 236" className="w-full" role="img" aria-label="Stat radar">
        <defs>
          <linearGradient id="radar-stroke" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#34d399" />
            <stop offset="1" stopColor="#22d3ee" />
          </linearGradient>
          <radialGradient id="radar-fill" cx="0.5" cy="0.45" r="0.65">
            <stop offset="0" stopColor="#34d399" stopOpacity="0.42" />
            <stop offset="1" stopColor="#22d3ee" stopOpacity="0.08" />
          </radialGradient>
          <radialGradient id="radar-halo" cx="0.5" cy="0.5" r="0.5">
            <stop offset="0" stopColor="#22d3ee" stopOpacity="0.16" />
            <stop offset="1" stopColor="#22d3ee" stopOpacity="0" />
          </radialGradient>
          <filter id="radar-glow" x="-40%" y="-40%" width="180%" height="180%">
            <feGaussianBlur stdDeviation="4.5" />
          </filter>
        </defs>

        {/* ambient halo behind the figure */}
        <circle cx={cx} cy={cy} r={R + 26} fill="url(#radar-halo)" />

        {/* grid rings + axes */}
        {[0.25, 0.5, 0.75, 1].map((f) => (
          <path key={f} d={pathFor(axes.map(() => f * 100))} fill="none" stroke={grid} strokeWidth={f === 1 ? 1.2 : 0.8} />
        ))}
        {axes.map((_, i) => {
          const [x, y] = point(i, 100)
          return <line key={i} x1={cx} y1={cy} x2={x} y2={y} stroke={grid} strokeWidth="0.8" />
        })}

        {/* glow underlay, then the crisp figure */}
        <motion.path
          d={d}
          animate={{ d }}
          transition={{ duration: 0.8, ease: EASE }}
          fill="none"
          stroke="url(#radar-stroke)"
          strokeWidth="5"
          strokeLinejoin="round"
          opacity="0.75"
          filter="url(#radar-glow)"
        />
        <motion.path
          d={d}
          animate={{ d }}
          transition={{ duration: 0.8, ease: EASE }}
          fill="url(#radar-fill)"
          stroke="url(#radar-stroke)"
          strokeWidth="2.2"
          strokeLinejoin="round"
        />

        {/* vertex dots + values */}
        {axes.map((a, i) => {
          const [x, y] = point(i, a.value)
          const [lx, ly] = point(i, Math.min(a.value + 16, 112))
          return (
            <g key={a.label}>
              <circle cx={x} cy={y} r={5} fill="#22d3ee" opacity="0.35" filter="url(#radar-glow)" />
              <circle cx={x} cy={y} r={2.6} fill="#d9fbff" />
              <text
                x={lx}
                y={ly}
                textAnchor="middle"
                dominantBaseline="middle"
                fontSize="9.5"
                fontWeight="700"
                fill="#8df0ff"
                className="font-mono"
              >
                {a.value.toFixed(0)}
              </text>
            </g>
          )
        })}

        {/* axis labels */}
        {axes.map((a, i) => {
          const [x, y] = point(i, 132)
          const anchor = x < 55 ? 'start' : x > 205 ? 'end' : 'middle'
          return (
            <text
              key={a.label}
              x={x}
              y={y}
              textAnchor={anchor}
              dominantBaseline="middle"
              fontSize={a.lines.length > 1 ? '7.2' : '9.5'}
              fontWeight="700"
              letterSpacing={a.lines.length > 1 ? '0.7' : '1.5'}
              fill="rgba(214, 226, 245, 0.72)"
              className="font-mono"
            >
              {a.lines.map((line, lineIndex) => (
                <tspan key={line} x={x} dy={lineIndex === 0 ? (a.lines.length > 1 ? '-0.45em' : '0') : '1.15em'}>{t(line)}</tspan>
              ))}
            </text>
          )
        })}
      </svg>
      {/* inner vignette, mirrors the hologram stage */}
      <div className="pointer-events-none absolute inset-0 rounded-[20px]" style={{ boxShadow: 'inset 0 0 40px rgba(0,0,0,0.5)' }} aria-hidden />
    </div>
  )
}

/* ---------------- history area chart ---------------- */

function HistoryChart({ values, color, colorSoft }: { values: number[]; color: string; colorSoft: string }) {
  const W = 560
  const H = 90
  const min = Math.min(...values) - 2
  const max = Math.max(...values) + 2
  const range = max - min || 1
  const pt = (v: number, i: number): string =>
    `${((i / Math.max(values.length - 1, 1)) * W).toFixed(1)},${(H - 6 - ((v - min) / range) * (H - 14)).toFixed(1)}`
  const line = values.map((v, i) => `${i === 0 ? 'M' : 'L'}${pt(v, i)}`).join(' ')
  const area = `${line} L${W},${H} L0,${H} Z`
  const gid = `hist-${color.replace('#', '')}`
  return (
    <div className="overflow-hidden rounded-2xl p-2" style={{ background: 'rgba(255,255,255,0.5)' }}>
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full" aria-hidden>
        <defs>
          <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor={colorSoft} stopOpacity="0.4" />
            <stop offset="1" stopColor={colorSoft} stopOpacity="0.02" />
          </linearGradient>
        </defs>
        <path d={area} fill={`url(#${gid})`} />
        <path d={line} fill="none" stroke={color} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    </div>
  )
}
