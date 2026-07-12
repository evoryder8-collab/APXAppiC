import { useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import type { CSSProperties } from 'react'
import { PERSONAS, type PersonaSlug } from '../lib/persona'

export function ProfileSwitcher({
  activePersona,
  busy,
  onSwitch,
}: {
  activePersona: PersonaSlug
  busy: boolean
  onSwitch: () => void
}) {
  const active = PERSONAS.find((persona) => persona.slug === activePersona) ?? PERSONAS[1]
  const [confirming, setConfirming] = useState(false)

  return (
    <>
      <motion.button
        type="button"
        data-testid="profile-switcher"
        aria-label="Return to profile selector"
        title="Switch profile"
        disabled={busy}
        onClick={() => setConfirming(true)}
        initial={{ opacity: 0, y: 18, scale: 0.94 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        whileTap={{ scale: 0.96 }}
        className="glass !fixed right-4 bottom-[calc(1rem+env(safe-area-inset-bottom))] z-[55] flex h-11 items-center gap-2 rounded-full px-3 text-ink shadow-lg transition disabled:opacity-60 sm:right-6"
        style={{
          '--glow-strong': active.halo,
          background: 'linear-gradient(145deg, rgba(255,255,255,.9), rgba(255,255,255,.68))',
        } as CSSProperties}
      >
        <span className="flex -space-x-1.5" aria-hidden>
          {PERSONAS.map((persona) => (
            <span
              key={persona.slug}
              className="h-5 w-5 rounded-full border-2 border-white shadow-sm"
              style={{
                background: persona.gradient,
                boxShadow: persona.slug === activePersona ? `0 0 0 2px ${persona.color}55` : undefined,
              }}
            />
          ))}
        </span>
        <span className="text-[11px] font-bold tracking-[0.13em] uppercase">
          {busy ? 'Leaving…' : 'Profiles'}
        </span>
        <svg viewBox="0 0 20 20" fill="none" className="h-3.5 w-3.5 text-ink-soft" aria-hidden>
          <path d="M15.5 6.5V3m0 0H12m3.5 0-3.1 3.1a5.6 5.6 0 1 0 1.1 7.9" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </motion.button>

      <AnimatePresence>
        {confirming && (
          <motion.div
            className="fixed inset-0 z-[75] flex items-end justify-center bg-black/35 p-4 pb-[max(1rem,env(safe-area-inset-bottom))] backdrop-blur-sm sm:items-center"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={() => setConfirming(false)}
          >
            <motion.div
              role="alertdialog"
              aria-modal="true"
              aria-labelledby="profile-logout-title"
              initial={{ opacity: 0, y: 24, scale: 0.97 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 14, scale: 0.98 }}
              onClick={(event) => event.stopPropagation()}
              className="glass w-full max-w-sm rounded-[2rem] p-5 shadow-2xl sm:p-6"
              style={{ '--glow-strong': active.halo } as CSSProperties}
            >
              <div className="flex items-center gap-3">
                <div className="grid h-11 w-11 shrink-0 place-items-center rounded-2xl bg-amber-500/12 text-xl" aria-hidden>!</div>
                <div>
                  <p className="font-mono text-[9px] font-bold tracking-[0.18em] text-amber-700 uppercase">Logout warning</p>
                  <h2 id="profile-logout-title" className="mt-1 font-display text-xl font-bold text-ink">You’re about to log out. Are you sure?</h2>
                </div>
              </div>
              <p className="mt-3 text-xs leading-relaxed font-medium text-ink-soft">Your synced information is safe. You will return to the animated profile selector and must sign in again.</p>
              <div className="mt-5 grid grid-cols-2 gap-2">
                <button type="button" onClick={() => setConfirming(false)} className="rounded-2xl bg-white/75 px-4 py-3 text-sm font-bold text-ink shadow-sm">Cancel</button>
                <button type="button" onClick={() => { setConfirming(false); onSwitch() }} className="rounded-2xl bg-amber-500 px-4 py-3 text-sm font-bold text-white shadow-lg">Yes</button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  )
}
