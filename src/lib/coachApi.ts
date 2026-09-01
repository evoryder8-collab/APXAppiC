import type { SupabaseClient } from '@supabase/supabase-js'
import { createSessionBoundSupabase, supabase } from './supabase'
import {
  EMPTY_COACH_ACCOUNT_CONTEXT,
  type CoachAccountContext,
  type CoachClientOverview,
  type CoachConsentScope,
  type CoachInvitationReceipt,
  type CoachInvitationPreview,
  type CoachPlanDraft,
  type CoachPlanVersionReceipt,
  type CoachRosterEntry,
} from './coachPlatform'

export class CoachAPIError extends Error {}

async function sessionClient(): Promise<SupabaseClient> {
  if (!supabase) throw new CoachAPIError('Coach tools need an online signed-in account.')
  const { data: { session }, error } = await supabase.auth.getSession()
  if (error || !session) throw new CoachAPIError('Sign in again to use coach tools.')
  const client = createSessionBoundSupabase(session.access_token)
  if (!client) throw new CoachAPIError('Coach tools are temporarily unavailable.')
  return client
}

async function rpc<T>(functionName: string, params?: Record<string, unknown>): Promise<T> {
  const client = await sessionClient()
  const { data, error } = await client.rpc(functionName, params)
  if (error) throw new CoachAPIError(error.message)
  return data as T
}

export async function fetchCoachAccountContext(
  client: SupabaseClient,
): Promise<{ context: CoachAccountContext; error: Error | null }> {
  const { data, error } = await client.rpc('coach_get_my_context')
  if (error) return { context: EMPTY_COACH_ACCOUNT_CONTEXT, error: new CoachAPIError(error.message) }
  return { context: (data ?? EMPTY_COACH_ACCOUNT_CONTEXT) as CoachAccountContext, error: null }
}

export const coachAPI = {
  previewInvitation: (token: string) =>
    rpc<CoachInvitationPreview>('coach_preview_invitation', { p_token: token }),
  roster: (query = '') => rpc<CoachRosterEntry[]>('coach_get_roster', { p_query: query || null }),
  createInvitation: (email: string, scopes: CoachConsentScope[], visualProgressRequested: boolean) =>
    rpc<CoachInvitationReceipt>('coach_create_invitation', {
      p_email: email,
      p_scopes: scopes,
      p_visual_progress_requested: visualProgressRequested,
    }),
  acceptInvitation: (token: string, scopes: CoachConsentScope[], visualProgressConsent: boolean) =>
    rpc<CoachAccountContext>('coach_accept_invitation', {
      p_token: token,
      p_scopes: scopes,
      p_visual_progress_consent: visualProgressConsent,
    }),
  clientOverview: (relationshipID: string) =>
    rpc<CoachClientOverview>('coach_get_client_overview', { p_relationship_id: relationshipID }),
  saveDraft: (relationshipID: string, plan: CoachPlanDraft, expectedVersion: number) =>
    rpc<CoachPlanVersionReceipt>('coach_save_plan_draft', {
      p_relationship_id: relationshipID,
      p_plan: plan,
      p_expected_version: expectedVersion,
    }),
  publishPlan: (relationshipID: string, plan: CoachPlanDraft, expectedVersion: number) =>
    rpc<CoachPlanVersionReceipt>('coach_publish_plan', {
      p_relationship_id: relationshipID,
      p_plan: plan,
      p_expected_version: expectedVersion,
    }),
  acknowledgePlan: (planVersionID: string) =>
    rpc<boolean>('client_acknowledge_coach_plan', { p_plan_version_id: planVersionID }),
  activatePlan: (planVersionID: string) =>
    rpc<{ plan_version_id: string; program_id: string; installed_day_ids: string[] }>(
      'client_activate_coach_plan',
      { p_plan_version_id: planVersionID },
    ),
  updateScopes: (
    relationshipID: string,
    scopes: CoachConsentScope[],
    visualProgressConsent: boolean,
  ) => rpc<CoachAccountContext>('client_update_coach_scopes', {
    p_relationship_id: relationshipID,
    p_scopes: scopes,
    p_visual_progress_consent: visualProgressConsent,
  }),
  endRelationship: (relationshipID: string) =>
    rpc<boolean>('end_coach_relationship', { p_relationship_id: relationshipID }),
}
