import type { Targets } from '../../lib/nutrition.ts'
import {
  restingEnergyProvenanceLabel,
  TARGET_REVIEW_REASON_LABELS,
  targetProvenanceLabel,
} from '../../lib/nutritionTargetPresentation.ts'

interface NutritionTargetStatusProps {
  targets: Pick<
    Targets,
    'activeBmr' | 'bmrSource' | 'isPublishable' | 'reviewReasons' | 'reviewState' | 'targetProvenance'
  >
  translate: (value: string) => string
}

export function NutritionTargetStatus({ targets, translate }: NutritionTargetStatusProps) {
  const needsReview = targets.reviewState !== 'ready'
  const stateLabel = targets.isPublishable ? 'Review recommended' : 'Target unavailable'

  return (
    <div
      data-testid="nutrition-target-status"
      data-target-review-state={targets.reviewState}
      className={`rounded-2xl border px-3.5 py-3 ${
        targets.isPublishable
          ? needsReview
            ? 'border-amber-300/45 bg-amber-50/70'
            : 'border-emerald-300/30 bg-emerald-50/55'
          : 'border-rose-300/40 bg-rose-50/70'
      }`}
    >
      <dl className="grid gap-2 text-[11px] sm:grid-cols-2">
        <div className="min-w-0">
          <dt className="font-mono text-[9px] font-black tracking-[0.14em] text-ink-faint uppercase">
            {translate('Target source')}
          </dt>
          <dd className="mt-0.5 break-words font-bold text-ink">
            {translate(targetProvenanceLabel(targets.targetProvenance))}
          </dd>
        </div>
        <div className="min-w-0">
          <dt className="font-mono text-[9px] font-black tracking-[0.14em] text-ink-faint uppercase">
            {translate('Resting energy')}
          </dt>
          <dd className="mt-0.5 break-words font-bold text-ink">
            {translate(restingEnergyProvenanceLabel(targets))}
            {targets.activeBmr > 0 ? ` · ${targets.activeBmr} kcal` : ''}
          </dd>
        </div>
      </dl>

      {needsReview && (
        <div className="mt-2.5 border-t border-current/10 pt-2.5" role="status" aria-live="polite">
          <p className={`text-[11px] font-black ${targets.isPublishable ? 'text-amber-900' : 'text-rose-800'}`}>
            {translate(stateLabel)}
          </p>
          <ul className="mt-1 space-y-1">
            {targets.reviewReasons.map((reason) => (
              <li key={reason} className="text-[10px] leading-relaxed font-semibold text-ink-soft">
                {translate(TARGET_REVIEW_REASON_LABELS[reason])}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}
