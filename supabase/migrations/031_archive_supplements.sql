-- Retire a supplement without erasing its historical check-offs.
--
-- supplement_logs references supplements with ON DELETE CASCADE, so deleting
-- a row to tidy the current stack would also delete the record of every day it
-- was taken. Both clients therefore hide archived rows while retaining them.
alter table public.supplements
  add column if not exists archived boolean not null default false;

comment on column public.supplements.archived is
  'Hidden from the active stack while historical supplement_logs remain intact.';
