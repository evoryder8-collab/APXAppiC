import type { CoachAccountContext } from './coachPlatform.ts'
import { coachClientPolicy, type CoachClientPolicy } from './coachPlatform.ts'
import type {
  AccountAccessEnvelope,
  AccountAccessResolution,
  AccountEntitlementState,
} from './types.ts'

export const SPONSORED_ACCESS_OFFLINE_MS = 24 * 60 * 60 * 1_000
export const WEB_APP_BUILD_NUMBER = 0
const ACCESS_CACHE_PREFIX = 'apex.account-access.v2'
const LEGACY_ACCESS_CACHE_PREFIX = 'apex.account-access.v1'
const WORKOUT_RECEIPT_ROUTE = /^\/(?:player|log)\/([^/]+)\/[^/]+\/*$/i
const COACH_INVITATION_ROUTE = /^\/coach\/invite\/[^/]+\/*$/i

export interface AccountAccessStorage {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
  removeItem(key: string): void
}

export type AccountAccessRPC = (
  name: string,
  args: Record<string, unknown>,
) => PromiseLike<{
  data: unknown
  error: { message: string } | null
}>

export type ResolvedAccountAccess = Extract<AccountAccessResolution, { status: 'resolved' }>
export type AccountAccessRecoveryReason = 'update_required' | 'revoked' | 'expired' | 'locked' | 'uncertain'

export class AccountAccessProtocolError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'AccountAccessProtocolError'
  }
}

const ENTITLEMENT_STATES = new Set<AccountEntitlementState>([
  'granted',
  'locked',
  'revoked',
  'expired',
  'missing',
])
const ISO_TIMESTAMP = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|([+-])(\d{2}):(\d{2}))$/

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function isTimestamp(value: unknown): value is string {
  if (typeof value !== 'string') return false
  const match = ISO_TIMESTAMP.exec(value)
  if (!match) return false
  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  const hour = Number(match[4])
  const minute = Number(match[5])
  const second = Number(match[6])
  const offsetHour = match[10] === undefined ? 0 : Number(match[10])
  const offsetMinute = match[11] === undefined ? 0 : Number(match[11])
  const leapYear = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0)
  const monthDays = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  return month >= 1
    && month <= 12
    && day >= 1
    && day <= monthDays[month - 1]
    && hour <= 23
    && minute <= 59
    && second <= 59
    && offsetHour <= 14
    && offsetMinute <= 59
    && (offsetHour < 14 || offsetMinute === 0)
    && Number.isFinite(Date.parse(value))
}

function isNullableTimestamp(value: unknown): value is string | null {
  return value === null || isTimestamp(value)
}

function currentMonotonicTime(): number | null {
  const value = globalThis.performance?.now()
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null
}

function normalizedEnvelope(value: unknown, expectedUserID: string): AccountAccessEnvelope | null {
  if (!isRecord(value) || value.user_id !== expectedUserID) return null
  if (typeof value.state !== 'string' || !ENTITLEMENT_STATES.has(value.state as AccountEntitlementState)) return null
  if (!isNullableTimestamp(value.expires_at) || !isNullableTimestamp(value.entitlement_updated_at)) return null
  if (!isTimestamp(value.server_now)) return null
  if (typeof value.sponsored_seat_active !== 'boolean') return null
  if (!Number.isInteger(value.minimum_build) || (value.minimum_build as number) < 0) return null
  if (typeof value.update_required !== 'boolean' || typeof value.web_beta_codes_enabled !== 'boolean') return null

  return {
    user_id: value.user_id,
    state: value.state as AccountEntitlementState,
    expires_at: value.expires_at,
    entitlement_updated_at: value.entitlement_updated_at,
    server_now: value.server_now,
    sponsored_seat_active: value.sponsored_seat_active,
    minimum_build: value.minimum_build as number,
    update_required: value.update_required,
    web_beta_codes_enabled: value.web_beta_codes_enabled,
  }
}

export function pendingAccountAccess(ownerUserID: string | null): AccountAccessResolution {
  return {
    status: 'pending',
    owner_user_id: ownerUserID,
    envelope: null,
    source: null,
    resolved_at: null,
    error: null,
  }
}

export function failedAccountAccess(ownerUserID: string, error: string): AccountAccessResolution {
  return {
    status: 'failed',
    owner_user_id: ownerUserID,
    envelope: null,
    source: null,
    resolved_at: null,
    error,
  }
}

export function localAccountAccess(ownerUserID: string, now = Date.now()): AccountAccessResolution {
  const timestamp = new Date(now).toISOString()
  const monotonicAnchor = currentMonotonicTime()
  return {
    status: 'resolved',
    owner_user_id: ownerUserID,
    source: 'local',
    resolved_at: timestamp,
    clock_observed_at: timestamp,
    elapsed_anchor_ms: 0,
    monotonic_anchor_ms: monotonicAnchor,
    error: null,
    envelope: {
      user_id: ownerUserID,
      state: 'granted',
      expires_at: null,
      entitlement_updated_at: timestamp,
      server_now: timestamp,
      sponsored_seat_active: false,
      minimum_build: 0,
      update_required: false,
      web_beta_codes_enabled: false,
    },
  }
}

/** Accept exactly one table-returning RPC row, owned by the active session. */
export function resolveAccountAccess(
  rpcData: unknown,
  expectedUserID: string,
  source: 'server' | 'cache' | 'local',
  resolvedAt = new Date().toISOString(),
  clockObservedAt = resolvedAt,
  monotonicAnchor = currentMonotonicTime(),
  clientBuild = WEB_APP_BUILD_NUMBER,
): ResolvedAccountAccess | null {
  if (
    !Array.isArray(rpcData)
    || rpcData.length !== 1
    || !isTimestamp(resolvedAt)
    || !isTimestamp(clockObservedAt)
    || Date.parse(clockObservedAt) < Date.parse(resolvedAt)
    || (monotonicAnchor !== null && (!Number.isFinite(monotonicAnchor) || monotonicAnchor < 0))
    || !Number.isInteger(clientBuild)
    || clientBuild < 0
  ) return null
  const envelope = normalizedEnvelope(rpcData[0], expectedUserID)
  if (!envelope) return null
  const updateRequired = clientBuild < envelope.minimum_build
  if (source === 'server' && envelope.update_required !== updateRequired) return null
  return {
    status: 'resolved',
    owner_user_id: expectedUserID,
    envelope: envelope.update_required === updateRequired
      ? envelope
      : { ...envelope, update_required: updateRequired },
    source,
    resolved_at: resolvedAt,
    clock_observed_at: clockObservedAt,
    elapsed_anchor_ms: 0,
    monotonic_anchor_ms: monotonicAnchor,
    error: null,
  }
}

export async function fetchMyAppAccess(
  rpc: AccountAccessRPC,
  expectedUserID: string,
  build = WEB_APP_BUILD_NUMBER,
  now?: number,
): Promise<ResolvedAccountAccess> {
  if (!Number.isInteger(build) || build < 0) {
    throw new AccountAccessProtocolError('Invalid web client build')
  }
  const { data, error } = await rpc('get_my_app_access', {
    p_platform: 'web',
    p_build: build,
  })
  if (error) throw new Error(error.message)
  const resolvedAt = now ?? Date.now()
  if (!Number.isFinite(resolvedAt)) {
    throw new AccountAccessProtocolError('Invalid access resolution time')
  }
  const timestamp = new Date(resolvedAt).toISOString()
  const access = resolveAccountAccess(
    data,
    expectedUserID,
    'server',
    timestamp,
    timestamp,
    currentMonotonicTime(),
    build,
  )
  if (!access) {
    throw new AccountAccessProtocolError('Access response did not belong to the authenticated account')
  }
  return access
}

/** Reject a delayed response instead of retaining a possibly broader grant. */
export function validatedAccountAccessProgression(
  previous: AccountAccessResolution,
  next: ResolvedAccountAccess,
): ResolvedAccountAccess {
  if (previous.status !== 'resolved' || previous.owner_user_id !== next.owner_user_id) return next
  const previousServerNow = Date.parse(previous.envelope.server_now)
  const nextServerNow = Date.parse(next.envelope.server_now)
  if (
    !Number.isFinite(previousServerNow)
    || !Number.isFinite(nextServerNow)
    || nextServerNow < previousServerNow
  ) {
    throw new AccountAccessProtocolError('Access response moved backwards in server time')
  }
  return next
}

function resolvedEnvelope(access: AccountAccessResolution | null | undefined): AccountAccessEnvelope | null {
  return access?.status === 'resolved' && access.owner_user_id === access.envelope.user_id
    ? access.envelope
    : null
}

function estimatedServerTime(
  access: ResolvedAccountAccess,
  now: number,
  monotonicNow = currentMonotonicTime(),
): number | null {
  const resolvedAt = Date.parse(access.resolved_at)
  const clockObservedAt = Date.parse(access.clock_observed_at)
  const serverNow = Date.parse(access.envelope.server_now)
  const wallElapsed = now - resolvedAt
  if (
    !Number.isFinite(now)
    || !Number.isFinite(resolvedAt)
    || !Number.isFinite(clockObservedAt)
    || !Number.isFinite(serverNow)
    || now < resolvedAt
    || now < clockObservedAt
    || !Number.isFinite(access.elapsed_anchor_ms)
    || access.elapsed_anchor_ms < 0
  ) {
    return null
  }

  let elapsed = wallElapsed
  if (access.monotonic_anchor_ms !== null) {
    if (monotonicNow === null || !Number.isFinite(monotonicNow)) return null
    const monotonicDelta = Math.floor(monotonicNow - access.monotonic_anchor_ms)
    if (monotonicDelta < 0) return null
    const monotonicElapsed = access.elapsed_anchor_ms + monotonicDelta
    if (!Number.isFinite(monotonicElapsed) || wallElapsed < monotonicElapsed) return null
    elapsed = Math.max(wallElapsed, monotonicElapsed)
  }
  if (now > clockObservedAt) access.clock_observed_at = new Date(now).toISOString()
  const estimated = serverNow + elapsed
  return Number.isFinite(estimated) ? estimated : null
}

function liveGraceDeadline(
  access: AccountAccessResolution | null | undefined,
  context: CoachAccountContext | null | undefined,
  now: number,
  monotonicNow = currentMonotonicTime(),
): number | null {
  const envelope = resolvedEnvelope(access)
  const sponsorship = context?.sponsorship
  const grace = sponsorship?.relationship_status === 'grace' || sponsorship?.seat_state === 'grace'
  if (
    access?.status !== 'resolved'
    || !envelope
    || envelope.update_required
    || !grace
    || !isTimestamp(sponsorship?.grace_ends_at)
  ) return null

  const serverTime = estimatedServerTime(access, now, monotonicNow)
  const graceEndsAt = Date.parse(sponsorship.grace_ends_at)
  if (serverTime === null || graceEndsAt <= serverTime) return null
  const deadline = Date.parse(access.resolved_at) + (graceEndsAt - Date.parse(envelope.server_now))
  return Number.isFinite(deadline) && deadline > now ? deadline : null
}

export function accountAccessHasIndividualAccess(
  access: AccountAccessResolution | null | undefined,
  now = Date.now(),
  monotonicNow = currentMonotonicTime(),
): boolean {
  const envelope = resolvedEnvelope(access)
  if (!envelope || envelope.update_required || envelope.state !== 'granted') return false
  if (envelope.expires_at === null) return true
  if (access?.status !== 'resolved') return false
  const serverTime = estimatedServerTime(access, now, monotonicNow)
  return serverTime !== null && Date.parse(envelope.expires_at) > serverTime
}

export function accountAccessHasSponsoredAccess(
  access: AccountAccessResolution | null | undefined,
  now = Date.now(),
  monotonicNow = currentMonotonicTime(),
): boolean {
  const envelope = resolvedEnvelope(access)
  if (!envelope || envelope.update_required || !envelope.sponsored_seat_active) return false
  if (access?.status !== 'resolved') return false
  const serverTime = estimatedServerTime(access, now, monotonicNow)
  return serverTime !== null
    && Date.parse(envelope.server_now) + SPONSORED_ACCESS_OFFLINE_MS > serverTime
}

/** Return the next local-wall-clock instant at which any access capability changes. */
export function accountAccessNextChangeAt(
  access: AccountAccessResolution | null | undefined,
  now = Date.now(),
  context?: CoachAccountContext,
  monotonicNow = currentMonotonicTime(),
): number | null {
  const envelope = resolvedEnvelope(access)
  if (
    access?.status !== 'resolved'
    || !envelope
    || envelope.update_required
    || !Number.isFinite(now)
  ) return null

  const resolvedAt = Date.parse(access.resolved_at)
  const serverNow = Date.parse(envelope.server_now)
  if (!Number.isFinite(resolvedAt) || !Number.isFinite(serverNow) || now < resolvedAt) return null
  if (estimatedServerTime(access, now, monotonicNow) === null) return null

  const deadlines: number[] = []
  if (envelope.state === 'granted' && envelope.expires_at !== null) {
    const deadline = resolvedAt + (Date.parse(envelope.expires_at) - serverNow)
    if (Number.isFinite(deadline) && deadline > now) deadlines.push(deadline)
  }
  if (envelope.sponsored_seat_active) {
    const deadline = resolvedAt + SPONSORED_ACCESS_OFFLINE_MS
    if (Number.isFinite(deadline) && deadline > now) deadlines.push(deadline)
  }
  const graceDeadline = liveGraceDeadline(access, context, now, monotonicNow)
  if (graceDeadline !== null) deadlines.push(graceDeadline)
  return deadlines.length > 0 ? Math.min(...deadlines) : null
}

export function accountAccessHasAppAccess(
  access: AccountAccessResolution | null | undefined,
  now = Date.now(),
  monotonicNow = currentMonotonicTime(),
): boolean {
  return accountAccessHasIndividualAccess(access, now, monotonicNow)
    || accountAccessHasSponsoredAccess(access, now, monotonicNow)
}

/** Explain a locked recovery surface without turning an uncertain check into a denial. */
export function accountAccessRecoveryReason(
  access: AccountAccessResolution | null | undefined,
  now = Date.now(),
  monotonicNow = currentMonotonicTime(),
): AccountAccessRecoveryReason {
  const envelope = resolvedEnvelope(access)
  if (access?.status !== 'resolved' || !envelope) return 'uncertain'
  if (envelope.update_required) return 'update_required'
  /* A sponsored flag is a separate access path. Once its 24-hour evidence
     window closes, an individual-state label cannot explain the whole lock. */
  if (envelope.sponsored_seat_active) return 'uncertain'
  if (envelope.state === 'revoked') return 'revoked'
  if (envelope.state === 'expired') return 'expired'

  if (envelope.state === 'granted' && envelope.expires_at !== null) {
    const serverTime = estimatedServerTime(access, now, monotonicNow)
    if (serverTime === null) return 'uncertain'
    if (Date.parse(envelope.expires_at) <= serverTime) return 'expired'
  }

  if (
    (envelope.state === 'locked' || envelope.state === 'missing')
    && !envelope.sponsored_seat_active
  ) return 'locked'
  return 'uncertain'
}

export function accountAccessAfterFailure(
  current: AccountAccessResolution,
  expectedUserID: string,
  error: string,
  now = Date.now(),
): AccountAccessResolution {
  if (current.status === 'resolved' && current.owner_user_id === expectedUserID) {
    /* Keep the last authoritative answer, including a denial. A transient
       outage must not turn minimum-build or revocation evidence into a less
       specific failed state (or reopen invitation bootstrap). */
    const observed = { ...current }
    void accountAccessHasAppAccess(observed, now)
    return observed
  }
  return failedAccountAccess(expectedUserID, error)
}

/** Drop relationship-derived access immediately while preserving an
 * independently valid individual grant for the same authenticated owner. */
export function accountAccessAfterRelationshipMutation(
  current: AccountAccessResolution,
  expectedUserID: string,
  error: string,
  now = Date.now(),
): AccountAccessResolution {
  if (current.status === 'resolved' && current.owner_user_id === expectedUserID) {
    const withoutSponsor: ResolvedAccountAccess = {
      ...current,
      envelope: { ...current.envelope, sponsored_seat_active: false },
    }
    if (accountAccessHasIndividualAccess(withoutSponsor, now)) return withoutSponsor
  }
  return failedAccountAccess(expectedUserID, error)
}

function accessCacheKey(ownerUserID: string): string {
  return `${ACCESS_CACHE_PREFIX}.${encodeURIComponent(ownerUserID)}`
}

function legacyAccessCacheKey(ownerUserID: string): string {
  return `${LEGACY_ACCESS_CACHE_PREFIX}.${encodeURIComponent(ownerUserID)}`
}

function availableStorage(storage?: AccountAccessStorage): AccountAccessStorage | null {
  if (storage) return storage
  return typeof globalThis.localStorage === 'undefined' ? null : globalThis.localStorage
}

export function clearCachedAccountAccess(
  ownerUserID: string,
  storage?: AccountAccessStorage,
): void {
  try {
    const target = availableStorage(storage)
    target?.removeItem(accessCacheKey(ownerUserID))
    target?.removeItem(legacyAccessCacheKey(ownerUserID))
  } catch {
    // Access resolution stays usable in memory when browser storage is blocked.
  }
}

export function saveCachedAccountAccess(
  access: AccountAccessResolution | null,
  expectedUserID: string,
  storage?: AccountAccessStorage,
  now = Date.now(),
): boolean {
  if (
    access?.status !== 'resolved'
    || access.owner_user_id !== expectedUserID
    || access.envelope.user_id !== expectedUserID
    || !accountAccessHasAppAccess(access, now)
  ) {
    clearCachedAccountAccess(expectedUserID, storage)
    return false
  }
  const target = availableStorage(storage)
  if (!target) return false
  try {
    target.setItem(accessCacheKey(expectedUserID), JSON.stringify({
      version: 2,
      owner_user_id: expectedUserID,
      cached_at: access.resolved_at,
      clock_observed_at: access.clock_observed_at,
      envelope: access.envelope,
    }))
    return true
  } catch {
    clearCachedAccountAccess(expectedUserID, target)
    return false
  }
}

export function loadCachedAccountAccess(
  expectedUserID: string,
  storage?: AccountAccessStorage,
  now = Date.now(),
  clientBuild = WEB_APP_BUILD_NUMBER,
): AccountAccessResolution | null {
  const target = availableStorage(storage)
  if (!target) return null
  try {
    const raw = target.getItem(accessCacheKey(expectedUserID))
    if (!raw) return null
    const record = JSON.parse(raw) as unknown
    if (
      !isRecord(record)
      || record.version !== 2
      || record.owner_user_id !== expectedUserID
      || !isTimestamp(record.cached_at)
      || !isTimestamp(record.clock_observed_at)
      || Date.parse(record.clock_observed_at) < Date.parse(record.cached_at)
    ) {
      clearCachedAccountAccess(expectedUserID, target)
      return null
    }
    const access = resolveAccountAccess(
      [record.envelope],
      expectedUserID,
      'cache',
      record.cached_at,
      record.clock_observed_at,
      currentMonotonicTime(),
      clientBuild,
    )
    if (access) access.elapsed_anchor_ms = now - Date.parse(record.cached_at)
    if (!access) {
      clearCachedAccountAccess(expectedUserID, target)
      return null
    }
    if (access.envelope.update_required) return access
    if (!accountAccessHasAppAccess(access, now)) {
      clearCachedAccountAccess(expectedUserID, target)
      return null
    }
    return access
  } catch {
    clearCachedAccountAccess(expectedUserID, target)
    return null
  }
}

export function clientPolicyForAccount(
  access: AccountAccessResolution,
  context: CoachAccountContext,
  now = Date.now(),
  monotonicNow = currentMonotonicTime(),
): CoachClientPolicy {
  const sponsored = accountAccessHasSponsoredAccess(access, now, monotonicNow)
  const grace = liveGraceDeadline(access, context, now, monotonicNow) !== null
  return coachClientPolicy({
    relationship_status: sponsored ? 'active' : grace ? context.sponsorship?.relationship_status ?? null : null,
    seat_state: sponsored ? 'active' : grace ? context.sponsorship?.seat_state ?? null : null,
    consented_scopes: context.sponsorship?.consented_scopes ?? [],
    individual_access: accountAccessHasIndividualAccess(access, now, monotonicNow),
  })
}

export function accountAccessAllowsRoute(
  access: AccountAccessResolution,
  context: CoachAccountContext,
  pathname: string,
  now = Date.now(),
  monotonicNow = currentMonotonicTime(),
): boolean {
  if (resolvedEnvelope(access)?.update_required) return false
  if (accountAccessHasIndividualAccess(access, now, monotonicNow)) return true
  let decodedPathname: string
  try {
    decodedPathname = decodeURIComponent(pathname)
  } catch {
    return false
  }
  const policy = clientPolicyForAccount(access, context, now, monotonicNow)
  if (accountAccessHasSponsoredAccess(access, now, monotonicNow)) {
    const workoutRoute = WORKOUT_RECEIPT_ROUTE.exec(decodedPathname)
    return workoutRoute
      ? workoutRoute[1].toLowerCase() === 'coach' && policy.can_follow_coach_plan
      : true
  }
  if (COACH_INVITATION_ROUTE.test(decodedPathname)) return !policy.coach_plan_read_only
  return decodedPathname === '/coach-plan' && policy.coach_plan_read_only
}
