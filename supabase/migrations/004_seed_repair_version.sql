-- Versioned completion marker for resumable per-user seed hydration.
-- Existing profiles start at 0 and are repaired once by the client.

alter table profile add column if not exists seed_version integer not null default 0;

notify pgrst, 'reload schema';
