export const COACH_CONSENT_SCOPES = [
  'nutrition',
  'workouts',
  'activity',
  'hydration',
  'supplements',
  'avatar',
  'measurements',
  'notes',
  'recovery',
  'visual_progress',
] as const

export type CoachConsentScope = (typeof COACH_CONSENT_SCOPES)[number]
export type CoachRelationshipStatus = 'invited' | 'active' | 'grace' | 'ended'
export type CoachSeatState = 'pending' | 'active' | 'grace' | 'released'

export interface CoachProfileSummary {
  status: 'development' | 'active' | 'suspended'
  display_name: string
  seat_limit: number
  active_seats: number
}

export interface CoachSponsorshipSummary {
  relationship_id: string
  coach_display_name: string
  relationship_status: CoachRelationshipStatus
  seat_state: CoachSeatState
  offered_scopes: CoachConsentScope[]
  consented_scopes: CoachConsentScope[]
  grace_ends_at: string | null
}

export interface CoachClientPolicyInput {
  relationship_status: CoachRelationshipStatus | null
  seat_state: CoachSeatState | null
  consented_scopes: readonly CoachConsentScope[]
  individual_access: boolean
}

export interface CoachClientPolicy {
  can_use_sponsored_app: boolean
  can_follow_coach_plan: boolean
  coach_plan_read_only: boolean
  can_create_custom_workouts: boolean
  can_rebuild_fitness_plan: boolean
  can_use_orbit: boolean
  can_use_nutrition: boolean
  can_use_avatar: boolean
  can_view_visual_progress: boolean
}

export function coachClientPolicy(input: CoachClientPolicyInput): CoachClientPolicy {
  const activeSponsorship = input.relationship_status === 'active' && input.seat_state === 'active'
  const grace = input.relationship_status === 'grace' || input.seat_state === 'grace'
  const relationshipExists = activeSponsorship || grace
  return {
    can_use_sponsored_app: activeSponsorship,
    can_follow_coach_plan: activeSponsorship,
    coach_plan_read_only: grace,
    can_create_custom_workouts: input.individual_access || !relationshipExists,
    can_rebuild_fitness_plan: input.individual_access || !relationshipExists,
    can_use_orbit: input.individual_access || !relationshipExists,
    can_use_nutrition: input.individual_access || !relationshipExists || activeSponsorship,
    can_use_avatar: input.individual_access || !relationshipExists || activeSponsorship,
    can_view_visual_progress: input.individual_access || !relationshipExists,
  }
}

export type CoachPlanChecklistKey =
  | 'nutrition'
  | 'workouts'
  | 'supplements'
  | 'hydration'
  | 'schedule'
  | 'review_date'

export interface CoachPlanChecklist extends Record<CoachPlanChecklistKey, boolean> {}

export type CoachExerciseUnit = 'reps' | 'seconds' | 'minutes' | 'metres' | 'steps' | 'rounds'

export interface CoachExerciseTemplate {
  id: string
  movement_id: string
  name: string
  sets: number
  target_min: number
  target_max: number
  unit: CoachExerciseUnit
  per_side: boolean
  rest_seconds: number
  tempo_up_seconds: number
  tempo_down_seconds: number
  tempo_pause_seconds: number
  notes: string
  optional: boolean
  group_id: string | null
  group_position: number | null
}

export interface CoachSessionTemplate {
  id: string
  weekday: number
  name: string
  session_mode: 'guided' | 'tracked'
  estimated_minutes: number
  warmup_note: string
  exercises: CoachExerciseTemplate[]
}

export interface CoachPlanDraft {
  title: string
  objective: string
  coach_note: string
  review_date: string | null
  checklist: CoachPlanChecklist
  sessions: CoachSessionTemplate[]
}

export interface CoachCurrentPlan {
  id: string
  relationship_id: string
  version: number
  status: 'draft' | 'published' | 'superseded'
  title: string
  objective: string
  coach_note: string
  review_date: string | null
  checklist: CoachPlanChecklist
  plan: CoachPlanDraft
  published_at: string | null
  acknowledged_at: string | null
  activated_at: string | null
}

export interface CoachAccountContext {
  coach: CoachProfileSummary | null
  sponsorship: CoachSponsorshipSummary | null
  current_plan: CoachCurrentPlan | null
  capabilities: {
    coach_workspace: boolean
    sponsored_client: boolean
  }
}

export const EMPTY_COACH_ACCOUNT_CONTEXT: CoachAccountContext = {
  coach: null,
  sponsorship: null,
  current_plan: null,
  capabilities: { coach_workspace: false, sponsored_client: false },
}

export interface CoachRosterEntry {
  id: string
  client_user_id: string
  display_name: string
  relationship_status: CoachRelationshipStatus
  seat_state: CoachSeatState
  consented_scopes: CoachConsentScope[]
  plan_version: number | null
  plan_title: string | null
  review_date: string | null
  published_at: string | null
  acknowledged_at: string | null
  activated_at: string | null
  attention: CoachRosterAttention[]
}

export interface CoachClientOverview {
  relationship_id: string
  client_user_id: string
  display_name: string
  relationship_status: CoachRelationshipStatus
  seat_state: CoachSeatState
  consented_scopes: CoachConsentScope[]
  measurements: null | {
    sex: string
    height_cm: number
    weight_kg: number
    body_fat_pct: number | null
    birthdate: string
  }
  avatar: null | Record<string, string | number | null>
  workouts: null | { completed_30d: number; last_completed_at: string | null }
  nutrition: null | { days_observed: number; average_kcal: number | null }
  hydration: null | { days_observed: number; average_litres: number | null }
  visual_progress_shared: boolean
  current_plan: CoachCurrentPlan | null
}

export interface CoachInvitationReceipt {
  invitation_id: string
  token: string
  expires_at: string
}

export interface CoachInvitationPreview {
  coach_display_name: string
  requested_scopes: CoachConsentScope[]
  visual_progress_requested: boolean
  expires_at: string
}

export interface CoachPlanVersionReceipt {
  id: string
  relationship_id: string
  version: number
  status: 'draft' | 'published' | 'superseded'
}

export interface CoachPlanIssue {
  code:
    | 'unknown_field'
    | 'too_long'
    | 'title_required'
    | 'objective_required'
    | 'review_date'
    | 'checklist'
    | 'sessions_required'
    | 'session_count'
    | 'duplicate_id'
    | 'weekday'
    | 'session_name'
    | 'session_mode'
    | 'estimated_minutes'
    | 'exercise_count'
    | 'movement'
    | 'exercise_name'
    | 'sets'
    | 'target'
    | 'target_order'
    | 'unit'
    | 'rest'
    | 'tempo'
    | 'group'
  path: string
}

const PLAN_FIELDS = new Set(['title', 'objective', 'coach_note', 'review_date', 'checklist', 'sessions'])
const CHECKLIST_FIELDS = new Set<CoachPlanChecklistKey>([
  'nutrition', 'workouts', 'supplements', 'hydration', 'schedule', 'review_date',
])
const SESSION_FIELDS = new Set([
  'id', 'weekday', 'name', 'session_mode', 'estimated_minutes', 'warmup_note', 'exercises',
])
const EXERCISE_FIELDS = new Set([
  'id', 'movement_id', 'name', 'sets', 'target_min', 'target_max', 'unit', 'per_side',
  'rest_seconds', 'tempo_up_seconds', 'tempo_down_seconds', 'tempo_pause_seconds',
  'notes', 'optional', 'group_id', 'group_position',
])
const EXERCISE_UNITS = new Set<CoachExerciseUnit>(['reps', 'seconds', 'minutes', 'metres', 'steps', 'rounds'])

function ownKeys(value: unknown): string[] {
  return value && typeof value === 'object' && !Array.isArray(value) ? Object.keys(value) : []
}

function unknownFields(value: unknown, allowed: ReadonlySet<string>, path: string): CoachPlanIssue[] {
  return ownKeys(value)
    .filter((key) => !allowed.has(key))
    .map((key) => ({ code: 'unknown_field', path: `${path}.${key}` }))
}

function boundedInteger(value: unknown, minimum: number, maximum: number): boolean {
  return Number.isInteger(value) && Number(value) >= minimum && Number(value) <= maximum
}

function validISODate(value: unknown): value is string {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const [year, month, day] = value.split('-').map(Number)
  const date = new Date(Date.UTC(year, month - 1, day))
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day
}

export function validateCoachPlan(
  value: CoachPlanDraft,
  options: { publishing: boolean; known_movement_ids?: ReadonlySet<string> },
): { publishable: boolean; issues: CoachPlanIssue[] } {
  const issues: CoachPlanIssue[] = unknownFields(value, PLAN_FIELDS, 'plan')
  const title = typeof value.title === 'string' ? value.title.trim() : ''
  const objective = typeof value.objective === 'string' ? value.objective.trim() : ''
  const coachNote = typeof value.coach_note === 'string' ? value.coach_note.trim() : ''
  if (title.length > 80) issues.push({ code: 'too_long', path: 'plan.title' })
  if (objective.length > 240) issues.push({ code: 'too_long', path: 'plan.objective' })
  if (coachNote.length > 4_000) issues.push({ code: 'too_long', path: 'plan.coach_note' })
  if (options.publishing && title.length < 2) issues.push({ code: 'title_required', path: 'plan.title' })
  if (options.publishing && objective.length < 2) issues.push({ code: 'objective_required', path: 'plan.objective' })
  if (value.review_date != null && !validISODate(value.review_date)) {
    issues.push({ code: 'review_date', path: 'plan.review_date' })
  }
  if (options.publishing && !validISODate(value.review_date)) {
    if (!issues.some((issue) => issue.code === 'review_date')) issues.push({ code: 'review_date', path: 'plan.review_date' })
  }

  issues.push(...unknownFields(value.checklist, CHECKLIST_FIELDS, 'plan.checklist'))
  if (options.publishing && (!value.checklist || [...CHECKLIST_FIELDS].some((key) => value.checklist[key] !== true))) {
    issues.push({ code: 'checklist', path: 'plan.checklist' })
  }

  const sessions = Array.isArray(value.sessions) ? value.sessions : []
  if (options.publishing && sessions.length === 0) issues.push({ code: 'sessions_required', path: 'plan.sessions' })
  if (sessions.length > 7) issues.push({ code: 'session_count', path: 'plan.sessions' })
  const identifiers = new Set<string>()
  sessions.forEach((session, sessionIndex) => {
    const path = `plan.sessions[${sessionIndex}]`
    issues.push(...unknownFields(session, SESSION_FIELDS, path))
    if (!session.id || identifiers.has(session.id)) issues.push({ code: 'duplicate_id', path: `${path}.id` })
    else identifiers.add(session.id)
    if (!boundedInteger(session.weekday, 1, 7)) issues.push({ code: 'weekday', path: `${path}.weekday` })
    if (typeof session.name !== 'string' || session.name.trim().length < 2 || session.name.trim().length > 80) {
      issues.push({ code: 'session_name', path: `${path}.name` })
    }
    if (session.session_mode !== 'guided' && session.session_mode !== 'tracked') {
      issues.push({ code: 'session_mode', path: `${path}.session_mode` })
    }
    if (!boundedInteger(session.estimated_minutes, 5, 360)) {
      issues.push({ code: 'estimated_minutes', path: `${path}.estimated_minutes` })
    }
    if (typeof session.warmup_note !== 'string' || session.warmup_note.length > 1_000) {
      issues.push({ code: 'too_long', path: `${path}.warmup_note` })
    }
    const exercises = Array.isArray(session.exercises) ? session.exercises : []
    if (options.publishing && exercises.length === 0) issues.push({ code: 'exercise_count', path: `${path}.exercises` })
    if (exercises.length > 30) issues.push({ code: 'exercise_count', path: `${path}.exercises` })
    exercises.forEach((exercise, exerciseIndex) => {
      const exercisePath = `${path}.exercises[${exerciseIndex}]`
      issues.push(...unknownFields(exercise, EXERCISE_FIELDS, exercisePath))
      if (!exercise.id || identifiers.has(exercise.id)) issues.push({ code: 'duplicate_id', path: `${exercisePath}.id` })
      else identifiers.add(exercise.id)
      if (
        typeof exercise.movement_id !== 'string' || exercise.movement_id.length < 2 ||
        (options.known_movement_ids && !options.known_movement_ids.has(exercise.movement_id))
      ) issues.push({ code: 'movement', path: `${exercisePath}.movement_id` })
      if (typeof exercise.name !== 'string' || exercise.name.trim().length < 2 || exercise.name.trim().length > 120) {
        issues.push({ code: 'exercise_name', path: `${exercisePath}.name` })
      }
      if (!boundedInteger(exercise.sets, 1, 12)) issues.push({ code: 'sets', path: `${exercisePath}.sets` })
      if (!boundedInteger(exercise.target_min, 1, 600) || !boundedInteger(exercise.target_max, 1, 600)) {
        issues.push({ code: 'target', path: `${exercisePath}.target` })
      } else if (exercise.target_min > exercise.target_max) {
        issues.push({ code: 'target_order', path: `${exercisePath}.target` })
      }
      if (!EXERCISE_UNITS.has(exercise.unit)) issues.push({ code: 'unit', path: `${exercisePath}.unit` })
      if (!boundedInteger(exercise.rest_seconds, 0, 600)) issues.push({ code: 'rest', path: `${exercisePath}.rest_seconds` })
      for (const key of ['tempo_up_seconds', 'tempo_down_seconds', 'tempo_pause_seconds'] as const) {
        const tempo = exercise[key]
        if (typeof tempo !== 'number' || !Number.isFinite(tempo) || tempo < 0 || tempo > 30) {
          issues.push({ code: 'tempo', path: `${exercisePath}.${key}` })
        }
      }
      if ((exercise.group_id == null) !== (exercise.group_position == null)) {
        issues.push({ code: 'group', path: `${exercisePath}.group` })
      }
      if (exercise.group_position != null && !boundedInteger(exercise.group_position, 1, 30)) {
        issues.push({ code: 'group', path: `${exercisePath}.group_position` })
      }
      if (typeof exercise.notes !== 'string' || exercise.notes.length > 1_000) {
        issues.push({ code: 'too_long', path: `${exercisePath}.notes` })
      }
    })
  })
  return { publishable: options.publishing && issues.length === 0, issues }
}

export type CoachRosterAttention =
  | 'plan_missing'
  | 'review_due'
  | 'awaiting_acknowledgement'
  | 'seat_grace'

export function coachRosterAttention(input: {
  relationship_status: CoachRelationshipStatus
  plan_version: number | null
  plan_published_at: string | null
  acknowledged_at: string | null
  review_date: string | null
  today: string
}): CoachRosterAttention[] {
  if (input.relationship_status === 'grace') return ['seat_grace']
  if (input.relationship_status !== 'active') return []
  if (input.plan_version == null) return ['plan_missing']
  const attention: CoachRosterAttention[] = []
  if (input.review_date && validISODate(input.review_date) && validISODate(input.today)) {
    const review = Date.parse(`${input.review_date}T00:00:00Z`)
    const today = Date.parse(`${input.today}T00:00:00Z`)
    if (review - today <= 7 * 86_400_000) attention.push('review_due')
  }
  if (input.plan_published_at && !input.acknowledged_at) attention.push('awaiting_acknowledgement')
  return attention
}
