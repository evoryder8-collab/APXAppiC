-- Which muscle group and mechanism each movement is timed by.
--
-- One tempo profile across 180 movements was the rigid rule it was meant to
-- replace. Where the evidence differentiates, it now does: the soleus is
-- roughly eighty per cent slow-twitch fibre and earns 12-25 reps *for
-- hypertrophy* rather than being pushed toward endurance work; the calf stores
-- and returns elastic energy, so its pause in the stretch is the exercise and
-- survives every goal instead of being dropped when the load goes up; eccentric
-- hamstring work gets four seconds down because that is where its evidence
-- lives; hip extension pauses at lockout because that is where its torque peaks.
--
-- Where the evidence does not differentiate -- ordinary multi-joint pressing,
-- pulling and squatting -- one profile is used and that is stated rather than
-- dressed up as twelve different numbers.

alter table public.movement_library
  add column if not exists tempo_class text not null default 'standard_compound';

alter table public.movement_library
  drop constraint if exists movement_library_tempo_class_check;
alter table public.movement_library
  add constraint movement_library_tempo_class_check check (tempo_class in (
    'standard_compound','calf_soleus','calf_gastroc','hamstring_eccentric',
    'glute_lockout','spinal_erector','single_joint','lateral_delt',
    'rotator_cuff','grip_and_small','adductor','core_braced'));

-- External rotation is loaded at end-range rotation, which is the shortened
-- position for the muscle doing the work rather than the stretch.
update public.movement_library set peak_tension = 'shortened'
where id = 'cable_external_rotation';

-- Mechanics decide the class before the muscle list does. Reading muscles
-- first put push-ups in with the arm work and deadlifts in with back
-- extensions, because the triceps and the erectors are in those lists.
update public.movement_library set tempo_class = case
  when pattern = 'calf' and (id = 'seated_calf_raise' or 'soleus' = any(primary_muscles))
    then 'calf_soleus'
  when pattern = 'calf' then 'calf_gastroc'
  when pattern like 'core\_%' then 'core_braced'
  when id in ('back_extension', 'back_extension_machine') then 'spinal_erector'
  when pattern in ('isolation_upper', 'isolation_lower') then case
    when 'rotator_cuff' = any(primary_muscles) then 'rotator_cuff'
    when 'side_delts' = any(primary_muscles) then 'lateral_delt'
    when primary_muscles && array['neck','deep_neck_flexors','foot_intrinsics','tibialis']
      or primary_muscles = array['forearms'] then 'grip_and_small'
    when primary_muscles && array['biceps','triceps'] then 'single_joint'
    when 'adductors' = any(primary_muscles) then 'adductor'
    when 'erectors' = any(primary_muscles) then 'spinal_erector'
    when primary_muscles && array['glutes','glute_medius'] then 'glute_lockout'
    when 'hamstrings' = any(primary_muscles) then 'hamstring_eccentric'
    else 'single_joint' end
  when peak_tension = 'shortened' and primary_muscles && array['glutes','glute_medius']
    then 'glute_lockout'
  when pattern = 'hip_hinge' and 'hamstrings' = any(primary_muscles)
    and not ('erectors' = any(primary_muscles)) then 'hamstring_eccentric'
  when 'erectors' = any(primary_muscles) and pattern = 'hip_hinge' and not loadable
    then 'spinal_erector'
  else 'standard_compound' end;

notify pgrst, 'reload schema';
