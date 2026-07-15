import { AnimatePresence, motion } from 'framer-motion'
import { useMemo, useState } from 'react'
import type { ActivityLevel, Profile } from '../lib/types'
import {
  ACTIVITY_CATALOG,
  ACTIVITY_CATEGORIES,
  PAL_LABELS,
  PAL_TONES,
  blockSummary,
  activityCatalogMap,
  emptyActivityBlock,
  netKcalForBlock,
  type ActivityBlock,
  type ActivityCategory,
  type ActivityEstimate,
  type ActivityPreset,
  type ActivityType,
} from '../lib/activity'
import { ACCENTS } from '../lib/theme'
import { GlassCard, GradientButton, Sheet, Stepper } from './ui'
import { translateInterfaceText, useLanguage } from '../lib/i18n'

const amber = ACCENTS.amber

interface TodaysActivitiesProps {
  profile: Profile
  activityTypes: ActivityType[]
  blocks: ActivityBlock[]
  estimate: ActivityEstimate
  quickTdee: number
  quickLevel: ActivityLevel
  frequentPresets: ActivityPreset[]
  yesterdayBlocks: ActivityBlock[]
  onChange: (blocks: ActivityBlock[]) => void
}

const GUIDE_LEVELS: Array<{
  level: ActivityLevel
  steps: string
  feet: string
  example: string
}> = [
  { level: 'sedentary', steps: '<5k steps', feet: '<2h on feet', example: 'Editing day, car everywhere, no workout.' },
  { level: 'light', steps: '5k to 7.5k', feet: '2 to 3h on feet', example: 'Desk day plus one short home workout.' },
  { level: 'moderate', steps: '7.5k to 10k', feet: '3 to 5h on feet', example: 'Desk day plus a full 45 to 60-minute session.' },
  { level: 'very', steps: '10k to 14k', feet: '5 to 8h on feet', example: 'Full shoot day or 4 to 6 massages given.' },
  { level: 'extra', steps: '14k+ steps', feet: '8h+ physical work', example: 'Championship filming marathon or double session day.' },
]

const PERSONA_DAYS = [
  { icon: 'camera', role: 'Videographer', day: '6h moving shoot + 2h rig carry', level: 'VERY' },
  { icon: 'hands', role: 'Massage therapist', day: '5 × 60-minute sessions', level: 'VERY' },
  { icon: 'desk', role: 'Office worker', day: 'Desk day + 50-minute gym session', level: 'MODERATE' },
]

function presetsFor(profile: Profile): ActivityPreset[] {
  if (profile.persona === 'constantine') {
    return [
      { label: '4h gimbal', typeId: 'gimbal-filming', patch: { durationMin: 240 } },
      { label: '2h rig carry', typeId: 'event-rig-carry', patch: { durationMin: 120 } },
      { label: '5 km run', typeId: 'jog-run', patch: { distanceKm: 5 } },
      { label: '8k steps', typeId: 'incidental-steps', patch: { steps: 8000 } },
    ]
  }
  if (profile.persona === 'june') {
    return [
      { label: '2 × 60m massage', typeId: 'massage-session', patch: { quantity: 2, durationMin: 60 } },
      { label: '20m APEX', typeId: 'apex-strength', patch: { durationMin: 20 } },
      { label: '30m cleaning', typeId: 'household-cleaning', patch: { quantity: 1, durationMin: 30 } },
      { label: '6k steps', typeId: 'incidental-steps', patch: { steps: 6000 } },
    ]
  }
  if (profile.persona === 'matthew') {
    return [
      { label: '60m strength', typeId: 'full-gym', patch: { durationMin: 60 } },
      { label: '25m HIIT', typeId: 'focus-hiit', patch: { durationMin: 25 } },
      { label: '5 km run', typeId: 'jog-run', patch: { distanceKm: 5 } },
      { label: '8k steps', typeId: 'incidental-steps', patch: { steps: 8000 } },
    ]
  }
  return [
    { label: '4h standing', typeId: 'standing-job', patch: { durationMin: 240 } },
    { label: '1h childcare', typeId: 'active-childcare', patch: { durationMin: 60 } },
    { label: '30m walk', typeId: 'casual-walk', patch: { durationMin: 30 } },
    { label: '6k steps', typeId: 'incidental-steps', patch: { steps: 6000 } },
  ]
}

function ActivityGlyph({ name, className = 'h-5 w-5' }: { name: string; className?: string }) {
  const common = { fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const }
  if (name === 'camera' || name === 'tripod') {
    return <svg viewBox="0 0 24 24" className={className} {...common}><rect x="4" y="7" width="14" height="10" rx="2" /><circle cx="11" cy="12" r="3" /><path d="m18 10 3-2v8l-3-2M8 7l1.3-2h4.4L15 7" /></svg>
  }
  if (name === 'hands') {
    return <svg viewBox="0 0 24 24" className={className} {...common}><path d="M7 13V6.8a1.5 1.5 0 0 1 3 0V11M10 11V5.7a1.5 1.5 0 0 1 3 0V11M13 11V7a1.5 1.5 0 0 1 3 0v6" /><path d="M7 10.5 5.8 9.3a1.5 1.5 0 0 0-2.2 2l3.3 5.1A5 5 0 0 0 11.1 19H13a5 5 0 0 0 5-5v-3a1.5 1.5 0 0 0-2-1.4" /></svg>
  }
  if (name === 'strength' || name === 'hammer') {
    return <svg viewBox="0 0 24 24" className={className} {...common}><path d="M5 9v6M8 7v10M16 7v10M19 9v6M8 12h8" /></svg>
  }
  if (name === 'bolt') {
    return <svg viewBox="0 0 24 24" className={className} {...common}><path d="m13.5 2-8 12H12l-1.5 8 8-12H12l1.5-8Z" /></svg>
  }
  if (name === 'desk') {
    return <svg viewBox="0 0 24 24" className={className} {...common}><rect x="5" y="4" width="14" height="9" rx="2" /><path d="M3 17h18M7 17v3M17 17v3M10 13v4" /></svg>
  }
  if (name === 'case') {
    return <svg viewBox="0 0 24 24" className={className} {...common}><rect x="3" y="7" width="18" height="13" rx="3" /><path d="M9 7V5h6v2M3 12h18M10 12v2h4v-2" /></svg>
  }
  if (name === 'cart') {
    return <svg viewBox="0 0 24 24" className={className} {...common}><path d="M3 4h2l2.2 10.2a2 2 0 0 0 2 1.6h7.9a2 2 0 0 0 1.9-1.4L21 8H6" /><circle cx="10" cy="19" r="1" /><circle cx="17" cy="19" r="1" /></svg>
  }
  if (name === 'home') {
    return <svg viewBox="0 0 24 24" className={className} {...common}><path d="m3 11 9-7 9 7M5 10v10h14V10M9 20v-6h6v6" /></svg>
  }
  if (name === 'watch') {
    return <svg viewBox="0 0 24 24" className={className} {...common}><rect x="7" y="6" width="10" height="12" rx="3" /><path d="m9 6 1-3h4l1 3M9 18l1 3h4l1-3M10 12h2l1-2 1 4" /></svg>
  }
  if (name === 'mobility') {
    return <svg viewBox="0 0 24 24" className={className} {...common}><circle cx="12" cy="5" r="2" /><path d="m8 21 2-7-3-3M16 21l-2-7 3-3M7 11l5-3 5 3" /></svg>
  }
  return <svg viewBox="0 0 24 24" className={className} {...common}><path d="M4 17c3-1 4-4 5-7l3 4 3-7 2 6h3" /><circle cx="6" cy="19" r="1.5" /><circle cx="18" cy="19" r="1.5" /></svg>
}

function presetBlock(preset: ActivityPreset, catalog: Map<string, ActivityType>): ActivityBlock {
  const type = catalog.get(preset.typeId)
  if (!type) throw new Error(`Unknown activity type ${preset.typeId}`)
  return { ...emptyActivityBlock(type), ...preset.patch }
}

function changeAmount(block: ActivityBlock, direction: -1 | 1, catalog: Map<string, ActivityType>): ActivityBlock {
  const type = catalog.get(block.typeId)
  if (!type) return block
  if (type.inputStyle === 'count') return { ...block, quantity: Math.max(1, block.quantity + direction), reconciled: false }
  if (type.inputStyle === 'duration') {
    const step = (type.defaultDurationMin ?? 30) >= 60 ? 30 : 5
    return { ...block, durationMin: Math.max(step, (block.durationMin ?? step) + direction * step), reconciled: false }
  }
  if (type.inputStyle === 'distance') return { ...block, distanceKm: Math.max(0.5, (block.distanceKm ?? 0.5) + direction * 0.5), reconciled: false }
  if (type.inputStyle === 'steps') return { ...block, steps: Math.max(0, (block.steps ?? 0) + direction * 1000), reconciled: false }
  return { ...block, watchKcal: Math.max(0, (block.watchKcal ?? 0) + direction * 25), reconciled: false }
}

function ActivityEditor({
  type,
  block,
  profile,
  catalog,
  onChange,
  onAdd,
}: {
  type: ActivityType
  block: ActivityBlock
  profile: Profile
  catalog: Map<string, ActivityType>
  onChange: (block: ActivityBlock) => void
  onAdd: () => void
}) {
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const kcal = Math.round(netKcalForBlock(block, profile.weight_kg, catalog))
  const longDuration = (type.defaultDurationMin ?? 0) >= 60
  const hasSessionLengthPicker = type.id === 'massage-session' || type.id === 'deep-tissue-massage'

  return (
    <motion.div
      initial={{ opacity: 0, height: 0 }}
      animate={{ opacity: 1, height: 'auto' }}
      className="overflow-hidden"
    >
      <div className="mx-1 mb-3 rounded-[1.4rem] border border-amber-400/20 bg-amber-50/55 p-4 shadow-inner">
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="text-sm font-bold text-ink">{t('Tune this block')}</p>
            <p className="mt-0.5 text-[11px] leading-relaxed font-medium text-ink-soft">{t(type.notes)}</p>
          </div>
          <div className="shrink-0 text-right">
            <motion.p key={kcal} initial={{ scale: 1.12, opacity: 0.6 }} animate={{ scale: 1, opacity: 1 }} className="font-mono text-xl font-bold" style={{ color: amber.deep }}>
              +{kcal}
            </motion.p>
            <p className="font-mono text-[8px] font-bold tracking-[0.14em] text-ink-faint uppercase">{t('NET KCAL')}</p>
          </div>
        </div>

        <div className="mt-4 space-y-4">
          {type.inputStyle === 'count' && (
            <>
              <div className="flex items-center justify-between gap-3">
                <p className="text-xs font-bold text-ink-soft">{t('How many?')}</p>
                <Stepper value={block.quantity} onChange={(quantity) => onChange({ ...block, quantity })} min={1} max={12} accent={amber} />
              </div>
              {hasSessionLengthPicker ? (
                <div>
                  <p className="mb-2 text-xs font-bold text-ink-soft">{t('Length each')}</p>
                  <div className="grid grid-cols-3 gap-2">
                    {[30, 60, 90].map((minutes) => (
                      <button
                        key={minutes}
                        type="button"
                        onClick={() => onChange({ ...block, durationMin: minutes })}
                        className="rounded-xl px-3 py-2 font-mono text-xs font-bold transition"
                        style={block.durationMin === minutes ? { background: amber.gradient, color: '#fff' } : { background: 'rgba(255,255,255,.75)', color: '#55555f', border: '1px solid rgba(26,26,34,.08)' }}
                      >
                        {minutes} min
                      </button>
                    ))}
                  </div>
                </div>
              ) : (
                <div className="flex items-center justify-between rounded-xl bg-white/55 px-3 py-2">
                  <p className="text-xs font-bold text-ink-soft">{t('Each block')}</p>
                  <p className="font-mono text-xs font-bold text-ink">{type.defaultDurationMin ?? block.durationMin ?? 0} min</p>
                </div>
              )}
            </>
          )}

          {type.inputStyle === 'duration' && (
            <div className="flex items-center justify-between gap-3">
              <p className="text-xs font-bold text-ink-soft">{t('Time active')}</p>
              <Stepper
                value={longDuration ? (block.durationMin ?? 60) / 60 : block.durationMin ?? 30}
                onChange={(value) => onChange({ ...block, durationMin: Math.round(value * (longDuration ? 60 : 1)) })}
                step={longDuration ? 0.5 : 5}
                min={longDuration ? 0.5 : 5}
                max={longDuration ? 16 : 240}
                unit={longDuration ? 'h' : 'min'}
                accent={amber}
              />
            </div>
          )}

          {type.inputStyle === 'distance' && (
            <div className="flex items-center justify-between gap-3">
              <p className="text-xs font-bold text-ink-soft">{t('Distance')}</p>
              <Stepper value={block.distanceKm ?? 5} onChange={(distanceKm) => onChange({ ...block, distanceKm })} step={0.5} min={0.5} max={100} unit="km" accent={amber} />
            </div>
          )}

          {type.inputStyle === 'steps' && (
            <div>
              <p className="mb-2 text-xs leading-relaxed font-bold text-ink-soft">{t('Steps not already covered by the blocks above.')}</p>
              <Stepper value={block.steps ?? 5000} onChange={(steps) => onChange({ ...block, steps })} step={1000} min={0} max={50000} unit="steps" accent={amber} />
            </div>
          )}

          {type.inputStyle === 'watch_kcal' && (
            <div className="flex items-center justify-between gap-3">
              <p className="text-xs font-bold text-ink-soft">{t('Watch reading')}</p>
              <Stepper value={block.watchKcal ?? 300} onChange={(watchKcal) => onChange({ ...block, watchKcal })} step={25} min={0} max={3000} unit="kcal" accent={amber} />
            </div>
          )}

          {type.supportsWatch && type.inputStyle !== 'watch_kcal' && (
            <label className="flex items-center justify-between gap-3 rounded-xl bg-white/55 px-3 py-2">
              <span>
                <span className="block text-xs font-bold text-ink">{t('Watch kcal')} <span className="font-medium text-ink-faint">{t('optional')}</span></span>
                <span className="block text-[9px] font-medium text-ink-faint">{t('APEX counts 80% and uses the higher estimate, never both.')}</span>
              </span>
              <input
                type="number"
                inputMode="numeric"
                min="0"
                value={block.watchKcal ?? ''}
                onChange={(event) => onChange({ ...block, watchKcal: event.target.value === '' ? null : Number(event.target.value) })}
                className="w-20 rounded-lg border border-ink/10 bg-white/80 px-2 py-1.5 text-right font-mono text-sm font-bold text-ink outline-none focus:border-amber-400"
                placeholder="0"
              />
            </label>
          )}
        </div>

        <div className="mt-4 flex items-center justify-between gap-3">
          <p className="text-[10px] leading-relaxed font-medium text-ink-faint">{t('Scaled live for')} {profile.weight_kg} kg</p>
          <GradientButton accent={amber} onClick={onAdd} className="!rounded-xl !px-4 !py-2.5 !text-xs">
            {t('Add to today')}
          </GradientButton>
        </div>
      </div>
    </motion.div>
  )
}

export function TodaysActivities({
  profile,
  activityTypes,
  blocks,
  estimate,
  quickTdee,
  quickLevel,
  frequentPresets,
  yesterdayBlocks,
  onChange,
}: TodaysActivitiesProps) {
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const [sheet, setSheet] = useState<'catalog' | 'guide' | null>(null)
  const [category, setCategory] = useState<ActivityCategory>('camera')
  const [draft, setDraft] = useState<ActivityBlock | null>(null)
  const catalog = useMemo(() => activityCatalogMap(activityTypes), [activityTypes])
  const availableTypes = activityTypes.length > 0 ? activityTypes : ACTIVITY_CATALOG
  const presets = useMemo(
    () => frequentPresets.length > 0 ? frequentPresets : presetsFor(profile),
    [frequentPresets, profile],
  )
  const precise = blocks.length > 0
  const displayTdee = precise ? estimate.tdee : quickTdee
  const displayLevel = precise ? estimate.level : quickLevel
  const tone = PAL_TONES[displayLevel]
  const categoryTypes = availableTypes.filter((type) => type.category === category)
  const hasCoveredMovement = blocks.some((item) => {
    const type = catalog.get(item.typeId)
    return item.typeId !== 'incidental-steps' && (type?.met ?? 1.2) > 1.2
  })
  const hasSteps = blocks.some((item) => item.typeId === 'incidental-steps')

  const addBlock = (block: ActivityBlock): void => onChange([...blocks, { ...block, id: crypto.randomUUID() }])
  const removeBlock = (id: string): void => onChange(blocks.filter((block) => block.id !== id))
  const updateBlock = (next: ActivityBlock): void => onChange(blocks.map((block) => block.id === next.id ? next : block))

  const openType = (type: ActivityType): void => setDraft(emptyActivityBlock(type))
  const addDraft = (): void => {
    if (!draft) return
    addBlock(draft)
    setDraft(null)
    setSheet(null)
  }

  const repeatYesterday = (): void => {
    if (yesterdayBlocks.length === 0) return
    const repeated = yesterdayBlocks.map((block) => ({
      ...block,
      id: crypto.randomUUID(),
      source: 'manual' as const,
      reconciled: false,
    }))
    onChange([...blocks, ...repeated])
  }

  return (
    <>
      <div id="today-activities" className="scroll-mt-24" data-testid="today-activities-panel">
      <GlassCard accent={amber} breathe={precise} className="p-0">
        <div className="p-4 sm:p-6">
          <div className="flex items-center justify-between gap-3">
            <div className="flex items-center gap-2">
              <span className="font-mono text-[9px] font-bold tracking-[0.22em] text-ink-faint uppercase">Daily activity engine</span>
              <span className="relative flex h-2 w-2" aria-hidden>
                {precise && <span className="absolute inset-0 animate-ping rounded-full bg-amber-400 opacity-45" />}
                <span className={`relative h-2 w-2 rounded-full ${precise ? 'bg-amber-500' : 'bg-ink/20'}`} />
              </span>
            </div>
            <button
              type="button"
              onClick={() => setSheet('guide')}
              className="flex h-8 w-8 items-center justify-center rounded-full border border-ink/8 bg-white/65 font-mono text-xs font-bold text-ink-soft shadow-sm"
              aria-label="Open activity level guide"
            >
              i
            </button>
          </div>

          <div className="mt-3 flex items-start justify-between gap-3">
            <div className="min-w-0 pt-1">
              <div className="flex flex-wrap items-center gap-2">
                <h2 className="font-display text-[22px] leading-none font-bold tracking-tight text-ink">Today's Activities</h2>
                <span
                  className="rounded-full px-2 py-0.5 font-mono text-[8px] font-bold tracking-[0.16em] uppercase"
                  style={precise ? { background: amber.gradient, color: '#fff' } : { background: 'rgba(26,26,34,.06)', color: '#74747f' }}
                >
                  {precise ? 'Precise' : 'Quick'}
                </span>
              </div>
              <p className="mt-2 max-w-[14rem] text-[12px] leading-relaxed font-medium text-ink-soft">
                Your baseline plus only the movement you log. No double counting.
              </p>
            </div>
            <div className="shrink-0 text-right">
              <motion.p
                key={displayTdee}
                initial={{ opacity: 0.45, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                className="font-mono text-[30px] leading-none font-bold tracking-[-0.07em]"
                style={{ color: tone.deep }}
              >
                {displayTdee.toLocaleString()}
              </motion.p>
              <p className="mt-1 font-mono text-[8px] font-bold tracking-[0.17em] text-ink-faint uppercase">estimated TDEE</p>
              <p className="mt-1 font-mono text-[10px] font-semibold" style={{ color: tone.deep }}>
                {precise ? `+${estimate.adjustedBlockKcal} activity` : 'one-tap estimate'}
              </p>
            </div>
          </div>

          <div className="mt-4 -mx-4 overflow-x-auto px-4 pb-1 [scrollbar-width:none] sm:-mx-6 sm:px-6">
            <div className="flex w-max gap-2">
              {presets.map((preset) => {
                const preview = presetBlock(preset, catalog)
                const kcal = Math.round(netKcalForBlock(preview, profile.weight_kg, catalog))
                return (
                  <button
                    key={preset.label}
                    type="button"
                    onClick={() => addBlock(preview)}
                    className="group flex items-center gap-2 rounded-2xl border border-amber-500/15 bg-white/70 px-3 py-2 text-left shadow-sm transition active:scale-[0.97]"
                    aria-label={`Add frequent activity ${preset.label}`}
                  >
                    <span className="flex h-7 w-7 items-center justify-center rounded-xl text-amber-700" style={{ background: amber.wash }}>
                      <ActivityGlyph name={catalog.get(preset.typeId)?.icon ?? 'walk'} className="h-4 w-4" />
                    </span>
                    <span>
                      <span className="block text-[11px] font-bold text-ink">{preset.label}</span>
                      <span className="block font-mono text-[8px] font-semibold text-ink-faint">+{kcal} net kcal</span>
                    </span>
                  </button>
                )
              })}
              <button
                type="button"
                onClick={repeatYesterday}
                disabled={yesterdayBlocks.length === 0}
                className="rounded-2xl border border-dashed border-ink/15 bg-white/40 px-3 py-2 text-[11px] font-bold text-ink-soft active:scale-[0.97] disabled:opacity-40"
              >
                {yesterdayBlocks.length > 0 ? '↻ Repeat yesterday' : 'No yesterday yet'}
              </button>
              <button
                type="button"
                onClick={() => setSheet('catalog')}
                className="rounded-2xl px-4 py-2 text-[11px] font-bold text-white shadow-md active:scale-[0.97]"
                style={{ background: amber.gradient }}
              >
                + Add block
              </button>
            </div>
          </div>

          <AnimatePresence initial={false}>
            {precise ? (
              <motion.div key="blocks" initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }} className="overflow-hidden">
                <div className="mt-4 space-y-2">
                  {blocks.map((block) => {
                    const type = catalog.get(block.typeId)
                    if (!type) return null
                    const kcal = Math.round(netKcalForBlock(block, profile.weight_kg, catalog))
                    return (
                      <motion.div
                        layout
                        key={block.id}
                        drag="x"
                        dragConstraints={{ left: -88, right: 0 }}
                        dragElastic={0.08}
                        onDragEnd={(_, info) => { if (info.offset.x < -72) removeBlock(block.id) }}
                        className="flex items-center gap-3 rounded-2xl border border-white/80 bg-white/58 p-2.5 shadow-sm"
                        data-testid="activity-block"
                      >
                        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl text-amber-700" style={{ background: amber.wash }}>
                          <ActivityGlyph name={type.icon} />
                        </span>
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-[12px] font-bold text-ink">{type.shortName}</p>
                          <p className="font-mono text-[9px] font-semibold text-ink-faint">{blockSummary(block, catalog)} · {block.reconciled ? 'final' : 'planned'}</p>
                        </div>
                        <div className="flex shrink-0 items-center gap-1.5">
                          <button type="button" onClick={() => updateBlock(changeAmount(block, -1, catalog))} aria-label={`Decrease ${type.name}`} className="flex h-7 w-7 items-center justify-center rounded-lg bg-ink/5 font-mono text-sm font-bold text-ink-soft">−</button>
                          <div className="min-w-12 text-center">
                            <p className="font-mono text-xs font-bold" style={{ color: amber.deep }}>+{kcal}</p>
                            <p className="font-mono text-[7px] font-semibold text-ink-faint">KCAL</p>
                          </div>
                          <button type="button" onClick={() => updateBlock(changeAmount(block, 1, catalog))} aria-label={`Increase ${type.name}`} className="flex h-7 w-7 items-center justify-center rounded-lg bg-ink/5 font-mono text-sm font-bold text-ink-soft">+</button>
                          <button type="button" onClick={() => removeBlock(block.id)} aria-label={`Remove ${type.name}`} className="ml-0.5 flex h-7 w-7 items-center justify-center rounded-lg text-sm font-bold text-ink-faint">×</button>
                        </div>
                      </motion.div>
                    )
                  })}
                </div>
                {hasCoveredMovement && hasSteps && (
                  <p className="mt-2 rounded-xl bg-amber-50/70 px-3 py-2 text-[10px] leading-relaxed font-medium text-amber-800">
                    Keep the steps field incidental. Subtract steps already represented by your walk or run block.
                  </p>
                )}
              </motion.div>
            ) : (
              <motion.button
                key="empty"
                type="button"
                onClick={() => setSheet('catalog')}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="mt-4 flex w-full items-center justify-between rounded-2xl border border-dashed border-amber-500/25 bg-white/35 px-3.5 py-3 text-left"
              >
                <span>
                  <span className="block text-[12px] font-bold text-ink">Want today's true number?</span>
                  <span className="mt-0.5 block text-[10px] font-medium text-ink-soft">Add one real activity and APEX switches to Precise Mode.</span>
                </span>
                <span className="ml-3 text-xl text-amber-600">+</span>
              </motion.button>
            )}
          </AnimatePresence>

          <div className="mt-4 grid grid-cols-[1fr_auto_1fr_auto_1fr] items-center gap-2 rounded-2xl border border-ink/5 bg-white/38 px-3 py-2.5 text-center">
            <div>
              <p className="font-mono text-[8px] font-bold tracking-wider text-ink-faint uppercase">Floor</p>
              <p className="font-mono text-sm font-bold text-ink">{estimate.floorKcal}</p>
            </div>
            <span className="font-mono text-sm text-ink-faint">+</span>
            <div>
              <p className="font-mono text-[8px] font-bold tracking-wider text-ink-faint uppercase">Blocks</p>
              <p className="font-mono text-sm font-bold text-ink">{precise ? estimate.adjustedBlockKcal : 'Quick'}</p>
            </div>
            <span className="font-mono text-sm text-ink-faint">=</span>
            <div>
              <p className="font-mono text-[8px] font-bold tracking-wider text-ink-faint uppercase">Today</p>
              <p className="font-mono text-sm font-bold" style={{ color: tone.deep }}>{displayTdee}</p>
            </div>
          </div>

          <motion.div
            layout
            className="mt-3 flex items-center justify-between gap-3 rounded-2xl border px-3.5 py-3"
            style={{ background: tone.wash, borderColor: `${tone.bright}33`, boxShadow: precise ? `0 12px 32px -18px ${tone.glow}` : undefined }}
          >
            <div className="min-w-0">
              <p className="font-mono text-[8px] font-bold tracking-[0.16em] uppercase" style={{ color: tone.deep }}>
                {precise ? `Computes to PAL ${estimate.pal.toFixed(2)}` : 'Current one-tap selection'}
              </p>
              <p className="mt-0.5 truncate text-[13px] font-bold text-ink">
                {PAL_LABELS[displayLevel].toUpperCase()} <span className="font-medium text-ink-soft">· {displayTdee.toLocaleString()} kcal day</span>
              </p>
            </div>
            {precise && (
              <button type="button" onClick={() => onChange([])} className="shrink-0 rounded-full bg-white/65 px-3 py-1.5 text-[9px] font-bold text-ink-soft shadow-sm">
                Clear day
              </button>
            )}
          </motion.div>

          {profile.calibration_history.length > 0 && Math.abs(profile.calibration_k - 1) >= 0.005 && (
            <p className="mt-2 rounded-xl bg-white/42 px-3 py-2 text-[10px] leading-relaxed font-medium text-ink-soft">
              Your engine runs about {Math.round(Math.abs(profile.calibration_k - 1) * 100)}% {profile.calibration_k >= 1 ? 'hotter' : 'cooler'} than the textbook estimate. Calibrated from your recent logged intake and morning weight.
            </p>
          )}

          {precise && estimate.safetyClamped && (
            <p className="mt-2 rounded-xl bg-amber-50/70 px-3 py-2 text-[10px] leading-relaxed font-medium text-amber-800">
              Your goal adjustment reached the recovery floor, so APEX held calories at BMR × 1.05 instead of cutting lower.
            </p>
          )}

          {precise && (
            <div className="mt-3 flex items-center justify-between gap-3 px-1">
              <p className="text-[10px] font-medium text-ink-faint">Plan now. Use + or − tonight if reality changed.</p>
              <span className="shrink-0 font-mono text-[8px] font-bold tracking-wider text-ink-faint uppercase">Swipe left to delete</span>
            </div>
          )}
        </div>
      </GlassCard>
      </div>

      <Sheet open={sheet === 'catalog'} onClose={() => { setSheet(null); setDraft(null) }} wide>
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="font-mono text-[9px] font-bold tracking-[0.2em] text-amber-700 uppercase">{t('Build the day')}</p>
            <h2 className="mt-1 font-display text-2xl font-bold tracking-tight text-ink">{t('Add an activity block')}</h2>
            <p className="mt-1 text-xs font-medium text-ink-soft">{t('Pick the closest real activity, then tune the amount.')}</p>
          </div>
          <button type="button" onClick={() => { setSheet(null); setDraft(null) }} aria-label="Close add activity sheet" className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-ink/5 text-lg text-ink-soft">×</button>
        </div>

        <div className="mt-4 -mx-5 overflow-x-auto px-5 [scrollbar-width:none]">
          <div className="flex w-max gap-2 pb-2">
            {ACTIVITY_CATEGORIES.map((item) => (
              <button
                key={item.id}
                type="button"
                onClick={() => { setCategory(item.id); setDraft(null) }}
                className="rounded-full px-3 py-1.5 text-[10px] font-bold transition"
                style={category === item.id ? { background: amber.gradient, color: '#fff' } : { background: 'rgba(255,255,255,.65)', color: '#55555f', border: '1px solid rgba(26,26,34,.08)' }}
              >
                {t(item.label)}
              </button>
            ))}
          </div>
        </div>

        <div className="mt-2 space-y-2">
          {categoryTypes.map((type) => {
            const sample = emptyActivityBlock(type, `preview-${type.id}`)
            const kcal = Math.round(netKcalForBlock(sample, profile.weight_kg, catalog))
            const selected = draft?.typeId === type.id
            return (
              <div key={type.id}>
                <button
                  type="button"
                  onClick={() => openType(type)}
                  aria-label={`${t('Configure')} ${t(type.name)}`}
                  className="flex w-full items-center gap-3 rounded-2xl border bg-white/55 p-3 text-left transition active:scale-[0.99]"
                  style={{ borderColor: selected ? amber.glowStrong : 'rgba(26,26,34,.07)', boxShadow: selected ? `0 10px 28px -20px ${amber.glowStrong}` : undefined }}
                >
                  <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl text-amber-700" style={{ background: amber.wash }}>
                    <ActivityGlyph name={type.icon} />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[13px] font-bold text-ink">{t(type.name)}</span>
                    <span className="mt-0.5 block truncate text-[10px] font-medium text-ink-soft">{t(type.notes)}</span>
                  </span>
                  <span className="shrink-0 text-right">
                    <span className="block font-mono text-xs font-bold" style={{ color: amber.deep }}>{kcal > 0 ? `+${kcal}` : t('FLOOR')}</span>
                    <span className="block font-mono text-[7px] font-semibold tracking-wide text-ink-faint">{t(kcal > 0 ? 'NET KCAL' : 'COVERED')}</span>
                  </span>
                </button>
                {selected && draft && <ActivityEditor type={type} block={draft} profile={profile} catalog={catalog} onChange={setDraft} onAdd={addDraft} />}
              </div>
            )
          })}
        </div>
      </Sheet>

      <Sheet open={sheet === 'guide'} onClose={() => setSheet(null)} wide>
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="font-mono text-[9px] font-bold tracking-[0.2em] text-amber-700 uppercase">Quick Mode guide</p>
            <h2 className="mt-1 font-display text-2xl font-bold tracking-tight text-ink">What does active mean?</h2>
            <p className="mt-1 text-xs leading-relaxed font-medium text-ink-soft">Use steps and hours on your feet. The job title does not matter.</p>
          </div>
          <button type="button" onClick={() => setSheet(null)} aria-label="Close activity level guide" className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-ink/5 text-lg text-ink-soft">×</button>
        </div>

        <div className="mt-5 space-y-2">
          {GUIDE_LEVELS.map((item) => {
            const itemTone = PAL_TONES[item.level]
            return (
              <div key={item.level} className="rounded-2xl border bg-white/52 p-3" style={{ borderColor: `${itemTone.bright}22` }}>
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <p className="font-mono text-[10px] font-bold tracking-wider" style={{ color: itemTone.deep }}>{PAL_LABELS[item.level].toUpperCase()}</p>
                  <div className="flex gap-1.5">
                    <span className="rounded-full bg-white/70 px-2 py-1 font-mono text-[8px] font-bold text-ink-soft">{item.steps}</span>
                    <span className="rounded-full bg-white/70 px-2 py-1 font-mono text-[8px] font-bold text-ink-soft">{item.feet}</span>
                  </div>
                </div>
                <p className="mt-1.5 text-[11px] leading-relaxed font-medium text-ink-soft">{item.example}</p>
              </div>
            )
          })}
        </div>

        <div className="mt-5">
          <p className="font-mono text-[9px] font-bold tracking-[0.18em] text-ink-faint uppercase">Three completely different days</p>
          <div className="mt-2 space-y-2">
            {PERSONA_DAYS.map((day) => (
              <div key={day.role} className="flex items-center gap-3 rounded-2xl bg-white/55 p-3">
                <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl text-amber-700" style={{ background: amber.wash }}><ActivityGlyph name={day.icon} /></span>
                <div className="min-w-0 flex-1">
                  <p className="text-[11px] font-bold text-ink">{day.role}</p>
                  <p className="truncate text-[10px] font-medium text-ink-soft">{day.day}</p>
                </div>
                <span className="font-mono text-[8px] font-bold text-amber-700">{day.level}</span>
              </div>
            ))}
          </div>
        </div>
      </Sheet>
    </>
  )
}
