-- Fail-safe profile policy and measurement provenance.
--
-- Presentation persona is not authorization. Every profile is standard unless
-- an immutable protected owner is assigned an exact bespoke protocol below.
-- Existing body-fat values survive, but values without a recorded source are
-- explicitly unverified and cannot silently act like measurements.

alter table public.profile
  add column if not exists profile_kind text not null default 'standard',
  add column if not exists bespoke_protocol_id text,
  add column if not exists body_fat_source text,
  add column if not exists body_fat_measured_at date;

alter table public.profile
  alter column profile_kind set default 'standard',
  alter column body_fat_pct drop default,
  alter column body_fat_pct drop not null;

update public.profile
set profile_kind = 'standard'
where profile_kind is null or btrim(profile_kind) = '';

update public.profile
set body_fat_source = 'legacy_unverified'
where body_fat_pct is not null
  and body_fat_source is null;

do $$
declare
  constantine_user constant uuid := '9a0fffbc-bb02-40ac-834a-d4e339b32574';
  june_user constant uuid := 'f1cc8158-0480-47c9-a2f1-bd03890182f9';
  matthew_user constant uuid := 'ed1fa9d3-9d39-4d39-9b66-a51f2d140492';
  iulian_user constant uuid := 'ce883869-fe72-4371-9788-5723d76f07b5';
begin
  if exists (
    select 1
    from public.profile
    where user_id = constantine_user
      and persona <> 'constantine'
  ) then
    raise exception 'Protected Constantine profile persona does not match its immutable owner';
  end if;

  if exists (
    select 1
    from public.profile
    where user_id = june_user
      and persona <> 'june'
  ) then
    raise exception 'Protected June profile persona does not match its immutable owner';
  end if;

  if exists (
    select 1
    from public.profile
    where user_id = matthew_user
      and persona <> 'matthew'
  ) then
    raise exception 'Protected Matthew profile persona does not match its immutable owner';
  end if;

  if exists (
    select 1
    from public.profile
    where user_id = iulian_user
      and persona <> 'iulian'
  ) then
    raise exception 'Protected Iulian profile persona does not match its immutable owner';
  end if;

  update public.profile
  set
    profile_kind = 'bespoke',
    bespoke_protocol_id = 'constantine-v8.5'
  where user_id = constantine_user
    and persona = 'constantine';

  update public.profile
  set
    profile_kind = 'bespoke',
    bespoke_protocol_id = 'june-v8.4'
  where user_id = june_user
    and persona = 'june';

  update public.profile
  set
    profile_kind = 'bespoke',
    bespoke_protocol_id = 'matthew-v1'
  where user_id = matthew_user
    and persona = 'matthew';

  update public.profile
  set
    profile_kind = 'bespoke',
    bespoke_protocol_id = 'iulian-v2'
  where user_id = iulian_user
    and persona = 'iulian';
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profile'::regclass
      and conname = 'profile_kind_allowed'
  ) then
    alter table public.profile
      add constraint profile_kind_allowed
      check (profile_kind in ('standard', 'bespoke'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profile'::regclass
      and conname = 'profile_protocol_presence'
  ) then
    alter table public.profile
      add constraint profile_protocol_presence
      check (
        (profile_kind = 'standard' and bespoke_protocol_id is null)
        or
        (profile_kind = 'bespoke' and bespoke_protocol_id is not null)
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profile'::regclass
      and conname = 'profile_bespoke_protocol_identity'
  ) then
    alter table public.profile
      add constraint profile_bespoke_protocol_identity
      check (
        profile_kind = 'standard'
        or (
          user_id = '9a0fffbc-bb02-40ac-834a-d4e339b32574'
          and persona = 'constantine'
          and bespoke_protocol_id = 'constantine-v8.5'
        )
        or (
          user_id = 'f1cc8158-0480-47c9-a2f1-bd03890182f9'
          and persona = 'june'
          and bespoke_protocol_id = 'june-v8.4'
        )
        or (
          user_id = 'ed1fa9d3-9d39-4d39-9b66-a51f2d140492'
          and persona = 'matthew'
          and bespoke_protocol_id = 'matthew-v1'
        )
        or (
          user_id = 'ce883869-fe72-4371-9788-5723d76f07b5'
          and persona = 'iulian'
          and bespoke_protocol_id = 'iulian-v2'
        )
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profile'::regclass
      and conname = 'profile_body_fat_source_allowed'
  ) then
    alter table public.profile
      add constraint profile_body_fat_source_allowed
      check (
        body_fat_source is null
        or body_fat_source in (
          'dexa',
          'bia_scale',
          'calipers',
          'professional_estimate',
          'self_estimate',
          'legacy_unverified'
        )
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profile'::regclass
      and conname = 'profile_body_fat_value_and_source'
  ) then
    alter table public.profile
      add constraint profile_body_fat_value_and_source
      check (
        (body_fat_pct is null and body_fat_source is null)
        or (
          body_fat_pct between 2 and 70
          and body_fat_source is not null
        )
      );
  end if;
end
$$;

comment on column public.profile.profile_kind is
  'Authorization boundary: standard is fail-safe; bespoke requires an exact protected protocol.';
comment on column public.profile.bespoke_protocol_id is
  'Protected prescription identifier. Persona and display name alone never authorize bespoke behavior.';
comment on column public.profile.body_fat_source is
  'Recorded source for body_fat_pct. legacy_unverified values remain visible but are ineligible for lean-mass energy equations.';
comment on column public.profile.body_fat_measured_at is
  'Date the body-fat evidence was obtained, when known.';

notify pgrst, 'reload schema';
