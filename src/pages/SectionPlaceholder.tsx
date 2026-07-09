import type { CSSProperties, ReactNode } from 'react'
import { motion } from 'framer-motion'
import { Link } from 'react-router-dom'
import type { Accent } from '../lib/theme'
import { accentVars } from '../lib/theme'
import { ChevronLeftIcon } from '../components/Icons'

interface SectionPlaceholderProps {
  accent: Accent
  title: string
  phase: string
  description: string
  icon: ReactNode
}

const EASE = [0.22, 1, 0.36, 1] as const

export function SectionPlaceholder({
  accent,
  title,
  phase,
  description,
  icon,
}: SectionPlaceholderProps) {
  return (
    <div className="mx-auto w-full max-w-3xl">
      <motion.div
        initial={{ opacity: 0, y: 18 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5, ease: EASE }}
      >
        <Link
          to="/"
          className="inline-flex items-center gap-1 rounded-full py-1 pr-3 text-sm font-semibold text-ink-soft transition-colors hover:text-ink"
        >
          <ChevronLeftIcon className="h-4 w-4" />
          Portal
        </Link>

        <div
          className="glass breathe mt-4 rounded-3xl p-6 sm:p-8"
          style={accentVars(accent) as CSSProperties}
        >
          <div
            className="pointer-events-none absolute inset-0 rounded-3xl"
            style={{
              background: `radial-gradient(120% 140% at 12% 0%, ${accent.wash} 0%, transparent 55%)`,
            }}
            aria-hidden
          />
          <div className="relative">
            <div
              className="flex h-16 w-16 items-center justify-center rounded-2xl text-white"
              style={{
                background: accent.gradient,
                boxShadow: `0 10px 24px -8px ${accent.glowStrong}, inset 0 1px 0 rgba(255,255,255,0.35)`,
              }}
            >
              {icon}
            </div>

            <h1 className="mt-5 font-display text-2xl font-bold tracking-tight text-ink sm:text-3xl">
              {title}
            </h1>
            <p className="mt-2 max-w-md text-[15px] leading-relaxed font-medium text-ink-soft">
              {description}
            </p>

            <span
              className="mt-5 inline-block rounded-full px-3.5 py-1.5 font-mono text-[12px] font-semibold tracking-wide text-white"
              style={{ background: accent.gradient }}
            >
              {phase}
            </span>
          </div>
        </div>

        {/* Shimmering glass skeletons hinting at the layout to come */}
        <div className="mt-5 space-y-4" aria-hidden>
          {[0, 1, 2].map((i) => (
            <motion.div
              key={i}
              initial={{ opacity: 0, y: 14 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.15 + i * 0.08, duration: 0.45, ease: EASE }}
              className="glass overflow-hidden rounded-3xl p-5"
            >
              <div className="skeleton absolute inset-0" />
              <div className="flex items-center gap-4">
                <div className="h-11 w-11 rounded-xl bg-ink/[0.05]" />
                <div className="flex-1 space-y-2.5">
                  <div className="h-3 w-2/5 rounded-full bg-ink/[0.07]" />
                  <div className="h-3 w-3/5 rounded-full bg-ink/[0.045]" />
                </div>
              </div>
            </motion.div>
          ))}
        </div>
      </motion.div>
    </div>
  )
}
