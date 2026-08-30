-- Keep complete source evidence outside the bounded client-search projection.
-- Archives remain private and are addressed by the checksums recorded per batch.
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'food-corpus-evidence',
  'food-corpus-evidence',
  false,
  52428800,
  array[
    'application/gzip',
    'application/x-gzip',
    'application/octet-stream'
  ]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
