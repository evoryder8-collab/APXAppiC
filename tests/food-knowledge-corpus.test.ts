import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import test from 'node:test'

const migrationPath = new URL(
  '../supabase/migrations/034_food_knowledge_corpus.sql',
  import.meta.url,
)
const registryPath = new URL('../tools/food_corpus/sources.json', import.meta.url)
const parserPath = new URL('../tools/food_corpus/import_food_corpus.py', import.meta.url)
const fixturePath = new URL(
  './fixtures/food-corpus/evidence-values.json',
  import.meta.url,
)

test('Food Knowledge Corpus schema is additive, evidence-preserving, and searchable', () => {
  assert.equal(existsSync(migrationPath), true, 'migration 034 must exist')
  const migration = readFileSync(migrationPath, 'utf8')

  for (const table of [
    'food_corpus_sources',
    'food_corpus_batches',
    'food_corpus_records',
    'food_corpus_names',
    'food_corpus_nutrients',
    'food_corpus_search',
  ]) {
    assert.match(migration, new RegExp(`create table if not exists public\\.${table}`, 'i'))
  }

  assert.match(migration, /observation_status[\s\S]*?'trace'[\s\S]*?'not_measured'[\s\S]*?'missing'/i)
  assert.match(migration, /basis_kind[\s\S]*?'per_100g'[\s\S]*?'per_100ml'/i)
  assert.match(migration, /original_value_text text/i)
  assert.match(migration, /source_record_id text not null/i)
  assert.match(migration, /unique\s*\(source_key,\s*source_record_id\)/i)
  assert.match(migration, /enable row level security/i)
  assert.match(migration, /food_corpus_search_catalog/i)
  assert.doesNotMatch(
    migration,
    /\b(?:drop\s+(?:table|column)|truncate\s+table|delete\s+from)\b/i,
  )
})

test('source registry gates every supplied database by licence and checksum', () => {
  assert.equal(existsSync(registryPath), true, 'source registry must exist')
  const sources = JSON.parse(readFileSync(registryPath, 'utf8')) as Array<{
    key: string
    licence: string
    attribution: string
    version: string
    checksum: string
    companions?: Array<{ path: string; checksum: string }>
    parser: string
    status: string
  }>

  const expected = [
    'usda-foundation',
    'usda-sr-legacy',
    'usda-fndds',
    'usda-branded',
    'swiss-fsvo',
    'uk-cofid',
    'fr-ciqual',
    'dk-frida',
    'jp-mext',
    'au-afcd',
    'se-livsmedelsverket',
    'ca-cnf',
    'no-matvaretabellen',
    'fi-fineli',
    'nz-concise',
    'fao-wafct',
    'fao-upulses',
    'fao-ufish',
    'fao-biofoodcomp',
    'open-food-facts',
  ]

  assert.deepEqual(
    expected.filter((key) => !sources.some((source) => source.key === key)),
    [],
  )
  for (const source of sources) {
    assert.ok(source.licence)
    assert.ok(source.attribution)
    assert.ok(source.version)
    assert.match(source.checksum, /^(?:sha256:[a-f0-9]{64}|pending-verification)$/)
    for (const companion of source.companions ?? []) {
      assert.ok(companion.path)
      assert.match(companion.checksum, /^sha256:[a-f0-9]{64}$/)
    }
    assert.ok(source.parser)
    assert.match(source.status, /^(?:approved|quarantined)$/)
  }

  assert.equal(
    sources.find((source) => source.key === 'open-food-facts')?.status,
    'quarantined',
    'ODbL data must not be blended into the permissively licensed corpus',
  )
  assert.equal(
    sources.find((source) => source.key === 'se-livsmedelsverket')?.companions?.length,
    1,
    'Swedish nutrient observations must be checksum-gated with their food rows',
  )
  assert.equal(
    sources.find((source) => source.key === 'ca-cnf')?.companions?.length,
    2,
    'Canadian nutrient observations and names must be checksum-gated with their food rows',
  )
  const importer = readFileSync(parserPath, 'utf8')
  assert.match(
    importer,
    /source\.get\(["']companions["'],\s*\[\]\)/,
    'registry validation and staging must enforce companion artifacts',
  )
})

test('canonical fixture parsing preserves trace, not-measured, missing, and basis semantics', () => {
  assert.equal(existsSync(parserPath), true, 'corpus importer must exist')
  assert.equal(existsSync(fixturePath), true, 'evidence fixture must exist')

  const result = spawnSync(
    'python3',
    [parserPath.pathname, 'parse-fixture', '--input', fixturePath.pathname],
    { encoding: 'utf8' },
  )
  assert.equal(result.status, 0, result.stderr)
  const records = result.stdout
    .trim()
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line))

  assert.equal(records.length, 2)
  assert.equal(records[0].basis.kind, 'per_100g')
  assert.equal(records[1].basis.kind, 'per_100ml')

  const nutrients = records.flatMap((record) => record.nutrients)
  assert.deepEqual(
    nutrients.map((nutrient) => [
      nutrient.observation_status,
      nutrient.value,
      nutrient.original_value_text,
    ]),
    [
      ['measured', 12.5, '12.5'],
      ['trace', null, 'tr'],
      ['not_measured', null, 'N'],
      ['missing', null, ''],
    ],
  )
  assert.equal(
    nutrients.some(
      (nutrient) =>
        nutrient.observation_status !== 'measured' && nutrient.value === 0,
    ),
    false,
  )
})

test('ingestion requires an external source root and external staging output', () => {
  const parser = readFileSync(parserPath, 'utf8')
  assert.match(parser, /--source-root/)
  assert.match(parser, /--output/)
  assert.match(parser, /assert_external_path/)
  assert.match(parser, /APEX_FOOD_CORPUS_SOURCE_ROOT/)
  assert.doesNotMatch(parser, /Downloads\/Food Facts for CB App/)
})

test('every approved source has a deterministic parser adapter', () => {
  const sources = JSON.parse(readFileSync(registryPath, 'utf8')) as Array<{
    parser: string
    status: string
  }>
  const expected = [
    ...new Set(
      sources
        .filter((source) => source.status === 'approved')
        .map((source) => source.parser),
    ),
  ].sort()
  const result = spawnSync('python3', [parserPath.pathname, 'list-parsers', '--json'], {
    encoding: 'utf8',
  })

  assert.equal(result.status, 0, result.stderr)
  const supported = JSON.parse(result.stdout) as string[]
  assert.deepEqual(expected.filter((parser) => !supported.includes(parser)), [])
})

test('staging emits canonical records and a bounded search projection, not a raw copy', () => {
  const parser = readFileSync(parserPath, 'utf8')
  assert.match(parser, /records\.ndjson/)
  assert.match(parser, /nutrients\.ndjson/)
  assert.match(parser, /search\.ndjson/)
  assert.match(parser, /source_priority/)
  assert.match(parser, /max_records/)
  assert.doesNotMatch(parser, /shutil\.copy|copyfile|copytree/)
})
