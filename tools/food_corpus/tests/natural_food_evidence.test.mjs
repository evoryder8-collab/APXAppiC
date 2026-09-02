import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import {
  buildNaturalFoodEvidence,
  canonicalNutrientCodeForSource,
  canonicalizeEvidenceUnit,
  canonicalizeNutrientEvidence,
  fingerprintMatches,
  normalizeReviewedCrosswalk,
  reviewedRejectionReport,
  stableJSONStringify,
  validateEvidenceBounds,
} from '../build_natural_food_evidence.mjs'
import {
  expandedReviewedNutrientIdentityCases,
  REVIEWED_NUTRIENT_IDENTITY_CASES,
} from './reviewed_nutrient_identity_cases.mjs'

const fixtureDirectory = join(dirname(fileURLToPath(import.meta.url)), 'fixtures')
const repositoryRoot = resolve(fixtureDirectory, '..', '..', '..', '..')
const committedReviewDirectory = join(repositoryRoot, 'docs', 'food-corpus', 'natural-food-evidence-review')
const committedSourceRegistry = join(repositoryRoot, 'tools', 'food_corpus', 'sources.json')
const committedEvidenceBundle = join(repositoryRoot, 'shared', 'natural-food-evidence.json')
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
    reviewed_macro_delta: { kcal_100: 0, protein_100: 0, carbs_100: 0, fat_100: 0 },
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

test('reviewed nutrient identities are source-key aware and unknown codes stay unchanged', () => {
  const expanded = expandedReviewedNutrientIdentityCases()
  assert.equal(expanded.length, 155)
  assert.equal(new Set(expanded.map(({ sourceKey, sourceCode }) => `${sourceKey}:${sourceCode}`)).size, 155)
  assert.deepEqual(
    expanded.reduce((counts, { sourceKey }) => ({ ...counts, [sourceKey]: (counts[sourceKey] ?? 0) + 1 }), {}),
    { 'usda-sr-legacy': 56, 'usda-foundation': 55, 'dk-frida': 44 },
  )
  for (const { code, usda = [], srLegacy = [], frida = [] } of REVIEWED_NUTRIENT_IDENTITY_CASES) {
    for (const sourceCode of usda) {
      assert.equal(canonicalNutrientCodeForSource('usda-sr-legacy', sourceCode), code)
      assert.equal(canonicalNutrientCodeForSource('usda-foundation', sourceCode), code)
    }
    for (const sourceCode of srLegacy) {
      assert.equal(canonicalNutrientCodeForSource('usda-sr-legacy', sourceCode), code)
    }
    for (const sourceCode of frida) {
      assert.equal(canonicalNutrientCodeForSource('dk-frida', sourceCode), code)
    }
  }

  assert.equal(canonicalNutrientCodeForSource('usda-sr-legacy', '999999'), '999999')
  assert.equal(canonicalNutrientCodeForSource('usda-foundation', '1406'), '1406')
  assert.equal(canonicalNutrientCodeForSource('dk-frida', '1162'), '1162')
  assert.equal(canonicalNutrientCodeForSource('unrelated-source', '1162'), '1162')

  assert.equal(canonicalizeEvidenceUnit('UG', {
    canonicalCode: 'VITA', sourceKey: 'usda-sr-legacy', sourceNutrientCode: '1106',
  }), 'µg RAE')
  assert.equal(canonicalizeEvidenceUnit('RE (µg/100g)', {
    canonicalCode: 'VITA', sourceKey: 'dk-frida', sourceNutrientCode: '12',
  }), 'µg RE')
  assert.equal(canonicalizeEvidenceUnit('UG', {
    canonicalCode: 'VITA', sourceKey: 'unrelated-source', sourceNutrientCode: '1106',
  }), 'µg')
})

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

test('generation canonicalizes compatible source units while preserving equivalent semantics', () => {
  const rows = [
    ['1008', 'Energy', 'KCAL'],
    ['1003', 'Protein', 'G'],
    ['1005', 'Carbohydrate', 'g'],
    ['1004', 'Total lipid', 'g per 100g'],
    ['1087', 'Calcium', 'MG'],
    ['1089', 'Iron', 'mg'],
    ['1090', 'Magnesium', 'mg per 100g'],
    ['1176', 'Biotin', 'UG'],
    ['1177', 'Folate', 'µg'],
    ['1178', 'Vitamin B-12', 'µg per 100g'],
    ['1106', 'Vitamin A, RAE', 'UG'],
  ].map(([source_nutrient_code, original_nutrient_name, unit]) => ({
    source_nutrient_code,
    original_nutrient_name,
    value: 1,
    unit,
    observation_status: 'measured',
    original_value_text: `1 ${unit}`,
    derivation_method: null,
    source_reference: `fixture:${source_nutrient_code}`,
  }))

  const evidence = canonicalizeNutrientEvidence(rows, {
    sourceKey: 'usda-sr-legacy', sourceRecordId: 'fixture-units', targetFingerprint,
  })
  const units = Object.fromEntries(evidence.map((row) => [row.nutrient_code, row.unit]))

  assert.equal(units.ENERC_KCAL, 'kcal')
  assert.deepEqual(
    [units.PROT, units.CHOAVL, units.FAT, units.CA, units.FE, units.MG],
    ['g', 'g', 'g', 'mg', 'mg', 'mg'],
  )
  assert.deepEqual([units.VITB7, units.VITB9, units.VITB12], ['µg', 'µg', 'µg'])
  assert.equal(units.VITA, 'µg RAE')
})

test('generation removes source basis syntax without erasing vitamin-equivalent semantics', () => {
  const fridaRows = [
    ['356', 'Energy (kcal)', 'kcal/100 g'],
    ['12', 'Vitamin A', 'RE (µg/100g)'],
    ['135', 'Vitamin E', 'alfa-TE'],
  ].map(([source_nutrient_code, original_nutrient_name, unit]) => ({
    source_nutrient_code,
    original_nutrient_name,
    value: 1,
    unit,
    observation_status: 'measured',
    original_value_text: `1 ${unit}`,
    derivation_method: null,
    source_reference: `fixture:${source_nutrient_code}`,
  }))

  const frida = canonicalizeNutrientEvidence(fridaRows, {
    sourceKey: 'dk-frida', sourceRecordId: 'fixture-frida-units', targetFingerprint,
  })
  const fridaUnits = Object.fromEntries(frida.map((row) => [row.nutrient_code, row.unit]))
  assert.deepEqual(fridaUnits, {
    ENERC_KCAL: 'kcal',
    VITA: 'µg RE',
    VITE: 'mg α-TE',
  })

  const iu = canonicalizeNutrientEvidence([{
    source_nutrient_code: '1104',
    original_nutrient_name: 'Vitamin A, IU',
    value: 54,
    unit: 'IU',
    observation_status: 'measured',
    original_value_text: '54 IU',
    derivation_method: null,
    source_reference: 'fixture:1104',
  }], {
    sourceKey: 'usda-sr-legacy', sourceRecordId: 'fixture-iu', targetFingerprint,
  })
  assert.equal(iu[0]?.unit, 'IU')
})

test('Foundation energy preserves the reviewed method and delta independent of row order', () => {
  const rows = [
    { source_nutrient_code: '2048', original_nutrient_name: 'Energy (Atwater Specific Factors)', value: 16, unit: 'KCAL', observation_status: 'measured', original_value_text: '16', derivation_method: null, source_reference: 'specific' },
    { source_nutrient_code: '2047', original_nutrient_name: 'Energy (Atwater General Factors)', value: 19, unit: 'KCAL', observation_status: 'measured', original_value_text: '19', derivation_method: null, source_reference: 'general' },
  ]
  const options = {
    sourceKey: 'usda-foundation', sourceRecordId: '2685568',
    targetFingerprint: { kcal_100: 17, protein_100: 1.21, carbs_100: 3.11, fat_100: 0.32 },
    reviewedMacroDelta: { kcal_100: 2, protein_100: -0.226, carbs_100: 0.16, fat_100: -0.115 },
  }
  for (const input of [rows, rows.toReversed()]) {
    const energy = canonicalizeNutrientEvidence(input, options)[0]
    assert.equal(energy.nutrient_code, 'ENERC_KCAL')
    assert.equal(energy.value_per_100, 19)
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
  await t.test('reviewed macro delta', async (t) => {
    const { directory, source } = await makeStagedSource(t)
    const changedReview = structuredClone(reviewedCrosswalk)
    changedReview.approvals[0].reviewed_macro_delta.kcal_100 = 1
    await assert.rejects(
      buildNaturalFoodEvidence({ crosswalk: changedReview, catalogue: [targetFood], sourceDirectories: { 'usda-sr-legacy': directory }, sourceRegistry: [source] }),
      /reviewed macro delta/i,
    )
  })
  await t.test('artifact label paired with registry checksum', async (t) => {
    const { directory, source } = await makeStagedSource(t)
    const manifestPath = join(directory, 'manifest.json')
    const manifest = JSON.parse(await readFile(manifestPath, 'utf8'))
    manifest.artifact = 'different-official.zip'
    await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`)
    await assert.rejects(
      buildNaturalFoodEvidence({ crosswalk: reviewedCrosswalk, catalogue: [targetFood], sourceDirectories: { 'usda-sr-legacy': directory }, sourceRegistry: [source] }),
      /artifact/i,
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

test('generator evidence values fail closed outside the inclusive numeric domain', () => {
  const row = {
    nutrient_code: 'X', name: 'x', value_per_100: 0, unit: 'g', observation_status: 'measured',
    original_value_text: '0', derivation_method: null, source_key: 'fixture', source_reference: 'fixture:1',
  }
  assert.doesNotThrow(() => validateEvidenceBounds([{ ...row, value_per_100: 0 }]))
  assert.doesNotThrow(() => validateEvidenceBounds([{ ...row, value_per_100: 1_000_000_000_000 }]))
  assert.throws(() => validateEvidenceBounds([{ ...row, value_per_100: -1 }]), /value|range/i)
  assert.throws(() => validateEvidenceBounds([{ ...row, value_per_100: 1_000_000_000_001 }]), /value|range/i)
})

test('committed review inputs normalize to 111 unique approvals and all nine categories', async () => {
  const crosswalk = await normalizeReviewedCrosswalk(committedReviewDirectory)
  assert.equal(crosswalk.approvals.length, 111)
  assert.equal(new Set(crosswalk.approvals.map((row) => `${row.target_id}\u0000${row.target_provider_product_id}`)).size, 111)
  assert.deepEqual([...new Set(crosswalk.approvals.map((row) => row.category))].sort(), [
    'egg', 'fish_shellfish', 'fruit', 'grain_starch', 'legume',
    'meat_poultry', 'nut_seed', 'plain_dairy', 'vegetable_leaf',
  ])
  assert.equal(crosswalk.approvals.find((row) => row.target_id.endsWith('000046'))?.donor_source_record_id, '167762')
  assert.equal(crosswalk.approvals.find((row) => row.target_id.endsWith('000001'))?.donor_source_key, 'dk-frida')
  assert.equal(crosswalk.approvals.find((row) => row.target_id.endsWith('000006'))?.review_sources.length, 2)
  assert.deepEqual(crosswalk.approvals.find((row) => row.target_id.endsWith('000013'))?.reviewed_macro_delta, {
    kcal_100: 0.034, protein_100: 0.025, carbs_100: 0, fat_100: 0.004,
  })
})

test('Frida attribution uses the actual CC BY 4.0 licence destination everywhere it ships', async () => {
  const sources = JSON.parse(await readFile(committedSourceRegistry, 'utf8'))
  const bundle = JSON.parse(await readFile(committedEvidenceBundle, 'utf8'))
  const expectedLicence = 'https://creativecommons.org/licenses/by/4.0/'
  const expectedAttribution = 'Marija Langwagen, Jette Jakobsen and Anders Poulsen: The Danish Food Composition Database, version 6.1, May 2026, National Food Institute, Technical University of Denmark.'

  const registrySource = sources.find((source) => source.key === 'dk-frida')
  const bundledSource = bundle.sources.find((source) => source.key === 'dk-frida')
  assert.equal(registrySource?.licence_url, expectedLicence)
  assert.equal(bundledSource?.licence_url, expectedLicence)
  assert.equal(registrySource?.attribution, expectedAttribution)
  assert.equal(bundledSource?.attribution, expectedAttribution)
})

test('committed evidence uses canonical display units without repeating its per-100 basis', async () => {
  const bundle = JSON.parse(await readFile(committedEvidenceBundle, 'utf8'))
  const rows = bundle.targets.flatMap((target) => target.evidence)
  const units = new Set(rows.map((row) => row.unit))

  assert.deepEqual([...units].sort(), [
    'IU', 'g', 'kcal', 'mg', 'mg α-TE', 'µg', 'µg RAE', 'µg RE',
  ])
  assert.equal(rows.some((row) => /(?:per|\/)\s*100/i.test(row.unit)), false)
  assert.equal(rows.some((row) => /alfa|\bRE\s*\(/i.test(row.unit)), false)
})

test('rejection report is derived from the supplied committed review data', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'apex-natural-food-rejections-'))
  t.after(() => rm(directory, { recursive: true, force: true }))
  await writeFile(join(directory, 'rejections.tsv'), [
    'target_id\ttarget_name\tcategory\treason_code\treason',
    'fixture-rejected-rice\tWhite rice, dry\tgrain_starch\tambiguous_identity\tTwo reviewed donors remain plausible.',
    'fixture-rejected-salmon\tSalmon fillet, raw\tfish_shellfish\tspecies_mismatch\tThe reviewed donor is species-specific.',
    '',
  ].join('\n'))

  const report = await reviewedRejectionReport(directory)
  assert.deepEqual(report.review_sources, ['rejections.tsv'])
  assert.equal(report.rejections.length, 2)
  assert.deepEqual(report.rejections.map(({ target_id, reason_code }) => ({ target_id, reason_code })), [
    { target_id: 'fixture-rejected-rice', reason_code: 'ambiguous_identity' },
    { target_id: 'fixture-rejected-salmon', reason_code: 'species_mismatch' },
  ])
})

test('committed rejection review keeps the named ambiguity and exactness boundaries explicit', async () => {
  const report = await reviewedRejectionReport(committedReviewDirectory)
  assert.equal(report.rejections.length, 26)
  assert.equal(report.rejections.some((row) => row.target_id.endsWith('000002') && row.reason_code === 'ambiguous_identity'), true)
  assert.equal(report.rejections.some((row) => row.target_name.includes('Sweet corn') && row.reason_code === 'ambiguous_identity'), true)
  assert.equal(report.rejections.some((row) => row.target_name.includes('Salmon fillet') && row.reason_code === 'species_mismatch'), true)
  assert.equal(report.rejections.some((row) => row.target_name.includes('Chicken breast, air fryer') && row.reason_code === 'preparation_mismatch'), true)
})
