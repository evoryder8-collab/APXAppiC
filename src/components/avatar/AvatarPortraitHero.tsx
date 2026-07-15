import { motion, useReducedMotion } from 'framer-motion'
import type { Profile } from '../../lib/types'
import { personaBySlug } from '../../lib/persona'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'

export function AvatarPortraitHero({ profile }: { profile: Profile }) {
  const persona = personaBySlug(profile.persona)
  const { language } = useLanguage()
  const reducedMotion = useReducedMotion()
  const t = (value: string): string => translateInterfaceText(value, language)

  return (
    <motion.section
      initial={reducedMotion ? false : { opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.7 }}
      className="relative isolate -mx-2 min-h-[370px] overflow-visible sm:min-h-[430px]"
      aria-label={`${persona.name} ${t('living profile')}`}
      style={{
        '--portrait-halo': persona.halo,
        '--portrait-color': persona.color,
        '--portrait-soft': persona.colorSoft,
      } as React.CSSProperties}
    >
      {/* The darkness is deliberately local to the subject. Its masked aura is
          roughly 30% wider than the portrait and dissolves into the page. */}
      <div className="pointer-events-none absolute inset-x-0 top-[48%] flex -translate-y-1/2 justify-center" aria-hidden>
      <div
        className="avatar-portrait-aura h-[330px] w-[min(96vw,470px)] sm:h-[390px] sm:w-[540px]"
        style={{
          background: `
            radial-gradient(ellipse at 50% 52%, rgba(3,7,18,.98) 0%, rgba(5,10,24,.94) 29%, rgba(8,14,30,.78) 45%, ${persona.halo} 61%, transparent 78%),
            radial-gradient(circle at 50% 44%, ${persona.color}38 0%, transparent 58%)
          `,
          WebkitMaskImage: 'radial-gradient(ellipse at center, #000 0 52%, rgba(0,0,0,.78) 63%, transparent 79%)',
          maskImage: 'radial-gradient(ellipse at center, #000 0 52%, rgba(0,0,0,.78) 63%, transparent 79%)',
        }}
      />
      </div>
      <div className="pointer-events-none absolute inset-x-0 top-[47%] flex -translate-y-1/2 justify-center" aria-hidden><div className="avatar-portrait-orbit h-[245px] w-[330px] rounded-[50%] border border-white/10 sm:h-[290px] sm:w-[410px]" /></div>
      <div className="pointer-events-none absolute inset-x-0 top-[48%] flex -translate-y-1/2 justify-center" aria-hidden><div className="avatar-portrait-orbit avatar-portrait-orbit-delay h-[190px] w-[285px] rounded-[50%] border sm:h-[230px] sm:w-[350px]" style={{ borderColor: `${persona.color}30` }} /></div>
      <div className="avatar-portrait-floor pointer-events-none absolute bottom-[3.9rem] left-1/2 h-16 w-[62%] max-w-[330px] -translate-x-1/2 rounded-[50%]" style={{ background: `radial-gradient(ellipse, ${persona.halo} 0%, rgba(2,6,16,.65) 38%, transparent 72%)` }} aria-hidden />

      <motion.div
        initial={reducedMotion ? false : { opacity: 0, y: -8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.22, duration: 0.55 }}
        className="absolute inset-x-0 top-3 z-20 flex justify-center"
      >
        <span className="rounded-full border border-white/12 bg-[#070b14]/55 px-3 py-1.5 font-mono text-[8px] font-black tracking-[0.24em] text-white/72 uppercase shadow-lg backdrop-blur-md">
          <span className="mr-2 inline-block h-1.5 w-1.5 rounded-full align-middle" style={{ background: persona.color, boxShadow: `0 0 12px ${persona.color}` }} />
          {t('Living profile')}
        </span>
      </motion.div>

      <div className="pointer-events-none absolute inset-x-0 top-9 z-10 flex justify-center">
        <motion.img
          src={persona.portrait}
          alt={`${persona.name} portrait`}
          initial={reducedMotion ? false : { opacity: 0, y: 34, scale: 0.9, filter: 'blur(14px) saturate(.55)' }}
          animate={{ opacity: 1, y: 0, scale: 1, filter: 'blur(0px) saturate(1.06)' }}
          transition={{ delay: 0.08, duration: 1.05, ease: [0.16, 1, 0.3, 1] }}
          className="avatar-portrait-subject h-[300px] w-[88%] max-w-[390px] object-contain object-bottom sm:h-[360px] sm:max-w-[455px]"
          style={{ filter: `drop-shadow(0 28px 34px rgba(0,0,0,.48)) drop-shadow(0 0 25px ${persona.halo})` }}
        />
      </div>

      <motion.div
        initial={reducedMotion ? false : { opacity: 0, y: 18 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.72, duration: 0.62, ease: [0.16, 1, 0.3, 1] }}
        className="absolute inset-x-3 bottom-0 z-20 text-center"
      >
        <p className="mx-auto inline-flex rounded-full border border-white/12 bg-[#07111f]/90 px-3 py-1.5 font-mono text-[9px] font-black tracking-[0.24em] uppercase shadow-[0_8px_22px_-13px_rgba(2,6,23,.95)] backdrop-blur-md" style={{ color: persona.colorSoft }}>
          {t(persona.title)}
        </p>
        <h1 className="mt-1 font-display text-[2rem] leading-none font-black tracking-[-0.045em] text-ink sm:text-4xl">{persona.name}</h1>
        <p className="mx-auto mt-2 max-w-md text-xs leading-relaxed font-semibold text-ink-soft">{t(persona.signature)}</p>
      </motion.div>
    </motion.section>
  )
}
