import { motion } from 'framer-motion'
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

  return (
    <motion.button
      type="button"
      data-testid="profile-switcher"
      aria-label="Return to profile selector"
      title="Switch profile"
      disabled={busy}
      onClick={onSwitch}
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
  )
}
