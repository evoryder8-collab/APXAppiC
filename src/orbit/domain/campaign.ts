import { CAMPAIGN_CONFIG, DEMANDING_MISSIONS, ORBIT_PLAN_VERSION } from './config.ts'
import { orbitUuid } from './ids.ts'
import type {
  CampaignFamily,
  CampaignPhase,
  CampaignSession,
  InductionOutcome,
  MarathonCampaign,
  MarathonInduction,
  MarathonInductionAnswers,
  OrbitRun,
  ReadinessComponent,
  RunMission,
  SessionPrescription,
} from './types.ts'
import type { CalendarEvent } from '../../lib/types.ts'

const DAY_MS = 86_400_000

export const EMPTY_INDUCTION_ANSWERS: MarathonInductionAnswers = {
  race_name: '', race_date: '', race_goal: '', target_time: '', course_profile: '', course_surface: '', climate_familiar: '',
  running_frequency: '', weekly_distance: '', longest_run: '', consistency: '', race_experience: '', marathon_experience: '',
  structured_plan: '', running_style: '', available_days: '', long_run_day: '', unavailable_days: [], strength_days_per_week: 0,
  constraints: [], previous_issue: '', previous_surgery: '', issue_status: '', pain_changes_movement: false, chest_discomfort: false,
  fainting: false, unusual_breathlessness: false, recent_illness_or_operation: false, professional_restriction: false, medication: '',
}

const FREQUENCY: Record<MarathonInductionAnswers['running_frequency'], number> = {
  none: 0, one: 1, two: 2, three: 3, four: 4, five_plus: 5, '': 0,
}

const WEEKLY_KM: Record<MarathonInductionAnswers['weekly_distance'], number> = {
  under_10: 7, '10_20': 15, '20_35': 27, '35_50': 42, over_50: 55, unsure: 0, '': 0,
}

const LONGEST_KM: Record<MarathonInductionAnswers['longest_run'], number> = {
  under_5: 4, '5_10': 8, '10_15': 12, '15_21': 18, over_21: 24, unsure: 0, '': 0,
}

const CONSISTENCY_MONTHS: Record<MarathonInductionAnswers['consistency'], number> = {
  none: 0, under_month: 0.5, one_three_months: 2, three_six_months: 4.5, over_six_months: 8, '': 0,
}

const AVAILABLE_DAYS: Record<MarathonInductionAnswers['available_days'], number> = {
  three: 3, four: 4, five: 5, six: 6, variable: 4, '': 3,
}

export interface InductionAssessment {
  outcome: InductionOutcome
  reason: string
  timeline_warning: string
  credible_base: boolean
  days_until_race: number
}

function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10)
}

function parseIso(value: string): Date {
  return new Date(`${value}T12:00:00`)
}

function addDays(value: string, days: number): string {
  return isoDate(new Date(parseIso(value).getTime() + days * DAY_MS))
}

function daysBetween(from: string, to: string): number {
  return Math.round((parseIso(to).getTime() - parseIso(from).getTime()) / DAY_MS)
}

export function inductionIsComplete(answers: MarathonInductionAnswers): boolean {
  return Boolean(
    answers.race_name.trim() && answers.race_date && answers.race_goal && answers.course_profile && answers.course_surface &&
    answers.running_frequency && answers.weekly_distance && answers.longest_run && answers.consistency && answers.race_experience &&
    answers.marathon_experience && answers.structured_plan && answers.running_style && answers.available_days && answers.long_run_day &&
    answers.previous_issue && answers.previous_surgery && answers.issue_status && answers.medication,
  )
}

export function assessInduction(answers: MarathonInductionAnswers, today = isoDate(new Date())): InductionAssessment {
  if (!inductionIsComplete(answers)) {
    return { outcome: 'more_information', reason: 'Complete the remaining induction questions before Orbit assigns a campaign.', timeline_warning: '', credible_base: false, days_until_race: 0 }
  }
  const concerning = answers.pain_changes_movement || answers.chest_discomfort || answers.fainting ||
    answers.unusual_breathlessness || answers.recent_illness_or_operation || answers.professional_restriction ||
    ['changes_movement', 'rehabilitating', 'restricted'].includes(answers.issue_status) || answers.previous_surgery === 'under_six_months'
  const daysUntilRace = daysBetween(today, answers.race_date)
  const credibleBase = FREQUENCY[answers.running_frequency] >= CAMPAIGN_CONFIG.minimumCredibleFrequency &&
    WEEKLY_KM[answers.weekly_distance] >= CAMPAIGN_CONFIG.minimumCredibleWeeklyKm &&
    LONGEST_KM[answers.longest_run] >= CAMPAIGN_CONFIG.minimumCredibleLongestKm &&
    CONSISTENCY_MONTHS[answers.consistency] >= 3
  if (concerning) {
    return {
      outcome: 'professional_review',
      reason: 'A current symptom, unresolved limitation, recent operation or existing restriction was reported. General Orbit remains available, but strenuous marathon preparation is paused pending professional review.',
      timeline_warning: '', credible_base: credibleBase, days_until_race: daysUntilRace,
    }
  }
  if (daysUntilRace < 0) {
    return { outcome: 'more_information', reason: 'The selected race date has already passed. Choose a future event.', timeline_warning: '', credible_base: credibleBase, days_until_race: daysUntilRace }
  }
  if (credibleBase && daysUntilRace < CAMPAIGN_CONFIG.minimumSpecificLeadDays) {
    return {
      outcome: 'more_information',
      reason: `There are ${daysUntilRace} days until the race, which is shorter than Orbit’s 12-week marathon-specific block. Choose a later event or change the objective rather than compressing the progression.`,
      timeline_warning: 'The selected timeline is too short for the standard marathon-specific block.', credible_base: true, days_until_race: daysUntilRace,
    }
  }
  if (!credibleBase) {
    const foundationWeeks = FREQUENCY[answers.running_frequency] <= 1 || WEEKLY_KM[answers.weekly_distance] < 10
      ? CAMPAIGN_CONFIG.beginnerFoundationWeeks
      : CONSISTENCY_MONTHS[answers.consistency] < 1
        ? CAMPAIGN_CONFIG.returningFoundationWeeks
        : CAMPAIGN_CONFIG.recreationalFoundationWeeks
    const requiredDays = (foundationWeeks + CAMPAIGN_CONFIG.marathonSpecificWeeks) * 7
    return {
      outcome: 'foundation',
      reason: `Foundation to First Marathon was selected because the recent base is below the marathon-specific gate: ${FREQUENCY[answers.running_frequency]} run days per week, approximately ${WEEKLY_KM[answers.weekly_distance]} km per week and a longest recent run near ${LONGEST_KM[answers.longest_run]} km.`,
      timeline_warning: daysUntilRace < requiredDays
        ? `The race is ${daysUntilRace} days away, but a credible Foundation plus marathon-specific journey needs approximately ${requiredDays} days. A later race is recommended.`
        : '',
      credible_base: false, days_until_race: daysUntilRace,
    }
  }
  return {
    outcome: 'ready',
    reason: 'Recent frequency, volume, long-run exposure and consistency support entry into a marathon-specific campaign.',
    timeline_warning: '', credible_base: true, days_until_race: daysUntilRace,
  }
}

export function assignCampaignFamily(answers: MarathonInductionAnswers, outcome: InductionOutcome): CampaignFamily {
  if (outcome === 'foundation') return 'foundation_first'
  if (answers.strength_days_per_week >= 2) return 'hybrid'
  if (answers.marathon_experience === 'two_four' || answers.marathon_experience === 'five_plus') return 'personal_best'
  const performanceGoal = answers.race_goal === 'target_time' || answers.race_goal === 'best_realistic'
  const performanceHistory = ['half', 'marathon', 'multiple_marathons'].includes(answers.race_experience)
  if (performanceGoal && performanceHistory) return 'first_performance'
  return 'first_finish'
}

function phaseForDate(date: string, campaign: Pick<MarathonCampaign, 'outcome' | 'race_date'>): CampaignPhase {
  const daysToRace = daysBetween(date, campaign.race_date)
  if (daysToRace < 0) return 'post_marathon'
  if (daysToRace <= 6) return 'race_week'
  if (daysToRace <= 20) return 'taper'
  if (daysToRace <= 27) return 'peak'
  if (daysToRace <= 48) return 'marathon_specific'
  if (daysToRace <= 69) return 'durability'
  if (daysToRace <= 83) return 'aerobic_build'
  return campaign.outcome === 'foundation' ? 'foundation' : 'aerobic_build'
}

function longRunDay(answers: MarathonInductionAnswers): number {
  if (answers.long_run_day === 'saturday') return 6
  if (answers.long_run_day === 'sunday') return 0
  return 0
}

function circularDistance(a: number, b: number): number {
  const distance = Math.abs(a - b)
  return Math.min(distance, 7 - distance)
}

function chooseRunDays(answers: MarathonInductionAnswers, legWeekdays: number[]): number[] {
  const count = Math.max(3, Math.min(6, AVAILABLE_DAYS[answers.available_days]))
  const blocked = new Set(answers.unavailable_days)
  const long = blocked.has(longRunDay(answers)) ? [0, 6, 5].find((day) => !blocked.has(day)) ?? 0 : longRunDay(answers)
  const selected = [long]
  while (selected.length < count) {
    const candidates = [0, 1, 2, 3, 4, 5, 6].filter((day) => !blocked.has(day) && !selected.includes(day))
    if (candidates.length === 0) break
    candidates.sort((a, b) => {
      const spacingA = Math.min(...selected.map((day) => circularDistance(a, day)))
      const spacingB = Math.min(...selected.map((day) => circularDistance(b, day)))
      const legPenaltyA = legWeekdays.includes(a) ? 2 : legWeekdays.some((day) => circularDistance(a, day) === 1) ? 1 : 0
      const legPenaltyB = legWeekdays.includes(b) ? 2 : legWeekdays.some((day) => circularDistance(b, day) === 1) ? 1 : 0
      return (spacingB - legPenaltyB) - (spacingA - legPenaltyA)
    })
    selected.push(candidates[0])
  }
  return selected.sort((a, b) => a - b)
}

function qualityMission(phase: CampaignPhase, week: number, runWalk: boolean): RunMission {
  if (runWalk || phase === 'foundation') return 'run_walk'
  if (phase === 'aerobic_build') return week % 2 === 0 ? 'hills' : 'aerobic_base'
  if (phase === 'durability') return week % 2 === 0 ? 'progression' : 'tempo'
  if (phase === 'marathon_specific') return week % 2 === 0 ? 'marathon_pace' : 'threshold'
  if (phase === 'peak') return 'marathon_pace'
  if (phase === 'taper') return 'marathon_pace'
  return 'easy'
}

function prescription(
  mission: RunMission,
  durationMin: number,
  phase: CampaignPhase,
  family: CampaignFamily,
  isLong = false,
): SessionPrescription {
  const titles: Record<RunMission, string> = {
    recovery: 'Recovery reset', easy: 'Easy aerobic run', aerobic_base: 'Aerobic base', long_run: 'Long-run durability',
    run_walk: 'Run-walk foundation', progression: 'Controlled progression', tempo: 'Tempo control', threshold: 'Threshold development',
    intervals: 'Controlled intervals', hills: 'Hill strength', marathon_pace: 'Marathon-pace durability', exploration: 'Exploration run',
    performance_test: 'Target marathon', free_run: 'Free run',
  }
  const demanding = DEMANDING_MISSIONS.includes(mission) && mission !== 'long_run' ? true : isLong && durationMin >= 90
  const easy = ['recovery', 'easy', 'aerobic_base', 'long_run', 'run_walk'].includes(mission)
  const purpose = mission === 'long_run'
    ? 'Build durable time on feet and practise controlled fueling without racing the session.'
    : mission === 'marathon_pace'
      ? 'Develop pace control and durability at the effort required by the target event.'
      : mission === 'hills'
        ? 'Build controlled climbing strength while protecting running form.'
        : mission === 'run_walk'
          ? 'Develop repeatable running frequency with planned walking before fatigue changes movement.'
          : easy
            ? 'Build aerobic volume without compromising the surrounding strength and recovery work.'
            : 'Apply one purposeful quality stimulus while keeping the rest of the week controlled.'
  const mainWork = mission === 'run_walk'
    ? 'Alternate 4 minutes of relaxed running with 1 minute of purposeful walking.'
    : mission === 'marathon_pace'
      ? `${Math.max(12, Math.round(durationMin * 0.45))} minutes at controlled marathon effort inside the session.`
      : mission === 'tempo'
        ? `${Math.max(10, Math.round(durationMin * 0.35))} minutes at comfortably hard, controlled effort.`
        : mission === 'threshold'
          ? `3 controlled blocks of ${Math.max(5, Math.round(durationMin * 0.12))} minutes with easy recovery.`
          : mission === 'hills'
            ? 'Use 6 to 8 controlled climbs with complete easy recoveries.'
            : mission === 'performance_test'
              ? 'Execute the rehearsed pacing and fueling strategy. Use effort as the fallback when conditions differ.'
              : 'Stay conversational and finish with the sense that more was available.'
  return {
    mission,
    title: titles[mission],
    purpose,
    duration_min: durationMin,
    distance_km: mission === 'performance_test' ? 42.195 : null,
    intensity: easy ? 'Conversational effort, RPE 2 to 4' : 'Controlled quality, never an all-out opening',
    warmup: demanding ? '10 minutes easy plus dynamic movement and 3 short relaxed strides.' : 'Begin with 5 minutes very easy and let rhythm arrive naturally.',
    main_work: mainWork,
    cooldown: demanding ? '8 to 10 minutes easy, then stop. Do not add bonus work.' : 'Finish with 3 to 5 easy minutes.',
    route_characteristics: mission === 'hills'
      ? 'A repeatable climb with a simple recovery descent.'
      : mission === 'tempo' || mission === 'threshold' || mission === 'marathon_pace'
        ? 'Long uninterrupted sections with low navigation complexity.'
        : 'Prefer a simple, mostly flat route when recovery is the priority.',
    minimum_version_min: mission === 'performance_test' ? null : Math.max(18, Math.round(durationMin * 0.65)),
    fueling_note: durationMin >= 90
      ? 'Use this as a fueling rehearsal with a familiar carbohydrate source and the exact plan already tested in training.'
      : durationMin >= 60
        ? 'Begin normally fueled and carry water when conditions or personal experience justify it.'
        : 'Your normal meal pattern is sufficient unless hunger or timing says otherwise.',
    why: `${phase.replaceAll('_', ' ')} phase · ${family.replaceAll('_', ' ')} campaign · placed to preserve recovery around demanding work.`,
    demanding,
  }
}

function baseLongMinutes(answers: MarathonInductionAnswers): number {
  const longest = LONGEST_KM[answers.longest_run]
  return Math.max(35, Math.min(130, Math.round(longest * 6.3)))
}

function longMinutesForWeek(answers: MarathonInductionAnswers, phase: CampaignPhase, weekIndex: number): number {
  if (phase === 'race_week') return 20
  if (phase === 'taper') return Math.max(50, Math.round(baseLongMinutes(answers) * 0.65))
  if (phase === 'peak') return Math.min(CAMPAIGN_CONFIG.maximumLongRunMinutes, Math.max(120, baseLongMinutes(answers) + weekIndex * 5))
  const growth = answers.consistency === 'none' || answers.consistency === 'under_month'
    ? CAMPAIGN_CONFIG.conservativeWeeklyDurationGrowth
    : CAMPAIGN_CONFIG.standardWeeklyDurationGrowth
  let duration = baseLongMinutes(answers) * Math.pow(growth, Math.min(weekIndex, 14))
  if ((weekIndex + 1) % CAMPAIGN_CONFIG.cutbackEveryWeeks === 0) duration *= CAMPAIGN_CONFIG.cutbackFactor
  if (phase === 'foundation') duration = Math.min(duration, 105)
  return Math.min(CAMPAIGN_CONFIG.maximumLongRunMinutes, Math.round(duration / 5) * 5)
}

function dateForWeekday(weekStart: string, weekday: number): string {
  const mondayIndex = weekday === 0 ? 6 : weekday - 1
  return addDays(weekStart, mondayIndex)
}

function mondayOnOrBefore(date: string): string {
  const parsed = parseIso(date)
  const day = parsed.getDay()
  return addDays(date, -(day === 0 ? 6 : day - 1))
}

export function generateCampaignSessions(
  campaign: MarathonCampaign,
  answers: MarathonInductionAnswers,
  legWeekdays: number[] = [],
  today = isoDate(new Date()),
): CampaignSession[] {
  if (campaign.outcome === 'professional_review' || campaign.outcome === 'more_information') return []
  const startMonday = mondayOnOrBefore(today)
  const end = addDays(campaign.race_date, 14)
  const totalWeeks = Math.min(52, Math.max(1, Math.ceil(daysBetween(startMonday, end) / 7)))
  const runDays = chooseRunDays(answers, legWeekdays)
  const longDay = runDays.includes(longRunDay(answers)) ? longRunDay(answers) : runDays.at(-1)!
  const runWalk = answers.running_style === 'run_walk' || answers.running_frequency === 'none' || answers.running_frequency === 'one'
  const sessions: CampaignSession[] = []
  for (let week = 0; week < totalWeeks; week += 1) {
    const weekStart = addDays(startMonday, week * 7)
    const phase = phaseForDate(weekStart, campaign)
    if (phase === 'post_marathon') {
      const date = dateForWeekday(weekStart, 3)
      const original = prescription('recovery', week === totalWeeks - 1 ? 30 : 20, phase, campaign.family)
      sessions.push(makeSession(campaign, date, phase, original))
      continue
    }
    if (phase === 'race_week') {
      for (const day of runDays.slice(0, 2)) {
        const date = dateForWeekday(weekStart, day)
        if (date >= campaign.race_date) continue
        sessions.push(makeSession(campaign, date, phase, prescription('easy', 22, phase, campaign.family)))
      }
      if (campaign.race_date >= weekStart && campaign.race_date <= addDays(weekStart, 6)) {
        sessions.push(makeSession(campaign, campaign.race_date, phase, prescription('performance_test', 270, phase, campaign.family)))
      }
      continue
    }
    const quality = qualityMission(phase, week, runWalk)
    const longMinutes = longMinutesForWeek(answers, phase, week)
    const qualityCandidates = runDays.filter((day) => day !== longDay && !legWeekdays.includes(day) && !legWeekdays.some((leg) => circularDistance(day, leg) === 1))
    const qualityDay = qualityCandidates.find((day) => circularDistance(day, longDay) >= 2) ?? runDays.find((day) => day !== longDay) ?? longDay
    for (const day of runDays) {
      const date = dateForWeekday(weekStart, day)
      if (date > campaign.race_date) continue
      const mission: RunMission = day === longDay ? 'long_run' : day === qualityDay ? quality : phase === 'foundation' ? 'run_walk' : 'easy'
      const duration = mission === 'long_run'
        ? longMinutes
        : mission === 'easy'
          ? Math.min(55, 30 + week * 2)
          : mission === 'run_walk'
            ? Math.min(45, 25 + week * 2)
            : phase === 'taper'
              ? 35
              : Math.min(65, 42 + Math.floor(week / 2) * 3)
      sessions.push(makeSession(campaign, date, phase, prescription(mission, duration, phase, campaign.family, mission === 'long_run')))
    }
  }
  return sessions.sort((a, b) => a.date.localeCompare(b.date))
}

function makeSession(campaign: MarathonCampaign, date: string, phase: CampaignPhase, original: SessionPrescription): CampaignSession {
  const now = new Date().toISOString()
  return {
    id: orbitUuid(campaign.user_id, `campaign-session:${campaign.id}:${date}:${original.mission}`),
    user_id: campaign.user_id,
    campaign_id: campaign.id,
    date,
    prescribed_date: date,
    phase,
    original,
    adapted: { ...original },
    status: 'planned',
    completion_run_id: null,
    adaptation_reason: '',
    user_override: false,
    created_at: now,
    updated_at: now,
    sync_state: 'queued',
  }
}

export function coordinateCampaignWithEvents(
  campaign: MarathonCampaign,
  sessions: CampaignSession[],
  events: CalendarEvent[],
  legWeekdays: number[] = [],
): { campaign: MarathonCampaign; sessions: CampaignSession[] } {
  const relevant = events.filter((event) => event.user_id === campaign.user_id && (event.type === 'filming_championship' || event.type === 'travel'))
  if (relevant.length === 0) return { campaign, sessions }
  const occupied = new Set(sessions.map((session) => session.date))
  const adaptations = [...campaign.adaptations]
  const next = sessions.map((session) => {
    const event = relevant.find((item) => session.date >= item.start_date && session.date <= item.end_date)
    if (!event || !session.adapted.demanding || session.status !== 'planned') return session
    const originalDate = session.date
    let movedDate: string | null = null
    for (let offset = 1; offset <= 3; offset += 1) {
      const candidate = addDays(originalDate, offset)
      const weekday = parseIso(candidate).getDay()
      const conflictsEvent = relevant.some((item) => candidate >= item.start_date && candidate <= item.end_date)
      if (!conflictsEvent && !occupied.has(candidate) && !legWeekdays.includes(weekday)) {
        movedDate = candidate
        break
      }
    }
    if (!movedDate) return session
    occupied.delete(originalDate)
    occupied.add(movedDate)
    const reason = `${session.adapted.title} moved from ${originalDate} to ${movedDate} because ${event.name} occupies the original date. The original prescription remains visible.`
    adaptations.push({
      id: orbitUuid(campaign.user_id, `calendar:${session.id}:${event.id}`), at: new Date().toISOString(), session_id: session.id,
      reason, original_mission: session.original.mission, adapted_mission: session.adapted.mission, accepted: null,
    })
    return { ...session, date: movedDate, adaptation_reason: reason, updated_at: new Date().toISOString(), sync_state: 'queued' as const }
  })
  return { campaign: { ...campaign, adaptations, updated_at: new Date().toISOString(), sync_state: 'queued' }, sessions: next.sort((a, b) => a.date.localeCompare(b.date)) }
}

export function readinessComponents(runs: OrbitRun[], sessions: CampaignSession[], campaign: MarathonCampaign): ReadinessComponent[] {
  const completed = sessions.filter((session) => session.status === 'completed')
  const recent = runs.filter((run) => daysBetween(run.local_date, isoDate(new Date())) <= 42)
  const longRuns = recent.filter((run) => run.mission === 'long_run')
  const controlled = recent.filter((run) => (run.check_in.perceived_effort ?? 10) <= 6)
  const fuelingChecks = longRuns.filter((run) => run.check_in.note.toLowerCase().includes('fuel'))
  const components: ReadinessComponent[] = [
    {
      key: 'consistency', label: 'Consistency',
      state: completed.length >= 10 ? 'strong' : completed.length >= 5 ? 'on_track' : 'developing',
      reason: `${completed.length} campaign sessions are recorded as completed.`,
    },
    {
      key: 'long_run', label: 'Long-run progression',
      state: longRuns.length >= 4 ? 'on_track' : longRuns.length >= 2 ? 'developing' : 'needs_attention',
      reason: `${longRuns.length} recent long runs are available for comparison.`,
    },
    {
      key: 'aerobic_control', label: 'Aerobic control',
      state: controlled.length >= Math.max(3, recent.length * 0.7) ? 'strong' : controlled.length >= 2 ? 'moderate' : 'developing',
      reason: `${controlled.length} recent runs were completed at controlled perceived effort.`,
    },
    {
      key: 'fueling', label: 'Fueling practice',
      state: fuelingChecks.length >= 3 ? 'on_track' : fuelingChecks.length > 0 ? 'developing' : 'needs_attention',
      reason: fuelingChecks.length > 0 ? `${fuelingChecks.length} long-run notes mention fueling practice.` : 'No completed fueling rehearsal is recorded yet.',
    },
    {
      key: 'strength', label: 'Strength coordination', state: campaign.family === 'hybrid' ? 'on_track' : 'moderate',
      reason: campaign.family === 'hybrid' ? 'The campaign is scheduled around the existing APEX strength week.' : 'Strength work remains visible when Orbit adapts the run week.',
    },
  ]
  if (campaign.phase === 'race_week' || campaign.phase === 'taper') {
    components.push({ key: 'race_week', label: 'Race-week preparation', state: campaign.phase === 'race_week' ? 'on_track' : 'developing', reason: 'Taper, pacing, fueling and equipment checks are active.' })
  }
  return components
}

export function createCampaign(
  induction: MarathonInduction,
  today = isoDate(new Date()),
): MarathonCampaign {
  const assessment = assessInduction(induction.answers, today)
  const family = assignCampaignFamily(induction.answers, assessment.outcome)
  const now = new Date().toISOString()
  const id = orbitUuid(induction.user_id, `campaign:${induction.id}:${ORBIT_PLAN_VERSION}`)
  const campaign: MarathonCampaign = {
    id,
    user_id: induction.user_id,
    client_idempotency_key: `campaign:${induction.id}:${ORBIT_PLAN_VERSION}`,
    induction_id: induction.id,
    family,
    phase: phaseForDate(today, { outcome: assessment.outcome, race_date: induction.answers.race_date }),
    outcome: assessment.outcome,
    status: assessment.outcome === 'professional_review' ? 'review_required' : assessment.outcome === 'more_information' ? 'paused' : 'active',
    race_name: induction.answers.race_name,
    race_date: induction.answers.race_date,
    race_goal: induction.answers.race_goal,
    started_at: now,
    plan_version: ORBIT_PLAN_VERSION,
    assignment_reason: assessment.reason,
    timeline_warning: assessment.timeline_warning,
    readiness: [],
    adaptations: [],
    created_at: now,
    updated_at: now,
    sync_state: 'queued',
  }
  return campaign
}

function easierPrescription(original: SessionPrescription, reason: string): SessionPrescription {
  const mission: RunMission = original.mission === 'long_run' ? 'easy' : 'recovery'
  return {
    ...original,
    mission,
    title: mission === 'easy' ? 'Easy aerobic run' : 'Recovery reset',
    purpose: 'Absorb the previous workload while preserving movement rhythm.',
    duration_min: Math.max(20, Math.round(original.duration_min * 0.65)),
    intensity: 'Conversational effort, RPE 2 to 3',
    main_work: 'Keep the entire run easy. Do not replace the removed quality block.',
    minimum_version_min: 18,
    why: reason,
    demanding: false,
  }
}

export function adaptAfterRun(
  campaign: MarathonCampaign,
  sessions: CampaignSession[],
  run: OrbitRun,
): { campaign: MarathonCampaign; sessions: CampaignSession[] } {
  const now = new Date().toISOString()
  const completedId = run.campaign_session_id
  let next = sessions.map((session) => session.id === completedId
    ? { ...session, status: 'completed' as const, completion_run_id: run.id, updated_at: now, sync_state: 'queued' as const }
    : session)
  const unexpectedlyHard = (run.check_in.perceived_effort ?? 0) >= 8 || run.check_in.legs === 'very_heavy' || run.check_in.discomfort === 'changed_movement'
  if (!unexpectedlyHard) return { campaign: { ...campaign, readiness: readinessComponents([run], next, campaign), updated_at: now }, sessions: next }
  const future = next.find((session) => session.date > run.local_date && session.adapted.demanding && session.status === 'planned')
  if (!future) return { campaign, sessions: next }
  const reason = 'The previous run was harder than intended, so the next demanding session is reduced instead of stacking fatigue.'
  const adaptation = {
    id: orbitUuid(campaign.user_id, `adaptation:${run.id}:${future.id}`), at: now, session_id: future.id, reason,
    original_mission: future.original.mission, adapted_mission: future.original.mission === 'long_run' ? 'easy' as const : 'recovery' as const, accepted: null,
  }
  next = next.map((session) => session.id === future.id
    ? { ...session, adapted: easierPrescription(session.original, reason), adaptation_reason: reason, updated_at: now, sync_state: 'queued' as const }
    : session)
  return {
    campaign: { ...campaign, adaptations: [...campaign.adaptations, adaptation], updated_at: now, sync_state: 'queued' },
    sessions: next,
  }
}

export function adaptAfterMissedSession(
  campaign: MarathonCampaign,
  sessions: CampaignSession[],
  missedSessionId: string,
): { campaign: MarathonCampaign; sessions: CampaignSession[] } {
  const now = new Date().toISOString()
  const missed = sessions.find((session) => session.id === missedSessionId)
  if (!missed) return { campaign, sessions }
  let next = sessions.map((session) => session.id === missedSessionId ? { ...session, status: 'missed' as const, updated_at: now, sync_state: 'queued' as const } : session)
  const futureHard = next.find((session) => session.date > missed.date && session.status === 'planned' && session.adapted.demanding)
  if (!futureHard || !missed.adapted.demanding) return { campaign, sessions: next }
  const reason = 'A missed demanding session is not stacked into the next days. The original prescription remains visible and the week continues forward.'
  next = next.map((session) => session.id === futureHard.id
    ? { ...session, adapted: easierPrescription(session.original, reason), adaptation_reason: reason, updated_at: now, sync_state: 'queued' as const }
    : session)
  return {
    campaign: {
      ...campaign,
      adaptations: [...campaign.adaptations, {
        id: orbitUuid(campaign.user_id, `missed:${missed.id}:${futureHard.id}`), at: now, session_id: futureHard.id, reason,
        original_mission: futureHard.original.mission, adapted_mission: next.find((session) => session.id === futureHard.id)!.adapted.mission, accepted: null,
      }],
      updated_at: now,
      sync_state: 'queued',
    },
    sessions: next,
  }
}

export function preserveUserOverride(session: CampaignSession, useOriginal: boolean): CampaignSession {
  return {
    ...session,
    adapted: useOriginal ? { ...session.original } : { ...session.adapted },
    user_override: true,
    adaptation_reason: useOriginal ? 'User kept the original prescription.' : session.adaptation_reason,
    updated_at: new Date().toISOString(),
    sync_state: 'queued',
  }
}

export function campaignFamilyLabel(family: CampaignFamily): string {
  return ({
    foundation_first: 'Foundation to First Marathon',
    first_finish: 'First Marathon: Finish Strong',
    first_performance: 'First Marathon: Performance',
    personal_best: 'Marathon Personal Best',
    hybrid: 'Hybrid Athlete Marathon',
  } satisfies Record<CampaignFamily, string>)[family]
}

export function campaignPhaseLabel(phase: CampaignPhase): string {
  return phase.split('_').map((word) => word[0].toUpperCase() + word.slice(1)).join(' ')
}
