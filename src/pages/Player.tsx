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
import { activityCatalogMap, activityLogFromBlock, emptyActivityBlock } from '../lib/activity'
import { activityLogId } from '../lib/ids'
import { translateInterfaceText, useLanguage } from '../lib/i18n'
import { WorkoutStatsSheet } from '../components/workout/WorkoutStatsSheet'

const PERSIST_KEY = 'apex.player.v1'

interface SetResult {
  reps: number | null
  rir: number | null
  skipped: boolean
  weight: number | null
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
  | { type: 'recordWeight'; exIdx: number; setNo: number; totalSets: number; weight: number | null }
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
    case 'recordWeight': {
      const existing = state.results[action.exIdx]
      const sets = [...Array(action.totalSets)].map((_, index) => {
        const current = existing?.sets[index]
        return current
          ? { ...current, weight: current.weight ?? existing?.weight ?? null }
          : { reps: null, rir: null, skipped: false, weight: null }
      })
      sets[action.setNo - 1] = { ...sets[action.setNo - 1], weight: action.weight }
      const weights = sets.map((set) => set.weight).filter((value): value is number => value != null)
      return {
        ...state,
        results: {
          ...state.results,
          [action.exIdx]: {
            weight: weights.length > 0 ? Math.max(...weights) : null,
            override: existing?.override ?? false,
            sets,
            skippedAll: existing?.skippedAll ?? false,
          },
        },
      }
    }
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
  const { language } = useLanguage()
  const voiceText = useCallback((value: string) => translateInterfaceText(value, language), [language])

  const accent: Accent = slug === 'main' || slug === 'custom' ? ACCENTS.violet : ACCENTS.teal
  const plan = useMemo(() => planForDate(data, slug as ProgramSlug, date, lite), [data, slug, date, lite])
  const blocks = useMemo(() => buildTimeline(plan), [plan])

  const [state, dispatch] = useReducer(reducer, null, (): PlayerState => {
    try {
      const saved = JSON.parse(localStorage.getItem(PERSIST_KEY) ?? 'null') as
        | (PlayerState & { slug: string; date: string; lite: boolean })
        | null
      if (saved && saved.slug === slug && saved.date === date && saved.lite === lite) {
        const restoredResults = Object.fromEntries(Object.entries(saved.results ?? {}).map(([key, result]) => [key, {
          ...result,
          sets: (result.sets ?? []).map((set) => ({ ...set, weight: set.weight ?? result.weight ?? null })),
        }]))
        return { idx: saved.idx, paused: true, elapsed: 0, results: restoredResults, countedReps: saved.countedReps, startedAt: saved.startedAt }
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
  const announcedRestThirty = useRef(-1)

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
      speak(`${voiceText(block.exercise.name)}. ${voiceText('Set')} ${block.setNo} ${voiceText('of')} ${block.totalSets}.`, language)
    } else if (block.kind === 'warmup' && voice) {
      speak(voiceText('Warm up. Get ready for the first exercise.'), language)
    } else if (block.kind === 'rest' && voice) {
      if (block.duration <= 30.5) {
        announcedRestThirty.current = state.idx
        speak(`${voiceText('Set finished. Now rest.')} ${block.captureLoad ? `${voiceText('Log the weight used for this set.')} ` : ''}${voiceText('30 seconds left. Prepare for the next set.')}`, language)
      } else {
        speak(`${voiceText('Set finished. Now rest.')} ${block.captureLoad ? voiceText('Log the weight used for this set.') : ''}`.trim(), language)
      }
    } else if (block.kind === 'done') {
      stopSpeech()
    }
  }, [state.idx, block, voice, voiceText, language])

  /* cadence + auto-advance */
  useEffect(() => {
    if (!block || state.paused) return
    if (block.kind === 'warmup') {
      if (state.elapsed >= block.duration) advance()
      return
    }
    if (block.kind === 'rest') {
      const remaining = block.duration - state.elapsed
      if (remaining <= 30.05 && remaining > 29.75 && announcedRestThirty.current !== state.idx) {
        announcedRestThirty.current = state.idx
        if (voice) speak(voiceText('30 seconds left. Prepare for the next set.'), language)
      }
      if (ticks && remaining <= 3.05 && remaining > 0 && Math.abs(remaining % 1) < 0.11) tick('accent')
      if (remaining <= 0) {
        if (voice) speak(`${voiceText('Rest over.')} ${voiceText(block.nextLabel)}.`, language)
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
          if (voice) speak(String(rep), language)
        }
      }
      if (target != null && state.elapsed >= target * block.repDuration + 0.3) {
        dispatch({ type: 'endSet', key: `${block.exIdx}-${block.setNo}`, reps: target })
        advance()
      }
    }
  }, [state.elapsed, state.paused, state.idx, block, advance, voice, ticks, voiceText, language])

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

  const saveExerciseLog = (exIdx: number, weights: Array<number | null>, rir: number | null, repsBySet: Array<number | null>, skippedAll: boolean, override: boolean): void => {
    const e = plan.exercises[exIdx]
    const usableWeights = weights.filter((value): value is number => value != null)
    dispatch({
      type: 'saveLog',
      exIdx,
      result: {
        weight: usableWeights.length > 0 ? Math.max(...usableWeights) : null,
        override,
        skippedAll,
        sets: repsBySet.map((r, index) => ({ reps: skippedAll ? null : r, rir, skipped: skippedAll, weight: skippedAll ? null : (weights[index] ?? null) })),
      },
    })
    if (voice && !skippedAll) speak(`${voiceText(e.name)}. ${voiceText('Exercise logged.')}`, language)
    advance()
  }

  /* -------- finish -------- */
  const finished = block?.kind === 'done'
  const savedRef = useRef(false)
  const [summary, setSummary] = useState<{ quality: number; streak: number; deltas: string[]; sessionId: string } | null>(null)
  const [showStats, setShowStats] = useState(false)

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
          weight_kg: r?.skippedAll ? null : (sr?.weight ?? r?.weight ?? null),
          reps: r?.skippedAll ? null : (sr?.reps ?? state.countedReps[`${exIdx}-${setNo}`] ?? null),
          rir: r?.skippedAll ? null : (sr?.rir ?? null),
          skipped: r?.skippedAll ?? !r,
          override_flag: r?.override ?? false,
          created_at: new Date().toISOString(),
        })
      }
    })

    const dayType = plan.programDay.day_type
    const activityTypeId = dayType === 't25'
      ? 'focus-hiit'
      : dayType === 'mobility' || dayType === 'fix'
        ? 'mobility'
        : 'apex-strength'
    const activityCatalog = activityCatalogMap(data.activity_types)
    const activityType = activityCatalog.get(activityTypeId)
    if (activityType && data.profile) {
      const activityBlock = {
        ...emptyActivityBlock(
          activityType,
          activityLogId(date, data.profile.user_id, `workout:${sessionId}`),
        ),
        durationMin: plan.programDay.est_minutes,
        source: 'workout_module' as const,
        reconciled: true,
      }
      upsert(
        'activity_logs',
        activityLogFromBlock(activityBlock, data.profile, date, activityCatalog),
      )
    }
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

    setSummary({ quality, streak: currentStreak({ ...data }, date) + 1, deltas, sessionId })
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
                results={state.results}
                onSetWeight={(exIdx, setNo, totalSets, weight) => dispatch({ type: 'recordWeight', exIdx, setNo, totalSets, weight })}
                guardian={guardian}
                setGuardian={setGuardian}
                guardianFactor={data.settings?.guardian_factor ?? 1.5}
                summary={summary}
                onShowStats={() => setShowStats(true)}
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
      <WorkoutStatsSheet open={showStats} onClose={() => setShowStats(false)} sessionId={summary?.sessionId ?? null} accent={accent} />
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
  onSaveLog: (exIdx: number, weights: Array<number | null>, rir: number | null, reps: Array<number | null>, skippedAll: boolean, override: boolean) => void
  results: Record<number, ExerciseResult>
  onSetWeight: (exIdx: number, setNo: number, totalSets: number, weight: number | null) => void
  guardian: { entered: number; safe: number; exIdx: number } | null
  setGuardian: (g: { entered: number; safe: number; exIdx: number } | null) => void
  guardianFactor: number
  summary: { quality: number; streak: number; deltas: string[]; sessionId: string } | null
  onShowStats: () => void
  onFinishExit: () => void
}) {
  const { block, accent } = props
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)

  if (block.kind === 'warmup') {
    const remaining = Math.max(0, block.duration - props.elapsed)
    return (
      <CenterCard accent={accent}>
        <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">{t('Warm-up')}</p>
        <p className="mt-2 text-[15px] leading-relaxed font-semibold text-ink">{block.text}</p>
        <p className="mt-4 font-mono text-5xl font-bold" style={{ color: accent.deep }}>
          {Math.ceil(remaining)}s
        </p>
        <div className="mt-5 flex justify-center gap-2">
          <PauseButton paused={props.paused} onPause={props.onPause} accent={accent} />
          <GhostButton onClick={props.onSkipRest}>{t('Skip')}</GhostButton>
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
            <GhostButton onClick={props.onSkipRest}>{t('Done')}</GhostButton>
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
          {t('Set')} {block.setNo} {t('of')} {block.totalSets}
          {e.per_side ? ` · ${t('per side')}` : ''}
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
            {block.targetReps != null ? `${t('of')} ${block.targetReps}` : t('to failure, tap done')}
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
    const existing = props.results[block.exIdx]
    const recommendation = props.recFor(block.exIdx)
    const captured = existing?.sets[block.afterSet - 1]?.weight ?? existing?.weight ?? recommendation?.weight ?? null
    return (
      <CenterCard accent={accent}>
        <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">{t('Rest')}</p>
        <RestRing accent={accent} remaining={remaining} total={block.duration} label={`${t('next')}: ${t(block.nextLabel)}`} />
        {block.captureLoad && (
          <RestLoadCapture
            key={`${block.exIdx}:${block.afterSet}`}
            accent={accent}
            exerciseName={block.exercise.name}
            setNo={block.afterSet}
            value={captured}
            recommended={recommendation?.weight ?? null}
            onChange={(weight) => props.onSetWeight(block.exIdx, block.afterSet, block.exercise.planned_sets, weight)}
          />
        )}
        <div className="mt-4 flex justify-center gap-2">
          <GhostButton onClick={props.onExtendRest}>+30s</GhostButton>
          <GradientButton accent={accent} onClick={props.onSkipRest}>
            {t('Skip')}
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
      <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">{t('Session complete')}</p>
      {props.summary && (
        <>
          <p className="mt-3 font-mono text-6xl font-bold" style={{ color: accent.deep }}>
            {(props.summary.quality * 100).toFixed(0)}%
          </p>
          <p className="mt-1 text-sm font-semibold text-ink-soft">{t('plan quality')}</p>
          <div className="mt-4 flex flex-wrap justify-center gap-1.5">
            <AccentChip accent={accent} solid>
              🔥 {props.summary.streak} {t('day streak').toUpperCase()}
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
        {props.summary && <GhostButton onClick={props.onShowStats} className="mb-2 w-full">{t('Workout stats at a glance')}</GhostButton>}
        <GradientButton accent={accent} onClick={props.onFinishExit} className="w-full">
          {t('Back to calendar')}
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

function RestLoadCapture({
  accent,
  exerciseName,
  setNo,
  value,
  recommended,
  onChange,
}: {
  accent: Accent
  exerciseName: string
  setNo: number
  value: number | null
  recommended: number | null
  onChange: (weight: number | null) => void
}) {
  const { language } = useLanguage()
  const t = (text: string): string => translateInterfaceText(text, language)
  const [draft, setDraft] = useState(value == null ? '' : String(value))
  const update = (next: number | null) => {
    const safe = next == null || !Number.isFinite(next) ? null : Math.max(0, Math.round(next * 2) / 2)
    setDraft(safe == null ? '' : String(safe))
    onChange(safe)
  }

  return (
    <div className="mx-auto mt-4 max-w-sm rounded-[1.4rem] border border-white/85 bg-white/68 p-3 text-left shadow-[0_14px_32px_-24px_rgba(76,29,149,.75)]">
      <div className="flex items-start justify-between gap-2"><div><p className="font-mono text-[8px] font-black tracking-[0.15em] text-violet-700 uppercase">{t('Log this set during the break')}</p><p className="mt-0.5 truncate text-xs font-black text-ink">{exerciseName} · {t('Set')} {setNo}</p></div>{recommended != null && <span className="shrink-0 rounded-full px-2 py-1 font-mono text-[8px] font-black" style={{ background: accent.wash, color: accent.deep }}>{t('Suggested')} {recommended}</span>}</div>
      <div className="mt-2 grid grid-cols-[2.5rem_minmax(0,1fr)_2.5rem] items-center gap-2">
        <button type="button" onClick={() => update((Number(draft.replace(',', '.')) || 0) - 2.5)} className="grid h-10 place-items-center rounded-xl bg-ink/6 font-mono text-lg font-black text-ink">−</button>
        <label className="relative"><span className="sr-only">{t('Weight used in kilograms')}</span><input autoFocus inputMode="decimal" type="text" value={draft} onChange={(event) => { const next = event.target.value.replace(/[^\d.,]/g, ''); setDraft(next); const parsed = Number(next.replace(',', '.')); onChange(next === '' || !Number.isFinite(parsed) ? null : parsed) }} onBlur={() => update(draft === '' ? null : Number(draft.replace(',', '.')))} placeholder="0" className="w-full rounded-xl border border-violet-200/70 bg-white/90 px-9 py-2 text-center font-mono text-2xl font-black text-ink outline-none focus:ring-2 focus:ring-violet-300" /><span className="pointer-events-none absolute inset-y-0 right-2 flex items-center font-mono text-[9px] font-black text-ink-faint">KG</span></label>
        <button type="button" onClick={() => update((Number(draft.replace(',', '.')) || 0) + 2.5)} className="grid h-10 place-items-center rounded-xl font-mono text-lg font-black text-white" style={{ background: accent.gradient }}>+</button>
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
  onSaveLog: (exIdx: number, weights: Array<number | null>, rir: number | null, reps: Array<number | null>, skippedAll: boolean, override: boolean) => void
  results: Record<number, ExerciseResult>
  guardian: { entered: number; safe: number; exIdx: number } | null
  setGuardian: (g: { entered: number; safe: number; exIdx: number } | null) => void
  guardianFactor: number
}) {
  const { exIdx, exercise: e, accent } = props
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const rec = props.recFor(exIdx)
  const existing = props.results[exIdx]
  const [weights, setWeights] = useState<Array<number | null>>(() =>
    [...Array(e.planned_sets)].map((_, index) => existing?.sets[index]?.weight ?? existing?.weight ?? rec?.weight ?? null),
  )
  const [rir, setRir] = useState<number | null>(1)
  const [reps, setReps] = useState<Array<number | null>>(() =>
    [...Array(e.planned_sets)].map((_, i) => props.counted[`${exIdx}-${i + 1}`] ?? (e.rep_unit === 'reps' ? Math.round((e.rep_min + e.rep_max) / 2) : null)),
  )
  const [overridden, setOverridden] = useState(false)

  const trySave = (): void => {
    const entered = Math.max(0, ...weights.filter((value): value is number => value != null))
    if (entered > 0 && rec) {
      const verdict = guardianCheck(entered, rec, props.guardianFactor)
      if (verdict.triggered && !overridden) {
        props.setGuardian({ entered, safe: verdict.safeLoad, exIdx })
        return
      }
    }
    props.onSaveLog(exIdx, weights, rir, reps, false, overridden)
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

      {e.increment_kg > 0 && <p className="mt-3 rounded-xl bg-violet-500/8 px-3 py-2 text-[10px] font-semibold text-violet-800">{t('Loads were captured during each rest. Correct any set below before saving.')}</p>}

      <div className="mt-4 space-y-2">
        {reps.map((r, i) => (
          <div key={i} className="grid grid-cols-[3.2rem_minmax(0,1fr)_auto] items-center gap-2 rounded-2xl bg-white/55 p-2 font-mono text-xs font-semibold text-ink-soft">
            <span>Set {i + 1}</span>
            {e.increment_kg > 0 ? <label className="relative min-w-0"><input aria-label={`Set ${i + 1} weight in kilograms`} inputMode="decimal" type="number" min="0" step="0.5" value={weights[i] ?? ''} onChange={(event) => setWeights((current) => current.map((value, index) => index === i ? (event.target.value === '' ? null : Number(event.target.value)) : value))} className="w-full rounded-xl border border-white/80 bg-white/85 py-2 pr-8 pl-2 text-right font-mono text-sm font-black text-ink outline-none focus:ring-2 focus:ring-violet-300" /><span className="pointer-events-none absolute inset-y-0 right-2 flex items-center text-[8px] font-black text-ink-faint">KG</span></label> : <span />}
            <div className="flex items-center gap-1"><button type="button" className="glass h-8 w-8 rounded-lg font-bold" onClick={() => setReps((a) => a.map((v, j) => (j === i ? Math.max(0, (v ?? 0) - 1) : v)))}>-</button><span className="w-7 text-center font-bold text-ink">{r ?? '–'}</span><button type="button" className="glass h-8 w-8 rounded-lg font-bold" onClick={() => setReps((a) => a.map((v, j) => (j === i ? (v ?? 0) + 1 : v)))}>+</button></div>
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
        <GhostButton className="flex-1" onClick={() => props.onSaveLog(exIdx, reps.map(() => null), null, reps.map(() => null), true, false)}>
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
                  setWeights((current) => current.map((value) => value != null && value > (props.guardian?.safe ?? value) ? (props.guardian?.safe ?? value) : value))
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
