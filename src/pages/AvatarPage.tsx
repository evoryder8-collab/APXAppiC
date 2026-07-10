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
import { BASELINE, overallOf, whatYourBodyNeeds } from '../lib/rpg'
import type { RpgSnapshot } from '../lib/types'

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

export function AvatarPage() {
  const { data, snapshots } = useStore()
  const navigate = useNavigate()
  const [showBaseline, setShowBaseline] = useState(false)
  const [range, setRange] = useState<30 | 90>(30)
  const [expanded, setExpanded] = useState<string | null>(null)

  const now = snapshots[snapshots.length - 1] ?? null
  const before = snapshots[Math.max(0, snapshots.length - 15)] ?? now
  const advice = useMemo(() => whatYourBodyNeeds(data, snapshots), [data, snapshots])

  if (!now) return null

  const level = Math.floor(now.overall)
  const levelFrac = now.overall - level

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
        {/* Level HUD + radar */}
        <div className="grid gap-4 sm:grid-cols-2">
          <GlassCard accent={emerald} breathe className="flex flex-col items-center justify-center p-6">
            <p className="font-mono text-[11px] font-bold tracking-[0.3em] text-ink-faint uppercase">Level</p>
            <div className="relative my-2">
              <p
                className="font-mono text-7xl font-bold"
                style={{
                  background: 'linear-gradient(135deg, #059669, #34d399)',
                  WebkitBackgroundClip: 'text',
                  WebkitTextFillColor: 'transparent',
                  filter: 'drop-shadow(0 4px 14px rgba(16,185,129,0.35))',
                }}
              >
                {level}
              </p>
            </div>
            <div className="h-2 w-40 overflow-hidden rounded-full bg-ink/8">
              <motion.div
                className="h-full rounded-full"
                style={{ background: emerald.gradient }}
                initial={{ width: 0 }}
                animate={{ width: `${levelFrac * 100}%` }}
                transition={{ duration: 1, ease: EASE }}
              />
            </div>
            <p className="mt-2 font-mono text-[11px] font-semibold text-ink-soft">
              {(levelFrac * 100).toFixed(0)}% to level {level + 1}
            </p>
          </GlassCard>

          <GlassCard accent={emerald} className="p-4">
            <Radar snapshot={now} />
          </GlassCard>
        </div>

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
                        <AccentChip accent={emerald}>{a.stat.toUpperCase()}</AccentChip>
                        <p className="mt-2 text-[15px] leading-snug font-bold text-ink">{a.headline}</p>
                        <p className="mt-1 text-[13px] leading-relaxed font-medium text-ink-soft">
                          {a.detail} {a.prescription}
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
                      <p className="text-sm font-bold text-ink">{s.label}</p>
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
                          ['Upper', now.strength_upper],
                          ['Lower', now.strength_lower],
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
        </GlassCard>

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
                Calibrated for a 34-year-old at 70 kg, 23% body fat, 178 cm, trained but returning
                from a 3-month layoff.
              </li>
              <li>
                <strong className="text-ink">Strength-Upper {BASELINE.strength_upper}:</strong> childhood
                bodybuilding (ages ~11-13) was upper-body only, so the top half starts moderately high.
              </li>
              <li>
                <strong className="text-ink">Strength-Lower {BASELINE.strength_lower}:</strong> legs were
                neglected during growth years and remain undersized relative to the upper body. Leg-day
                XP is permanently weighted 1.25x until the sub-bars converge.
              </li>
              <li>
                <strong className="text-ink">Endurance {BASELINE.endurance}:</strong> modest and
                layoff-adjusted. Aerobic adaptations fade fastest.
              </li>
              <li>
                <strong className="text-ink">Flexibility {BASELINE.flexibility}:</strong> low-moderate,
                priced in from desk and editing hours.
              </li>
              <li>
                <strong className="text-ink">Joint Health {BASELINE.joint}:</strong> moderate. Deloads,
                tapers and honest tempo keep it climbing.
              </li>
              <li>
                <strong className="text-ink">Health {BASELINE.health}:</strong> seeded from current
                logging habits.
              </li>
              <li>
                Overall computes from the weights (Strength 25%, Endurance 20%, Joint 20%, Health 20%,
                Flexibility 15%), starting at {overallOf(BASELINE).toFixed(1)}.
              </li>
            </motion.ul>
          )}
        </GlassCard>
      </div>
    </div>
  )
}

/* ---------------- hexagonal radar ---------------- */

function Radar({ snapshot }: { snapshot: RpgSnapshot }) {
  const axes = [
    { label: 'Health', value: snapshot.health },
    { label: 'Joint', value: snapshot.joint },
    { label: 'Flex', value: snapshot.flexibility },
    { label: 'Endur', value: snapshot.endurance },
    { label: 'Str ↑', value: snapshot.strength_upper },
    { label: 'Str ↓', value: snapshot.strength_lower },
  ]
  const cx = 110
  const cy = 100
  const R = 72

  const point = (i: number, v: number): [number, number] => {
    const angle = (Math.PI / 3) * i - Math.PI / 2
    const r = (v / 100) * R
    return [cx + r * Math.cos(angle), cy + r * Math.sin(angle)]
  }
  const pathFor = (vals: number[]): string =>
    vals.map((v, i) => `${i === 0 ? 'M' : 'L'}${point(i, v)[0].toFixed(1)},${point(i, v)[1].toFixed(1)}`).join(' ') + ' Z'

  const d = pathFor(axes.map((a) => a.value))

  return (
    <svg viewBox="0 0 220 200" className="w-full" role="img" aria-label="Stat radar">
      <defs>
        <linearGradient id="radar-fill" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#34d399" stopOpacity="0.55" />
          <stop offset="1" stopColor="#059669" stopOpacity="0.25" />
        </linearGradient>
      </defs>
      {[0.33, 0.66, 1].map((f) => (
        <path
          key={f}
          d={pathFor(axes.map(() => f * 100))}
          fill="none"
          stroke="rgba(26,26,34,0.1)"
          strokeWidth="1"
        />
      ))}
      {axes.map((_, i) => {
        const [x, y] = point(i, 100)
        return <line key={i} x1={cx} y1={cy} x2={x} y2={y} stroke="rgba(26,26,34,0.08)" strokeWidth="1" />
      })}
      <motion.path
        d={d}
        animate={{ d }}
        transition={{ duration: 0.8, ease: EASE }}
        fill="url(#radar-fill)"
        stroke="#059669"
        strokeWidth="2"
        strokeLinejoin="round"
        style={{ filter: 'drop-shadow(0 4px 10px rgba(16,185,129,0.35))' }}
      />
      {axes.map((a, i) => {
        const [x, y] = point(i, 121)
        return (
          <text
            key={a.label}
            x={x}
            y={y}
            textAnchor="middle"
            dominantBaseline="middle"
            className="fill-ink-soft font-mono text-[9.5px] font-bold"
          >
            {a.label}
          </text>
        )
      })}
    </svg>
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
