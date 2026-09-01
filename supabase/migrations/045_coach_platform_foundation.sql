-- Server-authoritative coach sponsorship, consent and immutable plan versions.
-- This migration deliberately contains no Coach price or purchasable product.

create extension if not exists pgcrypto;

create table if not exists public.coach_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 2 and 80),
  status text not null default 'development'
    check (status in ('development', 'active', 'suspended')),
  seat_limit integer not null default 10 check (seat_limit between 1 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.coach_invitations (
  id uuid primary key default gen_random_uuid(),
  coach_user_id uuid not null references public.coach_profiles(user_id) on delete cascade,
  invitee_email text not null check (char_length(invitee_email) between 3 and 320),
  token_hash text not null unique check (char_length(token_hash) = 64),
  requested_scopes text[] not null default array['nutrition', 'workouts', 'avatar']::text[],
  visual_progress_requested boolean not null default false,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'expired', 'revoked')),
  expires_at timestamptz not null,
  accepted_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at),
  check (
    requested_scopes <@ array[
      'nutrition', 'workouts', 'activity', 'hydration', 'supplements',
      'avatar', 'measurements', 'notes', 'recovery', 'visual_progress'
    ]::text[]
  ),
  check (visual_progress_requested or not ('visual_progress' = any(requested_scopes)))
);

create table if not exists public.coach_relationships (
  id uuid primary key default gen_random_uuid(),
  coach_user_id uuid not null references public.coach_profiles(user_id) on delete restrict,
  client_user_id uuid not null references auth.users(id) on delete restrict,
  invitation_id uuid references public.coach_invitations(id) on delete set null,
  status text not null default 'active'
    check (status in ('invited', 'active', 'grace', 'ended')),
  seat_state text not null default 'active'
    check (seat_state in ('pending', 'active', 'grace', 'released')),
  offered_scopes text[] not null default '{}',
  consented_scopes text[] not null default '{}',
  consented_at timestamptz not null default now(),
  visual_progress_consented_at timestamptz,
  grace_ends_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (coach_user_id, client_user_id),
  check (coach_user_id <> client_user_id),
  check (
    offered_scopes <@ array[
      'nutrition', 'workouts', 'activity', 'hydration', 'supplements',
      'avatar', 'measurements', 'notes', 'recovery', 'visual_progress'
    ]::text[]
    and consented_scopes <@ offered_scopes
  ),
  check (
    ('visual_progress' = any(consented_scopes)) = (visual_progress_consented_at is not null)
  )
);

create unique index if not exists coach_relationships_one_live_coach_per_client
  on public.coach_relationships (client_user_id)
  where status in ('active', 'grace');

create table if not exists public.coach_plan_versions (
  id uuid primary key default gen_random_uuid(),
  relationship_id uuid not null references public.coach_relationships(id) on delete restrict,
  coach_user_id uuid not null references public.coach_profiles(user_id) on delete restrict,
  version integer not null check (version between 1 and 10000),
  status text not null check (status in ('draft', 'published', 'superseded')),
  title text not null default '',
  objective text not null default '',
  coach_note text not null default '',
  review_date date,
  checklist jsonb not null default '{}'::jsonb,
  plan jsonb not null,
  created_at timestamptz not null default now(),
  published_at timestamptz,
  unique (relationship_id, version),
  check (octet_length(plan::text) <= 65536),
  check (octet_length(checklist::text) <= 4096),
  check ((status = 'published' and published_at is not null) or status <> 'published')
);

create unique index if not exists coach_plan_versions_one_current_published
  on public.coach_plan_versions (relationship_id)
  where status = 'published';

create table if not exists public.coach_plan_acknowledgements (
  id uuid primary key default gen_random_uuid(),
  plan_version_id uuid not null references public.coach_plan_versions(id) on delete restrict,
  relationship_id uuid not null references public.coach_relationships(id) on delete restrict,
  client_user_id uuid not null references auth.users(id) on delete restrict,
  acknowledged_at timestamptz,
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  unique (plan_version_id, client_user_id)
);

alter table public.program_days
  add column if not exists is_active boolean not null default true,
  add column if not exists coach_plan_version_id uuid references public.coach_plan_versions(id) on delete restrict;

create index if not exists program_days_active_coach_version_idx
  on public.program_days (user_id, program_id, coach_plan_version_id)
  where is_active;

create table if not exists public.coach_plan_installations (
  id uuid primary key default gen_random_uuid(),
  plan_version_id uuid not null references public.coach_plan_versions(id) on delete restrict,
  relationship_id uuid not null references public.coach_relationships(id) on delete restrict,
  client_user_id uuid not null references auth.users(id) on delete restrict,
  program_id uuid not null references public.programs(id) on delete restrict,
  installed_day_ids uuid[] not null default '{}',
  activated_at timestamptz not null default now(),
  unique (plan_version_id, client_user_id)
);

create table if not exists public.coach_audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  relationship_id uuid references public.coach_relationships(id) on delete restrict,
  event_type text not null check (char_length(event_type) between 3 and 80),
  metadata jsonb not null default '{}'::jsonb check (octet_length(metadata::text) <= 16384),
  created_at timestamptz not null default now()
);

create index if not exists coach_invitations_coach_status_idx
  on public.coach_invitations (coach_user_id, status, created_at desc);
create index if not exists coach_relationships_coach_status_idx
  on public.coach_relationships (coach_user_id, status, updated_at desc);
create index if not exists coach_plan_versions_relationship_version_idx
  on public.coach_plan_versions (relationship_id, version desc);
create index if not exists coach_audit_relationship_time_idx
  on public.coach_audit_log (relationship_id, created_at desc);

alter table public.coach_profiles enable row level security;
alter table public.coach_invitations enable row level security;
alter table public.coach_relationships enable row level security;
alter table public.coach_plan_versions enable row level security;
alter table public.coach_plan_acknowledgements enable row level security;
alter table public.coach_plan_installations enable row level security;
alter table public.coach_audit_log enable row level security;

-- No generic table policies are created. Every cross-account read or write is
-- mediated by a bounded RPC below, and ordinary owner tables retain their RLS.
revoke all on table public.coach_profiles from public, anon, authenticated;
revoke all on table public.coach_invitations from public, anon, authenticated;
revoke all on table public.coach_relationships from public, anon, authenticated;
revoke all on table public.coach_plan_versions from public, anon, authenticated;
revoke all on table public.coach_plan_acknowledgements from public, anon, authenticated;
revoke all on table public.coach_plan_installations from public, anon, authenticated;
revoke all on table public.coach_audit_log from public, anon, authenticated;

create or replace function public.prevent_coach_audit_mutation()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception 'coach audit facts are append only' using errcode = '42501';
end;
$$;

drop trigger if exists coach_audit_append_only on public.coach_audit_log;
create trigger coach_audit_append_only
before update or delete on public.coach_audit_log
for each row execute function public.prevent_coach_audit_mutation();

create or replace function public.coach_authenticated_user_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  return v_user_id;
end;
$$;

create or replace function public.coach_scopes_valid(p_scopes text[])
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select coalesce(p_scopes, '{}'::text[]) <@ array[
    'nutrition', 'workouts', 'activity', 'hydration', 'supplements',
    'avatar', 'measurements', 'notes', 'recovery', 'visual_progress'
  ]::text[];
$$;

create or replace function public.coach_json_has_only_keys(p_value jsonb, p_keys text[])
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select jsonb_typeof(p_value) = 'object'
    and not exists (
      select 1 from jsonb_object_keys(p_value) key where not (key = any(p_keys))
    );
$$;

create or replace function public.coach_json_integer_between(
  p_value jsonb,
  p_key text,
  p_min integer,
  p_max integer
)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select jsonb_typeof(p_value -> p_key) = 'number'
    and (p_value ->> p_key)::numeric = trunc((p_value ->> p_key)::numeric)
    and (p_value ->> p_key)::numeric between p_min and p_max;
$$;

create or replace function public.coach_validate_plan(p_plan jsonb, p_publishing boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_session jsonb;
  v_exercise jsonb;
  v_session_count integer;
  v_exercise_count integer;
  v_ids text[] := '{}';
  v_id text;
  v_group_id text;
  v_group_position jsonb;
  v_movement_id text;
begin
  if p_plan is null or jsonb_typeof(p_plan) <> 'object' then
    raise exception 'plan must be an object' using errcode = '22023';
  end if;
  if octet_length(p_plan::text) > 65536 then
    raise exception 'plan is too large' using errcode = '22023';
  end if;
  if not public.coach_json_has_only_keys(
    p_plan,
    array['title', 'objective', 'coach_note', 'review_date', 'checklist', 'sessions']
  ) then
    raise exception 'plan has unknown fields' using errcode = '22023';
  end if;
  if char_length(coalesce(p_plan ->> 'title', '')) > 80
     or char_length(coalesce(p_plan ->> 'objective', '')) > 240
     or char_length(coalesce(p_plan ->> 'coach_note', '')) > 4000 then
    raise exception 'plan text is too long' using errcode = '22023';
  end if;
  if p_publishing and (
    char_length(btrim(coalesce(p_plan ->> 'title', ''))) < 2
    or char_length(btrim(coalesce(p_plan ->> 'objective', ''))) < 2
  ) then
    raise exception 'published plans require title and objective' using errcode = '22023';
  end if;
  if p_plan ? 'review_date' and p_plan -> 'review_date' <> 'null'::jsonb then
    if coalesce(p_plan ->> 'review_date', '') !~ '^\d{4}-\d{2}-\d{2}$' then
      raise exception 'invalid review date' using errcode = '22023';
    end if;
    begin
      if to_char((p_plan ->> 'review_date')::date, 'YYYY-MM-DD') <> p_plan ->> 'review_date' then
        raise exception 'invalid review date' using errcode = '22023';
      end if;
    exception when others then
      raise exception 'invalid review date' using errcode = '22023';
    end;
  elsif p_publishing then
    raise exception 'published plans require a review date' using errcode = '22023';
  end if;
  if not public.coach_json_has_only_keys(
    coalesce(p_plan -> 'checklist', '{}'::jsonb),
    array['nutrition', 'workouts', 'supplements', 'hydration', 'schedule', 'review_date']
  ) then
    raise exception 'invalid checklist' using errcode = '22023';
  end if;
  if p_publishing and not (
    coalesce((p_plan #>> '{checklist,nutrition}')::boolean, false)
    and coalesce((p_plan #>> '{checklist,workouts}')::boolean, false)
    and coalesce((p_plan #>> '{checklist,supplements}')::boolean, false)
    and coalesce((p_plan #>> '{checklist,hydration}')::boolean, false)
    and coalesce((p_plan #>> '{checklist,schedule}')::boolean, false)
    and coalesce((p_plan #>> '{checklist,review_date}')::boolean, false)
  ) then
    raise exception 'published plan checklist is incomplete' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_plan -> 'sessions', '[]'::jsonb)) <> 'array' then
    raise exception 'sessions must be an array' using errcode = '22023';
  end if;
  v_session_count := jsonb_array_length(coalesce(p_plan -> 'sessions', '[]'::jsonb));
  if v_session_count > 7 or (p_publishing and v_session_count = 0) then
    raise exception 'published plans require one to seven sessions' using errcode = '22023';
  end if;

  for v_session in select value from jsonb_array_elements(coalesce(p_plan -> 'sessions', '[]'::jsonb)) loop
    if not public.coach_json_has_only_keys(
      v_session,
      array['id', 'weekday', 'name', 'session_mode', 'estimated_minutes', 'warmup_note', 'exercises']
    ) then
      raise exception 'session has unknown fields' using errcode = '22023';
    end if;
    v_id := v_session ->> 'id';
    if v_id is null or v_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or v_id = any(v_ids) then
      raise exception 'session identifier is invalid or duplicated' using errcode = '22023';
    end if;
    v_ids := array_append(v_ids, v_id);
    if not public.coach_json_integer_between(v_session, 'weekday', 1, 7)
       or not public.coach_json_integer_between(v_session, 'estimated_minutes', 5, 360)
       or char_length(btrim(coalesce(v_session ->> 'name', ''))) not between 2 and 80
       or coalesce(v_session ->> 'session_mode', '') not in ('guided', 'tracked')
       or char_length(coalesce(v_session ->> 'warmup_note', '')) > 1000 then
      raise exception 'session prescription is invalid' using errcode = '22023';
    end if;
    if jsonb_typeof(coalesce(v_session -> 'exercises', '[]'::jsonb)) <> 'array' then
      raise exception 'exercises must be an array' using errcode = '22023';
    end if;
    v_exercise_count := jsonb_array_length(coalesce(v_session -> 'exercises', '[]'::jsonb));
    if v_exercise_count > 30 or (p_publishing and v_exercise_count = 0) then
      raise exception 'sessions require one to thirty exercises' using errcode = '22023';
    end if;

    for v_exercise in select value from jsonb_array_elements(coalesce(v_session -> 'exercises', '[]'::jsonb)) loop
      if not public.coach_json_has_only_keys(
        v_exercise,
        array[
          'id', 'movement_id', 'name', 'sets', 'target_min', 'target_max', 'unit', 'per_side',
          'rest_seconds', 'tempo_up_seconds', 'tempo_down_seconds', 'tempo_pause_seconds',
          'notes', 'optional', 'group_id', 'group_position'
        ]
      ) then
        raise exception 'exercise has unknown fields' using errcode = '22023';
      end if;
      v_id := v_exercise ->> 'id';
      if v_id is null or v_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         or v_id = any(v_ids) then
        raise exception 'exercise identifier is invalid or duplicated' using errcode = '22023';
      end if;
      v_ids := array_append(v_ids, v_id);
      v_movement_id := v_exercise ->> 'movement_id';
      if v_movement_id is null or not exists (
        select 1 from public.movement_library movement
        where movement.id = v_movement_id
          and movement.review_status in ('internally_reviewed', 'expert_reviewed')
      ) then
        raise exception 'exercise movement is not in the reviewed APEX catalogue' using errcode = '22023';
      end if;
      if char_length(btrim(coalesce(v_exercise ->> 'name', ''))) not between 2 and 120
         or not public.coach_json_integer_between(v_exercise, 'sets', 1, 12)
         or not public.coach_json_integer_between(v_exercise, 'target_min', 1, 600)
         or not public.coach_json_integer_between(v_exercise, 'target_max', 1, 600)
         or (v_exercise ->> 'target_min')::integer > (v_exercise ->> 'target_max')::integer
         or coalesce(v_exercise ->> 'unit', '') not in ('reps', 'seconds', 'minutes', 'metres', 'steps', 'rounds')
         or not public.coach_json_integer_between(v_exercise, 'rest_seconds', 0, 600)
         or jsonb_typeof(v_exercise -> 'per_side') <> 'boolean'
         or jsonb_typeof(v_exercise -> 'optional') <> 'boolean'
         or char_length(coalesce(v_exercise ->> 'notes', '')) > 1000 then
        raise exception 'exercise prescription is invalid' using errcode = '22023';
      end if;
      if jsonb_typeof(v_exercise -> 'tempo_up_seconds') <> 'number'
         or jsonb_typeof(v_exercise -> 'tempo_down_seconds') <> 'number'
         or jsonb_typeof(v_exercise -> 'tempo_pause_seconds') <> 'number'
         or (v_exercise ->> 'tempo_up_seconds')::numeric not between 0 and 30
         or (v_exercise ->> 'tempo_down_seconds')::numeric not between 0 and 30
         or (v_exercise ->> 'tempo_pause_seconds')::numeric not between 0 and 30 then
        raise exception 'exercise tempo is invalid' using errcode = '22023';
      end if;
      v_group_id := nullif(v_exercise ->> 'group_id', '');
      v_group_position := v_exercise -> 'group_position';
      if (v_group_id is null) <> (v_group_position is null or v_group_position = 'null'::jsonb) then
        raise exception 'exercise group is incomplete' using errcode = '22023';
      end if;
      if v_group_id is not null and (
        v_group_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        or not public.coach_json_integer_between(v_exercise, 'group_position', 1, 30)
      ) then
        raise exception 'exercise group is invalid' using errcode = '22023';
      end if;
    end loop;
  end loop;
end;
$$;

create or replace function public.coach_release_expired_grace()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_relationship public.coach_relationships%rowtype;
begin
  for v_relationship in
    select * from public.coach_relationships
    where status = 'grace' and grace_ends_at <= now()
    for update
  loop
    update public.coach_relationships
    set status = 'ended', seat_state = 'released', ended_at = coalesce(ended_at, now()), updated_at = now()
    where id = v_relationship.id;
    insert into public.coach_audit_log(actor_user_id, relationship_id, event_type, metadata)
    values (
      v_relationship.coach_user_id,
      v_relationship.id,
      'grace_released',
      jsonb_build_object('grace_ended_at', v_relationship.grace_ends_at)
    );
  end loop;
end;
$$;

create or replace function public.coach_get_my_context()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := public.coach_authenticated_user_id();
  v_coach jsonb;
  v_sponsorship jsonb;
  v_current_plan jsonb;
  v_relationship_id uuid;
begin
  perform public.coach_release_expired_grace();

  select jsonb_build_object(
    'status', coach.status,
    'display_name', coach.display_name,
    'seat_limit', coach.seat_limit,
    'active_seats', (
      select count(*) from public.coach_relationships relationship
      where relationship.coach_user_id = coach.user_id
        and relationship.seat_state in ('active', 'grace')
    )
  ) into v_coach
  from public.coach_profiles coach
  where coach.user_id = v_user_id and coach.status in ('development', 'active');

  select relationship.id,
    jsonb_build_object(
      'relationship_id', relationship.id,
      'coach_display_name', coach.display_name,
      'relationship_status', relationship.status,
      'seat_state', relationship.seat_state,
      'consented_scopes', to_jsonb(relationship.consented_scopes),
      'grace_ends_at', relationship.grace_ends_at
    )
  into v_relationship_id, v_sponsorship
  from public.coach_relationships relationship
  join public.coach_profiles coach on coach.user_id = relationship.coach_user_id
  where relationship.client_user_id = v_user_id
    and relationship.status in ('active', 'grace')
  order by relationship.updated_at desc
  limit 1;

  if v_relationship_id is not null then
    select jsonb_build_object(
      'id', plan.id,
      'relationship_id', plan.relationship_id,
      'version', plan.version,
      'status', plan.status,
      'title', plan.title,
      'objective', plan.objective,
      'coach_note', plan.coach_note,
      'review_date', plan.review_date,
      'checklist', plan.checklist,
      'plan', plan.plan,
      'published_at', plan.published_at,
      'acknowledged_at', acknowledgement.acknowledged_at,
      'activated_at', acknowledgement.activated_at
    ) into v_current_plan
    from public.coach_plan_versions plan
    left join public.coach_plan_acknowledgements acknowledgement
      on acknowledgement.plan_version_id = plan.id
      and acknowledgement.client_user_id = v_user_id
    where plan.relationship_id = v_relationship_id and plan.status = 'published'
    limit 1;
  end if;

  return jsonb_build_object(
    'coach', v_coach,
    'sponsorship', v_sponsorship,
    'current_plan', v_current_plan,
    'capabilities', jsonb_build_object(
      'coach_workspace', v_coach is not null,
      'sponsored_client', v_sponsorship is not null
    )
  );
end;
$$;

create or replace function public.coach_get_roster(p_query text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_coach_id uuid := public.coach_authenticated_user_id();
  v_today date := current_date;
  v_result jsonb;
begin
  perform public.coach_release_expired_grace();
  if not exists (
    select 1 from public.coach_profiles
    where user_id = v_coach_id and status in ('development', 'active')
  ) then
    raise exception 'coach workspace unavailable' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(item order by sort_attention desc, display_name), '[]'::jsonb)
  into v_result
  from (
    select jsonb_build_object(
      'id', relationship.id,
      'client_user_id', relationship.client_user_id,
      'display_name', coalesce(nullif(btrim(profile.display_name), ''), 'APEX client'),
      'relationship_status', relationship.status,
      'seat_state', relationship.seat_state,
      'consented_scopes', to_jsonb(relationship.consented_scopes),
      'plan_version', plan.version,
      'plan_title', plan.title,
      'review_date', plan.review_date,
      'published_at', plan.published_at,
      'acknowledged_at', acknowledgement.acknowledged_at,
      'activated_at', acknowledgement.activated_at,
      'attention', case
        when relationship.status = 'grace' then jsonb_build_array('seat_grace')
        when plan.id is null then jsonb_build_array('plan_missing')
        else (case when plan.review_date <= v_today + 7 then jsonb_build_array('review_due') else '[]'::jsonb end)
          || (case when acknowledgement.acknowledged_at is null then jsonb_build_array('awaiting_acknowledgement') else '[]'::jsonb end)
      end
    ) item,
    coalesce(nullif(btrim(profile.display_name), ''), 'APEX client') display_name,
    case
      when relationship.status = 'grace' then 3
      when plan.id is null then 2
      when plan.review_date <= v_today + 7 or acknowledgement.acknowledged_at is null then 1
      else 0
    end sort_attention
    from public.coach_relationships relationship
    join public.profile profile on profile.user_id = relationship.client_user_id
    left join public.coach_plan_versions plan
      on plan.relationship_id = relationship.id and plan.status = 'published'
    left join public.coach_plan_acknowledgements acknowledgement
      on acknowledgement.plan_version_id = plan.id
      and acknowledgement.client_user_id = relationship.client_user_id
    where relationship.coach_user_id = v_coach_id
      and relationship.status in ('active', 'grace')
      and (
        nullif(btrim(coalesce(p_query, '')), '') is null
        or profile.display_name ilike '%' || btrim(p_query) || '%'
      )
  ) roster;
  return v_result;
end;
$$;

create or replace function public.coach_create_invitation(
  p_email text,
  p_scopes text[] default array['nutrition', 'workouts', 'avatar']::text[],
  p_visual_progress_requested boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_coach_id uuid := public.coach_authenticated_user_id();
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_scopes text[];
  v_token text := encode(gen_random_bytes(24), 'hex');
  v_invitation public.coach_invitations%rowtype;
  v_seat_limit integer;
  v_occupied integer;
begin
  select seat_limit into v_seat_limit from public.coach_profiles
  where user_id = v_coach_id and status in ('development', 'active') for update;
  if v_seat_limit is null then raise exception 'coach workspace unavailable' using errcode = '42501'; end if;
  if v_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'valid invitee email required' using errcode = '22023';
  end if;
  select coalesce(array_agg(distinct scope order by scope), '{}'::text[])
    into v_scopes from unnest(coalesce(p_scopes, '{}'::text[])) scope;
  if not public.coach_scopes_valid(v_scopes) then
    raise exception 'unknown consent scope' using errcode = '22023';
  end if;
  if 'visual_progress' = any(v_scopes) and not p_visual_progress_requested then
    raise exception 'visual progress requires explicit request' using errcode = '22023';
  end if;
  select count(*) into v_occupied from public.coach_relationships
  where coach_user_id = v_coach_id and seat_state in ('active', 'grace');
  if v_occupied >= v_seat_limit then raise exception 'no sponsored seat available' using errcode = '23514'; end if;

  update public.coach_invitations
  set status = 'revoked', revoked_at = now()
  where coach_user_id = v_coach_id and invitee_email = v_email and status = 'pending';

  insert into public.coach_invitations (
    coach_user_id, invitee_email, token_hash, requested_scopes,
    visual_progress_requested, expires_at
  ) values (
    v_coach_id, v_email, encode(digest(v_token, 'sha256'), 'hex'), v_scopes,
    p_visual_progress_requested, now() + interval '7 days'
  ) returning * into v_invitation;

  insert into public.coach_audit_log(actor_user_id, event_type, metadata)
  values (v_coach_id, 'invitation_created', jsonb_build_object(
    'invitation_id', v_invitation.id,
    'scopes', to_jsonb(v_scopes),
    'visual_progress_requested', p_visual_progress_requested
  ));
  return jsonb_build_object(
    'invitation_id', v_invitation.id,
    'token', v_token,
    'expires_at', v_invitation.expires_at
  );
end;
$$;

create or replace function public.coach_accept_invitation(
  p_token text,
  p_scopes text[] default null,
  p_visual_progress_consent boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_client_id uuid := public.coach_authenticated_user_id();
  v_email text := lower(btrim(coalesce(auth.jwt() ->> 'email', '')));
  v_invitation public.coach_invitations%rowtype;
  v_scopes text[];
  v_relationship public.coach_relationships%rowtype;
  v_seat_limit integer;
  v_occupied integer;
begin
  if coalesce(p_token, '') !~ '^[0-9a-f]{48}$' then
    raise exception 'invitation is invalid' using errcode = '22023';
  end if;
  select * into v_invitation from public.coach_invitations
  where token_hash = encode(digest(p_token, 'sha256'), 'hex') for update;
  if v_invitation.id is null or v_invitation.status <> 'pending' then
    raise exception 'invitation is unavailable' using errcode = '22023';
  end if;
  if v_invitation.expires_at <= now() then
    update public.coach_invitations set status = 'expired' where id = v_invitation.id;
    raise exception 'invitation has expired' using errcode = '22023';
  end if;
  if v_email = '' or v_email <> v_invitation.invitee_email then
    raise exception 'sign in with the invited email address' using errcode = '42501';
  end if;
  if v_client_id = v_invitation.coach_user_id then
    raise exception 'coach cannot accept own invitation' using errcode = '22023';
  end if;
  select coalesce(array_agg(distinct scope order by scope), '{}'::text[])
  into v_scopes
  from unnest(coalesce(p_scopes, v_invitation.requested_scopes)) scope
  where scope = any(v_invitation.requested_scopes)
    and (scope <> 'visual_progress' or p_visual_progress_consent);
  if not public.coach_scopes_valid(v_scopes) then raise exception 'unknown consent scope' using errcode = '22023'; end if;
  if p_visual_progress_consent and not v_invitation.visual_progress_requested then
    raise exception 'visual progress was not offered' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.coach_relationships
    where client_user_id = v_client_id and status in ('active', 'grace')
  ) then
    raise exception 'client already has a live coach relationship' using errcode = '23505';
  end if;
  select seat_limit into v_seat_limit from public.coach_profiles
  where user_id = v_invitation.coach_user_id and status in ('development', 'active') for update;
  if v_seat_limit is null then raise exception 'coach is unavailable' using errcode = '42501'; end if;
  select count(*) into v_occupied from public.coach_relationships
  where coach_user_id = v_invitation.coach_user_id and seat_state in ('active', 'grace');
  if v_occupied >= v_seat_limit then raise exception 'coach has no sponsored seat available' using errcode = '23514'; end if;

  insert into public.coach_relationships (
    coach_user_id, client_user_id, invitation_id, status, seat_state,
    offered_scopes, consented_scopes, visual_progress_consented_at
  ) values (
    v_invitation.coach_user_id, v_client_id, v_invitation.id, 'active', 'active',
    v_invitation.requested_scopes, v_scopes,
    case when 'visual_progress' = any(v_scopes) then now() else null end
  )
  on conflict (coach_user_id, client_user_id) do update set
    invitation_id = excluded.invitation_id,
    status = 'active',
    seat_state = 'active',
    offered_scopes = excluded.offered_scopes,
    consented_scopes = excluded.consented_scopes,
    consented_at = now(),
    visual_progress_consented_at = excluded.visual_progress_consented_at,
    grace_ends_at = null,
    ended_at = null,
    updated_at = now()
  returning * into v_relationship;

  update public.coach_invitations
  set status = 'accepted', accepted_by = v_client_id, accepted_at = now()
  where id = v_invitation.id;
  insert into public.coach_audit_log(actor_user_id, relationship_id, event_type, metadata)
  values (v_client_id, v_relationship.id, 'invitation_accepted', jsonb_build_object(
    'scopes', to_jsonb(v_scopes),
    'visual_progress_consent', p_visual_progress_consent
  ));
  return public.coach_get_my_context();
end;
$$;

create or replace function public.coach_get_client_overview(p_relationship_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_coach_id uuid := public.coach_authenticated_user_id();
  v_relationship public.coach_relationships%rowtype;
  v_profile public.profile%rowtype;
  v_result jsonb;
begin
  select * into v_relationship from public.coach_relationships
  where id = p_relationship_id and coach_user_id = v_coach_id and status in ('active', 'grace');
  if v_relationship.id is null then raise exception 'client relationship unavailable' using errcode = '42501'; end if;
  select * into v_profile from public.profile where user_id = v_relationship.client_user_id;
  v_result := jsonb_build_object(
    'relationship_id', v_relationship.id,
    'client_user_id', v_relationship.client_user_id,
    'display_name', coalesce(nullif(btrim(v_profile.display_name), ''), 'APEX client'),
    'relationship_status', v_relationship.status,
    'seat_state', v_relationship.seat_state,
    'consented_scopes', to_jsonb(v_relationship.consented_scopes),
    'measurements', case when 'measurements' = any(v_relationship.consented_scopes) then jsonb_build_object(
      'sex', v_profile.sex,
      'height_cm', v_profile.height_cm,
      'weight_kg', v_profile.weight_kg,
      'body_fat_pct', v_profile.body_fat_pct,
      'birthdate', v_profile.birthdate
    ) else null end,
    'avatar', case when 'avatar' = any(v_relationship.consented_scopes) then (
      select to_jsonb(snapshot) from (
        select date, overall, health, joint, flexibility, endurance, strength, strength_upper, strength_lower
        from public.rpg_snapshots
        where user_id = v_relationship.client_user_id order by date desc limit 1
      ) snapshot
    ) else null end,
    'workouts', case when 'workouts' = any(v_relationship.consented_scopes) then jsonb_build_object(
      'completed_30d', (select count(*) from public.workout_sessions
        where user_id = v_relationship.client_user_id and completed
          and date >= current_date - 29),
      'last_completed_at', (select max(completed_at) from public.workout_sessions
        where user_id = v_relationship.client_user_id and completed)
    ) else null end,
    'nutrition', case when 'nutrition' = any(v_relationship.consented_scopes) then (
      select jsonb_build_object(
        'days_observed', count(*),
        'average_kcal', round(avg(kcal))
      ) from public.daily_logs
      where user_id = v_relationship.client_user_id and date >= current_date - 6 and kcal is not null
    ) else null end,
    'hydration', case when 'hydration' = any(v_relationship.consented_scopes) then (
      select jsonb_build_object('days_observed', count(*), 'average_litres', round(avg(water_l)::numeric, 2))
      from public.daily_logs
      where user_id = v_relationship.client_user_id and date >= current_date - 6
    ) else null end,
    'visual_progress_shared', 'visual_progress' = any(v_relationship.consented_scopes)
  );
  return v_result;
end;
$$;

create or replace function public.coach_write_plan_version(
  p_relationship_id uuid,
  p_plan jsonb,
  p_expected_version integer,
  p_publish boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_coach_id uuid := public.coach_authenticated_user_id();
  v_relationship public.coach_relationships%rowtype;
  v_current integer;
  v_plan public.coach_plan_versions%rowtype;
  v_status text := case when p_publish then 'published' else 'draft' end;
begin
  select * into v_relationship from public.coach_relationships
  where id = p_relationship_id and coach_user_id = v_coach_id and status = 'active' for update;
  if v_relationship.id is null then raise exception 'active client relationship required' using errcode = '42501'; end if;
  select coalesce(max(version), 0) into v_current
  from public.coach_plan_versions where relationship_id = p_relationship_id;
  if coalesce(p_expected_version, -1) <> v_current then
    raise exception 'plan changed on another device' using errcode = '40001';
  end if;
  perform public.coach_validate_plan(p_plan, p_publish);
  if p_publish then
    update public.coach_plan_versions
    set status = 'superseded'
    where relationship_id = p_relationship_id and status = 'published';
  end if;
  insert into public.coach_plan_versions (
    relationship_id, coach_user_id, version, status, title, objective,
    coach_note, review_date, checklist, plan, published_at
  ) values (
    p_relationship_id, v_coach_id, v_current + 1, v_status,
    coalesce(p_plan ->> 'title', ''),
    coalesce(p_plan ->> 'objective', ''),
    coalesce(p_plan ->> 'coach_note', ''),
    nullif(p_plan ->> 'review_date', '')::date,
    coalesce(p_plan -> 'checklist', '{}'::jsonb),
    p_plan,
    case when p_publish then now() else null end
  ) returning * into v_plan;
  insert into public.coach_audit_log(actor_user_id, relationship_id, event_type, metadata)
  values (v_coach_id, p_relationship_id, case when p_publish then 'plan_published' else 'plan_draft_saved' end,
    jsonb_build_object('plan_version_id', v_plan.id, 'version', v_plan.version));
  return jsonb_build_object(
    'id', v_plan.id,
    'relationship_id', v_plan.relationship_id,
    'version', v_plan.version,
    'status', v_plan.status
  );
end;
$$;

create or replace function public.coach_save_plan_draft(
  p_relationship_id uuid,
  p_plan jsonb,
  p_expected_version integer
)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.coach_write_plan_version(p_relationship_id, p_plan, p_expected_version, false);
$$;

create or replace function public.coach_publish_plan(
  p_relationship_id uuid,
  p_plan jsonb,
  p_expected_version integer
)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.coach_write_plan_version(p_relationship_id, p_plan, p_expected_version, true);
$$;

create or replace function public.client_acknowledge_coach_plan(p_plan_version_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_client_id uuid := public.coach_authenticated_user_id();
  v_relationship_id uuid;
begin
  select plan.relationship_id into v_relationship_id
  from public.coach_plan_versions plan
  join public.coach_relationships relationship on relationship.id = plan.relationship_id
  where plan.id = p_plan_version_id
    and plan.status in ('published', 'superseded')
    and relationship.client_user_id = v_client_id
    and relationship.status in ('active', 'grace');
  if v_relationship_id is null then raise exception 'coach plan unavailable' using errcode = '42501'; end if;
  insert into public.coach_plan_acknowledgements (
    plan_version_id, relationship_id, client_user_id, acknowledged_at
  ) values (p_plan_version_id, v_relationship_id, v_client_id, now())
  on conflict (plan_version_id, client_user_id) do update
    set acknowledged_at = coalesce(public.coach_plan_acknowledgements.acknowledged_at, now());
  insert into public.coach_audit_log(actor_user_id, relationship_id, event_type, metadata)
  values (v_client_id, v_relationship_id, 'plan_acknowledged', jsonb_build_object('plan_version_id', p_plan_version_id));
  return true;
end;
$$;

create or replace function public.client_activate_coach_plan(p_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_client_id uuid := public.coach_authenticated_user_id();
  v_relationship public.coach_relationships%rowtype;
  v_plan public.coach_plan_versions%rowtype;
  v_program_id uuid;
  v_session jsonb;
  v_exercise jsonb;
  v_day_id uuid;
  v_exercise_id uuid;
  v_installed_days uuid[] := '{}';
begin
  -- Lock the relationship first, matching coach publication lock order. This
  -- makes activation causal when another device is publishing a replacement.
  select relationship.* into v_relationship
  from public.coach_relationships relationship
  join public.coach_plan_versions plan on plan.relationship_id = relationship.id
  where plan.id = p_plan_version_id
    and relationship.client_user_id = v_client_id
    and relationship.status = 'active'
    and relationship.seat_state = 'active'
  for update of relationship;
  if v_relationship.id is null or not ('workouts' = any(v_relationship.consented_scopes)) then
    raise exception 'active workout consent required' using errcode = '42501';
  end if;

  select plan.* into v_plan
  from public.coach_plan_versions plan
  where plan.id = p_plan_version_id
    and plan.relationship_id = v_relationship.id
    and plan.status = 'published'
  for update;
  if v_plan.id is null or not ('workouts' = any(v_relationship.consented_scopes)) then
    raise exception 'active workout consent required' using errcode = '42501';
  end if;
  perform public.coach_validate_plan(v_plan.plan, true);

  select id into v_program_id from public.programs
  where user_id = v_client_id and slug = 'coach' for update;
  if v_program_id is null then
    v_program_id := gen_random_uuid();
    insert into public.programs(id, user_id, slug, name, description)
    values (v_program_id, v_client_id, 'coach', v_plan.title, 'Coach plan · version ' || v_plan.version);
  else
    update public.programs
    set name = v_plan.title, description = 'Coach plan · version ' || v_plan.version
    where id = v_program_id and user_id = v_client_id;
  end if;

  -- Retire prior templates without deleting them. Completed sessions and logs
  -- continue to reference the exact version that prescribed them.
  update public.program_days
  set is_active = false
  where user_id = v_client_id and program_id = v_program_id and is_active;

  for v_session in select value from jsonb_array_elements(v_plan.plan -> 'sessions') loop
    v_day_id := gen_random_uuid();
    v_installed_days := array_append(v_installed_days, v_day_id);
    insert into public.program_days (
      id, user_id, program_id, weekday, name, day_type, est_minutes,
      warmup_note, sort_order, session_mode, is_active, coach_plan_version_id
    ) values (
      v_day_id, v_client_id, v_program_id,
      (v_session ->> 'weekday')::integer,
      v_session ->> 'name',
      'coach',
      (v_session ->> 'estimated_minutes')::integer,
      coalesce(v_session ->> 'warmup_note', ''),
      (v_session ->> 'weekday')::integer,
      v_session ->> 'session_mode',
      true,
      v_plan.id
    );
    for v_exercise in select value from jsonb_array_elements(v_session -> 'exercises') loop
      v_exercise_id := gen_random_uuid();
      insert into public.exercises (
        id, user_id, program_day_id, name, movement_id, work_group_id,
        work_group_position, sets, rep_min, rep_max, rep_unit, per_side,
        rest_sec, tempo_up_s, tempo_down_s, tempo_pause_s, tempo_note,
        notes, increment_kg, is_lite, optional, sort_order
      ) values (
        v_exercise_id, v_client_id, v_day_id,
        v_exercise ->> 'name',
        v_exercise ->> 'movement_id',
        nullif(v_exercise ->> 'group_id', '')::uuid,
        nullif(v_exercise ->> 'group_position', '')::integer,
        (v_exercise ->> 'sets')::integer,
        (v_exercise ->> 'target_min')::integer,
        (v_exercise ->> 'target_max')::integer,
        v_exercise ->> 'unit',
        (v_exercise ->> 'per_side')::boolean,
        (v_exercise ->> 'rest_seconds')::integer,
        (v_exercise ->> 'tempo_up_seconds')::numeric,
        (v_exercise ->> 'tempo_down_seconds')::numeric,
        (v_exercise ->> 'tempo_pause_seconds')::numeric,
        '',
        coalesce(v_exercise ->> 'notes', ''),
        0,
        false,
        (v_exercise ->> 'optional')::boolean,
        (select ordinal - 1 from jsonb_array_elements(v_session -> 'exercises') with ordinality item(value, ordinal)
          where item.value ->> 'id' = v_exercise ->> 'id' limit 1)
      );
    end loop;
  end loop;

  insert into public.coach_plan_installations (
    plan_version_id, relationship_id, client_user_id, program_id, installed_day_ids
  ) values (v_plan.id, v_relationship.id, v_client_id, v_program_id, v_installed_days)
  on conflict (plan_version_id, client_user_id) do update
    set program_id = excluded.program_id,
        installed_day_ids = excluded.installed_day_ids,
        activated_at = now();
  insert into public.coach_plan_acknowledgements (
    plan_version_id, relationship_id, client_user_id, acknowledged_at, activated_at
  ) values (v_plan.id, v_relationship.id, v_client_id, now(), now())
  on conflict (plan_version_id, client_user_id) do update
    set acknowledged_at = coalesce(public.coach_plan_acknowledgements.acknowledged_at, now()),
        activated_at = now();
  insert into public.coach_audit_log(actor_user_id, relationship_id, event_type, metadata)
  values (v_client_id, v_relationship.id, 'plan_activated', jsonb_build_object(
    'plan_version_id', v_plan.id,
    'program_id', v_program_id,
    'installed_day_ids', to_jsonb(v_installed_days)
  ));
  return jsonb_build_object(
    'plan_version_id', v_plan.id,
    'program_id', v_program_id,
    'installed_day_ids', to_jsonb(v_installed_days)
  );
end;
$$;

create or replace function public.client_update_coach_scopes(
  p_relationship_id uuid,
  p_scopes text[],
  p_visual_progress_consent boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_client_id uuid := public.coach_authenticated_user_id();
  v_relationship public.coach_relationships%rowtype;
  v_scopes text[];
begin
  select * into v_relationship from public.coach_relationships
  where id = p_relationship_id and client_user_id = v_client_id and status in ('active', 'grace') for update;
  if v_relationship.id is null then raise exception 'coach relationship unavailable' using errcode = '42501'; end if;
  select coalesce(array_agg(distinct scope order by scope), '{}'::text[])
  into v_scopes from unnest(coalesce(p_scopes, '{}'::text[])) scope
  where scope = any(v_relationship.offered_scopes)
    and (scope <> 'visual_progress' or p_visual_progress_consent);
  if not public.coach_scopes_valid(v_scopes) then raise exception 'unknown consent scope' using errcode = '22023'; end if;
  update public.coach_relationships set
    consented_scopes = v_scopes,
    visual_progress_consented_at = case when 'visual_progress' = any(v_scopes) then now() else null end,
    updated_at = now()
  where id = v_relationship.id;
  insert into public.coach_audit_log(actor_user_id, relationship_id, event_type, metadata)
  values (v_client_id, v_relationship.id, 'consent_scopes_updated', jsonb_build_object(
    'previous_scopes', to_jsonb(v_relationship.consented_scopes),
    'next_scopes', to_jsonb(v_scopes),
    'visual_progress_consent', p_visual_progress_consent
  ));
  return public.coach_get_my_context();
end;
$$;

create or replace function public.end_coach_relationship(p_relationship_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.coach_authenticated_user_id();
  v_relationship public.coach_relationships%rowtype;
begin
  select * into v_relationship from public.coach_relationships
  where id = p_relationship_id
    and (coach_user_id = v_actor or client_user_id = v_actor)
    and status = 'active'
  for update;
  if v_relationship.id is null then raise exception 'active coach relationship unavailable' using errcode = '42501'; end if;
  update public.coach_relationships set
    status = 'grace',
    seat_state = 'grace',
    grace_ends_at = now() + interval '30 days',
    ended_at = now(),
    updated_at = now()
  where id = v_relationship.id;
  insert into public.coach_audit_log(actor_user_id, relationship_id, event_type, metadata)
  values (v_actor, v_relationship.id, 'relationship_entered_grace', jsonb_build_object(
    'initiated_by', case when v_actor = v_relationship.coach_user_id then 'coach' else 'client' end,
    'grace_days', 30
  ));
  return true;
end;
$$;

-- Server role grant for the owner's exact account only. It creates neither a
-- client relationship nor a commercial entitlement.
insert into public.coach_profiles(user_id, display_name, status, seat_limit)
select account.id, coalesce(nullif(btrim(profile.display_name), ''), 'Constantine'), 'development', 10
from auth.users account
left join public.profile profile on profile.user_id = account.id
where account.id = '9a0fffbc-bb02-40ac-834a-d4e339b32574'::uuid
on conflict (user_id) do update set
  display_name = excluded.display_name,
  updated_at = now();

revoke all on function public.prevent_coach_audit_mutation() from public, anon, authenticated;
revoke all on function public.coach_authenticated_user_id() from public, anon, authenticated;
revoke all on function public.coach_scopes_valid(text[]) from public, anon, authenticated;
revoke all on function public.coach_json_has_only_keys(jsonb, text[]) from public, anon, authenticated;
revoke all on function public.coach_json_integer_between(jsonb, text, integer, integer) from public, anon, authenticated;
revoke all on function public.coach_validate_plan(jsonb, boolean) from public, anon, authenticated;
revoke all on function public.coach_release_expired_grace() from public, anon, authenticated;
revoke all on function public.coach_write_plan_version(uuid, jsonb, integer, boolean) from public, anon, authenticated;

revoke all on function public.coach_get_my_context() from public, anon;
revoke all on function public.coach_get_roster(text) from public, anon;
revoke all on function public.coach_create_invitation(text, text[], boolean) from public, anon;
revoke all on function public.coach_accept_invitation(text, text[], boolean) from public, anon;
revoke all on function public.coach_get_client_overview(uuid) from public, anon;
revoke all on function public.coach_save_plan_draft(uuid, jsonb, integer) from public, anon;
revoke all on function public.coach_publish_plan(uuid, jsonb, integer) from public, anon;
revoke all on function public.client_acknowledge_coach_plan(uuid) from public, anon;
revoke all on function public.client_activate_coach_plan(uuid) from public, anon;
revoke all on function public.client_update_coach_scopes(uuid, text[], boolean) from public, anon;
revoke all on function public.end_coach_relationship(uuid) from public, anon;

grant execute on function public.coach_get_my_context() to authenticated;
grant execute on function public.coach_get_roster(text) to authenticated;
grant execute on function public.coach_create_invitation(text, text[], boolean) to authenticated;
grant execute on function public.coach_accept_invitation(text, text[], boolean) to authenticated;
grant execute on function public.coach_get_client_overview(uuid) to authenticated;
grant execute on function public.coach_save_plan_draft(uuid, jsonb, integer) to authenticated;
grant execute on function public.coach_publish_plan(uuid, jsonb, integer) to authenticated;
grant execute on function public.client_acknowledge_coach_plan(uuid) to authenticated;
grant execute on function public.client_activate_coach_plan(uuid) to authenticated;
grant execute on function public.client_update_coach_scopes(uuid, text[], boolean) to authenticated;
grant execute on function public.end_coach_relationship(uuid) to authenticated;

notify pgrst, 'reload schema';
