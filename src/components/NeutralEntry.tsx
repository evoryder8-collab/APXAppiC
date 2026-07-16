import { motion, useReducedMotion } from 'framer-motion'
import { useEffect, useState } from 'react'
import { getIntroLanguage, INTRO_COPY, LANGUAGE_OPTIONS, setIntroLanguage, type IntroLanguage, type SelectableIntroLanguage } from '../lib/introLanguage'
import { ApexMark } from './Icons'
import { EASE } from './ui'

export function NeutralEntry({ onLogin }: { onLogin: () => void }) {
  const reduceMotion = useReducedMotion()
  const [language, setLanguage] = useState<IntroLanguage>(getIntroLanguage)
  const copy = INTRO_COPY[language]

  useEffect(() => {
    document.documentElement.lang = language
  }, [language])

  const chooseLanguage = (next: SelectableIntroLanguage): void => {
    setIntroLanguage(next)
    setLanguage(next)
  }

  return (
    <div className="apex-intro fixed inset-0 z-[70] overflow-hidden bg-[#05070b] text-white" data-testid="neutral-entry">
      <div className="intro-aurora absolute inset-0" aria-hidden />
      <div className="intro-grid absolute inset-0" aria-hidden />
      <div className="intro-vignette absolute inset-0" aria-hidden />

      <motion.header
        initial={reduceMotion ? false : { opacity: 0, y: -12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={reduceMotion ? { duration: 0 } : { duration: 0.65, delay: 0.08, ease: EASE }}
        className="absolute inset-x-0 top-0 z-30 flex items-center justify-between px-5 pt-[max(1.25rem,env(safe-area-inset-top))] sm:px-10"
      >
        <div className="flex items-center gap-3">
          <span className="flex h-9 w-9 items-center justify-center rounded-xl border border-white/12 bg-white/7 backdrop-blur-xl"><ApexMark className="h-5 w-5" /></span>
          <div>
            <p className="text-[13px] font-bold tracking-[0.3em]">APEX</p>
            <p className="mt-0.5 text-[8px] font-semibold tracking-[0.23em] text-white/38 uppercase">{copy.network}</p>
          </div>
        </div>
        <div className="flex items-center gap-2 font-mono text-[9px] tracking-[0.18em] text-white/45">
          <span className="relative flex h-2 w-2"><span className="absolute inset-0 animate-ping rounded-full bg-emerald-300 opacity-50" /><span className="relative h-2 w-2 rounded-full bg-emerald-300" /></span>
          {copy.secure}
        </div>
      </motion.header>

      <main className="relative z-10 flex min-h-dvh flex-col items-center justify-center overflow-y-auto px-6 pt-24 pb-[max(1.25rem,env(safe-area-inset-bottom))] text-center">
        <motion.div
          initial={reduceMotion ? false : { opacity: 0, y: 18, scale: 0.97 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          transition={reduceMotion ? { duration: 0 } : { duration: 0.68, delay: 0.16, ease: EASE }}
          className="flex w-full max-w-xl flex-col items-center"
        >
          <div className="intro-neutral-stage" aria-hidden="true">
            <span className="intro-neutral-aura" />
            <span className="intro-neutral-ring intro-neutral-ring-outer" />
            <span className="intro-neutral-ring intro-neutral-ring-inner" />
            <span className="intro-neutral-core"><ApexMark className="h-12 w-12" /></span>
          </div>
          <p className="mt-7 font-mono text-[9px] font-bold tracking-[0.3em] text-cyan-100/55 uppercase">{copy.neutralEyebrow}</p>
          <h1 className="mt-3 max-w-xl text-[clamp(2rem,9vw,4.6rem)] leading-[0.94] font-semibold tracking-[-0.065em]">{copy.neutralTitle}</h1>
          <p className="mt-4 max-w-md text-sm leading-relaxed font-medium text-white/48">{copy.neutralBody}</p>

          <div className="mt-8 w-full max-w-sm space-y-2.5">
            <button type="button" onClick={onLogin} className="intro-neutral-primary w-full rounded-2xl px-5 py-4 text-sm font-black text-[#05070b] transition active:scale-[.985]">{copy.enter}</button>
          </div>

          <div className="mt-7 flex items-center gap-1 rounded-full border border-white/8 bg-black/20 p-1" role="group" aria-label="Interface language">
            {LANGUAGE_OPTIONS.map((option) => (
              <button
                key={option.value}
                type="button"
                data-no-translate
                aria-pressed={language === option.value}
                onClick={() => chooseLanguage(option.value)}
                className={`rounded-full px-3 py-1.5 font-mono text-[9px] font-black tracking-[0.12em] transition ${language === option.value ? 'bg-white/12 text-white' : 'text-white/34 hover:text-white/65'}`}
              >
                {option.short}
              </button>
            ))}
          </div>
        </motion.div>
      </main>
    </div>
  )
}
