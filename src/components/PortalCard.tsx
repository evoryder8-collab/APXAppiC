import type { CSSProperties, ReactNode } from 'react'
import { motion } from 'framer-motion'
import { useNavigate } from 'react-router-dom'
import type { Accent } from '../lib/theme'
import { accentVars } from '../lib/theme'
import { ChevronRightIcon } from './Icons'

interface PortalCardProps {
  to: string
  accent: Accent
  title: string
  subtitle: string
  icon: ReactNode
  index: number
}

const EASE = [0.22, 1, 0.36, 1] as const

export function PortalCard({ to, accent, title, subtitle, icon, index }: PortalCardProps) {
  const navigate = useNavigate()

  return (
    <motion.button
      type="button"
      onClick={() => navigate(to)}
      initial={{ opacity: 0, y: 26 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.12 + index * 0.09, duration: 0.55, ease: EASE }}
      whileHover={{ y: -3 }}
      whileTap={{ scale: 0.97 }}
      className="glass breathe group relative w-full cursor-pointer overflow-hidden rounded-3xl p-5 text-left sm:p-6"
      style={
        {
          ...accentVars(accent),
          animationDelay: `${index * 0.45}s`,
        } as CSSProperties
      }
    >
      {/* Faint accent wash so each panel catches its own color */}
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          background: `radial-gradient(120% 140% at 12% 0%, ${accent.wash} 0%, transparent 55%)`,
        }}
        aria-hidden
      />

      <div className="relative flex items-center gap-4 sm:gap-5">
        <div
          className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl text-white transition-transform duration-300 group-hover:scale-105 sm:h-16 sm:w-16"
          style={{
            background: accent.gradient,
            boxShadow: `0 10px 24px -8px ${accent.glowStrong}, inset 0 1px 0 rgba(255,255,255,0.35)`,
          }}
        >
          {icon}
        </div>

        <div className="min-w-0 flex-1">
          <h2 className="font-display text-lg font-bold tracking-[0.14em] text-ink sm:text-xl">
            {title}
          </h2>
          <p className="mt-1 text-[13.5px] leading-snug font-medium text-ink-soft sm:text-sm">
            {subtitle}
          </p>
        </div>

        <ChevronRightIcon
          className="h-5 w-5 shrink-0 transition-transform duration-300 group-hover:translate-x-0.5"
          strokeWidth={2.2}
        />
      </div>
    </motion.button>
  )
}
