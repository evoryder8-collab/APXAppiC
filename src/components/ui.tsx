/* Shared glass UI primitives. */
import type { CSSProperties, ReactNode } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { Link } from 'react-router-dom'
import type { Accent } from '../lib/theme'
import { accentVars } from '../lib/theme'
import { ChevronLeftIcon } from './Icons'

export const EASE = [0.22, 1, 0.36, 1] as const

export function GlassCard({
  accent,
  breathe = false,
  className = '',
  style,
  children,
  onClick,
}: {
  accent?: Accent
  breathe?: boolean
  className?: string
  style?: CSSProperties
  children: ReactNode
  onClick?: () => void
}) {
  return (
    <div
      onClick={onClick}
      className={`glass relative overflow-hidden rounded-3xl ${breathe ? 'breathe' : ''} ${className}`}
      style={{ ...(accent ? accentVars(accent) : {}), ...style }}
    >
      {accent && (
        <div
          className="pointer-events-none absolute inset-0"
          style={{ background: `radial-gradient(120% 140% at 12% 0%, ${accent.wash} 0%, transparent 55%)` }}
          aria-hidden
        />
      )}
      <div className="relative">{children}</div>
    </div>
  )
}

export function BackLink({ to = '/', label = 'Portal' }: { to?: string; label?: string }) {
  return (
    <Link
      to={to}
      className="inline-flex items-center gap-1 rounded-full py-1 pr-3 text-sm font-semibold text-ink-soft transition-colors hover:text-ink"
    >
      <ChevronLeftIcon className="h-4 w-4" />
      {label}
    </Link>
  )
}

export function SectionHeader({
  accent,
  title,
  subtitle,
  right,
  backTo,
}: {
  accent: Accent
  title: string
  subtitle?: string
  right?: ReactNode
  backTo?: string
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.45, ease: EASE }}
      className="mb-5"
    >
      <BackLink to={backTo ?? '/'} />
      <div className="mt-2 flex items-end justify-between gap-3">
        <div>
          <h1 className="font-display text-[26px] leading-tight font-bold tracking-tight text-ink sm:text-3xl">
            {title}
          </h1>
          {subtitle && <p className="mt-1 text-sm font-medium text-ink-soft">{subtitle}</p>}
        </div>
        {right}
      </div>
      <div className="mt-3 h-1 w-16 rounded-full" style={{ background: accent.gradient }} />
    </motion.div>
  )
}

export function AccentChip({
  accent,
  children,
  solid = false,
  className = '',
}: {
  accent: Accent
  children: ReactNode
  solid?: boolean
  className?: string
}) {
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 font-mono text-[11px] font-semibold tracking-wide ${className}`}
      style={
        solid
          ? { background: accent.gradient, color: '#fff' }
          : { background: accent.wash, color: accent.deep, border: `1px solid ${accent.glowSoft}` }
      }
    >
      {children}
    </span>
  )
}

export function GradientButton({
  accent,
  children,
  onClick,
  className = '',
  breathe = false,
  disabled = false,
  type = 'button',
}: {
  accent: Accent
  children: ReactNode
  onClick?: () => void
  className?: string
  breathe?: boolean
  disabled?: boolean
  type?: 'button' | 'submit'
}) {
  return (
    <motion.button
      type={type}
      disabled={disabled}
      whileTap={{ scale: 0.97 }}
      onClick={onClick}
      className={`inline-flex items-center justify-center gap-2 rounded-2xl px-5 py-3 font-display text-[15px] font-bold text-white disabled:opacity-50 ${breathe ? 'breathe' : ''} ${className}`}
      style={{
        ...(accentVars(accent) as CSSProperties),
        background: accent.gradient,
        boxShadow: `0 12px 28px -10px ${accent.glowStrong}, inset 0 1px 0 rgba(255,255,255,0.35)`,
      }}
    >
      {children}
    </motion.button>
  )
}

export function GhostButton({
  children,
  onClick,
  className = '',
}: {
  children: ReactNode
  onClick?: () => void
  className?: string
}) {
  return (
    <motion.button
      type="button"
      whileTap={{ scale: 0.97 }}
      onClick={onClick}
      className={`glass inline-flex items-center justify-center gap-2 rounded-2xl px-4 py-2.5 text-sm font-bold text-ink ${className}`}
    >
      {children}
    </motion.button>
  )
}

export function Stepper({
  value,
  onChange,
  step = 1,
  min = 0,
  max = 99999,
  unit,
  accent,
  big = false,
}: {
  value: number
  onChange: (v: number) => void
  step?: number
  min?: number
  max?: number
  unit?: string
  accent: Accent
  big?: boolean
}) {
  const dec = (): void => onChange(Math.max(min, Math.round((value - step) * 100) / 100))
  const inc = (): void => onChange(Math.min(max, Math.round((value + step) * 100) / 100))
  const btn =
    'flex h-10 w-10 shrink-0 items-center justify-center rounded-xl font-mono text-lg font-bold text-white active:scale-95 transition-transform'
  return (
    <div className="flex items-center gap-3">
      <button type="button" className={btn} style={{ background: accent.gradient }} onClick={dec} aria-label="decrease">
        -
      </button>
      <div className={`min-w-[4.5rem] text-center font-mono font-bold text-ink ${big ? 'text-3xl' : 'text-xl'}`}>
        {step < 1 ? value.toFixed(2).replace(/\.?0+$/, '') || '0' : value}
        {unit && <span className="ml-1 text-xs font-semibold text-ink-soft">{unit}</span>}
      </div>
      <button type="button" className={btn} style={{ background: accent.gradient }} onClick={inc} aria-label="increase">
        +
      </button>
    </div>
  )
}

export function Toggle({
  on,
  onChange,
  accent,
  label,
}: {
  on: boolean
  onChange: (v: boolean) => void
  accent: Accent
  label?: string
}) {
  return (
    <button
      type="button"
      onClick={() => onChange(!on)}
      className="flex items-center gap-2"
      aria-pressed={on}
      aria-label={label}
    >
      <span
        className="relative h-7 w-12 rounded-full transition-colors duration-300"
        style={{ background: on ? accent.gradient : 'rgba(26,26,34,0.12)' }}
      >
        <span
          className="absolute top-0.5 h-6 w-6 rounded-full bg-white shadow-md transition-transform duration-300"
          style={{ transform: on ? 'translateX(22px)' : 'translateX(2px)' }}
        />
      </span>
    </button>
  )
}

export function Sparkline({
  values,
  accent,
  width = 120,
  height = 32,
}: {
  values: Array<number | null>
  accent: Accent
  width?: number
  height?: number
}) {
  const nums = values.map((v) => v ?? 0)
  const max = Math.max(...nums, 1)
  const min = Math.min(...nums, 0)
  const range = max - min || 1
  const pts = nums
    .map((v, i) => `${(i / Math.max(nums.length - 1, 1)) * width},${height - 3 - ((v - min) / range) * (height - 6)}`)
    .join(' ')
  const gid = `sg-${accent.key}-${width}`
  return (
    <svg width={width} height={height} className="overflow-visible" aria-hidden>
      <defs>
        <linearGradient id={gid} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor={accent.bright} />
          <stop offset="1" stopColor={accent.soft} />
        </linearGradient>
      </defs>
      <polyline points={pts} fill="none" stroke={`url(#${gid})`} strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" />
      {nums.length > 0 && (
        <circle
          cx={width}
          cy={height - 3 - ((nums[nums.length - 1] - min) / range) * (height - 6)}
          r={3}
          fill={accent.bright}
        />
      )}
    </svg>
  )
}

/* Bottom sheet on mobile, centered modal on larger screens */
export function Sheet({
  open,
  onClose,
  children,
  wide = false,
}: {
  open: boolean
  onClose: () => void
  children: ReactNode
  wide?: boolean
}) {
  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-50 flex items-end justify-center sm:items-center"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
        >
          <div className="absolute inset-0 bg-ink/20 backdrop-blur-sm" onClick={onClose} aria-hidden />
          <motion.div
            initial={{ y: 60, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={{ y: 60, opacity: 0 }}
            transition={{ duration: 0.28, ease: EASE }}
            className={`glass relative max-h-[88dvh] w-full overflow-y-auto rounded-t-3xl p-5 sm:rounded-3xl ${wide ? 'sm:max-w-2xl' : 'sm:max-w-md'} m-0 sm:m-4`}
            style={{ background: 'linear-gradient(150deg, rgba(255,255,255,0.88), rgba(255,255,255,0.78))' }}
          >
            {children}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}

export function Toasts({ items }: { items: Array<{ id: number; message: string; kind: 'error' | 'ok' }> }) {
  return (
    <div className="pointer-events-none fixed inset-x-0 bottom-4 z-[60] flex flex-col items-center gap-2 px-4">
      <AnimatePresence>
        {items.map((t) => (
          <motion.div
            key={t.id}
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 8 }}
            className="glass rounded-2xl px-4 py-2.5 text-sm font-semibold"
            style={{
              color: t.kind === 'error' ? '#b91c1c' : '#047857',
              boxShadow: `0 12px 30px -12px ${t.kind === 'error' ? 'rgba(220,38,38,0.4)' : 'rgba(16,185,129,0.4)'}`,
            }}
          >
            {t.message}
          </motion.div>
        ))}
      </AnimatePresence>
    </div>
  )
}

export function EmptyState({ title, body, icon }: { title: string; body: string; icon?: ReactNode }) {
  return (
    <div className="flex flex-col items-center py-10 text-center">
      {icon && <div className="mb-3 text-ink-faint">{icon}</div>}
      <p className="font-display text-lg font-bold text-ink">{title}</p>
      <p className="mt-1 max-w-xs text-sm font-medium text-ink-soft">{body}</p>
    </div>
  )
}
