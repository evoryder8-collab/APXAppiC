import { useMemo, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { ApexMark } from './Icons'
import { EASE } from './ui'
import { PERSONAS, type PersonaSlug } from '../lib/persona'

function circularOffset(index: number, active: number): -1 | 0 | 1 {
  const raw = (index - active + PERSONAS.length) % PERSONAS.length
  return raw === 0 ? 0 : raw === 1 ? 1 : -1
}

export function PersonaIntro({ onSelect }: { onSelect: (persona: PersonaSlug) => void }) {
  /* Matthew starts centre, with June left and Constantine right. */
  const [active, setActive] = useState(1)
  const [confirming, setConfirming] = useState(false)
  const selected = PERSONAS[active]

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
              Private performance network
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2 font-mono text-[9px] tracking-[0.18em] text-white/45">
          <span className="relative flex h-2 w-2">
            <span className="absolute inset-0 animate-ping rounded-full bg-emerald-300 opacity-50" />
            <span className="relative h-2 w-2 rounded-full bg-emerald-300" />
          </span>
          SECURE
        </div>
      </motion.header>

      <main className="relative z-10 flex min-h-dvh flex-col items-center overflow-hidden pt-[5.7rem] pb-[max(1.1rem,env(safe-area-inset-bottom))]">
        <motion.div
          initial={{ opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.75, delay: 0.35, ease: EASE }}
          className="z-20 px-5 text-center"
        >
          <p className="font-mono text-[9px] font-semibold tracking-[0.36em] text-white/42 uppercase">
            Identity protocol
          </p>
          <h1 className="mt-2 text-[clamp(1.65rem,7vw,3.3rem)] leading-none font-semibold tracking-[-0.055em]">
            Choose your system
          </h1>
        </motion.div>

        <motion.section
          className="relative mt-2 h-[min(58dvh,610px)] w-full max-w-5xl touch-pan-y select-none"
          style={{ perspective: 1100, transformStyle: 'preserve-3d' }}
          drag="x"
          dragConstraints={{ left: 0, right: 0 }}
          dragElastic={0.16}
          onDragEnd={(_, info) => {
            if (Math.abs(info.offset.x) < 44 && Math.abs(info.velocity.x) < 350) return
            rotate(info.offset.x < 0 ? 1 : -1)
          }}
          aria-label="Swipe left or right to choose a person"
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
            const x = offset === 0 ? '0%' : offset < 0 ? '-82%' : '82%'
            return (
              <motion.button
                type="button"
                key={persona.slug}
                initial={{ opacity: 0, scale: 0.25, y: 90, filter: 'blur(18px)' }}
                animate={{
                  opacity: isActive ? 1 : 0.48,
                  scale: isActive ? 1 : 0.7,
                  x,
                  y: isActive ? 0 : 34,
                  z: isActive ? 95 : -175,
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
                style={{ transformStyle: 'preserve-3d', zIndex: isActive ? 20 : 10, pointerEvents: isActive ? 'auto' : 'none' }}
                tabIndex={isActive ? 0 : -1}
                aria-label={isActive ? `Continue as ${persona.name}` : `${persona.name} preview`}
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
                aria-label={`Bring ${sidePersona.name} forward`}
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
            <button type="button" onClick={() => rotate(-1)} aria-label="Previous person" className="flex h-10 w-10 items-center justify-center rounded-full border border-white/10 bg-white/5 text-white/55 backdrop-blur-lg transition hover:bg-white/10 hover:text-white active:scale-95">
              <span aria-hidden>←</span>
            </button>
            <div className="flex gap-2" role="tablist" aria-label="People">
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
            <button type="button" onClick={() => rotate(1)} aria-label="Next person" className="flex h-10 w-10 items-center justify-center rounded-full border border-white/10 bg-white/5 text-white/55 backdrop-blur-lg transition hover:bg-white/10 hover:text-white active:scale-95">
              <span aria-hidden>→</span>
            </button>
          </div>
          <p className="mt-2 font-mono text-[8px] tracking-[0.24em] text-white/30 uppercase">
            Swipe to orbit · tap centre to enter
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
                    Identity selected
                  </p>
                  <h2 id="identity-confirm-title" className="mt-1 text-2xl font-semibold tracking-tight">
                    Enter as {selected.firstName}?
                  </h2>
                </div>
              </div>
              <p className="mt-5 text-sm leading-relaxed text-white/58">
                {selected.mission}. Your private data and progress remain isolated from every other profile.
              </p>
              <button
                type="button"
                onClick={() => onSelect(selected.slug)}
                className="mt-6 flex w-full items-center justify-center rounded-2xl px-5 py-3.5 text-sm font-bold text-[#06080b] transition active:scale-[0.98]"
                style={{ background: selected.gradient, boxShadow: `0 15px 40px -14px ${selected.halo}` }}
              >
                Confirm identity
              </button>
              <button type="button" onClick={() => setConfirming(false)} className="mt-2 w-full py-2 text-xs font-semibold text-white/42 transition hover:text-white/70">
                Keep exploring
              </button>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}
