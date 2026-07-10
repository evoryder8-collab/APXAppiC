/*
 * Guided Workout Player, the friction killer. Runs the whole session as a
 * timeline: warmup, set, rest, log, done. Rep cadence with voice + ticks,
 * breathing rest ring, checkpoint scrubber, fused 2-tap logging, guardian.
 */
import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { AnimatePresence, motion } from 'framer-motion'
import { ACCENTS, type Accent } from '../lib/theme'
import type { ProgramSlug } from '../lib/types'
import { useStore } from '../store/AppStore'
import { planForDate, type PlannedExercise } from '../lib/plan'
import { buildTimeline, plannedSetCount, type Block } from '../lib/playerTimeline'
import { guardianCheck, recommendLoad, type Recommendation } from '../lib/progression'
import { speak, stopSpeech, tick } from '../lib/audio'
import { currentStreak } from '../lib/streak'
import { AccentChip, GradientButton, GhostButton, Sheet, EASE } from '../components/ui'

const PERSIST_KEY = 'apex.player.v1'

interface SetResult {
  reps: number | null
  rir: number | null
  skipped: boolean
}

interface ExerciseResult {
  weight: number | null
  override: boolean
  sets: SetResult[]
  skippedAll: boolean
}

interface PlayerState {
  idx: number
  paused: boolean
  elapsed: number // seconds inside the current block
  results: Record<number, ExerciseResult>
  countedReps: Record<string, number> // `${exIdx}-${setNo}` -> reps counted by cadence
  startedAt: string
}

type Action =
  | { type: 'tick'; dt: number }
  | { type: 'jump'; idx: number }
  | { type: 'pause'; paused: boolean }
  | { type: 'extend'; seconds: number }
  | { type: 'endSet'; key: string; reps: number }
  | { type: 'saveLog'; exIdx: number; result: ExerciseResult }
  | { type: 'restore'; state: PlayerState }

function reducer(state: PlayerState, action: Action): PlayerState {
  switch (action.type) {
    case 'tick':
      return state.paused ? state : { ...state, elapsed: state.elapsed + action.dt }
    case 'jump':
      return { ...state, idx: action.idx, elapsed: 0, paused: false }
    case 'pause':
      return { ...state, paused: action.paused }
    case 'extend':
      /* pushing elapsed back extends the remaining countdown */
      return { ...state, elapsed: state.elapsed - action.seconds }
    case 'endSet':
      return { ...state, countedReps: { ...state.countedReps, [action.key]: action.reps } }
    case 'saveLog':
      return { ...state, results: { ...state.results, [action.exIdx]: action.result } }
    case 'restore':
      return action.state
    default:
      return state
  }
}

export function Player() {
  const { slug = 'transition', date = '' } = useParams<{ slug: ProgramSlug; date: string }>()
  const [params] = useSearchParams()
  const lite = params.get('lite') === '1'
  const navigate = useNavigate()
  const { data, upsert, toast } = useStore()

  const accent: Accent = slug === 'main' ? ACCENTS.violet : ACCENTS.teal
  const plan = useMemo(() => planForDate(data, slug as ProgramSlug, date, lite), [data, slug, date, lite])
  const blocks = useMemo(() => buildTimeline(plan), [plan])

  const [state, dispatch] = useReducer(reducer, null, (): PlayerState => {
    try {
      const saved = JSON.parse(localStorage.getItem(PERSIST_KEY) ?? 'null') as
        | (PlayerState & { slug: string; date: string; lite: boolean })
        | null
      if (saved && saved.slug === slug && saved.date === date && saved.lite === lite) {
        return { idx: saved.idx, paused: true, elapsed: 0, results: saved.results, countedReps: saved.countedReps, startedAt: saved.startedAt }
      }
    } catch {
      /* fresh start */
    }
    return { idx: 0, paused: false, elapsed: 0, results: {}, countedReps: {}, startedAt: new Date().toISOString() }
  })

  /* persist on change so backgrounding mid-session loses nothing */
  useEffect(() => {
    localStorage.setItem(
      PERSIST_KEY,
      JSON.stringify({ ...state, slug, date, lite }),
    )
  }, [state, slug, date, lite])

  const block: Block | undefined = blocks[state.idx]
  const voiceOn = data.settings?.voice_on ?? true
  const ticksOn = data.settings?.ticks_on ?? true
  const [voice, setVoice] = useState(voiceOn)
  const [ticks, setTicks] = useState(ticksOn)

  /* announced rep tracker to fire voice/tick exactly once per rep */
  const lastRep = useRef(0)
  const announcedBlock = useRef(-1)

  const advance = useCallback(() => {
    lastRep.current = 0
    dispatch({ type: 'jump', idx: Math.min(state.idx + 1, blocks.length - 1) })
  }, [state.idx, blocks.length])

  /* engine tick */
  useEffect(() => {
    const id = window.setInterval(() => dispatch({ type: 'tick', dt: 0.1 }), 100)
    return () => window.clearInterval(id)
  }, [])

  /* block entry announcements */
  useEffect(() => {
    if (!block || announcedBlock.current === state.idx) return
    announcedBlock.current = state.idx
    lastRep.current = 0
    if (block.kind === 'set' && voice) {
      speak(`${block.exercise.name}. Set ${block.setNo} of ${block.totalSets}.`)
    } else if (block.kind === 'warmup' && voice) {
      speak('Warm up. Band pull aparts, three sets of twenty.')
    } else if (block.kind === 'done') {
      stopSpeech()
    }
  }, [state.idx, block, voice])

  /* cadence + auto-advance */
  useEffect(() => {
    if (!block || state.paused) return
    if (block.kind === 'warmup') {
      if (state.elapsed >= block.duration) advance()
      return
    }
    if (block.kind === 'rest') {
      const remaining = block.duration - state.elapsed
      if (ticks && remaining <= 3.05 && remaining > 0 && Math.abs(remaining % 1) < 0.11) tick('accent')
      if (remaining <= 0) {
        if (voice) speak(`Rest over. ${block.nextLabel}.`)
        advance()
      }
      return
    }
    if (block.kind === 'set') {
      if (block.timed != null) {
        if (state.elapsed >= block.timed) {
          dispatch({ type: 'endSet', key: `${block.exIdx}-${block.setNo}`, reps: block.timed })
          advance()
        }
        return
      }
      const rep = Math.floor(state.elapsed / block.repDuration) + 1
      const target = block.targetReps
      if (rep !== lastRep.current && state.elapsed > 0.1) {
        lastRep.current = rep
        if (target == null || rep <= target) {
          if (ticks) tick('accent')
          if (voice) speak(String(rep))
        }
      }
      if (target != null && state.elapsed >= target * block.repDuration + 0.3) {
        dispatch({ type: 'endSet', key: `${block.exIdx}-${block.setNo}`, reps: target })
        advance()
      }
    }
  }, [state.elapsed, state.paused, block, advance, voice, ticks])

  /* stop speech on unmount */
  useEffect(() => () => stopSpeech(), [])

  /* -------- logging -------- */
  const [guardian, setGuardian] = useState<{ entered: number; safe: number; exIdx: number } | null>(null)

  const recFor = useCallback(
    (exIdx: number): Recommendation | null => {
      const e = plan.exercises[exIdx]
      if (!e || e.increment_kg === 0 || e.swapped || e.id.startsWith('addon')) return null
      const real = data.exercises.find((x) => x.id === e.id)
      return real ? recommendLoad(data, real) : null
    },
    [plan.exercises, data],
  )

  const saveExerciseLog = (exIdx: number, weight: number | null, rir: number | null, repsBySet: Array<number | null>, skippedAll: boolean, override: boolean): void => {
    const e = plan.exercises[exIdx]
    dispatch({
      type: 'saveLog',
      exIdx,
      result: {
        weight,
        override,
        skippedAll,
        sets: repsBySet.map((r) => ({ reps: skippedAll ? null : r, rir, skipped: skippedAll })),
      },
    })
    if (voice && !skippedAll) speak(`${e.name} logged.`)
    advance()
  }

  /* -------- finish -------- */
  const finished = block?.kind === 'done'
  const savedRef = useRef(false)
  const [summary, setSummary] = useState<{ quality: number; streak: number; deltas: string[] } | null>(null)

  useEffect(() => {
    if (!finished || savedRef.current || !plan.programDay) return
    savedRef.current = true

    const planned = plannedSetCount(plan)
    let completed = 0
    for (let i = 0; i < plan.exercises.length; i++) {
      const r = state.results[i]
      if (!r || r.skippedAll) continue
      completed += r.sets.filter((s) => !s.skipped).length
    }
    const quality = planned > 0 ? Math.min(1, completed / planned) : 1

    const sessionId = crypto.randomUUID()
    upsert('workout_sessions', {
      id: sessionId,
      user_id: data.profile?.user_id ?? '',
      date,
      program_day_id: plan.programDay.id,
      is_lite: lite,
      is_deload: plan.isDeload,
      is_event_recovery: plan.isRecoveryMicro,
      completed: true,
      quality_score: Math.round(quality * 100) / 100,
      started_at: state.startedAt,
      completed_at: new Date().toISOString(),
      notes: '',
    })
    plan.exercises.forEach((e, exIdx) => {
      const r = state.results[exIdx]
      const isRealExercise = data.exercises.some((x) => x.id === e.id)
      const setCount = e.planned_sets
      for (let setNo = 1; setNo <= setCount; setNo++) {
        const sr = r?.sets[setNo - 1]
        upsert('workout_logs', {
          id: crypto.randomUUID(),
          user_id: data.profile?.user_id ?? '',
          session_id: sessionId,
          exercise_id: isRealExercise ? e.id : null,
          exercise_name: e.name,
          set_no: setNo,
          weight_kg: r?.skippedAll ? null : (r?.weight ?? null),
          reps: r?.skippedAll ? null : (sr?.reps ?? state.countedReps[`${exIdx}-${setNo}`] ?? null),
          rir: r?.skippedAll ? null : (sr?.rir ?? null),
          skipped: r?.skippedAll ?? !r,
          override_flag: r?.override ?? false,
          created_at: new Date().toISOString(),
        })
      }
    })
    localStorage.removeItem(PERSIST_KEY)

    const t = plan.programDay.day_type
    const deltas =
      plan.isRecoveryMicro
        ? ['+Joint Health', '+Consistency']
        : t === 't25'
          ? ['+Endurance & VO2max', '+Consistency']
          : t === 'mobility' || t === 'fix'
            ? ['+Flexibility', '+Joint Health', '+Consistency']
            : t === 'legs_a' || t === 'legs_b'
              ? ['+Strength (legs, 1.25x boost)', '+Consistency']
              : ['+Strength (upper)', '+Consistency']
    if (plan.isDeload) deltas.unshift('+Joint Health (deload honored)')

    setSummary({ quality, streak: currentStreak({ ...data }, date) + 1, deltas })
    toast('Session saved', 'ok')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [finished])

  if (!plan.programDay || blocks.length <= 2) {
    return (
      <div className="mx-auto w-full max-w-md pt-10 text-center">
        <p className="font-display text-lg font-bold text-ink">Nothing to play today</p>
        <GhostButton className="mt-4" onClick={() => navigate(-1)}>
          Back
        </GhostButton>
      </div>
    )
  }

  const progress = Math.min(1, state.idx / (blocks.length - 1))

  return (
    <div className="mx-auto flex w-full max-w-xl flex-col" style={{ minHeight: 'calc(100dvh - 8rem)' }}>
      {/* header: progress + controls */}
      <div className="mb-4">
        <div className="flex items-center justify-between gap-3">
          <button type="button" onClick={() => navigate(-1)} className="text-sm font-bold text-ink-soft">
            ← Exit
          </button>
          <p className="min-w-0 truncate font-display text-sm font-bold text-ink">
            {plan.programDay.name}
            {lite ? ' · Lite' : ''}
          </p>
          <div className="flex gap-1.5">
            <button
              type="button"
              onClick={() => setVoice((v) => !v)}
              className="glass rounded-full px-2.5 py-1 text-[11px] font-bold"
              style={{ color: voice ? accent.deep : '#9a9aa4' }}
            >
              VOICE
            </button>
            <button
              type="button"
              onClick={() => setTicks((v) => !v)}
              className="glass rounded-full px-2.5 py-1 text-[11px] font-bold"
              style={{ color: ticks ? accent.deep : '#9a9aa4' }}
            >
              TICKS
            </button>
          </div>
        </div>
        <div className="mt-3 h-2 overflow-hidden rounded-full bg-ink/8">
          <motion.div
            className="h-full rounded-full"
            style={{ background: accent.gradient }}
            animate={{ width: `${progress * 100}%` }}
            transition={{ duration: 0.4, ease: EASE }}
          />
        </div>
      </div>

      {/* current block */}
      <div className="flex flex-1 items-center justify-center py-2">
        <AnimatePresence mode="wait">
          <motion.div
            key={state.idx}
            initial={{ opacity: 0, y: 18, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -12, scale: 0.98 }}
            transition={{ duration: 0.25, ease: EASE }}
            className="w-full"
          >
            {block && (
              <BlockView
                block={block}
                accent={accent}
                elapsed={state.elapsed}
                paused={state.paused}
                counted={state.countedReps}
                onPause={(p) => dispatch({ type: 'pause', paused: p })}
                onSkipRest={advance}
                onExtendRest={() => dispatch({ type: 'extend', seconds: 30 })}
                onEndMaxSet={(reps) => {
                  dispatch({ type: 'endSet', key: `${block.kind === 'set' ? `${block.exIdx}-${block.setNo}` : ''}`, reps })
                  advance()
                }}
                recFor={recFor}
                onSaveLog={saveExerciseLog}
                guardian={guardian}
                setGuardian={setGuardian}
                guardianFactor={data.settings?.guardian_factor ?? 1.5}
                summary={summary}
                onFinishExit={() => navigate(-1)}
              />
            )}
          </motion.div>
        </AnimatePresence>
      </div>

      {/* checkpoint scrubber */}
      <div className="mt-4 overflow-x-auto pb-2" role="navigation" aria-label="Session checkpoints">
        <div className="flex min-w-max items-center gap-1.5 px-1">
          {blocks.map((b, i) => {
            const active = i === state.idx
            const past = i < state.idx
            let label = ''
            if (b.kind === 'warmup') label = 'W'
            else if (b.kind === 'set') label = String(b.setNo)
            else if (b.kind === 'log') label = '✓'
            else if (b.kind === 'done') label = '🏁'
            if (b.kind === 'rest') {
              return <span key={i} className="h-1 w-3 shrink-0 rounded-full" style={{ background: past ? accent.bright : 'rgba(26,26,34,0.12)' }} />
            }
            return (
              <button
                key={i}
                type="button"
                onClick={() => dispatch({ type: 'jump', idx: i })}
                aria-label={`Checkpoint ${i + 1}`}
                className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full font-mono text-[11px] font-bold transition-all active:scale-90 ${active ? 'breathe' : ''}`}
                style={
                  active
                    ? ({ background: accent.gradient, color: '#fff', '--glow-soft': accent.glowSoft, '--glow-strong': accent.glowStrong } as React.CSSProperties)
                    : past
                      ? { background: accent.wash, color: accent.deep, border: `1px solid ${accent.glowSoft}` }
                      : { background: 'rgba(255,255,255,0.6)', color: '#9a9aa4', border: '1px solid rgba(26,26,34,0.08)' }
                }
              >
                {label}
              </button>
            )
          })}
        </div>
      </div>
    </div>
  )
}

/* ================= block views ================= */

function BlockView(props: {
  block: Block
  accent: Accent
  elapsed: number
  paused: boolean
  counted: Record<string, number>
  onPause: (p: boolean) => void
  onSkipRest: () => void
  onExtendRest: () => void
  onEndMaxSet: (reps: number) => void
  recFor: (exIdx: number) => Recommendation | null
  onSaveLog: (exIdx: number, weight: number | null, rir: number | null, reps: Array<number | null>, skippedAll: boolean, override: boolean) => void
  guardian: { entered: number; safe: number; exIdx: number } | null
  setGuardian: (g: { entered: number; safe: number; exIdx: number } | null) => void
  guardianFactor: number
  summary: { quality: number; streak: number; deltas: string[] } | null
  onFinishExit: () => void
}) {
  const { block, accent } = props

  if (block.kind === 'warmup') {
    const remaining = Math.max(0, block.duration - props.elapsed)
    return (
      <CenterCard accent={accent}>
        <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">Warm-up</p>
        <p className="mt-2 text-[15px] leading-relaxed font-semibold text-ink">{block.text}</p>
        <p className="mt-4 font-mono text-5xl font-bold" style={{ color: accent.deep }}>
          {Math.ceil(remaining)}s
        </p>
        <div className="mt-5 flex justify-center gap-2">
          <PauseButton paused={props.paused} onPause={props.onPause} accent={accent} />
          <GhostButton onClick={props.onSkipRest}>Skip</GhostButton>
        </div>
      </CenterCard>
    )
  }

  if (block.kind === 'set') {
    const e = block.exercise
    if (block.timed != null) {
      const remaining = Math.max(0, block.timed - props.elapsed)
      return (
        <CenterCard accent={accent}>
          <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">
            {e.name} · {block.setNo}/{block.totalSets}
          </p>
          <RestRing accent={accent} remaining={remaining} total={block.timed} label="hold" />
          <div className="mt-4 flex justify-center gap-2">
            <PauseButton paused={props.paused} onPause={props.onPause} accent={accent} />
            <GhostButton onClick={props.onSkipRest}>Done</GhostButton>
          </div>
        </CenterCard>
      )
    }
    const rep = Math.min(
      block.targetReps ?? 999,
      Math.floor(props.elapsed / block.repDuration) + 1,
    )
    return (
      <CenterCard accent={accent}>
        <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">
          Set {block.setNo} of {block.totalSets}
          {e.per_side ? ' · per side' : ''}
        </p>
        <h2 className="mt-1 font-display text-2xl leading-tight font-bold text-ink">{e.name}</h2>
        {e.tempo_note && <p className="mt-1 text-xs font-semibold text-ink-soft">{e.tempo_note}</p>}
        <div className="my-5">
          <motion.p
            key={rep}
            initial={{ scale: 0.8, opacity: 0.6 }}
            animate={{ scale: 1, opacity: 1 }}
            className="font-mono text-7xl font-bold"
            style={{ color: accent.deep }}
          >
            {rep}
          </motion.p>
          <p className="font-mono text-sm font-semibold text-ink-faint">
            {block.targetReps != null ? `of ${block.targetReps}` : 'to failure, tap done'}
          </p>
        </div>
        <div className="flex justify-center gap-2">
          <PauseButton paused={props.paused} onPause={props.onPause} accent={accent} />
          {block.targetReps == null && (
            <GradientButton accent={accent} onClick={() => props.onEndMaxSet(rep)}>
              Done at {rep}
            </GradientButton>
          )}
        </div>
      </CenterCard>
    )
  }

  if (block.kind === 'rest') {
    const remaining = Math.max(0, block.duration - props.elapsed)
    return (
      <CenterCard accent={accent}>
        <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">Rest</p>
        <RestRing accent={accent} remaining={remaining} total={block.duration} label={`next: ${block.nextLabel}`} />
        <div className="mt-4 flex justify-center gap-2">
          <GhostButton onClick={props.onExtendRest}>+30s</GhostButton>
          <GradientButton accent={accent} onClick={props.onSkipRest}>
            Skip
          </GradientButton>
        </div>
      </CenterCard>
    )
  }

  if (block.kind === 'log') {
    return <LogCard {...props} exIdx={block.exIdx} exercise={block.exercise} />
  }

  /* done */
  return (
    <CenterCard accent={accent}>
      <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">Session complete</p>
      {props.summary && (
        <>
          <p className="mt-3 font-mono text-6xl font-bold" style={{ color: accent.deep }}>
            {(props.summary.quality * 100).toFixed(0)}%
          </p>
          <p className="mt-1 text-sm font-semibold text-ink-soft">plan quality</p>
          <div className="mt-4 flex flex-wrap justify-center gap-1.5">
            <AccentChip accent={accent} solid>
              🔥 {props.summary.streak} DAY STREAK
            </AccentChip>
            {props.summary.deltas.map((d) => (
              <AccentChip key={d} accent={ACCENTS.emerald}>
                {d.toUpperCase()}
              </AccentChip>
            ))}
          </div>
        </>
      )}
      <div className="mt-6">
        <GradientButton accent={accent} onClick={props.onFinishExit} className="w-full">
          Back to calendar
        </GradientButton>
      </div>
    </CenterCard>
  )
}

function CenterCard({ accent, children }: { accent: Accent; children: React.ReactNode }) {
  return (
    <div
      className="glass breathe rounded-3xl p-6 text-center sm:p-8"
      style={{ '--glow-soft': accent.glowSoft, '--glow-strong': accent.glowStrong } as React.CSSProperties}
    >
      {children}
    </div>
  )
}

function PauseButton({ paused, onPause, accent }: { paused: boolean; onPause: (p: boolean) => void; accent: Accent }) {
  return paused ? (
    <GradientButton accent={accent} onClick={() => onPause(false)}>
      Resume
    </GradientButton>
  ) : (
    <GhostButton onClick={() => onPause(true)}>Pause</GhostButton>
  )
}

function RestRing({ accent, remaining, total, label }: { accent: Accent; remaining: number; total: number; label: string }) {
  const frac = total > 0 ? remaining / total : 0
  const R = 64
  const C = 2 * Math.PI * R
  return (
    <div className="relative mx-auto mt-4 h-40 w-40">
      <svg viewBox="0 0 160 160" className="h-full w-full -rotate-90">
        <circle cx="80" cy="80" r={R} fill="none" stroke="rgba(26,26,34,0.08)" strokeWidth="10" />
        <circle
          cx="80"
          cy="80"
          r={R}
          fill="none"
          stroke={accent.bright}
          strokeWidth="10"
          strokeLinecap="round"
          strokeDasharray={C}
          strokeDashoffset={C * (1 - frac)}
          style={{ filter: `drop-shadow(0 0 10px ${accent.glowStrong})`, transition: 'stroke-dashoffset 0.15s linear' }}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <p className="font-mono text-4xl font-bold" style={{ color: accent.deep }}>
          {Math.ceil(remaining)}
        </p>
        <p className="max-w-[7.5rem] truncate text-[10px] font-semibold text-ink-faint">{label}</p>
      </div>
    </div>
  )
}

/* ---------------- 2-tap log ---------------- */

function LogCard(props: {
  exIdx: number
  exercise: PlannedExercise
  accent: Accent
  counted: Record<string, number>
  recFor: (exIdx: number) => Recommendation | null
  onSaveLog: (exIdx: number, weight: number | null, rir: number | null, reps: Array<number | null>, skippedAll: boolean, override: boolean) => void
  guardian: { entered: number; safe: number; exIdx: number } | null
  setGuardian: (g: { entered: number; safe: number; exIdx: number } | null) => void
  guardianFactor: number
}) {
  const { exIdx, exercise: e, accent } = props
  const rec = props.recFor(exIdx)
  const [weight, setWeight] = useState<number | null>(rec?.weight ?? null)
  const [rir, setRir] = useState<number | null>(1)
  const [reps, setReps] = useState<Array<number | null>>(() =>
    [...Array(e.planned_sets)].map((_, i) => props.counted[`${exIdx}-${i + 1}`] ?? (e.rep_unit === 'reps' ? Math.round((e.rep_min + e.rep_max) / 2) : null)),
  )
  const [overridden, setOverridden] = useState(false)

  const trySave = (): void => {
    if (weight != null && rec) {
      const verdict = guardianCheck(weight, rec, props.guardianFactor)
      if (verdict.triggered && !overridden) {
        props.setGuardian({ entered: weight, safe: verdict.safeLoad, exIdx })
        return
      }
    }
    props.onSaveLog(exIdx, weight, rir, reps, false, overridden)
  }

  return (
    <CenterCard accent={accent}>
      <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">Log it</p>
      <h2 className="mt-1 font-display text-xl font-bold text-ink">{e.name}</h2>
      {rec?.weight != null && (
        <p className="mt-1 text-xs font-semibold" style={{ color: accent.deep }}>
          {rec.reason}
        </p>
      )}

      {e.increment_kg > 0 && (
        <div className="mt-4 flex items-center justify-center gap-3">
          <button type="button" onClick={() => setWeight((w) => Math.max(0, (w ?? 0) - 2.5))} className="glass h-11 w-11 rounded-xl font-mono text-lg font-bold text-ink">
            -
          </button>
          <div>
            <p className="font-mono text-4xl font-bold text-ink">{weight ?? 0}</p>
            <p className="text-[10px] font-bold text-ink-faint">KG</p>
          </div>
          <button type="button" onClick={() => setWeight((w) => (w ?? 0) + 2.5)} className="glass h-11 w-11 rounded-xl font-mono text-lg font-bold text-ink">
            +
          </button>
        </div>
      )}

      <div className="mt-4 space-y-1.5">
        {reps.map((r, i) => (
          <div key={i} className="flex items-center justify-center gap-2 font-mono text-sm font-semibold text-ink-soft">
            <span>Set {i + 1}</span>
            <button type="button" className="glass h-8 w-8 rounded-lg font-bold" onClick={() => setReps((a) => a.map((v, j) => (j === i ? Math.max(0, (v ?? 0) - 1) : v)))}>
              -
            </button>
            <span className="w-8 text-center font-bold text-ink">{r ?? '–'}</span>
            <button type="button" className="glass h-8 w-8 rounded-lg font-bold" onClick={() => setReps((a) => a.map((v, j) => (j === i ? (v ?? 0) + 1 : v)))}>
              +
            </button>
          </div>
        ))}
      </div>

      <div className="mt-4">
        <p className="text-[10px] font-bold tracking-widest text-ink-faint uppercase">Reps in reserve</p>
        <div className="mt-1.5 flex justify-center gap-1.5">
          {[0, 1, 2, 3, 4].map((v) => (
            <button
              key={v}
              type="button"
              onClick={() => setRir(v)}
              className="h-9 w-9 rounded-xl font-mono text-sm font-bold transition-all"
              style={
                rir === v
                  ? { background: accent.gradient, color: '#fff' }
                  : { background: 'rgba(255,255,255,0.6)', color: '#55555f', border: '1px solid rgba(26,26,34,0.08)' }
              }
            >
              {v}
            </button>
          ))}
        </div>
      </div>

      <div className="mt-5 flex gap-2">
        <GhostButton className="flex-1" onClick={() => props.onSaveLog(exIdx, null, null, reps.map(() => null), true, false)}>
          Skipped
        </GhostButton>
        <GradientButton accent={accent} className="flex-[2]" onClick={trySave}>
          Save & continue
        </GradientButton>
      </div>

      {/* Overload Guardian */}
      <Sheet open={props.guardian?.exIdx === exIdx && !!props.guardian} onClose={() => props.setGuardian(null)}>
        {props.guardian && (
          <div>
            <AccentChip accent={ACCENTS.amber} solid>
              OVERLOAD GUARDIAN
            </AccentChip>
            <h3 className="mt-3 font-display text-xl font-bold text-ink">
              {props.guardian.entered} kg is a big jump
            </h3>
            <p className="mt-2 text-sm leading-relaxed font-medium text-ink-soft">
              Muscle strength adapts faster than tendons and connective tissue, whose collagen
              remodels on a weeks-to-months timescale. Sudden load spikes raise tendinopathy and
              strain risk while adding little extra hypertrophy stimulus.
            </p>
            <div className="mt-4 flex gap-2">
              <GradientButton
                accent={ACCENTS.amber}
                className="flex-1"
                onClick={() => {
                  setWeight(props.guardian?.safe ?? weight)
                  props.setGuardian(null)
                }}
              >
                Use {props.guardian.safe} kg
              </GradientButton>
              <GhostButton
                className="flex-1"
                onClick={() => {
                  setOverridden(true)
                  props.setGuardian(null)
                }}
              >
                Override anyway
              </GhostButton>
            </div>
            <p className="mt-2 text-center text-[11px] font-medium text-ink-faint">
              Overrides are logged and ding Joint Health slightly.
            </p>
          </div>
        )}
      </Sheet>
    </CenterCard>
  )
}
