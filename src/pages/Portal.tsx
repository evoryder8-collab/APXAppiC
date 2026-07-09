import { motion } from 'framer-motion'
import { format } from 'date-fns'
import { PortalCard } from '../components/PortalCard'
import { ACCENTS } from '../lib/theme'
import { AvatarIcon, BoltIcon, LeafIcon, TransitionIcon } from '../components/Icons'

const EASE = [0.22, 1, 0.36, 1] as const

function greeting(now: Date): string {
  const h = now.getHours()
  if (h < 5) return 'Up late, Constantin.'
  if (h < 12) return 'Good morning, Constantin.'
  if (h < 18) return 'Good afternoon, Constantin.'
  return 'Good evening, Constantin.'
}

export function Portal() {
  const now = new Date()

  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col sm:min-h-[calc(100dvh-13rem)] sm:justify-center">
      <motion.header
        className="mt-2 mb-8 sm:mt-6 sm:mb-10"
        initial={{ opacity: 0, y: 18 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5, ease: EASE }}
      >
        <p className="font-mono text-[12px] font-medium tracking-[0.18em] text-ink-faint uppercase">
          {format(now, 'EEEE, d MMMM yyyy')}
        </p>
        <h1 className="mt-2 font-display text-[32px] leading-tight font-bold tracking-tight text-ink sm:text-4xl">
          {greeting(now)}
        </h1>
      </motion.header>

      <div className="grid gap-4 sm:grid-cols-2 sm:gap-5">
        <PortalCard
          to="/nutrition"
          accent={ACCENTS.amber}
          title="NUTRITION"
          subtitle="Meals, supplement stack, daily log"
          icon={<LeafIcon className="h-7 w-7" />}
          index={0}
        />
        <PortalCard
          to="/transition"
          accent={ACCENTS.teal}
          title="TRANSITION PHASE"
          subtitle="Current program, home training"
          icon={<TransitionIcon className="h-7 w-7" />}
          index={1}
        />
        <PortalCard
          to="/main-phase"
          accent={ACCENTS.violet}
          title="MAIN PHASE"
          subtitle="Elite V6, ready when you are"
          icon={<BoltIcon className="h-7 w-7" />}
          index={2}
        />
        <PortalCard
          to="/avatar"
          accent={ACCENTS.emerald}
          title="AVATAR"
          subtitle="Stats, level and what your body needs"
          icon={<AvatarIcon className="h-7 w-7" />}
          index={3}
        />
      </div>
    </div>
  )
}
