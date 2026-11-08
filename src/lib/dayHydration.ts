import type { AppData, DailyLog, ProgramDay, ProgramSlug } from './types.ts'
import { resolveHydrationTarget } from './hydration.ts'
import { resolveDailyBurnedEnergy } from './activity.ts'
import { activeInductionDayIds, activeTrainingProgramDays, isInsideInductionWindow } from './trainingInduction.ts'
import { simpleGuidedProgramSlug } from './simpleMode.ts'
import { recoveryDayMatchesDate } from './recoveryPlanner.ts'
import { dailyLogId, scopedUuid } from './ids.ts'
import { mergeHydrationEvents, resolveHydrationDay, type HydrationEvent } from './hydrationLedger.ts'
import { timeZoneFromSettings, zonedClock, zonedDateTimeToIso } from './mealTiming.ts'
import type { OwnerBoundMutationWrite } from './ownerBoundMutation.ts'

export type DrinkEdit = { addML: number } | { totalML: number }

/** Stage drink facts and their daily mirror under one account-owned durable mutation. */
export function editWebDrinks(data: AppData, ownerID: string, date: string, edit: DrinkEdit, now = new Date()) {
  if (data.profile?.user_id !== ownerID) throw new Error('The active account changed.')
  const existing = data.daily_logs.find(day => day.user_id === ownerID && day.date === date)
  const events = data.hydration_events ?? []
  const day = resolveHydrationDay({ ownerID, date, events, legacyDrinkLiters: existing?.water_l ?? 0 })
  const requested = 'addML' in edit ? day.drinkML + edit.addML : edit.totalML
  if (!Number.isFinite(requested)) throw new Error('Enter a valid water amount.')
  const total = Math.max(0, Math.round(requested))
  const writes: OwnerBoundMutationWrite[] = []
  if (total === day.drinkML) return { data, writes, result: total }
  const recordedAt = now.toISOString()
  const zone = timeZoneFromSettings(data.settings)
  const occurred = zonedClock(now, zone).date === date ? recordedAt : zonedDateTimeToIso(date, '12:00', zone)
  const added: HydrationEvent[] = []
  const removed = new Set<string>()
  const makeDrink = (ml: number, legacy: boolean): HydrationEvent => {
    const id = legacy ? scopedUuid('hydration-legacy', date, ownerID) : crypto.randomUUID()
    return { id, user_id: ownerID, client_idempotency_key: legacy ? `legacy:${date}` : `web:${id}`,
      local_date: date, occurred_at: occurred, amount_ml: ml, kind: legacy ? 'legacy' : 'water',
      palette_token: legacy ? 'legacy_anchor' : 'aqua', icon_token: legacy ? 'drop.circle' : 'drop.fill',
      source: legacy ? 'legacy' : 'web', healthkit_sample_id: null, created_at: recordedAt, updated_at: recordedAt }
  }

  // Keep historical aggregate-only days intact when editing them. The first added drink
  // on such a day materializes its baseline under the same stable key used on iPhone.
  if (total > day.drinkML) {
    const increase = total - day.drinkML
    if (increase > 10_000) throw new Error('Enter a smaller drink amount.')
    if (day.usesLegacyAggregate) added.push(makeDrink(day.drinkML, true))
    added.push(makeDrink(increase, false))
  } else if (!day.usesLegacyAggregate) {
    let remaining = day.drinkML - total
    const editable = mergeHydrationEvents([], events).filter(event => event.user_id === ownerID && event.local_date === date
      && event.kind !== 'food' && (event.source === 'web' || event.source === 'legacy'))
    for (const event of editable) {
      if (!remaining) break
      const take = Math.min(remaining, event.amount_ml)
      if (take === event.amount_ml) removed.add(event.id)
      else added.push({ ...event, amount_ml: event.amount_ml - take, updated_at: recordedAt })
      remaining -= take
    }
    if (remaining) throw new Error('Edit device-recorded drinks on the device that logged them.')
  }
  for (const id of removed) writes.push({ ownerID, table: 'hydration_events', type: 'delete', payload: { id, user_id: ownerID } })
  for (const event of added) writes.push({ ownerID, table: 'hydration_events', type: 'upsert', payload: { ...event } })
  const mirror: DailyLog = { ...(existing ?? { id: dailyLogId(date, ownerID), user_id: ownerID, date,
    kcal: null, protein_g: null, fat_g: null, carbs_g: null, estimated_tdee: null, computed_pal: null,
    activity_mode: 'quick', weight_kg: null }), water_l: total / 1_000 }
  writes.push({ ownerID, table: 'daily_logs', type: 'upsert', payload: { ...mirror } })
  return { writes, result: total, data: { ...data,
    daily_logs: [...data.daily_logs.filter(log => log.id !== mirror.id || log.user_id !== ownerID), mirror],
    hydration_events: mergeHydrationEvents(events.filter(event => event.user_id !== ownerID || !removed.has(event.id)), added),
  } }
}

/** Build indexes once per dashboard snapshot, including a replay over many historical days. */
export function waterTargetResolver(data: AppData, preferCoach = false, includeCustom = true) {
  const profile = data.profile
  const owner = profile?.user_id
  const preferences = data.hydration_preferences?.user_id === owner ? data.hydration_preferences : null
  const settings = data.settings?.user_id === owner ? data.settings : null
  const induction = settings?.addons.training_induction
  const wearable = new Map((settings?.addons.watch_activity_history ?? []).map(row => [row.date, row]))
  const dailyActivity = new Map<string, AppData['activity_logs']>()
  for (const row of data.activity_logs) {
    if (row.user_id !== owner) continue
    const group = dailyActivity.get(row.date) ?? []
    group.push(row)
    dailyActivity.set(row.date, group)
  }
  const slugs = new Map(data.programs.filter(p => p.user_id === owner).map(p => [p.id, p.slug]))
  const prescribed = new Set(data.exercises.filter(e => e.user_id === owner && !e.is_lite).map(e => e.program_day_id))
  const days = new Map<ProgramSlug, ProgramDay[]>()
  const main = activeInductionDayIds(induction, 'main')
  const transition = activeInductionDayIds(induction, 'transition')
  for (const day of activeTrainingProgramDays(data)) {
    const slug = slugs.get(day.program_id)
    const activeIDs = slug === 'transition' ? transition : slug === 'main' ? main : null
    if (!slug || !prescribed.has(day.id) || (activeIDs && !activeIDs.has(day.id) && !day.scheduled_date)) continue
    const group = days.get(slug) ?? []
    group.push(day)
    days.set(slug, group)
  }
  const fallback = simpleGuidedProgramSlug(profile?.persona, days.has('main'), days.has('transition'))
  return (date: string, today: string, hour: number) => {
    const slug = preferCoach && (days.has('coach') || !includeCustom) ? 'coach'
      : induction && days.has('transition') && isInsideInductionWindow(induction, 'transition', date) ? 'transition'
        : induction && days.has('main') && isInsideInductionWindow(induction, 'main', date) ? 'main' : fallback
    const primary = isInsideInductionWindow(induction, slug, date) ? days.get(slug) ?? [] : []
    const plannedMinutes = [...primary, ...(includeCustom ? days.get('custom') ?? [] : [])]
      .reduce((sum, row) => sum + (recoveryDayMatchesDate(row, date) ? Math.max(0, row.est_minutes) : 0), 0)
    const logs = dailyActivity.get(date) ?? []
    const record = wearable.get(date)
    return resolveHydrationTarget({
      sex: profile?.sex ?? 'male', weightKg: profile?.weight_kg ?? 87,
      mode: preferences?.target_mode, customTargetML: preferences?.target_ml,
      plannedExerciseMinutes: plannedMinutes, recordedExerciseMinutes: Math.max(record?.exercise_minutes ?? 0,
        logs.reduce((sum, row) => sum + Math.max(0, row.duration_min ?? 0), 0)),
      activeCalories: resolveDailyBurnedEnergy(record?.active_calories, logs), steps: record?.steps,
      dateRelation: date < today ? 'past' : date > today ? 'future' : 'today', localHour: hour,
    })
  }
}
