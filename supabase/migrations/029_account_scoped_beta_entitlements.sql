-- Beta access is an account fact, never a device flag or a client-writable
-- profile preference. Historical trial fields remain intact but are ignored
-- by the beta clients.

alter table public.profile
  add column if not exists beta_code_redeemed boolean not null default false;

create or replace function public.protect_profile_beta_entitlement()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Direct PostgREST writes run as anon/authenticated. The existing
  -- security-definer redeem_beta_code(text) RPC runs as its database owner,
  -- so it remains the only client-reachable path that may change this bit.
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' and new.beta_code_redeemed then
      raise exception 'beta_code_redeemed is server managed'
        using errcode = '42501';
    end if;
    if tg_op = 'UPDATE'
       and new.beta_code_redeemed is distinct from old.beta_code_redeemed then
      raise exception 'beta_code_redeemed is server managed'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profile_beta_entitlement_is_server_owned on public.profile;
create trigger profile_beta_entitlement_is_server_owned
before insert or update of beta_code_redeemed on public.profile
for each row execute function public.protect_profile_beta_entitlement();

-- The redemption RPC already owns the one-use code claim in production.
-- Keep it unavailable to anonymous callers while preserving authenticated use.
do $$
begin
  if to_regprocedure('public.redeem_beta_code(text)') is not null then
    execute 'revoke execute on function public.redeem_beta_code(text) from public, anon';
    execute 'grant execute on function public.redeem_beta_code(text) to authenticated';
  end if;
end;
$$;

notify pgrst, 'reload schema';
