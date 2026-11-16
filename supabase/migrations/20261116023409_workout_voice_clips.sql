-- Exercise names voiced for the guided-workout coach (function `workout-voice`).
-- Clips live in a private bucket; only the function (service role) reads or writes it.
insert into storage.buckets (id, name, public)
values ('workout-voice', 'workout-voice', false)
on conflict (id) do nothing;

-- One row per clip made, so each account's daily allowance can be counted. No policies: service role only.
create table if not exists public.workout_voice_generations (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  language text not null,
  characters integer not null check (characters between 1 and 80),
  created_at timestamptz not null default now()
);
alter table public.workout_voice_generations enable row level security;
create index if not exists workout_voice_generations_user_time on public.workout_voice_generations (user_id, created_at);
