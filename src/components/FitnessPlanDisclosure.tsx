import { AnimatePresence, motion, useReducedMotion } from 'framer-motion'
import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  collapsedFitnessPlanDisclosure,
  recordFitnessPlanIntroPresentation,
  selectFitnessPlanInfo,
  toggleFitnessPlanDisclosure,
  type FitnessPlanPhase,
} from '../lib/fitnessPlanDisclosure.ts'
import { ACCENTS } from '../lib/theme'
import { BoltIcon, DumbbellIcon, TransitionIcon } from './Icons'

interface FitnessPlanDisclosureProps {
  introSeen: boolean
  onIntroSeen: () => void
  transitionTitle: string
  mainTitle: string
  text: (value: string) => string
}

interface PhasePresentation {
  phase: FitnessPlanPhase
  title: string
  introduction: string
  introductionFull: string
  information: string
  destination: string
}

const EASE = [0.22, 1, 0.36, 1] as const

export function FitnessPlanDisclosure({
  introSeen,
  onIntroSeen,
  transitionTitle,
  mainTitle,
  text,
}: FitnessPlanDisclosureProps) {
  const navigate = useNavigate()
  const reducedMotion = useReducedMotion() ?? false
  const wrapper = useRef<HTMLElement>(null)
  const persistedThisExpansion = useRef(false)
  const [state, setState] = useState(collapsedFitnessPlanDisclosure)
  const phases: PhasePresentation[] = [
    {
      phase: 'transition',
      title: transitionTitle,
      introduction: text('Back after a long break?'),
      introductionFull: text("If you haven't trained in a long time."),
      information: text('Return here after a long break to rebuild consistency, movement quality and training tolerance.'),
      destination: '/transition',
    },
    {
      phase: 'main',
      title: mainTitle,
      introduction: text('Ready for the main phase.'),
      introductionFull: text('Fit enough to start the main journey.'),
      information: text("Choose this when regular training feels manageable and you're ready to build strength, muscle and performance."),
      destination: '/main-phase',
    },
  ]

  useEffect(() => {
    if (!state.expanded || !state.showsIntroduction) return
    const transitionTimer = window.setTimeout(() => {
      setState((current) => recordFitnessPlanIntroPresentation(current, 'transition').state)
    }, reducedMotion ? 0 : 380)
    const mainTimer = window.setTimeout(() => {
      setState((current) => recordFitnessPlanIntroPresentation(current, 'main').state)
    }, reducedMotion ? 0 : 560)
    return () => {
      window.clearTimeout(transitionTimer)
      window.clearTimeout(mainTimer)
    }
  }, [reducedMotion, state.expanded, state.showsIntroduction])

  useEffect(() => {
    if (
      state.showsIntroduction
      && state.presentedIntroductionPhases.length === 2
      && !persistedThisExpansion.current
    ) {
      persistedThisExpansion.current = true
      onIntroSeen()
    }
  }, [onIntroSeen, state.presentedIntroductionPhases.length, state.showsIntroduction])

  useEffect(() => {
    if (state.activeInfo === null) return
    const dismissOutside = (event: PointerEvent) => {
      if (!wrapper.current?.contains(event.target as Node)) {
        setState((current) => selectFitnessPlanInfo(current, null))
      }
    }
    window.addEventListener('pointerdown', dismissOutside)
    return () => window.removeEventListener('pointerdown', dismissOutside)
  }, [state.activeInfo])

  const toggleDisclosure = () => {
    setState((current) => {
      if (!current.expanded && !introSeen) persistedThisExpansion.current = false
      return toggleFitnessPlanDisclosure(current, introSeen)
    })
  }

  const openPhase = (phase: PhasePresentation) => {
    setState(collapsedFitnessPlanDisclosure())
    navigate(phase.destination)
  }

  const toggleInfo = (phase: FitnessPlanPhase) => {
    setState((current) => selectFitnessPlanInfo(current, phase))
  }

  return (
    <motion.section
      ref={wrapper}
      data-testid="portal.fitness-plan"
      className="glass relative overflow-visible rounded-3xl"
      initial={{ opacity: 0, y: reducedMotion ? 0 : 26 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.3, duration: 0.55, ease: EASE }}
    >
      <div
        className="pointer-events-none absolute inset-0"
        style={{ background: 'linear-gradient(135deg, rgba(45,212,191,0.12), transparent 45%, rgba(139,92,246,0.12))' }}
        aria-hidden
      />
      <button
        type="button"
        aria-expanded={state.expanded}
        aria-controls="fitness-plan-phases"
        onClick={toggleDisclosure}
        className="relative flex min-h-28 w-full cursor-pointer items-center gap-4 p-5 text-left sm:gap-5 sm:p-6"
      >
        <span
          className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl text-white sm:h-16 sm:w-16"
          style={{
            background: 'linear-gradient(145deg, #18bda7, #8154ed)',
            boxShadow: '0 12px 26px -9px rgba(112,75,229,0.48), inset 0 1px 0 rgba(255,255,255,0.4)',
          }}
        >
          <DumbbellIcon className="h-7 w-7" />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block font-display text-lg font-bold tracking-[0.14em] text-ink sm:text-xl">
            {text('Fitness Plan').toUpperCase()}
          </span>
          <span className="mt-1 block text-sm font-semibold text-ink-soft">
            {transitionTitle} <span aria-hidden>·</span> {mainTitle}
          </span>
          <span className="mt-3 flex gap-2" aria-hidden>
            <span className="h-1 w-6 rounded-full bg-teal-400" />
            <span className="h-1 w-6 rounded-full bg-violet-500" />
          </span>
        </span>
      </button>

      <AnimatePresence initial={false}>
        {state.expanded && (
          <motion.div
            id="fitness-plan-phases"
            className="relative grid gap-3 px-3 pb-3 sm:gap-4 sm:px-4 sm:pb-4"
            initial={{ opacity: 0, y: reducedMotion ? 0 : -12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: reducedMotion ? 0 : -8 }}
            transition={{ duration: reducedMotion ? 0.16 : 0.38, ease: EASE }}
          >
            {phases.map((phase, index) => {
              const accent = phase.phase === 'transition' ? ACCENTS.teal : ACCENTS.violet
              const introductionVisible = state.showsIntroduction
                && state.presentedIntroductionPhases.includes(phase.phase)
              const infoVisible = !state.showsIntroduction
              const infoActive = state.activeInfo === phase.phase
              return (
                <motion.article
                  key={phase.phase}
                  data-testid={phase.phase === 'transition' ? 'portal.transition' : 'portal.main'}
                  className="relative rounded-[1.35rem] border border-white/80 bg-white/60 p-3 shadow-[0_12px_28px_-20px_rgba(15,23,42,0.32)]"
                  initial={{ opacity: 0, y: reducedMotion ? 0 : 14 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: reducedMotion ? 0 : index * 0.1, duration: 0.38, ease: EASE }}
                >
                  <div className="flex items-start gap-2">
                    <button
                      type="button"
                      onClick={() => openPhase(phase)}
                      className="flex min-h-16 min-w-0 flex-1 cursor-pointer items-center gap-3 rounded-2xl text-left"
                    >
                      <span
                        className="flex h-11 w-11 shrink-0 items-center justify-center rounded-[0.9rem] text-white"
                        style={{ background: accent.gradient, boxShadow: `0 10px 22px -10px ${accent.glowStrong}` }}
                      >
                        {phase.phase === 'transition'
                          ? <TransitionIcon className="h-5 w-5" />
                          : <BoltIcon className="h-5 w-5" />}
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block font-display text-sm font-bold tracking-[0.12em] text-ink sm:text-base">
                          {phase.title.toUpperCase()}
                        </span>
                        <AnimatePresence initial={false}>
                          {introductionVisible && (
                            <motion.span
                              aria-label={phase.introductionFull}
                              className="mt-1 block text-xs leading-snug font-semibold"
                              style={{ color: accent.deep }}
                              initial={{ opacity: 0, y: reducedMotion ? 0 : -7 }}
                              animate={{ opacity: 1, y: 0 }}
                              transition={{ duration: reducedMotion ? 0.15 : 0.34, ease: EASE }}
                            >
                              {phase.introduction}
                            </motion.span>
                          )}
                        </AnimatePresence>
                      </span>
                    </button>

                    {infoVisible && (
                      <div className="relative shrink-0">
                        <button
                          type="button"
                          data-testid={phase.phase === 'transition'
                            ? 'fitness-plan.info.transition'
                            : 'fitness-plan.info.main'}
                          aria-label={phase.information}
                          aria-expanded={infoActive}
                          onClick={() => toggleInfo(phase.phase)}
                          className="relative flex h-11 w-11 cursor-pointer items-center justify-center overflow-hidden rounded-full border border-white/80"
                          style={{ color: accent.deep, background: accent.wash, boxShadow: `0 0 18px ${accent.glowSoft}` }}
                        >
                          <span className="font-display text-base font-bold">i</span>
                          <motion.span
                            className="pointer-events-none absolute inset-y-[-30%] w-2 rotate-[24deg] bg-white/90 blur-[1px]"
                            initial={{ x: '-240%' }}
                            animate={reducedMotion ? { opacity: 0.35 } : { x: ['-240%', '300%'] }}
                            transition={reducedMotion ? undefined : { duration: 0.8, repeat: Infinity, repeatDelay: 4.4, ease: 'easeInOut' }}
                            aria-hidden
                          />
                        </button>
                        <AnimatePresence>
                          {infoActive && (
                            <motion.div
                              role="tooltip"
                              className="absolute top-13 right-0 z-20 w-64 rounded-2xl border border-white/85 bg-white/95 p-4 text-sm leading-relaxed font-medium text-ink shadow-2xl backdrop-blur-xl"
                              initial={{ opacity: 0, scale: reducedMotion ? 1 : 0.96, y: reducedMotion ? 0 : -4 }}
                              animate={{ opacity: 1, scale: 1, y: 0 }}
                              exit={{ opacity: 0, scale: reducedMotion ? 1 : 0.97 }}
                              transition={{ duration: 0.18 }}
                            >
                              {phase.information}
                            </motion.div>
                          )}
                        </AnimatePresence>
                      </div>
                    )}
                  </div>
                </motion.article>
              )
            })}
          </motion.div>
        )}
      </AnimatePresence>
    </motion.section>
  )
}
