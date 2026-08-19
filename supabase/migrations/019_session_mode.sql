-- Two ways to train the same session.
--
-- "guided" runs the follow-along player: it paces the session, counts the reps
-- aloud, times the rests and the side switches, and asks what was lifted
-- between sets. That is what somebody new to training, or coming back from a
-- layoff, actually needs.
--
-- "tracked" shows the list and gets out of the way. Anyone running their own
-- progressive overload wants to work at their own rhythm and record what
-- happened -- weight, reps, and reps in reserve, which is the number that
-- decides whether next week goes up. Being paced through that is an
-- obstruction rather than a feature.
--
-- Both write identical history through the same code, so a set logged in one
-- and a set typed into the other are indistinguishable afterwards. Nothing
-- about progressive overload, the workout receipt or any strength comparison
-- depends on which screen was used.

alter table public.program_days
  add column if not exists session_mode text not null default 'guided';

alter table public.program_days
  drop constraint if exists program_days_session_mode_check;
alter table public.program_days
  add constraint program_days_session_mode_check
    check (session_mode in ('guided', 'tracked'));

notify pgrst, 'reload schema';
