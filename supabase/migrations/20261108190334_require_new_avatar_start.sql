-- Existing accounts keep their prior onboarding. New profiles receive the gate.
alter table public.profile add column avatar_starting_points_required boolean not null default false;
alter table public.profile alter column avatar_starting_points_required set default true;

create function public.preserve_avatar_onboarding_requirement() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.avatar_starting_points_required := true;
  else
    new.avatar_starting_points_required := old.avatar_starting_points_required;
  end if;
  return new;
end;
$$;
revoke all on function public.preserve_avatar_onboarding_requirement() from public, anon, authenticated;
create trigger preserve_avatar_onboarding_requirement before insert or update of avatar_starting_points_required
  on public.profile for each row execute function public.preserve_avatar_onboarding_requirement();
