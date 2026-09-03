-- TestFlight access is an account fact independent of profile creation.
-- The fixed deadline is deliberately shared by the release, rather than being
-- calculated from sign-up time, so the server can move the whole cohort to the
-- next commercial policy without installing a different client-side gate.

alter table public.profile
  add column if not exists created_at timestamptz;

update public.profile as profile
set created_at = account.created_at
from auth.users as account
where profile.user_id = account.id
  and profile.created_at is null;

alter table public.profile
  alter column created_at set default now(),
  alter column created_at set not null;

create table if not exists public.account_entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  state text not null default 'locked'
    constraint account_entitlements_state_allowed
    check (state in ('granted', 'locked', 'revoked')),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.client_release_policy (
  platform text primary key
    constraint client_release_policy_platform_allowed
    check (platform in ('ios', 'web')),
  minimum_build integer not null default 0
    constraint client_release_policy_minimum_build_nonnegative
    check (minimum_build >= 0),
  web_beta_codes_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

insert into public.client_release_policy (
  platform,
  minimum_build,
  web_beta_codes_enabled
) values
  ('ios', 0, false),
  ('web', 0, false)
on conflict (platform) do nothing;

-- The four protected owner accounts remain permanent. Insert them before the
-- general cohort so a rerun can never replace a later revoke or policy edit.
insert into public.account_entitlements (
  user_id,
  state,
  expires_at,
  created_at,
  updated_at
)
select
  account.id,
  'granted',
  null,
  account.created_at,
  now()
from auth.users as account
where account.id = any(array[
  '9a0fffbc-bb02-40ac-834a-d4e339b32574'::uuid,
  'f1cc8158-0480-47c9-a2f1-bd03890182f9'::uuid,
  'ed1fa9d3-9d39-4d39-9b66-a51f2d140492'::uuid,
  'ce883869-fe72-4371-9788-5723d76f07b5'::uuid
])
on conflict (user_id) do nothing;

insert into public.account_entitlements (
  user_id,
  state,
  expires_at,
  created_at,
  updated_at
)
select
  account.id,
  'granted',
  '2027-12-31T23:59:59Z'::timestamptz,
  account.created_at,
  now()
from auth.users as account
on conflict (user_id) do nothing;

create or replace function public.create_testflight_account_entitlement()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.account_entitlements (
    user_id,
    state,
    expires_at,
    created_at,
    updated_at
  ) values (
    new.id,
    'granted',
    case
      when new.id = any(array[
        '9a0fffbc-bb02-40ac-834a-d4e339b32574'::uuid,
        'f1cc8158-0480-47c9-a2f1-bd03890182f9'::uuid,
        'ed1fa9d3-9d39-4d39-9b66-a51f2d140492'::uuid,
        'ce883869-fe72-4371-9788-5723d76f07b5'::uuid
      ]) then null
      else '2027-12-31T23:59:59Z'::timestamptz
    end,
    coalesce(new.created_at, now()),
    now()
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke all on function public.create_testflight_account_entitlement()
  from public, anon, authenticated;

drop trigger if exists create_testflight_account_entitlement_on_signup on auth.users;
create trigger create_testflight_account_entitlement_on_signup
after insert on auth.users
for each row execute function public.create_testflight_account_entitlement();

alter table public.account_entitlements enable row level security;
alter table public.client_release_policy enable row level security;

revoke all on table public.account_entitlements from public, anon, authenticated;
revoke all on table public.client_release_policy from public, anon, authenticated;

create or replace function public.get_my_app_access(
  p_platform text,
  p_build integer
)
returns table (
  user_id uuid,
  state text,
  expires_at timestamptz,
  entitlement_updated_at timestamptz,
  server_now timestamptz,
  sponsored_seat_active boolean,
  minimum_build integer,
  update_required boolean,
  web_beta_codes_enabled boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_server_now timestamptz := statement_timestamp();
  v_entitlement public.account_entitlements%rowtype;
  v_state text;
  v_sponsored_seat_active boolean := false;
  v_minimum_build integer;
  v_web_beta_codes_enabled boolean := false;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_platform is null or p_platform not in ('ios', 'web') then
    raise exception 'unsupported client platform' using errcode = '22023';
  end if;
  if p_build is null or p_build < 0 then
    raise exception 'invalid client build' using errcode = '22023';
  end if;

  select entitlement.*
  into v_entitlement
  from public.account_entitlements as entitlement
  where entitlement.user_id = v_user_id;

  select
    policy.minimum_build,
    policy.web_beta_codes_enabled
  into
    v_minimum_build,
    v_web_beta_codes_enabled
  from public.client_release_policy as policy
  where policy.platform = p_platform;

  if v_minimum_build is null then
    raise exception 'client release policy unavailable' using errcode = '55000';
  end if;

  select exists (
    select 1
    from public.coach_relationships as relationship
    where relationship.client_user_id = v_user_id
      and relationship.status = 'active'
      and relationship.seat_state = 'active'
  )
  into v_sponsored_seat_active;

  v_state := case
    when v_entitlement.user_id is null then 'missing'
    when v_entitlement.state = 'revoked' then 'revoked'
    when v_entitlement.state = 'locked' then 'locked'
    when v_entitlement.expires_at is null
      or v_entitlement.expires_at > v_server_now then 'granted'
    else 'expired'
  end;

  return query select
    v_user_id,
    v_state,
    v_entitlement.expires_at,
    v_entitlement.updated_at,
    v_server_now,
    v_sponsored_seat_active,
    v_minimum_build,
    p_build < v_minimum_build,
    p_platform = 'web' and v_web_beta_codes_enabled;
end;
$$;

revoke all on function public.get_my_app_access(text, integer) from public, anon;
grant execute on function public.get_my_app_access(text, integer) to authenticated;

notify pgrst, 'reload schema';
