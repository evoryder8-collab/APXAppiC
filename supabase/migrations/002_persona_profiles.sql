-- Multi-person profile metadata and optional coach-authored nutrition targets.
-- Safe to run repeatedly against an existing APEX project.

alter table profile add column if not exists persona text not null default 'constantine';
alter table profile add column if not exists display_name text not null default 'Constantine';
alter table profile add column if not exists target_kcal integer;
alter table profile add column if not exists target_protein_g integer;
alter table profile add column if not exists target_fat_g integer;
alter table profile add column if not exists target_carbs_g integer;
alter table profile add column if not exists profile_note text not null default '';

update profile
set
  persona = coalesce(nullif(persona, ''), 'constantine'),
  display_name = coalesce(nullif(display_name, ''), 'Constantine')
where persona = '' or display_name = '';

-- Ask PostgREST to expose the new columns without waiting for cache expiry.
notify pgrst, 'reload schema';
