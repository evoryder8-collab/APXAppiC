import type { ActivityLog, ImportedActivity, Profile, WorkoutSession, ProgramDay } from '../../lib/types.ts'
import { activityLogId } from '../../lib/ids.ts'
import type { OrbitRun } from './types.ts'

export interface NutritionAdjustment {
  kcal: number
  carbs_g: number
  protein_g: number
  fat_g: number
  timing: 'normal_meals' | 'pre_and_post' | 'during_and_recovery'
  explanation: string
}

export interface TrainingAdjustmentProposal {
  action: 'none' | 'protect_next_lower' | 'replace_next_quality_with_easy'
  explanation: string
  reversible: true
}

export interface AvatarRunContribution {
  endurance_minutes: number
  joint_signal: number
  lower_body_signal: number
  pacing_discipline_signal: number
  explanation: string
}

export function authoritativeActivityLogs(existing: ActivityLog[], run: OrbitRun, profile: Profile): {
  removeIds: string[]
  orbitLog: ActivityLog
} {
  const removeIds = existing
    .filter((log) => log.date === run.local_date && (
      log.type_id === 'jog-run' ||
      (log.type_id === 'watch-kcal' && log.source !== 'orbit')
    ))
    .map((log) => log.id)
  const computed = Math.round(profile.weight_kg * run.metrics.distance_m / 1000)
  return {
    removeIds,
    orbitLog: {
      id: activityLogId(run.local_date, profile.user_id, `orbit:${run.id}`),
      user_id: profile.user_id,
      date: run.local_date,
      type_id: 'jog-run',
      quantity: 1,
      duration_min: Math.max(1, Math.round(run.metrics.moving_s / 60)),
      distance_km: Math.round(run.metrics.distance_m / 10) / 100,
      watch_kcal: null,
      computed_kcal: computed,
      source: 'orbit',
      reconciled: true,
      created_at: run.created_at,
      updated_at: run.updated_at,
    },
  }
}

export function importedActivityForRun(run: OrbitRun): ImportedActivity {
  return {
    id: `orbit-${run.id}`,
    user_id: run.user_id,
    date: run.local_date,
    kind: 'endurance',
    activity: `APEX Orbit: ${run.mission.replaceAll('_', ' ')}`,
    duration_min: Math.max(1, Math.round(run.metrics.moving_s / 60)),
    source: 'APEX Orbit',
  }
}

export function nutritionAdjustmentForRun(run: OrbitRun, weightKg: number): NutritionAdjustment {
  const durationMin = run.metrics.moving_s / 60
  if (durationMin < 60) {
    return {
      kcal: 0, carbs_g: 0, protein_g: 0, fat_g: 0, timing: 'normal_meals',
      explanation: 'This run fits inside the normal daily meal pattern. Orbit does not add food automatically.',
    }
  }
  if (durationMin < 90) {
    const carbs = Math.round(Math.min(45, weightKg * 0.5))
    return {
      kcal: carbs * 4, carbs_g: carbs, protein_g: 0, fat_g: 0, timing: 'pre_and_post',
      explanation: `Optional ${carbs} g carbohydrate adjustment around the run. Review the exact change before applying it.`,
    }
  }
  const duringHours = Math.max(0, durationMin / 60 - 1)
  const carbs = Math.round(Math.min(120, 30 + duringHours * 35))
  const protein = Math.round(Math.min(30, Math.max(20, weightKg * 0.3)))
  return {
    kcal: carbs * 4 + protein * 4,
    carbs_g: carbs,
    protein_g: protein,
    fat_g: 0,
    timing: 'during_and_recovery',
    explanation: `Long-run rehearsal: ${carbs} g carbohydrate across familiar pre-run, during-run and recovery foods, plus ${protein} g recovery protein. Nothing changes until you apply it.`,
  }
}

export function trainingAdjustmentForRun(
  run: OrbitRun,
  sessions: WorkoutSession[],
  programDays: ProgramDay[],
): TrainingAdjustmentProposal {
  const effort = run.check_in.perceived_effort ?? 0
  const highCost = effort >= 8 || run.check_in.legs === 'very_heavy' || run.metrics.moving_s >= 120 * 60
  if (!highCost) return { action: 'none', explanation: 'The run does not require a strength-programme change.', reversible: true }
  const dayType = new Map(programDays.map((day) => [day.id, day.day_type]))
  const nextLower = sessions
    .filter((session) => session.date > run.local_date && ['legs_a', 'legs_b'].includes(dayType.get(session.program_day_id) ?? ''))
    .sort((a, b) => a.date.localeCompare(b.date))[0]
  if (!nextLower) return { action: 'replace_next_quality_with_easy', explanation: 'The run carried high recovery cost. Orbit proposes easy running next instead of another demanding run.', reversible: true }
  return {
    action: 'protect_next_lower',
    explanation: `The run carried high recovery cost and the next lower-body session is ${nextLower.date}. Orbit proposes protecting that session rather than silently moving it.`,
    reversible: true,
  }
}

export function avatarContributionForRun(run: OrbitRun): AvatarRunContribution {
  const minutes = Math.round(run.metrics.moving_s / 60)
  const splits = run.metrics.splits.filter((split) => split.distance_m >= 900)
  const meanPace = splits.length > 0 ? splits.reduce((sum, split) => sum + split.pace_sec_km, 0) / splits.length : null
  const variation = meanPace == null || splits.length < 2 ? 0 : Math.sqrt(splits.reduce((sum, split) => sum + (split.pace_sec_km - meanPace) ** 2, 0) / splits.length) / meanPace
  return {
    endurance_minutes: minutes,
    joint_signal: run.check_in.discomfort === 'none' ? Math.min(1, minutes / 90) : 0,
    lower_body_signal: Math.min(1, minutes / 75),
    pacing_discipline_signal: variation > 0 ? Math.max(0, 1 - variation * 8) : 0,
    explanation: `Orbit contributes ${minutes} recorded endurance minutes. The existing Avatar engine receives one authoritative endurance record, not raw GPS points.`,
  }
}
