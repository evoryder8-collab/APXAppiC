import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { existsSync, readFileSync } from 'node:fs'
import test from 'node:test'
import {
  buildReviewCandidates,
  normalizeExerciseName,
  normalizeTag,
  parseExerciseImportCsv,
  renderReviewMigration,
} from '../tools/exercise-import-review.mjs'
import { CARDIO_MODALITIES, MOVEMENT_BY_ID, MOVEMENTS } from '../src/data/movements.ts'

const importPath = 'data/imports/exercise_extra_encyclopedia_with_sport_tags.csv'
const sourceSha256 = '8ae1056ec3787059a70623de7d2d56572e7760c3da97a7b505495d684d779e1d'
const normalizedSha256 = 'a7c3efb73ca84bcb597a5edc1955672bf2bd0ecd8f08625a87954bc231c17cd0'

test('the owner-supplied exercise import permits only repository line-ending normalization', () => {
  assert.equal(existsSync(importPath), true, `${importPath} is missing`)
  if (!existsSync(importPath)) return

  const source = readFileSync(importPath)
  assert.equal(createHash('sha256').update(source).digest('hex'), normalizedSha256)
  const restoredOwnerSource = source.toString('utf8').replaceAll('\n', '\r\n')
  assert.equal(
    createHash('sha256').update(restoredOwnerSource).digest('hex'),
    sourceSha256,
    'restoring CRLF must reproduce the exact owner-supplied file',
  )
})

test('the parser preserves 219 unique source rows and rejects malformed headers', () => {
  const rows = parseExerciseImportCsv(readFileSync(importPath, 'utf8'))
  assert.equal(rows.length, 219)
  assert.equal(new Set(rows.map((row) => normalizeExerciseName(row.name))).size, 219)
  assert.deepEqual(rows[0], {
    sourceRow: 2,
    name: 'Kettlebell Turkish Get-Up',
    equipment: 'Kettlebell',
    movementPattern: 'Lunge',
    exerciseType: 'Strength',
    modalityTags: ['Kettlebell', 'Full-Body'],
    sportTags: ['Kettlebell Sport'],
    notes: '',
  })

  assert.throws(
    () => parseExerciseImportCsv('name,equipment\nIncomplete,Kettlebell\n'),
    /expected CSV headers/i,
  )
  assert.equal(
    rows.find((row) => row.name === 'Seated Machine Shoulder Press (Neutral)')?.notes,
    '',
    'a missing optional trailing notes cell is normalized to empty',
  )
})

test('the parser handles quoted commas and escaped quotes without changing fields', () => {
  const rows = parseExerciseImportCsv(
    'name,equipment,movement_pattern,exercise_type,modality_tags,sport_tags,notes\n' +
      '"Clean, Double","Barbell","Hinge","Strength","Olympic;Full-Body","CrossFit","Uses ""double"" bars"\n',
  )
  assert.equal(rows[0].name, 'Clean, Double')
  assert.equal(rows[0].notes, 'Uses "double" bars')
  assert.deepEqual(rows[0].modalityTags, ['Olympic', 'Full-Body'])
})

test('review matching is exact after punctuation folding and never fuzzy', () => {
  const canonical = [
    ...MOVEMENTS
      .filter((movement) => movement.importSourceName == null && !movement.id.startsWith('steel_mace_'))
      .map(({ id, name }) => ({ id, name })),
    ...CARDIO_MODALITIES.map(({ id, name }) => ({ id, name })),
  ]
  const rows = parseExerciseImportCsv(readFileSync(importPath, 'utf8'))
  const candidates = buildReviewCandidates(rows, canonical, sourceSha256)
  const exact = candidates.filter((candidate) => candidate.matchStatus === 'canonical_exact')
  const pending = candidates.filter((candidate) => candidate.matchStatus === 'pending_review')

  assert.equal(exact.length, 10)
  assert.equal(pending.length, 209)
  assert.equal(candidates.every((candidate) => candidate.sourceSha256 === sourceSha256), true)
  assert.equal(
    candidates.find((candidate) => candidate.name === 'Archer Push-up')?.matchedMovementId,
    'archer_push_up',
  )
  assert.equal(
    candidates.find((candidate) => candidate.name === 'Archer Pull-up')?.matchedMovementId,
    null,
    'a similar name must not be promoted as an alias',
  )
  assert.equal(
    pending.every((candidate) => candidate.matchedMovementId === null),
    true,
  )
})

test('database tags use one deterministic lowercase vocabulary', () => {
  assert.equal(normalizeTag('Kettlebell Sport'), 'kettlebell_sport')
  assert.equal(normalizeTag('Full-Body'), 'full_body')
  assert.equal(normalizeTag(' CrossFit '), 'crossfit')
})

test('duplicate source or canonical names stop the import instead of overwriting', () => {
  const row = parseExerciseImportCsv(readFileSync(importPath, 'utf8'))[0]
  assert.throws(
    () => buildReviewCandidates([row, { ...row, sourceRow: 3 }], [], sourceSha256),
    /duplicate source exercise name/i,
  )
  assert.throws(
    () => buildReviewCandidates([row], [
      { id: 'first', name: row.name },
      { id: 'second', name: row.name.toLocaleLowerCase('en-US') },
    ], sourceSha256),
    /duplicate canonical movement name/i,
  )
})

test('migration is generated from the audited rows and protects the review queue from clients', () => {
  const migrationPath = 'supabase/migrations/023_movement_import_review_queue.sql'
  assert.equal(existsSync(migrationPath), true, `${migrationPath} is missing`)
  if (!existsSync(migrationPath)) return

  const canonical = [
    ...MOVEMENTS
      .filter((movement) => movement.importSourceName == null && !movement.id.startsWith('steel_mace_'))
      .map(({ id, name }) => ({ id, name })),
    ...CARDIO_MODALITIES.map(({ id, name }) => ({ id, name })),
  ]
  const candidates = buildReviewCandidates(
    parseExerciseImportCsv(readFileSync(importPath, 'utf8')),
    canonical,
    sourceSha256,
  )
  const migration = readFileSync(migrationPath, 'utf8')
  assert.equal(migration, renderReviewMigration(candidates, {
    sourceFilename: 'exercise_extra_encyclopedia_with_sport_tags.csv',
    sourceSha256,
  }))
  assert.match(migration, /create table if not exists public\.movement_import_review_queue/i)
  assert.match(migration, /primary key \(source_sha256, source_row\)/i)
  assert.match(migration, /match_status in \('canonical_exact', 'pending_review'\)/i)
  assert.match(migration, /review_status in \('pending', 'approved', 'rejected'\)/i)
  assert.match(migration, /alter table public\.movement_import_review_queue enable row level security/i)
  assert.match(migration, /revoke all on table public\.movement_import_review_queue from public, anon, authenticated/i)
  assert.match(migration, /grant all on table public\.movement_import_review_queue to service_role/i)
  assert.doesNotMatch(migration, /create policy/i, 'client roles must have no review-queue policy')
  assert.match(migration, /where queue\.match_status = 'canonical_exact'/i)
  assert.match(migration, /from unnest\(verified_tags\.tags\) as candidate\(tag\)/i)
  assert.doesNotMatch(migration, /\bverified\.tags\b/i, 'the tag update must reference the declared CTE')
  assert.match(migration, /219 source rows: 10 exact canonical matches, 209 pending review/i)
})

test('exact matches keep verified tags and approved enrichments keep source provenance', () => {
  assert.deepEqual(
    MOVEMENT_BY_ID.get('kettlebell_clean')?.disciplines,
    ['crossfit', 'strength', 'kettlebell_sport'],
  )
  assert.deepEqual(
    MOVEMENT_BY_ID.get('bear_crawl')?.disciplines,
    ['calisthenics', 'hiit', 'conditioning', 'crossfit'],
  )
  assert.equal(MOVEMENT_BY_ID.get('archer_pull_up')?.importSourceName, 'Archer Pull-up')
  assert.deepEqual(
    MOVEMENT_BY_ID.get('archer_pull_up')?.disciplines,
    ['strength', 'calisthenics', 'street_workout'],
  )
  assert.ok((MOVEMENT_BY_ID.get('archer_pull_up')?.evidenceSourceIds.length ?? 0) > 0)
})
