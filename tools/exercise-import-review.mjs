const EXPECTED_HEADERS = [
  'name',
  'equipment',
  'movement_pattern',
  'exercise_type',
  'modality_tags',
  'sport_tags',
  'notes',
]

function parseCsvRecords(source) {
  const records = []
  let record = []
  let field = ''
  let quoted = false

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index]
    if (quoted) {
      if (character === '"' && source[index + 1] === '"') {
        field += '"'
        index += 1
      } else if (character === '"') {
        quoted = false
      } else {
        field += character
      }
      continue
    }

    if (character === '"') {
      if (field.length > 0) throw new Error('Unexpected quote inside an unquoted CSV field')
      quoted = true
    } else if (character === ',') {
      record.push(field)
      field = ''
    } else if (character === '\n') {
      record.push(field.endsWith('\r') ? field.slice(0, -1) : field)
      records.push(record)
      record = []
      field = ''
    } else {
      field += character
    }
  }

  if (quoted) throw new Error('Unterminated quoted CSV field')
  if (field.length > 0 || record.length > 0) {
    record.push(field.endsWith('\r') ? field.slice(0, -1) : field)
    records.push(record)
  }
  return records
}

function splitTags(value) {
  return value
    .split(';')
    .map((tag) => tag.trim())
    .filter(Boolean)
}

export function normalizeExerciseName(value) {
  return value
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('en-US')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

export function normalizeTag(value) {
  return normalizeExerciseName(value).replace(/ /g, '_')
}

export function parseExerciseImportCsv(source) {
  const [headers, ...records] = parseCsvRecords(source)
  if (!headers || headers.length !== EXPECTED_HEADERS.length ||
      headers.some((header, index) => header !== EXPECTED_HEADERS[index])) {
    throw new Error(`Expected CSV headers: ${EXPECTED_HEADERS.join(',')}`)
  }

  return records
    .filter((record) => record.some((field) => field.length > 0))
    .map((record, index) => {
      if (record.length === EXPECTED_HEADERS.length - 1) record.push('')
      if (record.length !== EXPECTED_HEADERS.length) {
        throw new Error(`CSV source row ${index + 2} has ${record.length} fields; expected 7`)
      }
      const [name, equipment, movementPattern, exerciseType, modalityTags, sportTags, notes] = record
      if (![name, equipment, movementPattern, exerciseType, modalityTags].every((value) => value.trim())) {
        throw new Error(`CSV source row ${index + 2} is missing a required field`)
      }
      return {
        sourceRow: index + 2,
        name: name.trim(),
        equipment: equipment.trim(),
        movementPattern: movementPattern.trim(),
        exerciseType: exerciseType.trim(),
        modalityTags: splitTags(modalityTags),
        sportTags: splitTags(sportTags),
        notes: notes.trim(),
      }
    })
}

export function buildReviewCandidates(rows, canonicalMovements, sourceSha256) {
  if (!/^[0-9a-f]{64}$/.test(sourceSha256)) {
    throw new Error('sourceSha256 must be a lowercase SHA-256 digest')
  }
  const canonicalByName = new Map()
  for (const movement of canonicalMovements) {
    const normalizedName = normalizeExerciseName(movement.name)
    if (canonicalByName.has(normalizedName)) {
      throw new Error(`Duplicate canonical movement name: ${movement.name}`)
    }
    canonicalByName.set(normalizedName, movement)
  }

  const sourceNames = new Set()
  for (const row of rows) {
    const normalizedName = normalizeExerciseName(row.name)
    if (sourceNames.has(normalizedName)) {
      throw new Error(`Duplicate source exercise name: ${row.name}`)
    }
    sourceNames.add(normalizedName)
  }

  return rows.map((row) => {
    const normalizedName = normalizeExerciseName(row.name)
    const match = canonicalByName.get(normalizedName)
    return {
      ...row,
      normalizedName,
      movementPattern: normalizeTag(row.movementPattern),
      exerciseType: normalizeTag(row.exerciseType),
      modalityTags: row.modalityTags.map(normalizeTag),
      sportTags: row.sportTags.map(normalizeTag),
      sourceSha256,
      matchStatus: match ? 'canonical_exact' : 'pending_review',
      matchedMovementId: match?.id ?? null,
    }
  })
}

function sqlString(value) {
  return `'${value.replaceAll("'", "''")}'`
}

function sqlArray(values) {
  if (values.length === 0) return 'array[]::text[]'
  return `array[${values.map(sqlString).join(', ')}]::text[]`
}

export function renderReviewMigration(candidates, { sourceFilename, sourceSha256 }) {
  if (!sourceFilename?.trim()) throw new Error('sourceFilename is required')
  if (!/^[0-9a-f]{64}$/.test(sourceSha256)) {
    throw new Error('sourceSha256 must be a lowercase SHA-256 digest')
  }
  if (candidates.some((candidate) => candidate.sourceSha256 !== sourceSha256)) {
    throw new Error('Every candidate must retain the supplied source SHA-256')
  }

  const ordered = [...candidates].sort((left, right) => left.sourceRow - right.sourceRow)
  const exactCount = ordered.filter((candidate) => candidate.matchStatus === 'canonical_exact').length
  const pendingCount = ordered.filter((candidate) => candidate.matchStatus === 'pending_review').length
  const rows = ordered.map((candidate) => [
    '  (',
    sqlString(sourceSha256),
    `, ${candidate.sourceRow}, `,
    sqlString(sourceFilename),
    ', ',
    sqlString(candidate.name),
    ', ',
    sqlString(candidate.normalizedName),
    ', ',
    sqlString(candidate.equipment),
    ', ',
    sqlString(candidate.movementPattern),
    ', ',
    sqlString(candidate.exerciseType),
    ', ',
    sqlArray(candidate.modalityTags),
    ', ',
    sqlArray(candidate.sportTags),
    ', ',
    sqlString(candidate.notes),
    ', ',
    sqlString(candidate.matchStatus),
    ', ',
    candidate.matchedMovementId ? sqlString(candidate.matchedMovementId) : 'null',
    ')',
  ].join('')).join(',\n')

  return `-- Stages the owner-supplied movement expansion for explicit review.
-- Regenerate with: node tools/exercise-import-review.mjs
-- Original source SHA-256: ${sourceSha256}
-- ${ordered.length} source rows: ${exactCount} exact canonical matches, ${pendingCount} pending review.
-- Pending rows are deliberately not selectable or auto-assignable.

create table if not exists public.movement_import_review_queue (
  source_sha256 text not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  source_row integer not null check (source_row >= 2),
  source_filename text not null,
  name text not null,
  normalized_name text not null,
  equipment_label text not null,
  movement_pattern text not null,
  exercise_type text not null,
  modality_tags text[] not null default '{}',
  sport_tags text[] not null default '{}',
  notes text not null default '',
  match_status text not null check (match_status in ('canonical_exact', 'pending_review')),
  matched_movement_id text references public.movement_library(id) on delete restrict,
  review_status text not null default 'pending'
    check (review_status in ('pending', 'approved', 'rejected')),
  review_notes text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (source_sha256, source_row),
  unique (source_sha256, normalized_name),
  check (
    (match_status = 'canonical_exact' and matched_movement_id is not null)
    or (match_status = 'pending_review' and matched_movement_id is null)
  )
);

create index if not exists movement_import_review_queue_movement_idx
  on public.movement_import_review_queue (matched_movement_id)
  where matched_movement_id is not null;
create index if not exists movement_import_review_queue_reviewer_idx
  on public.movement_import_review_queue (reviewed_by)
  where reviewed_by is not null;

alter table public.movement_import_review_queue enable row level security;
revoke all on table public.movement_import_review_queue from public, anon, authenticated;
grant all on table public.movement_import_review_queue to service_role;

comment on table public.movement_import_review_queue is
  'Service-only staging queue. Rows must be enriched and reviewed before entering the canonical movement library.';

insert into public.movement_import_review_queue (
  source_sha256, source_row, source_filename, name, normalized_name,
  equipment_label, movement_pattern, exercise_type, modality_tags, sport_tags,
  notes, match_status, matched_movement_id
) values
${rows}
on conflict (source_sha256, source_row) do nothing;

with verified_tags as (
  select
    queue.matched_movement_id,
    array_agg(distinct sport.sport_tag order by sport.sport_tag) as tags
  from public.movement_import_review_queue as queue
  cross join lateral unnest(queue.sport_tags) as sport(sport_tag)
  where queue.match_status = 'canonical_exact'
    and queue.source_sha256 = ${sqlString(sourceSha256)}
  group by queue.matched_movement_id
)
update public.movement_library as movement
set disciplines = movement.disciplines || (
  select coalesce(array_agg(candidate.tag order by candidate.tag), '{}'::text[])
  from unnest(verified_tags.tags) as candidate(tag)
  where not candidate.tag = any(movement.disciplines)
)
from verified_tags
where movement.id = verified_tags.matched_movement_id;

notify pgrst, 'reload schema';
`
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  const { readFileSync } = await import('node:fs')
  const { CARDIO_MODALITIES, MOVEMENTS } = await import('../src/data/movements.ts')
  const sourceFilename = 'exercise_extra_encyclopedia_with_sport_tags.csv'
  const sourceSha256 = '8ae1056ec3787059a70623de7d2d56572e7760c3da97a7b505495d684d779e1d'
  const source = readFileSync(`data/imports/${sourceFilename}`, 'utf8')
  const canonical = [
    ...MOVEMENTS.map(({ id, name }) => ({ id, name })),
    ...CARDIO_MODALITIES.map(({ id, name }) => ({ id, name })),
  ]
  const candidates = buildReviewCandidates(
    parseExerciseImportCsv(source),
    canonical,
    sourceSha256,
  )
  process.stdout.write(renderReviewMigration(candidates, { sourceFilename, sourceSha256 }))
}
