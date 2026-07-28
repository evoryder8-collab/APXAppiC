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
import { buildTimeline, countedRepsForSet, plannedSetCount, type Block } from '../lib/playerTimeline'
import { guardianCheck, recommendLoad, type Recommendation } from '../lib/progression'
import { speak, stopSpeech, tick } from '../lib/audio'
import { currentStreak } from '../lib/streak'
import { AccentChip, GradientButton, GhostButton, Sheet, EASE } from '../components/ui'
import { activityCatalogMap, activityLogFromBlock, emptyActivityBlock } from '../lib/activity'
import { activityLogId } from '../lib/ids'
import { translateInterfaceText, useLanguage } from '../lib/i18n'
import { WorkoutStatsSheet } from '../components/workout/WorkoutStatsSheet'
import { catalogExerciseByName, displayExerciseName } from '../data/exerciseCatalog'
import { isConditioningFocusT25 } from '../lib/focusT25'
import { useFoodStore } from '../store/FoodStore'
import {
  ATHLETE_SUPPORT_PROTOCOLS,
  postWorkoutMealTargetFor,
  powderGramsForProtein,
} from '../lib/personalProtocol'

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
  finalized?: boolean
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
            finalized: existing?.finalized ?? false,
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
  const voiceText = useCallback((value: string) => {
    const exercise = catalogExerciseByName(value)
    return exercise ? displayExerciseName(exercise, language) : translateInterfaceText(value, language)
  }, [language])

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
  const [setAnnouncementReady, setSetAnnouncementReady] = useState(true)
  const [showExerciseList, setShowExerciseList] = useState(false)

  /* announced rep tracker to fire voice/tick exactly once per rep */
  const lastRep = useRef(0)
  const announcedBlock = useRef(-1)
  const announcedRestThirty = useRef(-1)
  const stateIdxRef = useRef(state.idx)
  stateIdxRef.current = state.idx

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
      setSetAnnouncementReady(false)
      const entryIndex = state.idx
      const side = block.side ? ` ${voiceText(block.side === 'left' ? 'Left side' : 'Right side')}.` : ''
      const started = speak(
        `${voiceText(block.exercise.name)}.${side} ${voiceText('Set')} ${block.setNo} ${voiceText('of')} ${block.totalSets}.`,
        language,
        {
          onEnd: () => {
            if (stateIdxRef.current !== entryIndex) return
            dispatch({ type: 'jump', idx: entryIndex })
            setSetAnnouncementReady(true)
          },
        },
      )
      if (!started) setSetAnnouncementReady(true)
    } else if (block.kind === 'set') {
      setSetAnnouncementReady(true)
    } else if (block.kind === 'warmup' && voice) {
      speak(voiceText('Warm up. Get ready for the first exercise.'), language)
    } else if (block.kind === 'side_switch' && voice) {
      speak(`${voiceText('Change legs')}. ${voiceText('Right side')} ${voiceText('in three seconds')}.`, language)
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

  useEffect(() => {
    if (voice) return
    stopSpeech()
    setSetAnnouncementReady(true)
  }, [voice])

  /* cadence + auto-advance */
  useEffect(() => {
    if (!block || state.paused) return
    if (block.kind === 'warmup') {
      if (state.elapsed >= block.duration) advance()
      return
    }
    if (block.kind === 'side_switch') {
      const remaining = block.duration - state.elapsed
      if (ticks && remaining <= 3.05 && remaining > 0 && Math.abs(remaining % 1) < 0.11) tick('accent')
      if (remaining <= 0) advance()
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
        if (block.reviewExercise && !state.results[block.exIdx]?.finalized) return
        if (voice) speak(`${voiceText('Rest over.')} ${voiceText(block.nextLabel)}.`, language)
        advance()
      }
      return
    }
    if (block.kind === 'set') {
      if (!setAnnouncementReady) return
      if (block.timed != null) {
        if (state.elapsed >= block.timed) {
          dispatch({ type: 'endSet', key: block.resultKey, reps: block.timed })
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
        dispatch({ type: 'endSet', key: block.resultKey, reps: target })
        advance()
      }
    }
  }, [state.elapsed, state.paused, state.idx, state.results, block, advance, voice, ticks, voiceText, language, setAnnouncementReady])

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

  const saveExerciseLog = (exIdx: number, weights: Array<number | null>, rir: number | null, repsBySet: Array<number | null>, skippedAll: boolean, override: boolean, advanceAfter = true): void => {
    const e = plan.exercises[exIdx]
    const usableWeights = weights.filter((value): value is number => value != null)
    dispatch({
      type: 'saveLog',
      exIdx,
      result: {
        weight: usableWeights.length > 0 ? Math.max(...usableWeights) : null,
        override,
        skippedAll,
        finalized: true,
        sets: repsBySet.map((r, index) => ({ reps: skippedAll ? null : r, rir, skipped: skippedAll, weight: skippedAll ? null : (weights[index] ?? null) })),
      },
    })
    if (voice && !skippedAll) speak(`${voiceText(e.name)}. ${voiceText('Exercise logged.')}`, language)
    if (advanceAfter || (block?.kind === 'rest' && state.elapsed >= block.duration)) advance()
  }

  /* -------- finish -------- */
  const finished = block?.kind === 'done'
  const savedRef = useRef(false)
  const [summary, setSummary] = useState<{ quality: number; streak: number; deltas: string[]; sessionId: string; completedAt: string } | null>(null)
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
    const completedAt = new Date().toISOString()
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
      completed_at: completedAt,
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
          reps: r?.skippedAll ? null : (sr?.reps ?? countedRepsForSet(state.countedReps, exIdx, setNo, e.per_side) ?? null),
          rir: r?.skippedAll ? null : (sr?.rir ?? null),
          skipped: r?.skippedAll ?? !r,
          override_flag: r?.override ?? false,
          created_at: new Date().toISOString(),
        })
      }
    })

    const completedFocusT25 = plan.exercises.some((exercise, index) =>
      isConditioningFocusT25(exercise.name) && state.results[index] && !state.results[index].skippedAll,
    )
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
    if (completedFocusT25 && dayType !== 't25' && data.profile) {
      const focusType = activityCatalog.get('focus-hiit')
      if (focusType) {
        const focusBlock = {
          ...emptyActivityBlock(
            focusType,
            activityLogId(date, data.profile.user_id, `workout:${sessionId}:focus-t25`),
          ),
          durationMin: 25,
          source: 'workout_module' as const,
          reconciled: true,
        }
        upsert('activity_logs', activityLogFromBlock(focusBlock, data.profile, date, activityCatalog))
      }
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
    if (completedFocusT25 && dayType !== 't25') deltas.push('+Endurance & HIIT')

    setSummary({ quality, streak: currentStreak({ ...data }, date) + 1, deltas, sessionId, completedAt })
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
          <p className="min-w-0 flex-1 text-center font-display text-xs leading-tight font-bold text-ink sm:text-sm">
            {plan.programDay.name}
            {lite ? ' · Lite' : ''}
          </p>
          <div className="flex gap-1.5">
            <button
              type="button"
              onClick={() => setShowExerciseList(true)}
              aria-label={voiceText('Exercise list')}
              className="glass grid h-7 w-7 place-items-center rounded-full font-serif text-sm font-black text-ink"
            >
              i
            </button>
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
                  dispatch({ type: 'endSet', key: block.kind === 'set' ? block.resultKey : '', reps })
                  advance()
                }}
                onConfirmCheck={(exIdx, completed) => saveExerciseLog(exIdx, [null], null, [completed ? 1 : null], !completed, false)}
                recFor={recFor}
                onSaveLog={saveExerciseLog}
                results={state.results}
                onSetWeight={(exIdx, setNo, totalSets, weight) => dispatch({ type: 'recordWeight', exIdx, setNo, totalSets, weight })}
                onSetReps={(exIdx, setNo, reps) => dispatch({ type: 'endSet', key: `${exIdx}-${setNo}`, reps })}
                guardian={guardian}
                setGuardian={setGuardian}
                guardianFactor={data.settings?.guardian_factor ?? 1.5}
                summary={summary}
                sessionDate={date}
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
            else if (b.kind === 'set') label = `${b.setNo}${b.side ? (b.side === 'left' ? 'L' : 'R') : ''}`
            else if (b.kind === 'side_switch') label = '↔'
            else if (b.kind === 'check') label = '✓'
            else if (b.kind === 'log') label = '✓'
            else if (b.kind === 'done') label = '🏁'
            if (b.kind === 'rest' || b.kind === 'side_switch') {
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
      <AnimatePresence>
        {showExerciseList && (
          <motion.div
            className="fixed inset-0 z-[80] grid place-items-center bg-ink/28 px-5 backdrop-blur-sm"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onPointerDown={(event) => {
              if (event.target === event.currentTarget) setShowExerciseList(false)
            }}
          >
            <motion.div
              role="dialog"
              aria-modal="true"
              aria-label={voiceText('Exercise list')}
              initial={{ opacity: 0, y: 12, scale: 0.97 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 8, scale: 0.98 }}
              className="glass w-full max-w-sm rounded-[1.8rem] border border-white/85 p-4 shadow-2xl"
            >
              <div className="flex items-center justify-between gap-3">
                <div>
                  <p className="font-mono text-[9px] font-black tracking-[.16em] text-ink-faint uppercase">{voiceText('Full session')}</p>
                  <h2 className="font-display text-lg font-black text-ink">{plan.programDay.name}</h2>
                </div>
                <button type="button" onClick={() => setShowExerciseList(false)} className="grid h-9 w-9 place-items-center rounded-full bg-ink/6 text-lg font-black text-ink">×</button>
              </div>
              <div className="mt-3 max-h-[52dvh] space-y-2 overflow-y-auto pr-1">
                {plan.exercises.map((exercise, index) => {
                  const activeExercise = block && 'exIdx' in block ? block.exIdx === index : false
                  return (
                    <div
                      key={`${exercise.id}:${index}`}
                      className="flex items-start gap-3 rounded-2xl border p-3"
                      style={{
                        borderColor: activeExercise ? accent.glowStrong : 'rgba(26,26,34,.07)',
                        background: activeExercise ? accent.wash : 'rgba(255,255,255,.58)',
                      }}
                    >
                      <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full font-mono text-[10px] font-black" style={{ background: activeExercise ? accent.gradient : 'rgba(26,26,34,.06)', color: activeExercise ? '#fff' : '#6b6b75' }}>{index + 1}</span>
                      <div className="min-w-0">
                        <p className="font-display text-sm leading-snug font-black text-ink">{voiceText(exercise.name)}</p>
                        <p className="mt-0.5 font-mono text-[9px] font-bold text-ink-faint">
                          {exercise.planned_sets} {voiceText('sets')} · {exercise.rep_min === exercise.rep_max ? exercise.rep_min : `${exercise.rep_min}–${exercise.rep_max}`} {voiceText(exercise.rep_unit)}
                        </p>
                      </div>
                    </div>
                  )
                })}
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
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
  onConfirmCheck: (exIdx: number, completed: boolean) => void
  recFor: (exIdx: number) => Recommendation | null
  onSaveLog: (exIdx: number, weights: Array<number | null>, rir: number | null, reps: Array<number | null>, skippedAll: boolean, override: boolean, advanceAfter?: boolean) => void
  results: Record<number, ExerciseResult>
  onSetWeight: (exIdx: number, setNo: number, totalSets: number, weight: number | null) => void
  onSetReps: (exIdx: number, setNo: number, reps: number) => void
  guardian: { entered: number; safe: number; exIdx: number } | null
  setGuardian: (g: { entered: number; safe: number; exIdx: number } | null) => void
  guardianFactor: number
  summary: { quality: number; streak: number; deltas: string[]; sessionId: string; completedAt: string } | null
  sessionDate: string
  onShowStats: () => void
  onFinishExit: () => void
}) {
  const { block, accent } = props
  const { language } = useLanguage()
  const t = (value: string): string => {
    const exercise = catalogExerciseByName(value)
    return exercise ? displayExerciseName(exercise, language) : translateInterfaceText(value, language)
  }
  const nextLabel = (value: string): string => {
    const setMatch = value.match(/^(.+), set (\d+)$/i)
    return setMatch ? `${t(setMatch[1])}, ${t('Set')} ${setMatch[2]}` : t(value)
  }

  if (block.kind === 'warmup') {
    const remaining = Math.max(0, block.duration - props.elapsed)
    return (
      <CenterCard accent={accent}>
        <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">{t('Warm-up')}</p>
        <p className="mt-2 text-[15px] leading-relaxed font-semibold text-ink">{t(block.text)}</p>
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

  if (block.kind === 'check') {
    const parts = block.exercise.notes.split('|').map((part) => part.trim()).filter(Boolean)
    return (
      <CenterCard accent={accent}>
        <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">{t('Secondary session')}</p>
        <div className="mx-auto mt-4 grid h-20 w-20 place-items-center rounded-full text-4xl text-white shadow-[0_20px_45px_-20px_rgba(13,148,136,.9)]" style={{ background: accent.gradient }}>✓</div>
        <h2 className="mt-4 font-display text-2xl font-bold text-ink">{t(block.exercise.name)}</h2>
        {parts.slice(1).map((part) => <p key={part} className="mt-2 text-sm font-semibold leading-relaxed text-ink-soft">{t(part)}</p>)}
        <div className="mt-6 grid gap-2 sm:grid-cols-2">
          <GradientButton accent={accent} onClick={() => props.onConfirmCheck(block.exIdx, true)}>
            {t('Mark complete')}
          </GradientButton>
          <GhostButton onClick={() => props.onConfirmCheck(block.exIdx, false)}>
            {t('Skip today')}
          </GhostButton>
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
            {t(e.name)} · {block.setNo}/{block.totalSets}
            {block.side ? ` · ${t(block.side === 'left' ? 'Left side' : 'Right side')}` : ''}
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
          {block.side ? ` · ${t(block.side === 'left' ? 'Left side' : 'Right side')}` : ''}
        </p>
        <h2 className="mt-1 font-display text-2xl leading-tight font-bold text-ink">{t(e.name)}</h2>
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
              {t('Done at')} {rep}
            </GradientButton>
          )}
          {block.targetReps != null && (
            <GhostButton onClick={() => props.onEndMaxSet(rep)}>
              {t('End set at')} {rep}
            </GhostButton>
          )}
        </div>
      </CenterCard>
    )
  }

  if (block.kind === 'side_switch') {
    const remaining = Math.max(0, block.duration - props.elapsed)
    return (
      <CenterCard accent={accent}>
        <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">{t('Change legs')}</p>
        <h2 className="mt-2 font-display text-2xl font-black text-ink">{t(block.exercise.name)}</h2>
        <RestRing accent={accent} remaining={remaining} total={block.duration} label={t('Right side')} />
      </CenterCard>
    )
  }

  if (block.kind === 'rest') {
    const remaining = Math.max(0, block.duration - props.elapsed)
    const existing = props.results[block.exIdx]
    const recommendation = props.recFor(block.exIdx)
    const captured = existing?.sets[block.afterSet - 1]?.weight ?? existing?.weight ?? recommendation?.weight ?? null
    const countedReps = countedRepsForSet(props.counted, block.exIdx, block.afterSet, block.exercise.per_side)
      ?? Math.round((block.exercise.rep_min + block.exercise.rep_max) / 2)
    const captureReps = block.exercise.rep_unit === 'reps'
    return (
      <CenterCard accent={accent}>
        <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">{t('Rest')}</p>
        <RestRing accent={accent} remaining={remaining} total={block.duration} label={`${t('next')}: ${nextLabel(block.nextLabel)}`} />
        {!block.reviewExercise && (block.captureLoad || captureReps) && (
          <RestSetCapture
            key={`${block.exIdx}:${block.afterSet}`}
            accent={accent}
            exerciseName={t(block.exercise.name)}
            setNo={block.afterSet}
            weight={captured}
            recommended={recommendation?.weight ?? null}
            captureWeight={block.captureLoad}
            reps={countedReps}
            targetReps={Math.round((block.exercise.rep_min + block.exercise.rep_max) / 2)}
            captureReps={captureReps}
            onWeightChange={(weight) => props.onSetWeight(block.exIdx, block.afterSet, block.exercise.planned_sets, weight)}
            onRepsChange={(reps) => props.onSetReps(block.exIdx, block.afterSet, reps)}
          />
        )}
        {block.reviewExercise && !existing?.finalized && (
          <LogCard
            {...props}
            exIdx={block.exIdx}
            exercise={block.exercise}
            embedded
          />
        )}
        {block.reviewExercise && existing?.finalized && (
          <p className="mx-auto mt-4 max-w-sm rounded-2xl bg-emerald-500/10 px-4 py-3 text-sm font-black text-emerald-800">
            ✓ {t('Exercise saved. Rest continues.')}
          </p>
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
          <PostWorkoutRecoveryPrompt completedAt={props.summary.completedAt} date={props.sessionDate} />
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

function PostWorkoutRecoveryPrompt({ completedAt, date }: { completedAt: string; date: string }) {
  const { language } = useLanguage()
  const { data } = useStore()
  const foodStore = useFoodStore()
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 30_000)
    return () => window.clearInterval(timer)
  }, [])
  const persona = data.profile?.persona
  const day = new Date(`${date}T12:00:00`)
  const weekday = day.getDay() === 0 ? 7 : day.getDay()
  const mealTarget = persona ? postWorkoutMealTargetFor(persona, weekday) : null
  const protocol = persona ? ATHLETE_SUPPORT_PROTOCOLS[persona] : null
  const whey = [...foodStore.foods]
    .filter((food) => food.protein_100 != null && food.protein_100 > 0 && /whey|zer|เวย์/i.test(`${food.name} ${food.brand ?? ''} ${Object.values(food.names_i18n).join(' ')}`))
    .sort((left, right) => Number(/leesport/i.test(`${right.name} ${right.brand ?? ''}`)) - Number(/leesport/i.test(`${left.name} ${left.brand ?? ''}`)))[0]
  const quickProteinTarget = protocol
    ? Math.round((protocol.clusterDextrin.proteinAndCarbProteinG[0] + protocol.clusterDextrin.proteinAndCarbProteinG[1]) / 2)
    : null
  const wheyPowderG = whey?.protein_100 != null && quickProteinTarget != null
    ? powderGramsForProtein(whey.protein_100, quickProteinTarget)
    : null
  const hasSpecificMealTarget = Boolean(!mealTarget?.normalBalancedMeal && mealTarget?.proteinG && mealTarget.carbsG)
  const hasProductLabelCorrection = Boolean(wheyPowderG && whey && quickProteinTarget)
  const text = language === 'ro'
    ? {
        eyebrow: 'RECUPERAREA A ÎNCEPUT',
        title: 'Reîncarcă fără grabă',
        body: mealTarget?.normalBalancedMeal
          ? 'Sesiunea de azi cere o masă normală și echilibrată. Urmează masa planificată.'
          : hasSpecificMealTarget && mealTarget?.proteinG && mealTarget.carbsG
            ? `Ținta mesei după sesiunea de azi: ${mealTarget.proteinG[0]}–${mealTarget.proteinG[1]} g proteine · ${mealTarget.carbsG[0]}–${mealTarget.carbsG[1]} g carbohidrați.`
            : 'Țintește proteine de calitate și carbohidrați potriviți volumului antrenamentului în următoarele două ore.',
        fast: hasProductLabelCorrection && wheyPowderG && whey && quickProteinTarget
          ? `Corecție rapidă după eticheta produsului salvat: ${wheyPowderG} g ${whey.brand || whey.name} oferă aproximativ ${quickProteinTarget} g proteine. Adaugă cluster dextrin doar după deficitul rămas.`
          : 'Rapid: whey isolate cu cluster dextrin când masa planificată este la peste două ore. Altfel, urmează masa planificată.',
        context: 'Dacă urmează alt antrenament greu în mai puțin de patru ore, prioritizează carbohidrații și hidratarea.',
        remaining: 'minute rămase în fereastra principală',
        passed: 'Fereastra de două ore a trecut. Totalul zilei rămâne cel mai important.',
        note: 'Nu este un prag anabolic de la minut la minut.',
      }
    : language === 'th'
      ? {
          eyebrow: 'เริ่มการฟื้นตัวแล้ว',
          title: 'เติมพลังโดยไม่ต้องรีบ',
          body: mealTarget?.normalBalancedMeal
            ? 'วันนี้ให้รับประทานมื้อสมดุลตามแผนตามปกติ'
            : hasSpecificMealTarget && mealTarget?.proteinG && mealTarget.carbsG
              ? `เป้าหมายมื้อหลังการฝึกวันนี้: โปรตีน ${mealTarget.proteinG[0]}–${mealTarget.proteinG[1]} กรัม · คาร์โบไฮเดรต ${mealTarget.carbsG[0]}–${mealTarget.carbsG[1]} กรัม`
              : 'รับโปรตีนคุณภาพและคาร์โบไฮเดรตตามปริมาณการฝึกภายในสองชั่วโมง',
          fast: hasProductLabelCorrection && wheyPowderG && whey && quickProteinTarget
            ? `ตัวเลือกเร็วจากฉลากอาหารที่บันทึกไว้: ${wheyPowderG} กรัม ${whey.brand || whey.name} ให้โปรตีนประมาณ ${quickProteinTarget} กรัม เติมคลัสเตอร์เดกซ์ทรินตามส่วนที่ยังขาดเท่านั้น`
            : 'ถ้ามื้อที่วางแผนไว้อีกเกินสองชั่วโมง ใช้เวย์ไอโซเลตกับคลัสเตอร์เดกซ์ทริน มิฉะนั้นให้กินมื้อที่วางแผนไว้',
          context: 'หากมีการฝึกหนักอีกครั้งภายในสี่ชั่วโมง ให้เน้นคาร์โบไฮเดรตและน้ำ',
          remaining: 'นาทีที่เหลือในช่วงสำคัญ',
          passed: 'ช่วงสองชั่วโมงผ่านไปแล้ว ปริมาณอาหารตลอดวันยังสำคัญที่สุด',
          note: 'นี่ไม่ใช่เส้นตายรายนาที',
        }
      : {
          eyebrow: 'RECOVERY STARTED',
          title: 'Refuel without rushing',
          body: mealTarget?.normalBalancedMeal
            ? 'Today calls for a normal balanced meal. Follow the planned meal.'
            : hasSpecificMealTarget && mealTarget?.proteinG && mealTarget.carbsG
              ? `Today’s post-session meal target: ${mealTarget.proteinG[0]}–${mealTarget.proteinG[1]} g protein · ${mealTarget.carbsG[0]}–${mealTarget.carbsG[1]} g carbohydrate.`
              : 'Aim for quality protein and carbohydrate matched to the session within two hours.',
          fast: hasProductLabelCorrection && wheyPowderG && whey && quickProteinTarget
            ? `Fast correction from the saved product label: ${wheyPowderG} g ${whey.brand || whey.name} provides about ${quickProteinTarget} g protein. Add cluster dextrin only for the remaining gap.`
            : 'If the planned meal is more than two hours away, use whey isolate with cluster dextrin. Otherwise eat the planned meal.',
          context: 'If another hard session starts within four hours, prioritize carbohydrate and hydration.',
          remaining: 'minutes left in the high-value window',
          passed: 'The two-hour window has passed. The full day still matters most.',
          note: 'This is not a minute-by-minute anabolic cliff.',
        }
  const remaining = Math.max(0, Math.ceil((Date.parse(completedAt) + 120 * 60_000 - now) / 60_000))
  return (
    <div className="mt-5 rounded-2xl border border-emerald-200/70 bg-gradient-to-br from-emerald-50/95 to-cyan-50/90 p-4 text-left shadow-[0_18px_42px_-30px_rgba(16,185,129,.75)]">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="font-mono text-[8px] font-black tracking-[.16em] text-emerald-700">{text.eyebrow}</p>
          <h3 className="mt-1 font-display text-lg font-black text-ink">{text.title}</h3>
        </div>
        <div className="shrink-0 rounded-xl bg-white/75 px-2.5 py-2 text-center shadow-sm">
          <p className="font-mono text-xl font-black text-emerald-700">{remaining || '✓'}</p>
          <p className="max-w-16 text-[6px] leading-tight font-black text-ink-faint uppercase">{remaining ? text.remaining : text.passed}</p>
        </div>
      </div>
      <p className="mt-2 text-[11px] leading-relaxed font-bold text-ink">{text.body}</p>
      <p className="mt-2 text-[10px] leading-relaxed font-semibold text-ink-soft">{text.fast}</p>
      <p className="mt-2 text-[9px] leading-relaxed font-semibold text-cyan-800">{text.context}</p>
      <p className="mt-2 text-[8px] font-semibold text-ink-faint">{text.note}</p>
    </div>
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
        <p className="max-w-[8.5rem] px-1 text-center text-[9px] leading-tight font-semibold text-ink-faint">{label}</p>
      </div>
    </div>
  )
}

function RestSetCapture({
  accent,
  exerciseName,
  setNo,
  weight,
  recommended,
  captureWeight,
  reps,
  targetReps,
  captureReps,
  onWeightChange,
  onRepsChange,
}: {
  accent: Accent
  exerciseName: string
  setNo: number
  weight: number | null
  recommended: number | null
  captureWeight: boolean
  reps: number
  targetReps: number
  captureReps: boolean
  onWeightChange: (weight: number | null) => void
  onRepsChange: (reps: number) => void
}) {
  const { language } = useLanguage()
  const t = (text: string): string => translateInterfaceText(text, language)
  const [draft, setDraft] = useState(weight == null ? '' : String(weight))
  const [repDraft, setRepDraft] = useState(String(reps))
  const updateWeight = (next: number | null) => {
    const safe = next == null || !Number.isFinite(next) ? null : Math.max(0, Math.round(next * 2) / 2)
    setDraft(safe == null ? '' : String(safe))
    onWeightChange(safe)
  }
  const updateReps = (next: number) => {
    const safe = Math.max(0, Math.min(999, Math.round(Number.isFinite(next) ? next : 0)))
    setRepDraft(String(safe))
    onRepsChange(safe)
  }

  return (
    <div className="mx-auto mt-4 max-w-sm rounded-[1.4rem] border border-white/85 bg-white/68 p-3 text-left shadow-[0_14px_32px_-24px_rgba(76,29,149,.75)]">
      <div className="flex items-start justify-between gap-2"><div><p className="font-mono text-[8px] font-black tracking-[0.15em] text-violet-700 uppercase">{t('Log this set during the break')}</p><p className="mt-0.5 truncate text-xs font-black text-ink">{exerciseName} · {t('Set')} {setNo}</p></div>{recommended != null && <span className="shrink-0 rounded-full px-2 py-1 font-mono text-[8px] font-black" style={{ background: accent.wash, color: accent.deep }}>{t('Suggested')} {recommended}</span>}</div>
      <div className={`mt-2 grid gap-2 ${captureWeight && captureReps ? 'grid-cols-1 sm:grid-cols-2' : 'grid-cols-1'}`}>
        {captureReps && <div><div className="mb-1 flex items-center justify-between"><span className="font-mono text-[8px] font-black tracking-wide text-ink-faint uppercase">{t('Actual reps')}</span><span className="font-mono text-[8px] font-bold text-ink-faint">{t('Target')} {targetReps}</span></div><div className="grid grid-cols-[2.25rem_minmax(0,1fr)_2.25rem] items-center gap-1.5"><button type="button" onClick={() => updateReps((Number(repDraft) || 0) - 1)} className="grid h-10 place-items-center rounded-xl bg-ink/6 font-mono text-lg font-black text-ink">−</button><input inputMode="numeric" type="number" min="0" value={repDraft} onChange={(event) => { setRepDraft(event.target.value); const parsed = Number(event.target.value); if (Number.isFinite(parsed)) onRepsChange(Math.max(0, Math.round(parsed))) }} onBlur={() => updateReps(Number(repDraft))} className="w-full rounded-xl border border-cyan-200/70 bg-white/90 px-2 py-2 text-center font-mono text-xl font-black text-ink outline-none focus:ring-2 focus:ring-cyan-300" /><button type="button" onClick={() => updateReps((Number(repDraft) || 0) + 1)} className="grid h-10 place-items-center rounded-xl font-mono text-lg font-black text-white" style={{ background: accent.gradient }}>+</button></div></div>}
        {captureWeight && <div><span className="mb-1 block font-mono text-[8px] font-black tracking-wide text-ink-faint uppercase">{t('Weight used')}</span><div className="grid grid-cols-[2.25rem_minmax(5.5rem,1fr)_2.25rem] items-center gap-1.5"><button type="button" onClick={() => updateWeight((Number(draft.replace(',', '.')) || 0) - 2.5)} className="grid h-10 place-items-center rounded-xl bg-ink/6 font-mono text-lg font-black text-ink">−</button><label className="relative min-w-0"><span className="sr-only">{t('Weight used in kilograms')}</span><input inputMode="decimal" type="text" value={draft} onChange={(event) => { const next = event.target.value.replace(/[^\d.,]/g, ''); setDraft(next); const parsed = Number(next.replace(',', '.')); onWeightChange(next === '' || !Number.isFinite(parsed) ? null : parsed) }} onBlur={() => updateWeight(draft === '' ? null : Number(draft.replace(',', '.')))} placeholder="0" className="w-full min-w-0 rounded-xl border border-violet-200/70 bg-white/90 py-2 pr-7 pl-2 text-center font-mono text-xl font-black text-ink outline-none focus:ring-2 focus:ring-violet-300" /><span className="pointer-events-none absolute inset-y-0 right-1.5 flex items-center font-mono text-[8px] font-black text-ink-faint">KG</span></label><button type="button" onClick={() => updateWeight((Number(draft.replace(',', '.')) || 0) + 2.5)} className="grid h-10 place-items-center rounded-xl font-mono text-lg font-black text-white" style={{ background: accent.gradient }}>+</button></div></div>}
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
  onSaveLog: (exIdx: number, weights: Array<number | null>, rir: number | null, reps: Array<number | null>, skippedAll: boolean, override: boolean, advanceAfter?: boolean) => void
  results: Record<number, ExerciseResult>
  guardian: { entered: number; safe: number; exIdx: number } | null
  setGuardian: (g: { entered: number; safe: number; exIdx: number } | null) => void
  guardianFactor: number
  embedded?: boolean
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
    [...Array(e.planned_sets)].map((_, i) => countedRepsForSet(props.counted, exIdx, i + 1, e.per_side) ?? (e.rep_unit === 'reps' ? Math.round((e.rep_min + e.rep_max) / 2) : null)),
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
    props.onSaveLog(exIdx, weights, rir, reps, false, overridden, !props.embedded)
  }

  const content = (
    <>
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
        <GhostButton className="flex-1" onClick={() => props.onSaveLog(exIdx, reps.map(() => null), null, reps.map(() => null), true, false, !props.embedded)}>
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
    </>
  )
  return props.embedded
    ? <div className="mx-auto mt-4 max-h-[45dvh] max-w-sm overflow-y-auto rounded-[1.5rem] border border-white/85 bg-white/72 p-4 text-center shadow-[0_16px_34px_-26px_rgba(76,29,149,.9)]">{content}</div>
    : <CenterCard accent={accent}>{content}</CenterCard>
}
