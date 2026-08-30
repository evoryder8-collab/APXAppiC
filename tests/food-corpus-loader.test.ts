import assert from 'node:assert/strict'
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs'
import { gunzipSync } from 'node:zlib'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import test from 'node:test'

const importerPath = new URL('../tools/food_corpus/import_food_corpus.py', import.meta.url)

test('validated staging emits one atomic, idempotent psql load outside the repository', () => {
  const temporaryRoot = mkdtempSync(join(tmpdir(), 'apex-food-corpus-loader-'))
  const stageDirectory = join(temporaryRoot, 'fixture-source')
  const outputPath = join(temporaryRoot, 'load.psql')
  const queryOutputDirectory = join(temporaryRoot, 'management-sql')
  const remoteOutputDirectory = join(temporaryRoot, 'remote-sql')
  const compactRemoteOutputDirectory = join(temporaryRoot, 'compact-remote-sql')
  mkdirSync(stageDirectory)

  const source = {
    source_key: 'fixture-source',
    dataset_name: 'Fixture source',
    publisher: 'APEX tests',
    version: '1',
    source_url: 'https://example.test/source',
    licence_id: 'CC0-1.0',
    licence_url: 'https://creativecommons.org/publicdomain/zero/1.0/',
    attribution: 'APEX deterministic fixture.',
    checksum_sha256: 'a'.repeat(64),
    parser_version: 'fixture_v1',
    redistribution_scope: 'permissive',
    ingest_status: 'registered',
    metadata: {},
  }
  const batch = {
    id: 'cf87d423-ad7c-506f-928b-1867ac050761',
    source_key: 'fixture-source',
    source_checksum_sha256: 'a'.repeat(64),
    parser_version: 'fixture_v1',
    status: 'validated',
    records_seen: 1,
    records_accepted: 1,
    records_rejected: 0,
    validation_report: {},
  }
  const record = {
    id: '716ed368-cabf-5a42-b17e-72a20a8397bf',
    source_key: 'fixture-source',
    source_record_id: 'one',
    batch_id: batch.id,
    canonical_name: "Food with apostrophe's evidence",
    scientific_name: null,
    brand: null,
    barcode: null,
    market: null,
    primary_language: 'en',
    basis_kind: 'per_100g',
    basis_amount: 100,
    basis_unit: 'g',
    preparation_state: null,
    edible_portion_percent: null,
    density_g_ml: null,
    source_priority: 20,
    source_metadata: {},
  }
  const name = {
    record_id: record.id,
    language: 'en',
    name: record.canonical_name,
    normalized_name: 'food with apostrophe s evidence',
    name_kind: 'canonical',
    market: null,
  }
  const nutrient = {
    record_id: record.id,
    nutrient_code: 'ENERC_KCAL',
    source_nutrient_code: '1008',
    original_nutrient_name: 'Energy',
    value: 123,
    unit: 'kcal',
    original_value_text: '123',
    observation_status: 'measured',
    derivation_method: null,
    source_reference: null,
  }
  const search = {
    record_id: record.id,
    source_key: 'fixture-source',
    source_record_id: 'one',
    name: record.canonical_name,
    names_i18n: { en: record.canonical_name },
    aliases: [],
    brand: null,
    barcode: null,
    market: null,
    basis_kind: 'per_100g',
    preparation_state: null,
    kcal: 123,
    protein_g: null,
    carbs_g: null,
    fat_g: null,
    fibre_g: null,
    sugar_g: null,
    saturated_fat_g: null,
    salt_g: null,
    water_g: null,
    source_priority: 20,
    search_text: 'food with apostrophe s evidence',
  }

  for (const [file, rows] of Object.entries({
    'sources.ndjson': [source],
    'batches.ndjson': [batch],
    'records.ndjson': [record],
    'names.ndjson': [name],
    'nutrients.ndjson': [nutrient],
    'search.ndjson': [search],
  })) {
    writeFileSync(join(stageDirectory, file), `${rows.map((row) => JSON.stringify(row)).join('\n')}\n`)
  }
  writeFileSync(
    join(stageDirectory, 'manifest.json'),
    JSON.stringify({
      schema_version: 1,
      state: 'validated',
      checksum_verified: true,
      batch_id: batch.id,
      source: { key: source.source_key },
      files: [
        'sources.ndjson',
        'batches.ndjson',
        'records.ndjson',
        'names.ndjson',
        'nutrients.ndjson',
        'search.ndjson',
      ],
    }),
  )

  try {
    const emitted = spawnSync(
      'python3',
      [
        importerPath.pathname,
        'emit-psql',
        '--stage-dir',
        stageDirectory,
        '--output',
        outputPath,
      ],
      { encoding: 'utf8' },
    )
    assert.equal(emitted.status, 0, emitted.stderr)
    const sql = readFileSync(outputPath, 'utf8')
    assert.match(sql, /\\set ON_ERROR_STOP on/)
    assert.match(sql, /begin;/i)
    assert.match(sql, /\\copy apex_food_corpus_sources_payload/i)
    assert.match(sql, /on conflict \(id\) do update/i)
    assert.match(sql, /status = 'retired'/i)
    assert.match(sql, /status = 'active'/i)
    assert.match(sql, /commit;/i)
    assert.doesNotMatch(sql, /\bdelete\s+from\s+public\b|\btruncate\s+public\b|\bdrop\s+table\s+public\b/i)
    assert.doesNotMatch(sql, /Food Facts for CB App|\/Users\/jaxoncorrey/)

    const queryEmission = spawnSync(
      'python3',
      [
        importerPath.pathname,
        'emit-query-sql',
        '--stage-dir',
        stageDirectory,
        '--output-dir',
        queryOutputDirectory,
        '--max-bytes',
        '4096',
      ],
      { encoding: 'utf8' },
    )
    assert.equal(queryEmission.status, 0, queryEmission.stderr)
    const queryFiles = readdirSync(queryOutputDirectory).filter((file) => file.endsWith('.sql'))
    assert.equal(queryFiles[0], '000-register.sql')
    assert.equal(queryFiles.at(-1), '999-activate.sql')
    for (const file of queryFiles) {
      assert.ok(statSync(join(queryOutputDirectory, file)).size < 16_384)
    }
    const activation = readFileSync(join(queryOutputDirectory, '999-activate.sql'), 'utf8')
    assert.match(activation, /raise exception/i)
    assert.match(activation, /status = 'retired'/i)
    assert.match(activation, /status = 'active'/i)
    assert.doesNotMatch(activation, /\bdelete\s+from\s+public\b|\btruncate\s+public\b/i)

    const remoteEmission = spawnSync(
      'python3',
      [
        importerPath.pathname,
        'emit-remote-sql',
        '--stage-dir',
        stageDirectory,
        '--output-dir',
        remoteOutputDirectory,
        '--base-url',
        'https://example.test/corpus-transfer',
        '--max-bytes',
        '4096',
      ],
      { encoding: 'utf8' },
    )
    assert.equal(remoteEmission.status, 0, remoteEmission.stderr)
    const remoteScripts = readdirSync(remoteOutputDirectory).filter((file) => file.endsWith('.sql'))
    assert.equal(remoteScripts[0], '000-register.sql')
    assert.equal(remoteScripts.at(-1), '999-activate.sql')
    const remoteRecords = readFileSync(join(remoteOutputDirectory, '010-records-00001.sql'), 'utf8')
    assert.match(remoteRecords, /extensions\.http_get/i)
    assert.match(remoteRecords, /extensions\.digest/i)
    assert.match(remoteRecords, /raise exception/i)
    assert.doesNotMatch(remoteRecords, /Food with apostrophe/)

    const compactRemoteEmission = spawnSync(
      'python3',
      [
        importerPath.pathname,
        'emit-remote-sql',
        '--stage-dir',
        stageDirectory,
        '--output-dir',
        compactRemoteOutputDirectory,
        '--base-url',
        'https://example.test/compact-corpus-transfer',
        '--max-bytes',
        '4096',
        '--compact-evidence',
      ],
      { encoding: 'utf8' },
    )
    assert.equal(compactRemoteEmission.status, 0, compactRemoteEmission.stderr)
    const compactScripts = readdirSync(compactRemoteOutputDirectory).filter((file) => file.endsWith('.sql'))
    assert.equal(compactScripts.some((file) => file.startsWith('030-nutrients')), false)
    const compactArchivePath = join(compactRemoteOutputDirectory, 'evidence', 'nutrients.ndjson.gz')
    assert.equal(
      gunzipSync(readFileSync(compactArchivePath)).toString('utf8'),
      readFileSync(join(stageDirectory, 'nutrients.ndjson'), 'utf8'),
    )
    const compactRegister = readFileSync(join(compactRemoteOutputDirectory, '000-register.sql'), 'utf8')
    assert.match(compactRegister, /food-corpus-evidence\/fixture-source\/cf87d423-ad7c-506f-928b-1867ac050761\/nutrients\.ndjson\.gz/)
    assert.match(compactRegister, /evidence_archive_sha256/)
    const compactActivation = readFileSync(join(compactRemoteOutputDirectory, '999-activate.sql'), 'utf8')
    assert.doesNotMatch(compactActivation, /food corpus nutrients count mismatch/i)
  } finally {
    rmSync(temporaryRoot, { recursive: true, force: true })
  }
})
