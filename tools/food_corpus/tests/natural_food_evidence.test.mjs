import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import {
  buildNaturalFoodEvidence,
  canonicalizeNutrientEvidence,
  fingerprintMatches,
  normalizeReviewedCrosswalk,
  reviewedRejectionReport,
  stableJSONStringify,
  validateEvidenceBounds,
} from '../build_natural_food_evidence.mjs'

const fixtureDirectory = join(dirname(fileURLToPath(import.meta.url)), 'fixtures')
const targetFingerprint = { kcal_100: 32, protein_100: 0.67, carbs_100: 7.68, fat_100: 0.3 }
const targetFood = {
  id: 'fixture-target-strawberry',
  owner_user_id: null,
  name: 'Strawberries, fresh',
  brand: null,
  barcode: null,
  source: 'apex_cache',
  provider_product_id: 'apex-curated:fixture-strawberry',
  nutrition_basis: 'per_100g',
  preparation_state: 'as_sold',
  ...targetFingerprint,
  nutrient_evidence: [],
}
const reviewedCrosswalk = {
  schema_version: 1,
  approvals: [{
    category: 'fruit',
    target_id: targetFood.id,
    target_provider_product_id: targetFood.provider_product_id,
    target_name: targetFood.name,
    target_nutrition_basis: 'per_100g',
    target_preparation_state: 'as_sold',
    donor_id: 'fixture-donor-strawberry',
    donor_source_key: 'usda-sr-legacy',
    donor_source_record_id: 'fixture-167762',
    donor_name: 'Strawberries, raw',
  }],
}

function sha256(value) {
  return `sha256:${createHash('sha256').update(value).digest('hex')}`
}

async function makeStagedSource(t) {
  const directory = await mkdtemp(join(tmpdir(), 'apex-natural-food-evidence-'))
  t.after(() => rm(directory, { recursive: true, force: true }))
  const records = await readFile(join(fixtureDirectory, 'natural_food_records.ndjson'), 'utf8')
  const nutrients = await readFile(join(fixtureDirectory, 'natural_food_nutrients.ndjson'), 'utf8')
  await writeFile(join(directory, 'records.ndjson'), records)
  await writeFile(join(directory, 'nutrients.ndjson'), nutrients)
  const source = {
    key: 'usda-sr-legacy', dataset_name: 'Fixture Official Foods', publisher: 'Fixture Publisher',
    version: 'fixture-1', path: 'fixtures/official.zip', licence: 'CC0-1.0',
    licence_url: 'https://example.test/licence', attribution: 'Fixture official composition data.',
    checksum: 'sha256:fixture-upstream-artifact', parser: 'usda_fooddata_central_v1', status: 'approved',
  }
  const manifest = {
    artifact: 'official.zip', checksum_verified: true,
    file_checksums: { 'records.ndjson': sha256(records), 'nutrients.ndjson': sha256(nutrients) },
    schema_version: 1, source, state: 'validated',
  }
  await writeFile(join(directory, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`)
  return { directory, source }
}

async function readFixtureRows() {
  const text = await readFile(join(fixtureDirectory, 'natural_food_nutrients.ndjson'), 'utf8')
  return text.trim().split('\n').map((line) => JSON.parse(line))
}

test('bounded canonical projection preserves trace, below-detection, and missing instead of zero-filling', async () => {
  const evidence = canonicalizeNutrientEvidence(await readFixtureRows(), {
    sourceKey: 'usda-sr-legacy', sourceRecordId: 'fixture-167762', targetFingerprint,
  })

  assert.deepEqual(evidence.map((row) => row.nutrient_code), [
    'ENERC_KCAL', 'PROT', 'CHOAVL', 'FAT', 'VITC', 'VITB7', 'FE', 'I',
  ])
  assert.deepEqual(
    evidence.slice(4).map(({ nutrient_code, value_per_100, observation_status }) => ({ nutrient_code, value_per_100, observation_status })),
    [
      { nutrient_code: 'VITC', value_per_100: null, observation_status: 'trace' },
      { nutrient_code: 'VITB7', value_per_100: null, observation_status: 'missing' },
      { nutrient_code: 'FE', value_per_100: 0.41, observation_status: 'measured' },
      { nutrient_code: 'I', value_per_100: null, observation_status: 'below_detection' },
    ],
  )
  assert.equal(evidence.some((row) => row.name === 'Outside bounded projection'), false)
})

test('Foundation energy chooses the explicit method nearest the reviewed target independent of row order', () => {
  const rows = [
    { source_nutrient_code: '2048', original_nutrient_name: 'Energy (Atwater Specific Factors)', value: 112.20227, unit: 'KCAL', observation_status: 'measured', original_value_text: '112.20227', derivation_method: null, source_reference: 'specific' },
    { source_nutrient_code: '2047', original_nutrient_name: 'Energy (Atwater General Factors)', value: 106.034, unit: 'KCAL', observation_status: 'measured', original_value_text: '106.034', derivation_method: null, source_reference: 'general' },
  ]
  const options = {
    sourceKey: 'usda-foundation', sourceRecordId: '2646170',
    targetFingerprint: { kcal_100: 106, protein_100: 22.5, carbs_100: 0, fat_100: 1.93 },
  }
  for (const input of [rows, rows.toReversed()]) {
    const energy = canonicalizeNutrientEvidence(input, options)[0]
    assert.equal(energy.nutrient_code, 'ENERC_KCAL')
    assert.equal(energy.value_per_100, 106.034)
    assert.equal(energy.source_reference, 'general')
  }
})

test('generator fingerprint gates are inclusive and independently reject drift', () => {
  const target = { kcal_100: 100, protein_100: 10, carbs_100: 10, fat_100: 10 }
  assert.equal(fingerprintMatches(target, { kcal_100: 105, protein_100: 10.5, carbs_100: 10.5, fat_100: 10.5 }), true)
  assert.equal(fingerprintMatches(target, { kcal_100: 105.000001, protein_100: 10, carbs_100: 10, fat_100: 10 }), false)
  assert.equal(fingerprintMatches(target, { kcal_100: 100, protein_100: 10.500001, carbs_100: 10, fat_100: 10 }), false)
  assert.equal(fingerprintMatches(target, { kcal_100: 100, protein_100: 10, carbs_100: null, fat_100: 10 }), false)
})

test('checksum-verified build emits one whole donor with exact target and corpus aliases', async (t) => {
  const { directory, source } = await makeStagedSource(t)
  const result = await buildNaturalFoodEvidence({
    crosswalk: reviewedCrosswalk,
    catalogue: [targetFood],
    sourceDirectories: { 'usda-sr-legacy': directory },
    sourceRegistry: [source],
  })

  assert.equal(result.bundle.targets.length, 1)
  const entry = result.bundle.targets[0]
  assert.deepEqual(entry.aliases.map(({ kind, id, provider_product_id }) => ({ kind, id, provider_product_id })), [
    { kind: 'target', id: targetFood.id, provider_product_id: targetFood.provider_product_id },
    { kind: 'donor', id: 'fixture-donor-strawberry', provider_product_id: 'corpus:usda-sr-legacy:fixture-167762' },
  ])
  assert.equal(new Set(entry.evidence.map((row) => row.source_key)).size, 1)
  assert.equal(entry.evidence.every((row) => row.source_key === 'usda-sr-legacy' && row.source_reference), true)
  assert.equal(entry.evidence.some((row) => row.nutrient_code === 'VITC'), true)
  assert.deepEqual(result.summary.category_counts, { fruit: 1 })
})

test('build fails closed on checksum, target preparation, and macro drift', async (t) => {
  await t.test('checksum', async (t) => {
    const { directory, source } = await makeStagedSource(t)
    await writeFile(join(directory, 'nutrients.ndjson'), '{}\n', { flag: 'a' })
    await assert.rejects(
      buildNaturalFoodEvidence({ crosswalk: reviewedCrosswalk, catalogue: [targetFood], sourceDirectories: { 'usda-sr-legacy': directory }, sourceRegistry: [source] }),
      /checksum/i,
    )
  })
  await t.test('preparation', async (t) => {
    const { directory, source } = await makeStagedSource(t)
    await assert.rejects(
      buildNaturalFoodEvidence({ crosswalk: reviewedCrosswalk, catalogue: [{ ...targetFood, preparation_state: 'cooked' }], sourceDirectories: { 'usda-sr-legacy': directory }, sourceRegistry: [source] }),
      /preparation/i,
    )
  })
  await t.test('macro', async (t) => {
    const { directory, source } = await makeStagedSource(t)
    await assert.rejects(
      buildNaturalFoodEvidence({ crosswalk: reviewedCrosswalk, catalogue: [{ ...targetFood, carbs_100: 20 }], sourceDirectories: { 'usda-sr-legacy': directory }, sourceRegistry: [source] }),
      /fingerprint|macro/i,
    )
  })
})

test('reviewed donor names tolerate case-only report formatting but reject a near-neighbour description', async (t) => {
  const { directory, source } = await makeStagedSource(t)
  const caseOnly = structuredClone(reviewedCrosswalk)
  caseOnly.approvals[0].donor_name = 'Strawberries, Raw'
  const accepted = await buildNaturalFoodEvidence({
    crosswalk: caseOnly, catalogue: [targetFood],
    sourceDirectories: { 'usda-sr-legacy': directory }, sourceRegistry: [source],
  })
  assert.equal(accepted.bundle.targets.length, 1)

  const nearNeighbour = structuredClone(reviewedCrosswalk)
  nearNeighbour.approvals[0].donor_name = 'Strawberries, raw, frozen'
  await assert.rejects(
    buildNaturalFoodEvidence({
      crosswalk: nearNeighbour, catalogue: [targetFood],
      sourceDirectories: { 'usda-sr-legacy': directory }, sourceRegistry: [source],
    }),
    /donor name/i,
  )
})

test('serialization and generated content are deterministic', async (t) => {
  const { directory, source } = await makeStagedSource(t)
  const options = {
    crosswalk: reviewedCrosswalk, catalogue: [targetFood],
    sourceDirectories: { 'usda-sr-legacy': directory }, sourceRegistry: [source],
  }
  const first = await buildNaturalFoodEvidence(options)
  const second = await buildNaturalFoodEvidence(options)
  assert.equal(stableJSONStringify(first.bundle), stableJSONStringify(second.bundle))
  assert.equal(stableJSONStringify(first.summary), stableJSONStringify(second.summary))
})

test('record caps reject count and serialized-byte overflow', () => {
  const row = {
    nutrient_code: 'X', name: 'x', value_per_100: 1, unit: 'g', observation_status: 'measured',
    original_value_text: '1', derivation_method: null, source_key: 'fixture', source_reference: 'fixture:1',
  }
  assert.throws(() => validateEvidenceBounds(Array.from({ length: 97 }, () => row)), /96/)
  assert.throws(() => validateEvidenceBounds([{ ...row, original_value_text: 'x'.repeat(66_000) }]), /65,536/)
})

test('three reviewed reports normalize to 111 unique approvals and all nine categories', async () => {
  const reviewDirectory = resolve(fixtureDirectory, '..', '..', '..', '..', '.superpowers', 'sdd', '2026-09-01-natural-food-micronutrient-enrichment')
  const crosswalk = await normalizeReviewedCrosswalk(reviewDirectory)
  assert.equal(crosswalk.approvals.length, 111)
  assert.equal(new Set(crosswalk.approvals.map((row) => `${row.target_id}\u0000${row.target_provider_product_id}`)).size, 111)
  assert.deepEqual([...new Set(crosswalk.approvals.map((row) => row.category))].sort(), [
    'egg', 'fish_shellfish', 'fruit', 'grain_starch', 'legume',
    'meat_poultry', 'nut_seed', 'plain_dairy', 'vegetable_leaf',
  ])
  assert.equal(crosswalk.approvals.find((row) => row.target_id.endsWith('000046'))?.donor_source_record_id, '167762')
  assert.equal(crosswalk.approvals.find((row) => row.target_id.endsWith('000001'))?.donor_source_key, 'dk-frida')
  assert.equal(crosswalk.approvals.find((row) => row.target_id.endsWith('000006'))?.review_sources.length, 2)
})

test('reviewed rejection report keeps the named ambiguity and exactness boundaries explicit', () => {
  const report = reviewedRejectionReport()
  assert.equal(report.rejections.some((row) => row.target_id.endsWith('000002') && row.reason_code === 'ambiguous_identity'), true)
  assert.equal(report.rejections.some((row) => row.target_name.includes('Sweet corn') && row.reason_code === 'ambiguous_identity'), true)
  assert.equal(report.rejections.some((row) => row.target_name.includes('Salmon fillet') && row.reason_code === 'species_mismatch'), true)
  assert.equal(report.rejections.some((row) => row.target_name.includes('Chicken breast, air fryer') && row.reason_code === 'preparation_mismatch'), true)
})
