/* Markdown export for AI program assessment: Blob download + clipboard. */
import { format } from 'date-fns'
import type { AppData, ProgramSlug } from './types'
import { approachRamp } from './plan'
import type { LoggedFoodEntry, LoggedMeal } from './food'
import { analyzeMealTiming, fallbackMealTime, timedMeal, zonedClock } from './mealTiming'

export interface MealTimingReportContext {
  meals: LoggedMeal[]
  entries: LoggedFoodEntry[]
  timeZone: string
  fallbackTimes?: Record<string, string>
}

export function buildReport(
  data: AppData,
  slug: ProgramSlug,
  fromIso: string,
  toIso: string,
  mealTiming?: MealTimingReportContext,
): string {
  const program = data.programs.find((p) => p.slug === slug)
  const dayById = new Map(data.program_days.map((d) => [d.id, d]))
  const exById = new Map(data.exercises.map((e) => [e.id, e]))
  const lines: string[] = []

  lines.push(`# APEX training report: ${program?.name ?? slug}`)
  lines.push(`Range: ${fromIso} to ${toIso}. Generated ${format(new Date(), 'yyyy-MM-dd HH:mm')}.`)
  lines.push('')

  /* Calendar overview */
  lines.push('## Calendar overview')
  const sessions = data.workout_sessions
    .filter((s) => s.date >= fromIso && s.date <= toIso)
    .sort((a, b) => a.date.localeCompare(b.date))
  const deloads = new Set(data.deload_marks.map((m) => m.date))
  for (const s of sessions) {
    const day = dayById.get(s.program_day_id)
    const flags = [
      s.is_lite ? 'Lite' : 'Full',
      s.is_deload || deloads.has(s.date) ? 'DELOAD' : null,
      s.is_event_recovery ? 'EVENT RECOVERY' : null,
      approachRamp(s.date, data.events) != null ? 'event window' : null,
      s.completed ? `completed, quality ${(s.quality_score * 100).toFixed(0)}%` : 'planned only',
    ].filter(Boolean)
    lines.push(`- ${s.date}: ${day?.name ?? '?'} (${flags.join(', ')})`)
  }
  if (data.events.length) {
    lines.push('')
    lines.push('### Events')
    for (const ev of data.events) {
      lines.push(`- ${ev.name} (${ev.type}), ${ev.start_date} to ${ev.end_date}`)
    }
  }
  lines.push('')

  /* Sessions with logs */
  lines.push('## Logged sessions')
  for (const s of sessions) {
    if (!s.completed) continue
    const day = dayById.get(s.program_day_id)
    lines.push(`### ${s.date}: ${day?.name ?? '?'}${s.is_lite ? ' (Lite)' : ''}`)
    if (s.notes) lines.push(`Notes: ${s.notes}`)
    const logs = data.workout_logs
      .filter((l) => l.session_id === s.id)
      .sort((a, b) => a.exercise_name.localeCompare(b.exercise_name) || a.set_no - b.set_no)
    let currentName = ''
    for (const l of logs) {
      const name = l.exercise_name || exById.get(l.exercise_id ?? '')?.name || 'Exercise'
      if (name !== currentName) {
        lines.push(`- **${name}**`)
        currentName = name
      }
      if (l.skipped) {
        lines.push(`  - Set ${l.set_no}: skipped`)
      } else {
        const bits = [
          l.weight_kg != null ? `${l.weight_kg} kg` : 'bodyweight',
          l.reps != null ? `${l.reps} reps` : null,
          l.rir != null ? `RIR ${l.rir}` : null,
          l.override_flag ? 'guardian override' : null,
        ].filter(Boolean)
        lines.push(`  - Set ${l.set_no}: ${bits.join(', ')}`)
      }
    }
    lines.push('')
  }

  /* Daily logs */
  lines.push('## Daily logs')
  const dailies = data.daily_logs
    .filter((d) => d.date >= fromIso && d.date <= toIso)
    .sort((a, b) => a.date.localeCompare(b.date))
  for (const d of dailies) {
    lines.push(
      `- ${d.date}: ${d.kcal ?? '?'} kcal, P ${d.protein_g ?? '?'} g, F ${d.fat_g ?? '?'} g, C ${d.carbs_g ?? '?'} g, water ${d.water_l} L`,
    )
  }
  lines.push('')

  if (mealTiming) {
    const meals = mealTiming.meals
      .filter((meal) => meal.local_date >= fromIso && meal.local_date <= toIso)
      .sort((left, right) => left.local_date.localeCompare(right.local_date) || left.logged_at.localeCompare(right.logged_at))
    const mealIds = new Set(meals.map((meal) => meal.id))
    const entries = mealTiming.entries.filter((entry) => mealIds.has(entry.meal_id))
    const timed = meals.map((meal) => timedMeal(
      meal,
      entries,
      mealTiming.timeZone,
      mealTiming.fallbackTimes?.[meal.id] ?? fallbackMealTime(meal),
    ))
    const analysis = analyzeMealTiming({
      meals,
      entries,
      sessions: data.workout_sessions.filter((session) => session.date >= fromIso && session.date <= toIso),
      timeZone: mealTiming.timeZone,
      fallbackTimes: mealTiming.fallbackTimes,
      recoveryNutrition: data.settings?.addons.recovery_nutrition,
    })

    lines.push('## Meal timing and pre-workout context')
    lines.push(`Timezone: ${mealTiming.timeZone}.`)
    lines.push(`Recorded meal finish times: ${analysis.recordedMeals}. Estimated times: ${analysis.estimatedMeals}.`)
    if (analysis.typicalVariationMinutes != null) {
      lines.push(`Typical within-slot timing variation: ${analysis.typicalVariationMinutes} minutes. Rhythm score: ${analysis.rhythmScore ?? '?'} / 100.`)
    }
    if (analysis.workoutsWithContext > 0) {
      lines.push(`Workout starts with meal context: ${analysis.workoutsWithContext}. Comfort window ${analysis.readyStarts}, tradeoff window ${analysis.transitionStarts}, settling window ${analysis.settlingStarts}.`)
      lines.push(`Average interval from the latest completed meal to training: ${analysis.averageWaitMinutes ?? '?'} minutes.`)
    }
    lines.push('')
    lines.push('### Meals')
    for (const item of timed) {
      lines.push(
        `- ${item.meal.local_date} ${item.time}: ${item.meal.display_name}, ${Math.round(item.meal.total_kcal)} kcal, P ${Math.round(item.meal.total_protein_g)} g, C ${Math.round(item.meal.total_carbs_g)} g, F ${Math.round(item.meal.total_fat_g)} g. Time ${item.recorded ? 'recorded' : 'estimated'}. Comfort estimate ${item.window.transitionAfterMinutes} to ${item.window.readyAfterMinutes} minutes.`,
      )
    }
    if (timed.length === 0) lines.push('- No structured meal timing was recorded in this range.')
    lines.push('')
    lines.push('### Workout timing relative to meals')
    for (const relation of analysis.workoutRelations) {
      const start = zonedClock(relation.startedAt, mealTiming.timeZone).time
      lines.push(relation.mealId
        ? `- ${relation.date} ${start}: started ${relation.waitedMinutes} minutes after ${relation.mealName}. Zone: ${relation.zone}.`
        : `- ${relation.date} ${start}: no reliably recorded earlier meal on this day.`)
    }
    if (analysis.workoutRelations.length === 0) lines.push('- No workout start timestamps were available in this range.')
    lines.push('')
    lines.push('### Post-workout nutrition timing')
    lines.push(`Completed workouts with timestamps: ${analysis.completedWorkouts}. Exact eating starts recorded: ${analysis.recoveryMealsRecorded}.`)
    if (analysis.recoveryTimingScore != null) {
      lines.push(`Average post-workout timing signal: ${analysis.recoveryTimingScore} / 100. Average workout-to-eating-start gap: ${analysis.averageRecoveryGapMinutes ?? '?'} minutes.`)
    }
    for (const relation of analysis.postWorkoutRelations) {
      const completed = zonedClock(relation.completedAt, mealTiming.timeZone).time
      if (relation.source === 'recorded_start' && relation.mealStartedAt) {
        const started = zonedClock(relation.mealStartedAt, mealTiming.timeZone).time
        lines.push(`- ${relation.date}: workout ended ${completed}; eating started ${started}, ${relation.gapMinutes} minutes later; timing signal ${relation.timingScore} / 100${relation.mealName ? `; meal ${relation.mealName}` : ''}.`)
      } else if (relation.source === 'inferred_finish') {
        lines.push(`- ${relation.date}: workout ended ${completed}; ${relation.mealName ?? 'next meal'} finished ${relation.gapMinutes} minutes later. Eating start was not explicitly recorded.`)
      } else {
        lines.push(`- ${relation.date}: workout ended ${completed}; no post-workout eating start was recorded.`)
      }
    }
    if (analysis.postWorkoutRelations.length === 0) lines.push('- No completed workout timestamps were available in this range.')
    lines.push('')
  }

  /* RPG snapshot */
  const snap = data.rpg_snapshots[data.rpg_snapshots.length - 1]
  if (snap) {
    lines.push('## Current RPG stats')
    lines.push(`- Overall: ${snap.overall}`)
    lines.push(`- Health: ${snap.health}`)
    lines.push(`- Joint Health Balance: ${snap.joint}`)
    lines.push(`- Flexibility: ${snap.flexibility}`)
    lines.push(`- Endurance & VO2max: ${snap.endurance}`)
    lines.push(
      `- Strength: ${snap.strength} (upper ${snap.strength_upper} / lower ${snap.strength_lower})`,
    )
  }
  return lines.join('\n')
}

export function downloadReport(markdown: string, filename: string): void {
  const blob = new Blob([markdown], { type: 'text/markdown;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}

export async function copyReport(markdown: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(markdown)
    return true
  } catch {
    return false
  }
}
