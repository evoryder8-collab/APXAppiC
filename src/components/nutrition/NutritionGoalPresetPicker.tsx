import { useState } from 'react'
import type { Goal } from '../../lib/types.ts'
import type { NutritionGoalPreset } from '../../lib/nutrition.ts'

interface NutritionGoalPresetPickerProps {
  presets: NutritionGoalPreset[]
  selected: Goal
  onSelect: (goal: Goal) => void
  translate?: (value: string) => string
}

export function NutritionGoalPresetPicker({
  presets,
  selected,
  onSelect,
  translate = (value) => value,
}: NutritionGoalPresetPickerProps) {
  const [explainedGoal, setExplainedGoal] = useState<Goal | null>(null)
  const explained = presets.find((preset) => preset.goal === explainedGoal)

  return (
    <div>
      <div className="grid grid-cols-3 gap-2">
        {presets.map((preset) => {
          const active = selected === preset.goal
          return (
            <div key={preset.goal} className={`relative min-w-0 rounded-2xl border transition ${active ? 'border-amber-400 bg-amber-500 text-white shadow-[0_12px_26px_-16px_rgba(245,158,11,.8)]' : 'border-amber-500/15 bg-white/80 text-ink'}`}>
              <button
                type="button"
                aria-pressed={active}
                onClick={() => onSelect(preset.goal)}
                className="min-h-14 w-full rounded-2xl px-2 pb-2 pt-5 text-center text-[10px] font-black leading-tight sm:px-3 sm:text-xs"
              >
                {translate(preset.label)}
              </button>
              <button
                type="button"
                aria-label={`${translate('About')} ${translate(preset.label)}`}
                aria-expanded={explainedGoal === preset.goal}
                onClick={() => setExplainedGoal((current) => current === preset.goal ? null : preset.goal)}
                className={`absolute right-1.5 top-1.5 grid h-5 w-5 place-items-center rounded-full border text-[9px] font-black ${active ? 'border-white/70 text-white' : 'border-amber-500/45 text-amber-800'}`}
              >
                i
              </button>
            </div>
          )
        })}
      </div>
      {explained && (
        <div role="status" className="mt-2 rounded-2xl border border-amber-500/15 bg-amber-50/75 px-3.5 py-3 text-left">
          <p className="text-xs font-black text-ink">{translate(explained.label)} · {Math.round((explained.factor - 1) * 100) > 0 ? '+' : ''}{Math.round((explained.factor - 1) * 100)}%</p>
          <p className="mt-1 text-[11px] font-semibold leading-relaxed text-ink-soft">{translate(explained.explanation)}</p>
          <p className="mt-1.5 text-[10px] font-bold leading-relaxed text-amber-900">{translate(explained.caution)}</p>
        </div>
      )}
    </div>
  )
}
