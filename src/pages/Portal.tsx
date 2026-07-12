import { motion } from 'framer-motion'
import { format } from 'date-fns'
import { PortalCard } from '../components/PortalCard'
import { ACCENTS } from '../lib/theme'
import { BoltIcon, LeafIcon, TransitionIcon } from '../components/Icons'
import { useStore } from '../store/AppStore'
import { personaBySlug } from '../lib/persona'

const EASE = [0.22, 1, 0.36, 1] as const

function greeting(now: Date, name: string): string {
  const h = now.getHours()
  if (h < 5) return `Up late, ${name}.`
  if (h < 12) return `Good morning, ${name}.`
  if (h < 18) return `Good afternoon, ${name}.`
  return `Good evening, ${name}.`
}

export function Portal() {
  const { data } = useStore()
  const now = new Date()
  const profile = data.profile
  const persona = personaBySlug(profile?.persona ?? 'constantine')
  const firstName = profile?.display_name?.split(' ')[0] || persona.firstName
  const transition = data.programs.find((program) => program.slug === 'transition')
  const main = data.programs.find((program) => program.slug === 'main')

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
          {greeting(now, firstName)}
        </h1>
        <p className="mt-2 text-sm font-medium text-ink-soft">{persona.signature}</p>
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
          title={(transition?.name ?? 'Transition phase').toUpperCase()}
          subtitle={profile?.persona === 'june' ? 'Busy-day glute growth fallback' : profile?.persona === 'matthew' ? 'Fast, repeatable morning training' : 'Current program, home training'}
          icon={<TransitionIcon className="h-7 w-7" />}
          index={1}
        />
        <PortalCard
          to="/main-phase"
          accent={ACCENTS.violet}
          title={(main?.name ?? 'Main phase').toUpperCase()}
          subtitle={profile?.persona === 'june' ? 'Full glute-focused home programme' : profile?.persona === 'matthew' ? 'Lean power, abs and conditioning' : 'Elite V6, ready when you are'}
          icon={<BoltIcon className="h-7 w-7" />}
          index={2}
        />
        <PortalCard
          to="/avatar"
          accent={ACCENTS.emerald}
          title={profile?.display_name || persona.name}
          subtitle="Stats, level and what your body needs"
          portrait={persona.portrait}
          portraitAlt={`${profile?.display_name || persona.name} portrait`}
          index={3}
        />
      </div>
    </div>
  )
}
