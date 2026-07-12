import { useEffect, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { LANGUAGE_OPTIONS } from '../lib/introLanguage'
import { useLanguage } from '../lib/i18n'
import { EASE } from './ui'

export function PortalLanguageMenu() {
  const { language, setLanguage } = useLanguage()
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)
  const selected = LANGUAGE_OPTIONS.find((option) => option.value === language) ?? LANGUAGE_OPTIONS[0]

  useEffect(() => {
    if (!open) return
    const close = (event: PointerEvent): void => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false)
    }
    window.addEventListener('pointerdown', close)
    return () => window.removeEventListener('pointerdown', close)
  }, [open])

  return (
    <div ref={rootRef} className="fixed bottom-[calc(1rem+env(safe-area-inset-bottom))] left-4 z-[54] sm:left-6">
      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: 8, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 6, scale: 0.98 }}
            transition={{ duration: 0.2, ease: EASE }}
            className="portal-language-menu"
            role="listbox"
            aria-label="Languages"
          >
            <p className="px-3 pt-2.5 pb-1.5 font-mono text-[7px] font-bold tracking-[0.2em] text-ink-faint uppercase">
              Interface language
            </p>
            {LANGUAGE_OPTIONS.map((option) => {
              const active = option.value === language
              return (
                <button
                  key={option.value}
                  type="button"
                  data-no-translate
                  role="option"
                  aria-selected={active}
                  onClick={() => { setLanguage(option.value); setOpen(false) }}
                  className="portal-language-option"
                >
                  <span className={`intro-language-glyph ${option.value}`} aria-hidden>{option.glyph}</span>
                  <span className="min-w-0 flex-1 text-left">
                    <span className="block text-xs font-bold text-ink">{option.nativeName}</span>
                    <span className="mt-0.5 block text-[9px] text-ink-faint">{option.englishName}</span>
                  </span>
                  <span className={`intro-language-check ${active ? 'active' : ''}`} aria-hidden>{active ? '✓' : ''}</span>
                </button>
              )
            })}
          </motion.div>
        )}
      </AnimatePresence>

      <motion.button
        type="button"
        whileTap={{ scale: 0.96 }}
        onClick={() => setOpen((current) => !current)}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label="Change language"
        className="glass flex h-11 items-center gap-2 rounded-full px-2.5 pr-3 text-ink shadow-lg"
      >
        <span className="portal-language-glyph" aria-hidden>{selected.glyph}</span>
        <span>
          <span className="block font-mono text-[7px] leading-none font-bold tracking-[0.15em] text-ink-faint uppercase">Language</span>
          <span data-no-translate className="mt-1 block text-[10px] leading-none font-bold">{selected.nativeName}</span>
        </span>
        <motion.svg animate={{ rotate: open ? 180 : 0 }} viewBox="0 0 20 20" fill="none" className="ml-0.5 h-3 w-3 text-ink-faint" aria-hidden>
          <path d="m5 7.5 5 5 5-5" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
        </motion.svg>
      </motion.button>
    </div>
  )
}
