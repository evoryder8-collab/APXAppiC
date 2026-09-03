import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

import {
  AccountAccessProtocolError,
  accountAccessNextChangeAt,
  accountAccessRecoveryReason,
  accountAccessHasAppAccess,
  accountAccessHasIndividualAccess,
  accountAccessHasSponsoredAccess,
  accountAccessAllowsRoute,
  accountAccessAfterFailure,
  accountAccessAfterRelationshipMutation,
  clearCachedAccountAccess,
  clientPolicyForAccount,
  failedAccountAccess,
  fetchMyAppAccess,
  loadCachedAccountAccess,
  localAccountAccess,
  pendingAccountAccess,
  resolveAccountAccess,
  saveCachedAccountAccess,
  validatedAccountAccessProgression,
} from '../src/lib/coachAccess.ts'
import { EMPTY_COACH_ACCOUNT_CONTEXT, type CoachAccountContext } from '../src/lib/coachPlatform.ts'
import { LANGUAGE_OPTIONS } from '../src/lib/introLanguage.ts'
import { UI_TRANSLATIONS } from '../src/lib/translations.ts'
import type { AccountAccessEnvelope } from '../src/lib/types.ts'

const OWNER_ID = '11111111-1111-4111-8111-111111111111'
const OTHER_OWNER_ID = '22222222-2222-4222-8222-222222222222'
const NOW = Date.parse('2026-09-01T12:00:00Z')

function envelope(patch: Partial<AccountAccessEnvelope> = {}): AccountAccessEnvelope {
  return {
    user_id: OWNER_ID,
    state: 'granted',
    expires_at: '2027-12-31T23:59:59Z',
    entitlement_updated_at: '2026-09-01T00:00:00Z',
    server_now: '2026-09-01T12:00:00Z',
    sponsored_seat_active: false,
    minimum_build: 0,
    update_required: false,
    web_beta_codes_enabled: false,
    ...patch,
  }
}

class MemoryStorage {
  readonly values = new Map<string, string>()
  failWrites = false

  getItem(key: string): string | null {
    return this.values.get(key) ?? null
  }

  setItem(key: string, value: string): void {
    if (this.failWrites) throw new Error('storage unavailable')
    this.values.set(key, value)
  }

  removeItem(key: string): void {
    this.values.delete(key)
  }
}

test('a profileless account unlocks only from a complete envelope owned by the authenticated user', () => {
  const resolved = resolveAccountAccess([envelope()], OWNER_ID, 'server', '2026-09-01T12:00:00Z')

  assert.equal(resolved?.status, 'resolved')
  assert.equal(accountAccessHasIndividualAccess(resolved, NOW), true)
  assert.equal(accountAccessHasAppAccess(resolved, NOW), true)
  assert.equal(resolveAccountAccess([envelope({ user_id: OTHER_OWNER_ID })], OWNER_ID, 'server'), null)
  assert.equal(resolveAccountAccess([], OWNER_ID, 'server'), null)
  assert.equal(resolveAccountAccess([envelope(), envelope()], OWNER_ID, 'server'), null)
  assert.equal(resolveAccountAccess([{ ...envelope(), server_now: 'not-a-date' }], OWNER_ID, 'server'), null)
  assert.equal(resolveAccountAccess([{ ...envelope(), server_now: '0' }], OWNER_ID, 'server'), null)
  assert.equal(resolveAccountAccess([{ ...envelope(), server_now: '2026-02-31T12:00:00Z' }], OWNER_ID, 'server'), null)
  assert.equal(resolveAccountAccess([{ ...envelope(), expires_at: '2027-12-31' }], OWNER_ID, 'server'), null)
})

test('pending and failed resolutions stay locked while active sponsored access comes only from the envelope', () => {
  const pending = pendingAccountAccess(OWNER_ID)
  const failed = failedAccountAccess(OWNER_ID, 'offline')
  const sponsored = resolveAccountAccess([
    envelope({ state: 'locked', expires_at: null, sponsored_seat_active: true }),
  ], OWNER_ID, 'server', '2026-09-01T12:00:00Z')

  assert.equal(accountAccessHasAppAccess(pending, NOW), false)
  assert.equal(accountAccessHasAppAccess(failed, NOW), false)
  assert.equal(accountAccessHasIndividualAccess(sponsored, NOW), false)
  assert.equal(accountAccessHasSponsoredAccess(sponsored, NOW), true)
  assert.equal(accountAccessHasAppAccess(sponsored, NOW), true)
})

test('revoked, expired, malformed and update-required envelopes fail closed', () => {
  for (const denied of [
    envelope({ state: 'revoked' }),
    envelope({ state: 'locked' }),
    envelope({ state: 'missing' }),
    envelope({ state: 'expired' }),
    envelope({ expires_at: '2026-09-01T11:59:59Z' }),
    envelope({ minimum_build: 1, update_required: true }),
  ]) {
    assert.equal(
      accountAccessHasAppAccess(resolveAccountAccess([denied], OWNER_ID, 'server'), NOW),
      false,
    )
  }

  assert.equal(resolveAccountAccess([{ ...envelope(), expires_at: 'invalid' }], OWNER_ID, 'server'), null)
  assert.equal(resolveAccountAccess([{ ...envelope(), minimum_build: -1 }], OWNER_ID, 'server'), null)
  assert.equal(resolveAccountAccess([{ ...envelope(), sponsored_seat_active: 'yes' }], OWNER_ID, 'server'), null)
})

test('recovery reasons distinguish authoritative denials from an uncertain access check', () => {
  const resolved = (patch: Partial<AccountAccessEnvelope>) => resolveAccountAccess(
    [envelope(patch)],
    OWNER_ID,
    'server',
    '2026-09-01T12:00:00Z',
  )

  assert.equal(accountAccessRecoveryReason(pendingAccountAccess(OWNER_ID), NOW), 'uncertain')
  assert.equal(accountAccessRecoveryReason(failedAccountAccess(OWNER_ID, 'offline'), NOW), 'uncertain')
  assert.equal(accountAccessRecoveryReason(resolved({ minimum_build: 1, update_required: true }), NOW), 'update_required')
  assert.equal(accountAccessRecoveryReason(resolved({ state: 'revoked' }), NOW), 'revoked')
  assert.equal(accountAccessRecoveryReason(resolved({ state: 'expired' }), NOW), 'expired')
  assert.equal(accountAccessRecoveryReason(resolved({ state: 'locked', expires_at: null }), NOW), 'locked')
  assert.equal(accountAccessRecoveryReason(resolved({ state: 'missing', expires_at: null }), NOW), 'locked')
  assert.equal(accountAccessRecoveryReason(resolved({ expires_at: '2026-09-01T12:00:00Z' }), NOW), 'expired')

  const staleSponsor = resolved({
    state: 'locked',
    expires_at: null,
    sponsored_seat_active: true,
  })
  assert.equal(
    accountAccessRecoveryReason(staleSponsor, Date.parse('2026-09-02T12:00:00Z')),
    'uncertain',
  )
  for (const state of ['revoked', 'expired'] as const) {
    assert.equal(
      accountAccessRecoveryReason(
        resolved({ state, expires_at: null, sponsored_seat_active: true }),
        Date.parse('2026-09-02T12:00:00Z'),
      ),
      'uncertain',
      `stale sponsored evidence cannot authoritatively classify an individually ${state} account`,
    )
  }

  const rolledBack = resolved({ expires_at: '2026-09-02T12:00:00Z' })
  assert.ok(rolledBack)
  assert.equal(accountAccessHasIndividualAccess(rolledBack, Date.parse('2026-09-01T18:00:00Z')), true)
  assert.equal(accountAccessRecoveryReason(rolledBack, Date.parse('2026-09-01T17:00:00Z')), 'uncertain')
})

test('an explicit entitlement expiry cannot predate the server clock even when the device clock is behind', () => {
  const inconsistent = resolveAccountAccess([
    envelope({
      expires_at: '2026-09-01T11:59:59Z',
      server_now: '2026-09-01T12:00:00Z',
    }),
  ], OWNER_ID, 'server')

  assert.equal(accountAccessHasIndividualAccess(inconsistent, Date.parse('2026-08-01T00:00:00Z')), false)
})

test('bounded access advances from server_now by local elapsed time instead of trusting wall-clock parity', () => {
  const skewedIndividual = resolveAccountAccess([
    envelope({
      expires_at: '2026-09-02T12:00:00Z',
      server_now: '2026-09-01T12:00:00Z',
    }),
  ], OWNER_ID, 'cache', '2026-08-01T12:00:00Z')
  const skewedSponsor = resolveAccountAccess([
    envelope({
      state: 'locked',
      expires_at: null,
      sponsored_seat_active: true,
      server_now: '2026-09-01T12:00:00Z',
    }),
  ], OWNER_ID, 'cache', '2026-08-01T12:00:00Z')

  assert.equal(accountAccessHasIndividualAccess(skewedIndividual, Date.parse('2026-08-02T11:59:59Z')), true)
  assert.equal(accountAccessHasIndividualAccess(skewedIndividual, Date.parse('2026-08-02T12:00:00Z')), false)
  assert.equal(accountAccessHasSponsoredAccess(skewedSponsor, Date.parse('2026-08-02T11:59:59Z')), true)
  assert.equal(accountAccessHasSponsoredAccess(skewedSponsor, Date.parse('2026-08-02T12:00:00Z')), false)
  assert.equal(accountAccessHasAppAccess(skewedIndividual, Date.parse('2026-07-31T12:00:00Z')), false)
})

test('a partial wall-clock rollback after a later observation fails bounded access closed', () => {
  const bounded = resolveAccountAccess([
    envelope({
      expires_at: '2026-09-02T12:00:00Z',
      server_now: '2026-09-01T12:00:00Z',
    }),
  ], OWNER_ID, 'server', '2026-08-01T12:00:00Z')
  const permanent = resolveAccountAccess([
    envelope({ expires_at: null }),
  ], OWNER_ID, 'server', '2026-08-01T12:00:00Z')

  assert.ok(bounded)
  assert.ok(permanent)
  assert.equal(accountAccessHasIndividualAccess(bounded, Date.parse('2026-08-01T22:00:00Z')), true)
  assert.equal(accountAccessHasIndividualAccess(bounded, Date.parse('2026-08-01T17:00:00Z')), false)
  assert.equal(accountAccessNextChangeAt(bounded, Date.parse('2026-08-01T17:00:00Z')), null)
  assert.equal(accountAccessHasIndividualAccess(permanent, Date.parse('2026-08-01T22:00:00Z')), true)
  assert.equal(accountAccessHasIndividualAccess(permanent, Date.parse('2026-08-01T17:00:00Z')), true)
})

test('the elapsed clock detects a rollback before the first post-resolution access check', () => {
  const resolvedAt = '2026-08-01T12:00:00Z'
  const bounded = resolveAccountAccess(
    [envelope({ expires_at: '2026-09-02T12:00:00Z' })],
    OWNER_ID,
    'server',
    resolvedAt,
    resolvedAt,
    1_000,
  )

  assert.ok(bounded)
  assert.equal(
    accountAccessHasIndividualAccess(
      bounded,
      Date.parse('2026-08-01T17:00:00Z'),
      1_000 + (10 * 60 * 60 * 1_000),
    ),
    false,
    'ten elapsed hours cannot be represented by only five hours of wall-clock progress',
  )
})

test('the next access change maps server deadlines onto one local elapsed-time deadline', () => {
  const both = resolveAccountAccess([
    envelope({
      expires_at: '2026-09-03T12:00:00Z',
      sponsored_seat_active: true,
      server_now: '2026-09-01T12:00:00Z',
    }),
  ], OWNER_ID, 'cache', '2026-08-01T12:00:00Z')

  assert.equal(
    accountAccessNextChangeAt(both, Date.parse('2026-08-01T12:00:00Z')),
    Date.parse('2026-08-02T12:00:00Z'),
    'the sponsored policy change happens before the individual entitlement expiry',
  )
  assert.equal(
    accountAccessNextChangeAt(both, Date.parse('2026-08-02T12:00:00Z')),
    Date.parse('2026-08-03T12:00:00Z'),
    'after sponsorship ages out, the individual entitlement deadline remains',
  )
  assert.equal(
    accountAccessNextChangeAt(
      resolveAccountAccess([envelope({ expires_at: null })], OWNER_ID, 'cache', '2026-08-01T12:00:00Z'),
      Date.parse('2036-08-01T12:00:00Z'),
    ),
    null,
    'permanent protected-owner grants have no artificial freshness deadline',
  )
})

test('the access cache is owner-scoped and independent from the app-data cache', () => {
  const storage = new MemoryStorage()
  storage.setItem(`apex.cache.v2.${OWNER_ID}`, JSON.stringify({ profile: { user_id: OTHER_OWNER_ID } }))
  const resolved = resolveAccountAccess([envelope()], OWNER_ID, 'server', '2026-09-01T12:00:00Z')

  assert.equal(saveCachedAccountAccess(resolved, OWNER_ID, storage, NOW), true)
  const cached = loadCachedAccountAccess(OWNER_ID, storage, NOW)
  assert.equal(cached?.status, 'resolved')
  assert.equal(cached?.source, 'cache')
  assert.equal(cached?.owner_user_id, OWNER_ID)
  assert.equal(accountAccessHasAppAccess(cached, NOW), true)
  assert.deepEqual(JSON.parse(storage.getItem(`apex.cache.v2.${OWNER_ID}`) ?? '{}'), {
    profile: { user_id: OTHER_OWNER_ID },
  })
  assert.equal(loadCachedAccountAccess(OTHER_OWNER_ID, storage, NOW), null)

  clearCachedAccountAccess(OWNER_ID, storage)
  assert.equal(loadCachedAccountAccess(OWNER_ID, storage, NOW), null)
})

test('individual grants cache until their explicit expiry, including permanent protected owners', () => {
  const storage = new MemoryStorage()
  const oldPermanentGrant = resolveAccountAccess([
    envelope({ expires_at: null, server_now: '2020-01-01T00:00:00Z' }),
  ], OWNER_ID, 'server', '2020-01-01T00:00:01Z')

  assert.equal(saveCachedAccountAccess(oldPermanentGrant, OWNER_ID, storage, Date.parse('2020-01-01T00:00:01Z')), true)
  assert.equal(
    accountAccessHasAppAccess(loadCachedAccountAccess(OWNER_ID, storage, Date.parse('2035-01-01T00:00:00Z')), Date.parse('2035-01-01T00:00:00Z')),
    true,
  )

  const expiring = resolveAccountAccess([
    envelope({ expires_at: '2026-09-02T00:00:00Z' }),
  ], OWNER_ID, 'server', '2026-09-01T12:00:00Z')
  assert.equal(saveCachedAccountAccess(expiring, OWNER_ID, storage, NOW), true)
  assert.equal(loadCachedAccountAccess(OWNER_ID, storage, Date.parse('2026-09-01T23:59:59Z'))?.status, 'resolved')
  assert.equal(loadCachedAccountAccess(OWNER_ID, storage, Date.parse('2026-09-02T00:00:00Z')), null)
})

test('a failed cache replacement cannot leave an older broader grant behind', () => {
  const storage = new MemoryStorage()
  const permanent = resolveAccountAccess([
    envelope({ expires_at: null }),
  ], OWNER_ID, 'server', '2026-09-01T12:00:01Z')
  const expiring = resolveAccountAccess([
    envelope({ expires_at: '2026-09-02T00:00:00Z' }),
  ], OWNER_ID, 'server', '2026-09-01T12:00:02Z')

  assert.equal(saveCachedAccountAccess(permanent, OWNER_ID, storage, NOW), true)
  storage.failWrites = true
  assert.equal(saveCachedAccountAccess(expiring, OWNER_ID, storage, NOW), false)
  assert.equal(loadCachedAccountAccess(OWNER_ID, storage, NOW), null)
})

test('sponsored-only cache expires 24 hours after server_now and malformed or mismatched records fail closed', () => {
  const storage = new MemoryStorage()
  const sponsored = resolveAccountAccess([
    envelope({ state: 'locked', expires_at: null, sponsored_seat_active: true }),
  ], OWNER_ID, 'server', '2026-09-01T12:00:00Z')

  assert.equal(saveCachedAccountAccess(sponsored, OWNER_ID, storage, NOW), true)
  assert.equal(loadCachedAccountAccess(OWNER_ID, storage, Date.parse('2026-09-02T11:59:59Z'))?.status, 'resolved')
  assert.equal(loadCachedAccountAccess(OWNER_ID, storage, Date.parse('2026-09-02T12:00:00Z')), null)

  assert.equal(saveCachedAccountAccess(sponsored, OWNER_ID, storage, NOW), true)
  const accessKey = [...storage.values.keys()].find((key) => key.includes('account-access'))
  assert.ok(accessKey)
  const record = JSON.parse(storage.getItem(accessKey) ?? '{}')
  storage.setItem(accessKey, JSON.stringify({ ...record, owner_user_id: OTHER_OWNER_ID }))
  assert.equal(loadCachedAccountAccess(OWNER_ID, storage, NOW), null)

  storage.setItem(accessKey, JSON.stringify({ ...record, cached_at: 'not-a-date' }))
  assert.equal(loadCachedAccountAccess(OWNER_ID, storage, NOW), null)
})

test('the cache persists the latest clock observation so a later rollback cannot extend bounded access', () => {
  const storage = new MemoryStorage()
  const bounded = resolveAccountAccess([
    envelope({ expires_at: '2026-09-02T12:00:00Z' }),
  ], OWNER_ID, 'server', '2026-08-01T12:00:00Z')

  assert.ok(bounded)
  assert.equal(saveCachedAccountAccess(bounded, OWNER_ID, storage, Date.parse('2026-08-01T22:00:00Z')), true)
  assert.equal(loadCachedAccountAccess(OWNER_ID, storage, Date.parse('2026-08-01T17:00:00Z')), null)
})

test('minimum-build evidence is validated live and recalculated when a different web build loads the cache', () => {
  assert.equal(
    resolveAccountAccess([
      envelope({ minimum_build: 20, update_required: false }),
    ], OWNER_ID, 'server', '2026-09-01T12:00:00Z'),
    null,
    'a live response cannot contradict the build sent to the RPC',
  )

  const storage = new MemoryStorage()
  const issuedToBuild20 = resolveAccountAccess(
    [envelope({ minimum_build: 20, update_required: false })],
    OWNER_ID,
    'server',
    '2026-09-01T12:00:00Z',
    '2026-09-01T12:00:00Z',
    null,
    20,
  )
  assert.ok(issuedToBuild20)
  assert.equal(saveCachedAccountAccess(issuedToBuild20, OWNER_ID, storage, NOW), true)

  const olderBuild = loadCachedAccountAccess(OWNER_ID, storage, NOW, 19)
  assert.equal(olderBuild?.status, 'resolved')
  assert.equal(olderBuild?.envelope.update_required, true)
  assert.equal(accountAccessHasAppAccess(olderBuild, NOW), false)

  const currentBuild = loadCachedAccountAccess(OWNER_ID, storage, NOW, 20)
  assert.equal(currentBuild?.status, 'resolved')
  assert.equal(currentBuild?.envelope.update_required, false)
  assert.equal(accountAccessHasAppAccess(currentBuild, NOW), true)
})

test('coach restrictions trust sponsored access from the access envelope, never coach-context rows', () => {
  const activeContext = {
    ...EMPTY_COACH_ACCOUNT_CONTEXT,
    sponsorship: {
      relationship_id: '33333333-3333-4333-8333-333333333333',
      coach_display_name: 'Coach',
      relationship_status: 'active',
      seat_state: 'active',
      offered_scopes: [],
      consented_scopes: [],
      grace_ends_at: null,
    },
    capabilities: { coach_workspace: false, sponsored_client: true },
  } satisfies CoachAccountContext
  const contextOnly = resolveAccountAccess([
    envelope({ state: 'locked', expires_at: null, sponsored_seat_active: false }),
  ], OWNER_ID, 'server', '2026-09-01T12:00:00Z')
  const envelopeSponsored = resolveAccountAccess([
    envelope({ state: 'locked', expires_at: null, sponsored_seat_active: true }),
  ], OWNER_ID, 'server', '2026-09-01T12:00:00Z')

  assert.ok(contextOnly)
  assert.ok(envelopeSponsored)
  assert.equal(clientPolicyForAccount(contextOnly, activeContext, NOW).can_use_sponsored_app, false)
  assert.equal(clientPolicyForAccount(envelopeSponsored, EMPTY_COACH_ACCOUNT_CONTEXT, NOW).can_use_sponsored_app, true)
  assert.equal(clientPolicyForAccount(envelopeSponsored, EMPTY_COACH_ACCOUNT_CONTEXT, NOW).can_create_custom_workouts, false)
})

test('coach grace remains read-only policy context without becoming sponsored app access', () => {
  const graceContext = {
    ...EMPTY_COACH_ACCOUNT_CONTEXT,
    sponsorship: {
      relationship_id: '33333333-3333-4333-8333-333333333333',
      coach_display_name: 'Coach',
      relationship_status: 'grace',
      seat_state: 'grace',
      offered_scopes: [],
      consented_scopes: [],
      grace_ends_at: '2026-09-08T00:00:00Z',
    },
    capabilities: { coach_workspace: false, sponsored_client: true },
  } satisfies CoachAccountContext
  const individual = resolveAccountAccess([envelope()], OWNER_ID, 'server', '2026-09-01T12:00:00Z')

  assert.ok(individual)
  const policy = clientPolicyForAccount(individual, graceContext, NOW)
  assert.equal(policy.can_use_sponsored_app, false)
  assert.equal(policy.coach_plan_read_only, true)
})

test('coach grace ends at its server-anchored deadline and participates in deadline scheduling', () => {
  const access = resolveAccountAccess([
    envelope({ state: 'locked', expires_at: null }),
  ], OWNER_ID, 'server', '2026-08-01T12:00:00Z')
  const context = {
    ...EMPTY_COACH_ACCOUNT_CONTEXT,
    sponsorship: {
      relationship_id: '33333333-3333-4333-8333-333333333333',
      coach_display_name: 'Coach',
      relationship_status: 'grace',
      seat_state: 'grace',
      offered_scopes: [],
      consented_scopes: [],
      grace_ends_at: '2026-09-01T18:00:00Z',
    },
  } satisfies CoachAccountContext

  assert.ok(access)
  assert.equal(
    accountAccessNextChangeAt(access, Date.parse('2026-08-01T12:00:00Z'), context),
    Date.parse('2026-08-01T18:00:00Z'),
  )
  assert.equal(
    clientPolicyForAccount(access, context, Date.parse('2026-08-01T17:59:59Z')).coach_plan_read_only,
    true,
  )
  assert.equal(
    clientPolicyForAccount(access, context, Date.parse('2026-08-01T18:00:00Z')).coach_plan_read_only,
    false,
  )
  assert.equal(
    clientPolicyForAccount(access, {
      ...context,
      sponsorship: { ...context.sponsorship, grace_ends_at: null },
    }, Date.parse('2026-08-01T12:00:00Z')).coach_plan_read_only,
    false,
  )
})

test('grace can reach only the read-only coach-plan route without unlocking the app', () => {
  const graceContext = {
    ...EMPTY_COACH_ACCOUNT_CONTEXT,
    sponsorship: {
      relationship_id: '33333333-3333-4333-8333-333333333333',
      coach_display_name: 'Coach',
      relationship_status: 'grace',
      seat_state: 'grace',
      offered_scopes: [],
      consented_scopes: [],
      grace_ends_at: '2026-09-08T00:00:00Z',
    },
  } satisfies CoachAccountContext
  const locked = resolveAccountAccess([
    envelope({ state: 'locked', expires_at: null }),
  ], OWNER_ID, 'server', '2026-09-01T12:00:00Z')

  assert.ok(locked)
  assert.equal(accountAccessHasAppAccess(locked, NOW), false)
  assert.equal(accountAccessAllowsRoute(locked, graceContext, '/coach-plan', NOW), true)
  assert.equal(accountAccessAllowsRoute(locked, graceContext, '/coach/invite/token-123', NOW), false)
  assert.equal(accountAccessAllowsRoute(locked, graceContext, '/', NOW), false)
  assert.equal(accountAccessAllowsRoute(locked, graceContext, '/custom-workouts', NOW), false)
})

test('a locked authenticated account can use only an exact invitation bootstrap route', () => {
  const locked = resolveAccountAccess([
    envelope({ state: 'locked', expires_at: null }),
  ], OWNER_ID, 'server', '2026-09-01T12:00:00Z')

  assert.ok(locked)
  assert.equal(accountAccessAllowsRoute(locked, EMPTY_COACH_ACCOUNT_CONTEXT, '/coach/invite/token-123', NOW), true)
  assert.equal(accountAccessAllowsRoute(locked, EMPTY_COACH_ACCOUNT_CONTEXT, '/COACH/INVITE/token-123/', NOW), true)
  assert.equal(accountAccessAllowsRoute(locked, EMPTY_COACH_ACCOUNT_CONTEXT, '/coach/invite', NOW), false)
  assert.equal(accountAccessAllowsRoute(locked, EMPTY_COACH_ACCOUNT_CONTEXT, '/coach/invite/token-123/extra', NOW), false)
  assert.equal(accountAccessAllowsRoute(locked, EMPTY_COACH_ACCOUNT_CONTEXT, '/coach-plan/extra', NOW), false)
  assert.equal(
    accountAccessAllowsRoute(
      resolveAccountAccess([envelope({ minimum_build: 1, update_required: true })], OWNER_ID, 'server', '2026-09-01T12:00:00Z')!,
      EMPTY_COACH_ACCOUNT_CONTEXT,
      '/coach/invite/token-123',
      NOW,
    ),
    false,
    'a minimum-build requirement must take precedence over invitation bootstrap',
  )
})

test('direct workout player and logger routes preserve individual access but constrain sponsored-only access', () => {
  const sponsored = resolveAccountAccess([
    envelope({ state: 'locked', expires_at: null, sponsored_seat_active: true }),
  ], OWNER_ID, 'server', '2026-09-01T12:00:00Z')
  const individual = resolveAccountAccess([
    envelope({ sponsored_seat_active: false }),
  ], OWNER_ID, 'server', '2026-09-01T12:00:00Z')

  assert.ok(sponsored)
  assert.ok(individual)
  assert.equal(accountAccessAllowsRoute(sponsored, EMPTY_COACH_ACCOUNT_CONTEXT, '/player/coach/2026-09-01', NOW), true)
  assert.equal(accountAccessAllowsRoute(sponsored, EMPTY_COACH_ACCOUNT_CONTEXT, '/log/coach/2026-09-01', NOW), true)
  assert.equal(accountAccessAllowsRoute(sponsored, EMPTY_COACH_ACCOUNT_CONTEXT, '/player/custom/2026-09-01', NOW), false)
  assert.equal(accountAccessAllowsRoute(sponsored, EMPTY_COACH_ACCOUNT_CONTEXT, '/log/main/2026-09-01', NOW), false)
  assert.equal(accountAccessAllowsRoute(sponsored, EMPTY_COACH_ACCOUNT_CONTEXT, '/PLAYER/custom/2026-09-01', NOW), false)
  assert.equal(accountAccessAllowsRoute(sponsored, EMPTY_COACH_ACCOUNT_CONTEXT, '/player/custom/2026-09-01/', NOW), false)
  assert.equal(accountAccessAllowsRoute(sponsored, EMPTY_COACH_ACCOUNT_CONTEXT, '/%70layer/custom/2026-09-01', NOW), false)
  assert.equal(accountAccessAllowsRoute(sponsored, EMPTY_COACH_ACCOUNT_CONTEXT, '/play%65r/custom/2026-09-01', NOW), false)
  assert.equal(accountAccessAllowsRoute(sponsored, EMPTY_COACH_ACCOUNT_CONTEXT, '/%70layer/coach/2026-09-01', NOW), true)
  assert.equal(accountAccessAllowsRoute(sponsored, EMPTY_COACH_ACCOUNT_CONTEXT, '/player/%63ustom/2026-09-01', NOW), false)
  assert.equal(accountAccessAllowsRoute(sponsored, EMPTY_COACH_ACCOUNT_CONTEXT, '/player/%/2026-09-01', NOW), false)
  assert.equal(accountAccessAllowsRoute(sponsored, EMPTY_COACH_ACCOUNT_CONTEXT, '/LOG/coach/2026-09-01/', NOW), true)
  assert.equal(accountAccessAllowsRoute(individual, EMPTY_COACH_ACCOUNT_CONTEXT, '/player/custom/2026-09-01', NOW), true)
  assert.equal(accountAccessAllowsRoute(individual, EMPTY_COACH_ACCOUNT_CONTEXT, '/log/main/2026-09-01', NOW), true)
})

test('web access is requested through the authenticated get_my_app_access contract', async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const access = await fetchMyAppAccess(async (name, args) => {
    calls.push({ name, args })
    return { data: [envelope()], error: null }
  }, OWNER_ID, 17, NOW)

  assert.deepEqual(calls, [{
    name: 'get_my_app_access',
    args: { p_platform: 'web', p_build: 17 },
  }])
  assert.equal(access.status, 'resolved')
  assert.equal(access.owner_user_id, OWNER_ID)
  assert.equal(access.source, 'server')

  await assert.rejects(
    fetchMyAppAccess(async () => ({ data: [envelope({ user_id: OTHER_OWNER_ID })], error: null }), OWNER_ID, 17, NOW),
    (error) => error instanceof AccountAccessProtocolError,
  )
  await assert.rejects(
    fetchMyAppAccess(async () => ({ data: envelope(), error: null }), OWNER_ID, 17, NOW),
    (error) => error instanceof AccountAccessProtocolError,
  )
  await assert.rejects(
    fetchMyAppAccess(async () => ({ data: null, error: { message: 'offline' } }), OWNER_ID, 17, NOW),
    (error) => error instanceof Error
      && !(error instanceof AccountAccessProtocolError)
      && /offline/i.test(error.message),
  )
})

test('a regressed server observation fails closed even when it carries a newer denial', () => {
  const current = resolveAccountAccess([
    envelope({ server_now: '2026-09-01T13:00:00Z' }),
  ], OWNER_ID, 'server', '2026-09-01T13:00:00Z')
  const staleRevocation = resolveAccountAccess([
    envelope({ state: 'revoked', server_now: '2026-09-01T12:00:00Z' }),
  ], OWNER_ID, 'server', '2026-09-01T13:00:01Z')
  const currentRevocation = resolveAccountAccess([
    envelope({ state: 'revoked', server_now: '2026-09-01T14:00:00Z' }),
  ], OWNER_ID, 'server', '2026-09-01T14:00:00Z')

  assert.ok(current)
  assert.ok(staleRevocation)
  assert.ok(currentRevocation)
  assert.throws(
    () => validatedAccountAccessProgression(current, staleRevocation),
    (error) => error instanceof AccountAccessProtocolError,
  )
  assert.equal(validatedAccountAccessProgression(current, currentRevocation), currentRevocation)
})

test('transient refresh failure preserves a same-owner resolved answer without granting from another owner', () => {
  const valid = resolveAccountAccess([envelope()], OWNER_ID, 'cache', '2026-09-01T11:00:00Z')
  const expired = resolveAccountAccess([
    envelope({ expires_at: '2026-09-01T11:59:59Z' }),
  ], OWNER_ID, 'cache', '2026-09-01T11:00:00Z')
  const updateRequired = resolveAccountAccess([
    envelope({ minimum_build: 1, update_required: true }),
  ], OWNER_ID, 'server', '2026-09-01T11:00:00Z')

  const preserved = accountAccessAfterFailure(valid, OWNER_ID, 'offline', NOW)
  assert.notEqual(preserved, valid, 'React must receive a new resolution object to re-evaluate elapsed access')
  assert.ok(preserved.status === 'resolved')
  assert.equal(preserved.envelope, valid.envelope)
  assert.equal(preserved.clock_observed_at, '2026-09-01T12:00:00.000Z')
  assert.equal(valid.clock_observed_at, '2026-09-01T11:00:00Z')
  assert.equal(accountAccessAfterFailure(valid, OTHER_OWNER_ID, 'offline', NOW).status, 'failed')
  assert.notEqual(accountAccessAfterFailure(expired, OWNER_ID, 'offline', NOW), expired)
  assert.deepEqual(accountAccessAfterFailure(updateRequired, OWNER_ID, 'offline', NOW), updateRequired)
  assert.equal(
    accountAccessAllowsRoute(
      accountAccessAfterFailure(updateRequired, OWNER_ID, 'offline', NOW),
      EMPTY_COACH_ACCOUNT_CONTEXT,
      '/coach/invite/token-123',
      NOW,
    ),
    false,
  )
  assert.equal(accountAccessAfterFailure(pendingAccountAccess(OWNER_ID), OWNER_ID, 'offline', NOW).status, 'failed')
})

test('relationship mutations invalidate sponsored evidence without discarding independent access', () => {
  const sponsoredOnly = resolveAccountAccess([
    envelope({ state: 'locked', expires_at: null, sponsored_seat_active: true }),
  ], OWNER_ID, 'server', '2026-09-01T12:00:00Z')
  const individualAndSponsored = resolveAccountAccess([
    envelope({ sponsored_seat_active: true }),
  ], OWNER_ID, 'server', '2026-09-01T12:00:00Z')

  assert.ok(sponsoredOnly)
  assert.ok(individualAndSponsored)
  assert.equal(
    accountAccessAfterRelationshipMutation(sponsoredOnly, OWNER_ID, 'rechecking', NOW).status,
    'failed',
  )
  const individual = accountAccessAfterRelationshipMutation(
    individualAndSponsored,
    OWNER_ID,
    'rechecking',
    NOW,
  )
  assert.ok(individual.status === 'resolved')
  assert.equal(individual.envelope.sponsored_seat_active, false)
  assert.equal(accountAccessHasIndividualAccess(individual, NOW), true)
  assert.equal(accountAccessAfterRelationshipMutation(individualAndSponsored, OTHER_OWNER_ID, 'rechecking', NOW).status, 'failed')
})

test('local demo access is an explicit resolved owner-bound grant', () => {
  const local = localAccountAccess(OWNER_ID, NOW)

  assert.equal(local.status, 'resolved')
  assert.equal(local.source, 'local')
  assert.equal(local.owner_user_id, OWNER_ID)
  assert.equal(accountAccessHasAppAccess(local, NOW), true)
  assert.equal(local.envelope?.web_beta_codes_enabled, false)
})

test('the web recovery surface offers retry and safe sign-out without pretending to sell access', async () => {
  const [app, invitation, recovery, store, coachPlan] = await Promise.all([
    readFile(new URL('../src/App.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/pages/CoachInvitation.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/components/AccessRecovery.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/store/AppStore.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/pages/CoachPlan.tsx', import.meta.url), 'utf8'),
  ])

  assert.match(app, /accountAccessAllowsRoute/)
  assert.match(app, /appAccess\.status === 'pending'/)
  assert.match(app, /<AccessRecovery/)
  assert.match(app, /const gracePlanOnly = clientPolicyForAccount\(appAccess, coachContext\)\.coach_plan_read_only/)
  assert.match(app, /const appUnlocked = accountAccessHasAppAccess\(appAccess\)/)
  assert.match(app, /if \(gracePlanOnly \|\| appUnlocked\) return <Navigate to="\/coach-plan" replace \/>/)
  assert.match(app, /settingsOnly \? <AccountFeature capability="can_rebuild_fitness_plan"><WorkoutSection slug="transition"/)
  assert.match(store, /accountAccessNextChangeAt\(appAccess, Date\.now\(\), coachContext\)/)
  assert.match(store, /window\.setTimeout/)
  assert.doesNotMatch(store, /setInterval/)
  assert.match(store, /if \(reachesDeadline\)[\s\S]*refreshAppAccess\(\)[\s\S]*refreshCoachContext\(\)/)
  assert.match(store, /const adoptSession = useCallback[\s\S]*checkpointAccountAccess\(\)/)
  assert.match(store, /const coachContextFetchGeneration = useRef\(0\)/)
  assert.match(store, /const refreshCoachContext = useCallback[\s\S]*\+\+coachContextFetchGeneration\.current[\s\S]*generation !== coachContextFetchGeneration\.current/)
  assert.match(store, /const on = \(\): void => \{[\s\S]*refreshAppAccess\(\)[\s\S]*refreshCoachContext\(\)/)
  assert.match(store, /error instanceof AccountAccessProtocolError[\s\S]*failedAccountAccess/)
  assert.match(store, /error instanceof AccountAccessProtocolError \|\| !accountAccessHasAppAccess\(failed\)/)
  assert.match(store, /const previousAccess = appAccessRef\.current[\s\S]*validatedAccountAccessProgression\(previousAccess, next\)/)
  assert.match(store, /type RefreshAppAccessOptions = \{ failClosed\?: boolean \}/)
  assert.match(store, /if \(options\?\.failClosed\)[\s\S]*accountAccessAfterRelationshipMutation/)
  assert.match(store, /const nextAccess =[\s\S]*if \(accountAccessHasAppAccess\(nextAccess\)\) \{[\s\S]*hydratePrivateState\(nextSession\)[\s\S]*clearPrivateState\(\)/)
  assert.match(store, /const fetchAll = useCallback[\s\S]*if \(!session \|\| !accountAccessHasAppAccess\(appAccessRef\.current\)\) return/)
  assert.match(store, /accountAccessHasAppAccess\(appAccess\)[\s\S]*void fetchAll\(\)/)
  assert.match(store, /if \(!sb \|\| !session \|\| !accountAccessHasAppAccess\(appAccess\)\) return/)
  assert.match(app, /if \(!accountAccessHasAppAccess\(appAccess\)\) return <>{children}<\/>/)
  assert.match(invitation, /refreshAppAccess/)
  assert.match(invitation, /coachAPI\.acceptInvitation[\s\S]*refreshAppAccess\(\{ failClosed: true \}\)/)
  assert.match(invitation, /disabled=\{accepting \|\| \(scopes\.length === 0 && !visualProgress\)\}/)
  assert.match(coachPlan, /clientPolicyForAccount\(appAccess, coachContext\)/)
  assert.match(coachPlan, /refreshAppAccess\(\{ failClosed: true \}\)/)
  assert.match(coachPlan, /\.then\(\(ended\) => \{ if \(ended\) navigate/)
  assert.match(recovery, /Check access again/)
  assert.match(recovery, /signOut/)
  assert.match(recovery, /refreshAppAccess/)
  assert.match(recovery, /Promise\.allSettled\(\[\s*refreshAppAccess\(\),\s*refreshCoachContext\(\)/)
  assert.match(recovery, /accountAccessRecoveryReason\(appAccess\)/)
  assert.match(recovery, /window\.location\.reload\(\)/)
  assert.match(recovery, /Purchases are not available in this web preview\./)
  assert.doesNotMatch(recovery, /(?:CHF|displayPrice|purchase\s*\(|redeemBeta|beta code)/i)
  assert.match(
    store,
    /const signOut = useCallback\(async \(\) => \{[\s\S]*?let remoteSignOut[\s\S]*?try \{[\s\S]*?remoteSignOut = supabase\.auth\.signOut\(\)[\s\S]*?\} finally \{[\s\S]*?adoptSession\(null\)[\s\S]*?\}[\s\S]*?await remoteSignOut/,
    'local account state must clear before waiting for a network sign-out',
  )
})

test('entitlement recovery copy is authored in every offered web language', () => {
  assert.deepEqual(LANGUAGE_OPTIONS.map(({ value }) => value), ['en', 'th', 'ro'])
  const copy = [
    'Access needs attention',
    'APEX needs an update',
    'Access was revoked',
    'Access has expired',
    'Access is not active',
    'This APEX web version is older than the minimum version required for your account.',
    'Access for this account has been revoked.',
    'Access for this account has expired.',
    'This account does not currently have access to APEX.',
    'Reload the page to check for the required web version. If this message remains, that version is not available here yet.',
    'Check access again if this changed recently, or sign out safely.',
    'Check access again if access was renewed, or sign out safely.',
    'Check access again if your account was just updated, or sign out safely.',
    'Reload APEX',
    'Check access again',
    'Purchases are not available in this web preview.',
    'Access is still unavailable. Try again when online, or sign out safely.',
  ]
  for (const key of copy) {
    assert.ok(UI_TRANSLATIONS[key]?.ro.trim(), `missing Romanian web recovery copy: ${key}`)
    assert.ok(UI_TRANSLATIONS[key]?.th.trim(), `missing Thai web recovery copy: ${key}`)
  }
})
