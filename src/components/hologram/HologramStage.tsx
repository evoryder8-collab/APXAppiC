import { useMemo } from 'react'
import type { Accent } from '../../lib/theme'
import type { DayType } from '../../lib/types'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import { HoloBody, type MuscleGroup } from '../../../Holographic Body Fitness Component/handoff/HoloBody'
import { musclesForWorkout, readableMuscleName } from './muscleMap'

export function HologramStage({
  dayType,
  accent,
  height = 260,
  exerciseNames = [],
}: {
  dayType: DayType | null
  accent: Accent
  height?: number
  exerciseNames?: string[]
}) {
  const { language } = useLanguage()
  const t = (value: string) => translateInterfaceText(value, language)
  const highlighted = useMemo(
    () => musclesForWorkout(dayType, exerciseNames) as MuscleGroup[],
    [dayType, exerciseNames],
  )
  const label = highlighted.slice(0, 4).map((muscle) => t(readableMuscleName(muscle))).join(' · ')

  return (
    <div
      className="glass rounded-3xl p-1.5"
      style={{ boxShadow: `inset 0 1px 0 rgba(255,255,255,0.95), 0 20px 44px -18px ${accent.glowSoft}` }}
    >
      <div
        className="relative overflow-hidden rounded-[20px] bg-[#060b16]"
        style={{
          height,
          boxShadow: `inset 0 0 0 1px ${accent.glowSoft}, inset 0 0 60px rgba(3,4,12,0.75)`,
        }}
        role="img"
        aria-label={label ? `${t('Holographic body')}: ${label}` : t('Holographic body')}
      >
        <HoloBody highlightedMuscles={highlighted} rotationSeconds={14} className="absolute inset-0" />
        <div className="pointer-events-none absolute inset-x-0 top-0 z-10 flex items-start justify-between gap-2 p-3">
          <span className="rounded-full border border-cyan-200/15 bg-[#06111d]/55 px-2.5 py-1 font-mono text-[8px] font-bold tracking-[0.14em] text-cyan-100/75 uppercase backdrop-blur-md">
            {t('Muscle target map')}
          </span>
          {label && (
            <span className="max-w-[62%] rounded-full border border-amber-200/15 bg-[#160e05]/55 px-2.5 py-1 text-right font-mono text-[7px] leading-tight font-bold tracking-[0.06em] text-amber-100/80 uppercase backdrop-blur-md">
              {label}
            </span>
          )}
        </div>
        <div className="pointer-events-none absolute inset-0 z-10 rounded-[20px]" style={{ boxShadow: 'inset 0 0 46px rgba(0,0,0,0.45)' }} aria-hidden />
      </div>
    </div>
  )
}
