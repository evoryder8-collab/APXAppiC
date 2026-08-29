import { motion } from 'framer-motion'
import { format } from 'date-fns'
import { PortalCard } from '../components/PortalCard'
import { FitnessPlanDisclosure } from '../components/FitnessPlanDisclosure'
import { ACCENTS } from '../lib/theme'
import { DumbbellIcon, LeafIcon, OrbitIcon } from '../components/Icons'
import { useStore } from '../store/AppStore'
import { personaBySlug } from '../lib/persona'
import { PortalLanguageMenu } from '../components/PortalLanguageMenu'
import { useOrbitText } from '../orbit/ui/i18n'
import { useLanguage } from '../lib/i18n'
import { UI_TRANSLATIONS } from '../lib/translations'

const EASE = [0.22, 1, 0.36, 1] as const

function greeting(now: Date, name: string): string {
  const h = now.getHours()
  if (h < 5) return `Up late, ${name}.`
  if (h < 12) return `Good morning, ${name}.`
  if (h < 18) return `Good afternoon, ${name}.`
  return `Good evening, ${name}.`
}

export function Portal() {
  const { data, setSettings } = useStore()
  const t = useOrbitText()
  const { language } = useLanguage()
  const portalText = (value: string): string => language === 'en' ? value : UI_TRANSLATIONS[value]?.[language] ?? t(value)
  const now = new Date()
  const profile = data.profile
  const persona = personaBySlug(profile?.persona ?? 'constantine')
  const firstName = profile?.display_name?.split(' ')[0] || persona.firstName

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
        <div className="sm:col-span-2">
          <PortalCard
            to="/avatar"
            accent={ACCENTS.emerald}
            title={profile?.display_name || persona.name}
            subtitle="Stats, level and what your body needs"
            portrait={persona.portrait}
            portraitAlt={`${profile?.display_name || persona.name} portrait`}
            index={0}
          />
        </div>
        <div className="sm:col-span-2">
          <PortalCard
            to="/nutrition"
            accent={ACCENTS.amber}
            title="NUTRITION"
            subtitle="Meals, supplement stack, daily log"
            icon={<LeafIcon className="h-7 w-7" />}
            index={1}
          />
        </div>
        <div className="sm:col-span-2">
          <FitnessPlanDisclosure
            introSeen={Boolean(data.settings?.addons.fitness_plan_intro_seen)}
            onIntroSeen={() => {
              const addons = data.settings?.addons
              if (!addons) return
              setSettings({
                addons: {
                  ...addons,
                  fitness_plan_intro_seen: true,
                },
              })
            }}
            transitionTitle={portalText('Transition phase')}
            mainTitle={portalText('Main phase')}
            text={portalText}
          />
        </div>
        {data.programs.some((program) => program.slug === 'custom') && (
          <PortalCard
            to="/custom-workouts"
            accent={ACCENTS.violet}
            title={portalText('Custom workouts').toUpperCase()}
            subtitle={portalText('Sessions you built yourself')}
            icon={<DumbbellIcon className="h-7 w-7" />}
            index={3}
          />
        )}
        <PortalCard
          to="/orbit"
          accent={ACCENTS.ice}
          title="APEX ORBIT"
          subtitle="Run intelligence and marathon conditioning"
          icon={<OrbitIcon className="h-8 w-8" />}
          index={4}
        />
      </div>
      <PortalLanguageMenu />
    </div>
  )
}
