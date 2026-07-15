import { useEffect, useMemo, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { ApexMark } from './Icons'
import { EASE } from './ui'
import { PERSONAS, type PersonaSlug } from '../lib/persona'
import {
  getIntroLanguage,
  INTRO_COPY,
  LANGUAGE_OPTIONS,
  LANGUAGE_PROMPTS,
  setIntroLanguage,
  type IntroLanguage,
  type SelectableIntroLanguage,
} from '../lib/introLanguage'

function circularOffset(index: number, active: number): -2 | -1 | 0 | 1 {
  const raw = (index - active + PERSONAS.length) % PERSONAS.length
  if (raw === 0) return 0
  if (raw === 1) return 1
  if (raw === PERSONAS.length - 1) return -1
  return -2
}

function IntroLanguageMenu({
  language,
  onChange,
}: {
  language: IntroLanguage
  onChange: (language: SelectableIntroLanguage) => void
}) {
  const [promptIndex, setPromptIndex] = useState(0)
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)
  const selected = LANGUAGE_OPTIONS.find((option) => option.value === language)

  useEffect(() => {
    const timer = window.setInterval(() => {
      setPromptIndex((current) => (current + 1) % LANGUAGE_PROMPTS.length)
    }, 1800)
    return () => window.clearInterval(timer)
  }, [])

  useEffect(() => {
    if (!open) return
    const close = (event: PointerEvent): void => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false)
    }
    window.addEventListener('pointerdown', close)
    return () => window.removeEventListener('pointerdown', close)
  }, [open])

  return (
    <div className="intro-language-row" ref={rootRef}>
      <div className="intro-language-prompt" aria-hidden="true">
        <AnimatePresence mode="wait" initial={false}>
          <motion.span
            key={LANGUAGE_PROMPTS[promptIndex]}
            initial={{ opacity: 0, y: 5 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -5 }}
            transition={{ duration: 0.28, ease: EASE }}
          >
            {LANGUAGE_PROMPTS[promptIndex]}
          </motion.span>
        </AnimatePresence>
      </div>
      <span className="sr-only">Choose your language. Alege limba. เลือกภาษาของคุณ</span>

      <div className="relative">
        <button
          type="button"
          className="intro-language-trigger"
          data-no-translate
          aria-haspopup="listbox"
          aria-expanded={open}
          aria-label="Choose English, Thai or Romanian"
          onClick={() => setOpen((current) => !current)}
        >
          <span className="intro-language-globe" aria-hidden>
            {selected?.glyph ?? '◌'}
          </span>
          <span className="min-w-0">
            <span className="block text-[9px] leading-none font-bold tracking-[0.18em] text-white/38 uppercase">
              {selected?.short ?? 'TH / RO'}
            </span>
            <span className="mt-1 block truncate text-[11px] leading-none font-semibold text-white/88">
              {selected?.nativeName ?? 'Language'}
            </span>
          </span>
          <motion.svg
            animate={{ rotate: open ? 180 : 0 }}
            transition={{ duration: 0.22 }}
            viewBox="0 0 20 20"
            fill="none"
            className="ml-1 h-3.5 w-3.5 shrink-0 text-white/42"
            aria-hidden
          >
            <path d="m5 7.5 5 5 5-5" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
          </motion.svg>
        </button>

        <AnimatePresence>
          {open && (
            <motion.div
              initial={{ opacity: 0, y: -7, scale: 0.97 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: -5, scale: 0.98 }}
              transition={{ duration: 0.2, ease: EASE }}
              className="intro-language-menu"
              role="listbox"
              aria-label="Languages"
            >
              <p className="px-3 pt-2.5 pb-1.5 font-mono text-[7px] font-bold tracking-[0.24em] text-white/30 uppercase">
                Interface language
              </p>
              {LANGUAGE_OPTIONS.map((option) => {
                const active = option.value === language
                return (
                  <button
                    type="button"
                    key={option.value}
                    data-no-translate
                    role="option"
                    aria-selected={active}
                    className="intro-language-option"
                    onClick={() => {
                      onChange(option.value)
                      setOpen(false)
                    }}
                  >
                    <span className={`intro-language-glyph ${option.value}`} aria-hidden>{option.glyph}</span>
                    <span className="min-w-0 flex-1 text-left">
                      <span className="block text-xs font-semibold text-white/90">{option.nativeName}</span>
                      <span className="mt-0.5 block text-[9px] text-white/34">{option.englishName}</span>
                    </span>
                    <span className={`intro-language-check ${active ? 'active' : ''}`} aria-hidden>{active ? '✓' : ''}</span>
                  </button>
                )
              })}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  )
}

export function PersonaIntro({ onSelect }: { onSelect: (persona: PersonaSlug) => void }) {
  /* Matthew starts centre; the fourth profile remains one swipe away. */
  const [active, setActive] = useState(() => Math.max(0, PERSONAS.findIndex((persona) => persona.slug === 'matthew')))
  const [confirming, setConfirming] = useState(false)
  const [language, setLanguage] = useState<IntroLanguage>(getIntroLanguage)
  const selected = PERSONAS[active]
  const copy = INTRO_COPY[language]

  useEffect(() => {
    document.documentElement.lang = language
  }, [language])

  const chooseLanguage = (nextLanguage: SelectableIntroLanguage): void => {
    setIntroLanguage(nextLanguage)
    setLanguage(nextLanguage)
  }

  const constellation = useMemo(
    () => PERSONAS.map((persona, index) => ({ persona, index, offset: circularOffset(index, active) })),
    [active],
  )

  const rotate = (direction: -1 | 1): void => {
    setConfirming(false)
    setActive((current) => (current + direction + PERSONAS.length) % PERSONAS.length)
  }

  return (
    <div className="apex-intro fixed inset-0 z-[70] overflow-hidden bg-[#05070b] text-white">
      <div className="intro-aurora absolute inset-0" aria-hidden />
      <div className="intro-grid absolute inset-0" aria-hidden />
      <div className="intro-vignette absolute inset-0" aria-hidden />

      <motion.header
        initial={{ opacity: 0, y: -12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.8, delay: 0.15, ease: EASE }}
        className="absolute inset-x-0 top-0 z-30 flex items-center justify-between px-5 pt-[max(1.25rem,env(safe-area-inset-top))] sm:px-10"
      >
        <div className="flex items-center gap-3">
          <span className="flex h-9 w-9 items-center justify-center rounded-xl border border-white/12 bg-white/7 backdrop-blur-xl">
            <ApexMark className="h-5 w-5" />
          </span>
          <div>
            <p className="text-[13px] font-bold tracking-[0.3em]">APEX</p>
            <p className="mt-0.5 text-[8px] font-semibold tracking-[0.23em] text-white/38 uppercase">
              {copy.network}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2 font-mono text-[9px] tracking-[0.18em] text-white/45">
          <span className="relative flex h-2 w-2">
            <span className="absolute inset-0 animate-ping rounded-full bg-emerald-300 opacity-50" />
            <span className="relative h-2 w-2 rounded-full bg-emerald-300" />
          </span>
          {copy.secure}
        </div>
      </motion.header>

      <main className="relative z-10 flex min-h-dvh flex-col items-center overflow-hidden pt-[5.35rem] pb-[max(1.1rem,env(safe-area-inset-bottom))]">
        <motion.div
          initial={{ opacity: 0, y: -7 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.26, ease: EASE }}
          className="z-50 mb-3 px-4"
        >
          <IntroLanguageMenu language={language} onChange={chooseLanguage} />
        </motion.div>
        <motion.div
          initial={{ opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.75, delay: 0.35, ease: EASE }}
          className="z-20 px-5 text-center"
        >
          <p className="font-mono text-[9px] font-semibold tracking-[0.36em] text-white/42 uppercase">
            {copy.protocol}
          </p>
          <h1 className="mt-2 text-[clamp(1.65rem,7vw,3.3rem)] leading-none font-semibold tracking-[-0.055em]">
            {copy.chooseSystem}
          </h1>
        </motion.div>

        <motion.section
          className="relative mt-1 h-[min(52dvh,570px)] min-h-[390px] w-full max-w-5xl touch-pan-y select-none"
          style={{ perspective: 1100, transformStyle: 'preserve-3d' }}
          drag="x"
          dragConstraints={{ left: 0, right: 0 }}
          dragElastic={0.16}
          onDragEnd={(_, info) => {
            if (Math.abs(info.offset.x) < 44 && Math.abs(info.velocity.x) < 350) return
            rotate(info.offset.x < 0 ? 1 : -1)
          }}
          aria-label={copy.selectorLabel}
        >
          <div className="intro-orbit absolute top-[48%] left-1/2 h-[44%] w-[72%] -translate-x-1/2 -translate-y-1/2 rounded-[50%] border border-white/8" aria-hidden />
          <div
            className="pointer-events-none absolute top-[82%] left-1/2 h-16 w-[52%] -translate-x-1/2 rounded-[50%] opacity-55 blur-2xl"
            style={{ background: selected.halo }}
            aria-hidden
          />

          {constellation.map(({ persona, index, offset }) => {
            const isActive = offset === 0
            /* Keep the side-card centre outside the active card's hit area so
               tapping a visible side portrait reliably rotates it forward. */
            const hiddenRear = Math.abs(offset) > 1
            const x = offset === 0 ? '0%' : offset < 0 ? '-82%' : '82%'
            return (
              <motion.button
                type="button"
                key={persona.slug}
                initial={{ opacity: 0, scale: 0.25, y: 90, filter: 'blur(18px)' }}
                animate={{
                  opacity: isActive ? 1 : hiddenRear ? 0 : 0.48,
                  scale: isActive ? 1 : hiddenRear ? 0.48 : 0.7,
                  x,
                  y: isActive ? 0 : 34,
                  z: isActive ? 95 : hiddenRear ? -360 : -175,
                  rotateY: offset * -35,
                  filter: isActive ? 'blur(0px)' : 'blur(1.2px)',
                }}
                transition={{
                  opacity: { duration: 0.35 },
                  delay: index * 0.09,
                  type: 'spring',
                  stiffness: 190,
                  damping: 24,
                  mass: 0.85,
                }}
                onClick={() => {
                  if (isActive) setConfirming(true)
                  else {
                    setConfirming(false)
                    setActive(index)
                  }
                }}
                className="absolute inset-y-0 left-1/2 w-[68vw] max-w-[430px] -translate-x-1/2 cursor-pointer outline-none focus-visible:ring-2 focus-visible:ring-white/70"
                style={{ transformStyle: 'preserve-3d', zIndex: isActive ? 20 : hiddenRear ? 0 : 10, pointerEvents: isActive ? 'auto' : 'none' }}
                tabIndex={isActive ? 0 : -1}
                aria-label={isActive ? copy.continueAs(persona.name) : copy.preview(persona.name)}
                aria-pressed={isActive}
              >
                <span
                  className="pointer-events-none absolute top-[12%] left-1/2 h-[48%] w-[64%] -translate-x-1/2 rounded-full opacity-75 blur-[52px]"
                  style={{ background: persona.halo }}
                  aria-hidden
                />
                <span className="intro-portrait-mask absolute inset-x-0 top-0 h-[82%] overflow-hidden">
                  <motion.img
                    src={persona.portrait}
                    alt=""
                    draggable={false}
                    animate={isActive ? { y: [0, -5, 0] } : { y: 0 }}
                    transition={isActive ? { duration: 5, repeat: Infinity, ease: 'easeInOut' } : { duration: 0.4 }}
                    className="absolute inset-0 h-full w-full object-contain object-bottom"
                    style={{ filter: `drop-shadow(0 24px 42px ${persona.halo})` }}
                  />
                  {isActive && <span className="intro-scan absolute inset-x-[12%] top-[15%] h-px" aria-hidden />}
                </span>

                <span className="absolute inset-x-0 bottom-[2%] flex flex-col items-center px-2 text-center">
                  <motion.span
                    animate={{ opacity: isActive ? 1 : 0.48, scale: isActive ? 1 : 0.9 }}
                    className="font-mono text-[9px] font-bold tracking-[0.3em] uppercase"
                    style={{ color: persona.colorSoft }}
                  >
                    {persona.title}
                  </motion.span>
                  <span className="mt-1.5 text-[clamp(1.45rem,6vw,2.65rem)] leading-none font-semibold tracking-[-0.05em]">
                    {persona.name}
                  </span>
                  <span className={`mt-2 max-w-[18rem] text-[11px] leading-relaxed font-medium text-white/52 ${isActive ? 'block' : 'hidden sm:block'}`}>
                    {persona.signature}
                  </span>
                </span>
              </motion.button>
            )
          })}

          {/* Dedicated side hit-zones keep swipe-like depth while making the
              visible rear portraits effortless to tap on narrow screens. */}
          {([-1, 1] as const).map((side) => {
            const sideIndex = (active + side + PERSONAS.length) % PERSONAS.length
            const sidePersona = PERSONAS[sideIndex]
            return (
              <button
                key={`hit-${side}`}
                type="button"
                onClick={() => { setConfirming(false); setActive(sideIndex) }}
                className={`absolute inset-y-[8%] z-30 w-[36%] ${side < 0 ? 'left-0' : 'right-0'}`}
                aria-label={copy.bringForward(sidePersona.name)}
              />
            )
          })}
        </motion.section>

        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1.05, duration: 0.65 }}
          className="z-30 mt-auto flex w-full max-w-md flex-col items-center px-6"
        >
          <div className="flex items-center gap-4">
            <button type="button" onClick={() => rotate(-1)} aria-label={copy.previous} className="flex h-10 w-10 items-center justify-center rounded-full border border-white/10 bg-white/5 text-white/55 backdrop-blur-lg transition hover:bg-white/10 hover:text-white active:scale-95">
              <span aria-hidden>←</span>
            </button>
            <div className="flex gap-2" role="tablist" aria-label={copy.people}>
              {PERSONAS.map((persona, index) => (
                <button
                  key={persona.slug}
                  type="button"
                  role="tab"
                  aria-selected={index === active}
                  aria-label={persona.name}
                  onClick={() => { setConfirming(false); setActive(index) }}
                  className="h-1.5 rounded-full transition-all duration-500"
                  style={{ width: index === active ? 28 : 6, background: index === active ? selected.color : 'rgba(255,255,255,.2)' }}
                />
              ))}
            </div>
            <button type="button" onClick={() => rotate(1)} aria-label={copy.next} className="flex h-10 w-10 items-center justify-center rounded-full border border-white/10 bg-white/5 text-white/55 backdrop-blur-lg transition hover:bg-white/10 hover:text-white active:scale-95">
              <span aria-hidden>→</span>
            </button>
          </div>
          <p className="mt-2 font-mono text-[8px] tracking-[0.24em] text-white/30 uppercase">
            {copy.swipeHint}
          </p>
        </motion.div>
      </main>

      <AnimatePresence>
        {confirming && (
          <motion.div
            className="fixed inset-0 z-[90] flex items-end justify-center bg-black/55 px-4 pb-[max(1rem,env(safe-area-inset-bottom))] backdrop-blur-md sm:items-center sm:pb-0"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={() => setConfirming(false)}
          >
            <motion.div
              initial={{ opacity: 0, y: 32, scale: 0.96 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 18, scale: 0.98 }}
              transition={{ duration: 0.42, ease: EASE }}
              onClick={(event) => event.stopPropagation()}
              className="w-full max-w-md overflow-hidden rounded-[2rem] border border-white/12 bg-[#0b0e14]/92 p-6 shadow-2xl backdrop-blur-2xl sm:p-7"
              style={{ boxShadow: `0 28px 90px -25px ${selected.halo}` }}
              role="dialog"
              aria-modal="true"
              aria-labelledby="identity-confirm-title"
            >
              <div className="flex items-center gap-4">
                <div className="relative h-16 w-16 shrink-0 overflow-hidden rounded-2xl border border-white/12 bg-white/5">
                  <img src={selected.portrait} alt="" className="h-full w-full scale-125 object-contain object-bottom" />
                </div>
                <div>
                  <p className="font-mono text-[9px] font-bold tracking-[0.22em] uppercase" style={{ color: selected.colorSoft }}>
                    {copy.identitySelected}
                  </p>
                  <h2 id="identity-confirm-title" className="mt-1 text-2xl font-semibold tracking-tight">
                    {copy.enterAs(selected.firstName)}
                  </h2>
                </div>
              </div>
              <p className="mt-5 text-sm leading-relaxed text-white/58">
                {selected.mission}. {copy.privacy}
              </p>
              <button
                type="button"
                onClick={() => onSelect(selected.slug)}
                className="mt-6 flex w-full items-center justify-center rounded-2xl px-5 py-3.5 text-sm font-bold text-[#06080b] transition active:scale-[0.98]"
                style={{ background: selected.gradient, boxShadow: `0 15px 40px -14px ${selected.halo}` }}
              >
                {copy.confirm}
              </button>
              <button type="button" onClick={() => setConfirming(false)} className="mt-2 w-full py-2 text-xs font-semibold text-white/42 transition hover:text-white/70">
                {copy.explore}
              </button>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}
