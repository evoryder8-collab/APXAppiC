#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { createReadStream } from 'node:fs'
import { readFile, writeFile } from 'node:fs/promises'
import { createInterface } from 'node:readline'
import { dirname, relative, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import process from 'node:process'

const MAX_EVIDENCE_ROWS = 96
const MAX_EVIDENCE_BYTES = 65_536
const FINGERPRINT_FIELDS = [
  ['kcal_100', 5, 0.03],
  ['protein_100', 0.5, 0.05],
  ['carbs_100', 0.5, 0.05],
  ['fat_100', 0.5, 0.05],
]
const RUNTIME_FINGERPRINT_FIELDS = [
  ['kcal_100', 1],
  ['protein_100', 0.05],
  ['carbs_100', 0.05],
  ['fat_100', 0.05],
]
const VALID_STATUSES = new Set([
  'measured', 'calculated', 'estimated', 'reported', 'trace',
  'below_detection', 'not_measured', 'missing',
])

const USDA_SOURCES = ['usda-sr-legacy', 'usda-foundation']
const USDA = (sourceCodes) => Object.fromEntries(USDA_SOURCES.map((key) => [key, sourceCodes]))

/*
 * This is the complete shipped projection and its explicit source-code
 * precedence. Source row order never participates in canonicalization.
 * Standard totals/forms precede alternate label, unit, or component rows.
 */
const NUTRIENT_PROJECTION = [
  { code: 'ENERC_KCAL', candidates: { ...USDA(['1008', '2047', '2048']), 'dk-frida': ['356', '359'] } },
  { code: 'PROT', candidates: { ...USDA(['1003']), 'dk-frida': ['218'] } },
  { code: 'CHOAVL', candidates: { ...USDA(['1005']), 'dk-frida': ['172'] } },
  { code: 'FIBT', candidates: { ...USDA(['1079']), 'dk-frida': ['168'] } },
  { code: 'SUGAR', candidates: { ...USDA(['2000']), 'dk-frida': ['245'] } },
  { code: 'STARCH', candidates: { ...USDA(['1009']), 'dk-frida': ['243'] } },
  { code: 'FAT', candidates: { ...USDA(['1004']), 'dk-frida': ['141'] } },
  { code: 'FASAT', candidates: { ...USDA(['1258']), 'dk-frida': ['248'] } },
  { code: 'FATRN', candidates: { ...USDA(['1257']), 'dk-frida': ['261'] } },
  { code: 'FAMS', candidates: { ...USDA(['1292']), 'dk-frida': ['247'] } },
  { code: 'FAPU', candidates: { ...USDA(['1293']), 'dk-frida': ['251'] } },
  { code: 'OMEGA3', candidates: { 'dk-frida': ['249'] } },
  { code: 'OMEGA3_ALA', candidates: USDA(['1404', '1270']) },
  { code: 'OMEGA3_EPA', candidates: USDA(['1278']) },
  { code: 'OMEGA3_DPA', candidates: USDA(['1280']) },
  { code: 'OMEGA3_DHA', candidates: USDA(['1272']) },
  { code: 'OMEGA6', candidates: { 'dk-frida': ['250'] } },
  { code: 'OMEGA6_LA', candidates: USDA(['1316', '1269']) },
  { code: 'OMEGA6_GLA', candidates: USDA(['1321']) },
  { code: 'OMEGA6_AA', candidates: USDA(['1406']) },
  { code: 'CHOLE', candidates: { ...USDA(['1253']), 'dk-frida': ['115'] } },
  { code: 'NA', candidates: { ...USDA(['1093']), 'dk-frida': ['201'] } },
  { code: 'NACL', candidates: { 'dk-frida': ['327'] } },
  { code: 'WATER', candidates: { ...USDA(['1051']), 'dk-frida': ['268'] } },
  { code: 'VITA', candidates: { ...USDA(['1106', '1104']), 'dk-frida': ['12'] } },
  { code: 'VITC', candidates: { ...USDA(['1162']), 'dk-frida': ['47'] } },
  { code: 'VITD', candidates: { ...USDA(['1114', '1112', '1110']), 'dk-frida': ['126'] } },
  { code: 'VITE', candidates: { ...USDA(['1109']), 'dk-frida': ['135'] } },
  { code: 'VITK', candidates: { ...USDA(['1185', '1183', '1184']), 'dk-frida': ['442', '164'] } },
  { code: 'VITB1', candidates: { ...USDA(['1165']), 'dk-frida': ['37', '36'] } },
  { code: 'VITB2', candidates: { ...USDA(['1166']), 'dk-frida': ['39'] } },
  { code: 'VITB3', candidates: { ...USDA(['1167']), 'dk-frida': ['294'] } },
  { code: 'VITB5', candidates: { ...USDA(['1170']), 'dk-frida': ['210'] } },
  { code: 'VITB6', candidates: { ...USDA(['1175']), 'dk-frida': ['40'] } },
  { code: 'VITB7', candidates: { ...USDA(['1176']), 'dk-frida': ['42'] } },
  { code: 'VITB9', candidates: { ...USDA(['1177', '1190', '1187']), 'dk-frida': ['143'] } },
  { code: 'VITB12', candidates: { ...USDA(['1178']), 'dk-frida': ['38'] } },
  { code: 'CARTB', candidates: { ...USDA(['1107']), 'dk-frida': ['303'] } },
  { code: 'CA', candidates: { ...USDA(['1087']), 'dk-frida': ['108'] } },
  { code: 'FE', candidates: { ...USDA(['1089']), 'dk-frida': ['162'] } },
  { code: 'MG', candidates: { ...USDA(['1090']), 'dk-frida': ['184'] } },
  { code: 'P', candidates: { ...USDA(['1091']), 'dk-frida': ['214'] } },
  { code: 'K', candidates: { ...USDA(['1092']), 'dk-frida': ['165'] } },
  { code: 'ZN', candidates: { ...USDA(['1095']), 'dk-frida': ['274'] } },
  { code: 'CU', candidates: { ...USDA(['1098']), 'dk-frida': ['166'] } },
  { code: 'MN', candidates: { ...USDA(['1101']), 'dk-frida': ['187'] } },
  { code: 'SE', candidates: { ...USDA(['1103']), 'dk-frida': ['230'] } },
  { code: 'I', candidates: { ...USDA(['1100']), 'dk-frida': ['163'] } },
]

function isFiniteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value)
}

function canonicalObject(value) {
  if (Array.isArray(value)) return value.map(canonicalObject)
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalObject(value[key])]))
  }
  return value
}

export function stableJSONStringify(value) {
  return `${JSON.stringify(canonicalObject(value), null, 2)}\n`
}

function fingerprintFromFood(food) {
  return Object.fromEntries(FINGERPRINT_FIELDS.map(([field]) => [field, food[field]]))
}

function assertFiniteFingerprint(fingerprint, label) {
  for (const [field] of FINGERPRINT_FIELDS) {
    if (!isFiniteNumber(fingerprint[field])) throw new Error(`${label} macro fingerprint has non-finite ${field}`)
  }
}

export function fingerprintMatches(target, donor) {
  return FINGERPRINT_FIELDS.every(([field, absoluteTolerance, relativeTolerance]) => {
    const targetValue = target[field]
    const donorValue = donor[field]
    return isFiniteNumber(targetValue)
      && isFiniteNumber(donorValue)
      && Math.abs(targetValue - donorValue) <= Math.max(absoluteTolerance, Math.abs(targetValue) * relativeTolerance)
  })
}

export function runtimeFingerprintMatches(reviewed, candidate) {
  return RUNTIME_FINGERPRINT_FIELDS.every(([field, absoluteTolerance]) => {
    const reviewedValue = reviewed[field]
    const candidateValue = candidate[field]
    return isFiniteNumber(reviewedValue)
      && isFiniteNumber(candidateValue)
      && Math.abs(reviewedValue - candidateValue) <= Math.max(absoluteTolerance, Math.abs(reviewedValue) * 0.02)
  })
}

function deterministicRow(rows, candidateCodes, canonicalCode, sourceKey, targetFingerprint) {
  const candidates = rows.filter((row) => candidateCodes.includes(String(row.source_nutrient_code)))
  if (candidates.length === 0) return null

  if (canonicalCode === 'ENERC_KCAL' && sourceKey === 'usda-foundation') {
    const targetEnergy = targetFingerprint.kcal_100
    const numeric = candidates.filter((row) => isFiniteNumber(row.value))
    if (numeric.length === 0) return candidates.toSorted((left, right) => (
      candidateCodes.indexOf(String(left.source_nutrient_code)) - candidateCodes.indexOf(String(right.source_nutrient_code))
      || String(left.source_reference ?? '').localeCompare(String(right.source_reference ?? ''))
    ))[0]
    return numeric.toSorted((left, right) => (
      Math.abs(left.value - targetEnergy) - Math.abs(right.value - targetEnergy)
      || candidateCodes.indexOf(String(left.source_nutrient_code)) - candidateCodes.indexOf(String(right.source_nutrient_code))
      || String(left.source_reference ?? '').localeCompare(String(right.source_reference ?? ''))
    ))[0]
  }

  const preferredCode = candidateCodes.find((code) => candidates.some((row) => String(row.source_nutrient_code) === code))
  const preferred = candidates.filter((row) => String(row.source_nutrient_code) === preferredCode)
  if (preferred.length === 1) return preferred[0]
  const signatures = new Set(preferred.map((row) => JSON.stringify([
    row.value, row.unit, row.observation_status, row.original_value_text, row.derivation_method,
  ])))
  if (signatures.size !== 1) {
    throw new Error(`Ambiguous ${sourceKey} ${canonicalCode} rows for source nutrient ${preferredCode}`)
  }
  return preferred.toSorted((left, right) => String(left.source_reference ?? '').localeCompare(String(right.source_reference ?? '')))[0]
}

function evidenceRow(row, canonicalCode, sourceKey, sourceRecordId) {
  if (!VALID_STATUSES.has(row.observation_status)) {
    throw new Error(`Unsupported observation status ${String(row.observation_status)} for ${sourceKey}:${sourceRecordId}`)
  }
  if (row.value !== null && !isFiniteNumber(row.value)) {
    throw new Error(`Non-finite nutrient value for ${sourceKey}:${sourceRecordId}:${row.source_nutrient_code}`)
  }
  if (typeof row.original_nutrient_name !== 'string' || !row.original_nutrient_name.trim()) {
    throw new Error(`Missing official nutrient name for ${sourceKey}:${sourceRecordId}:${row.source_nutrient_code}`)
  }
  if (typeof row.unit !== 'string' || !row.unit.trim()) {
    throw new Error(`Missing official nutrient unit for ${sourceKey}:${sourceRecordId}:${row.source_nutrient_code}`)
  }
  if (typeof row.original_value_text !== 'string') {
    throw new Error(`Missing official original text for ${sourceKey}:${sourceRecordId}:${row.source_nutrient_code}`)
  }
  const sourceReference = typeof row.source_reference === 'string' && row.source_reference.trim()
    ? row.source_reference
    : `corpus:${sourceKey}:${sourceRecordId}:nutrient:${row.source_nutrient_code}`
  return {
    nutrient_code: canonicalCode,
    name: row.original_nutrient_name,
    value_per_100: row.value,
    unit: row.unit,
    observation_status: row.observation_status,
    original_value_text: row.original_value_text,
    derivation_method: row.derivation_method ?? null,
    source_key: sourceKey,
    source_reference: sourceReference,
  }
}

export function canonicalizeNutrientEvidence(rows, { sourceKey, sourceRecordId, targetFingerprint }) {
  assertFiniteFingerprint(targetFingerprint, 'Reviewed target')
  const evidence = []
  for (const projection of NUTRIENT_PROJECTION) {
    const candidates = projection.candidates[sourceKey]
    if (!candidates) continue
    const row = deterministicRow(rows, candidates, projection.code, sourceKey, targetFingerprint)
    if (row) evidence.push(evidenceRow(row, projection.code, sourceKey, sourceRecordId))
  }
  validateEvidenceBounds(evidence)
  return evidence
}

export function validateEvidenceBounds(evidence) {
  if (evidence.length > MAX_EVIDENCE_ROWS) {
    throw new Error(`Evidence array exceeds the 96-row cap (${evidence.length})`)
  }
  const bytes = Buffer.byteLength(JSON.stringify(evidence), 'utf8')
  if (bytes > MAX_EVIDENCE_BYTES) {
    throw new Error(`Evidence array exceeds the 65,536-byte cap (${bytes})`)
  }
}

function fingerprintFromEvidence(evidence, label) {
  const byCode = new Map(evidence.map((row) => [row.nutrient_code, row]))
  const fingerprint = {
    kcal_100: byCode.get('ENERC_KCAL')?.value_per_100,
    protein_100: byCode.get('PROT')?.value_per_100,
    carbs_100: byCode.get('CHOAVL')?.value_per_100,
    fat_100: byCode.get('FAT')?.value_per_100,
  }
  assertFiniteFingerprint(fingerprint, label)
  return fingerprint
}

async function hashFile(path) {
  const hash = createHash('sha256')
  for await (const chunk of createReadStream(path)) hash.update(chunk)
  return `sha256:${hash.digest('hex')}`
}

function requireEqual(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label} mismatch: expected ${String(expected)}, received ${String(actual)}`)
}

function normalizedReviewedName(value) {
  return String(value).normalize('NFKC').trim().replace(/\s+/g, ' ').toLocaleLowerCase('en-US')
}

function requireReviewedName(actual, expected, label) {
  if (normalizedReviewedName(actual) !== normalizedReviewedName(expected)) {
    throw new Error(`${label} mismatch: expected ${String(expected)}, received ${String(actual)}`)
  }
}

async function verifyStagedSource(sourceKey, directory, sourceRegistry) {
  let manifest
  try {
    manifest = JSON.parse(await readFile(resolve(directory, 'manifest.json'), 'utf8'))
  } catch (error) {
    throw new Error(`Cannot read staged manifest for ${sourceKey}: ${error instanceof Error ? error.message : String(error)}`)
  }
  const registered = sourceRegistry.find((source) => source.key === sourceKey)
  if (!registered) throw new Error(`Source ${sourceKey} is absent from the approved registry`)
  requireEqual(registered.status, 'approved', `${sourceKey} registry status`)
  requireEqual(manifest.schema_version, 1, `${sourceKey} staged schema`)
  requireEqual(manifest.state, 'validated', `${sourceKey} staged state`)
  requireEqual(manifest.checksum_verified, true, `${sourceKey} checksum verification`)
  requireEqual(manifest.source?.key, sourceKey, `${sourceKey} source key`)
  for (const field of ['status', 'version', 'checksum', 'parser', 'dataset_name', 'publisher']) {
    requireEqual(manifest.source?.[field], registered[field], `${sourceKey} ${field}`)
  }
  for (const file of ['records.ndjson', 'nutrients.ndjson']) {
    const expected = manifest.file_checksums?.[file]
    if (typeof expected !== 'string' || !expected.startsWith('sha256:')) {
      throw new Error(`${sourceKey} manifest lacks a checksum for ${file}`)
    }
    const actual = await hashFile(resolve(directory, file))
    if (actual !== expected) throw new Error(`${sourceKey} checksum mismatch for ${file}: expected ${expected}, received ${actual}`)
  }
  return {
    artifact: manifest.artifact,
    artifact_sha256: registered.checksum,
    attribution: registered.attribution,
    dataset_name: registered.dataset_name,
    key: sourceKey,
    licence: registered.licence,
    licence_url: registered.licence_url,
    parser: registered.parser,
    publisher: registered.publisher,
    staged_file_sha256: {
      'nutrients.ndjson': manifest.file_checksums['nutrients.ndjson'],
      'records.ndjson': manifest.file_checksums['records.ndjson'],
    },
    version: registered.version,
  }
}

async function readFilteredNDJSON(path, wantedRecordIDs, kind) {
  const rows = []
  const input = createReadStream(path, { encoding: 'utf8' })
  const lines = createInterface({ input, crlfDelay: Infinity })
  let lineNumber = 0
  try {
    for await (const line of lines) {
      lineNumber += 1
      if (!line.trim()) continue
      let row
      try {
        row = JSON.parse(line)
      } catch (error) {
        throw new Error(`Invalid ${kind} NDJSON at ${path}:${lineNumber}: ${error instanceof Error ? error.message : String(error)}`)
      }
      const recordID = kind === 'record' ? row.id : row.record_id
      if (wantedRecordIDs.has(recordID)) rows.push(row)
    }
  } finally {
    lines.close()
    input.destroy()
  }
  return rows
}

function reviewedTarget(catalogue, approval) {
  const matches = catalogue.filter((food) => (
    food.id === approval.target_id
    && food.provider_product_id === approval.target_provider_product_id
  ))
  if (matches.length !== 1) {
    throw new Error(`Reviewed target identity ${approval.target_id} / ${approval.target_provider_product_id} resolved ${matches.length} catalogue rows`)
  }
  const target = matches[0]
  requireEqual(target.name, approval.target_name, `${approval.target_id} reviewed target name`)
  requireEqual(target.nutrition_basis, approval.target_nutrition_basis, `${approval.target_id} nutrition basis`)
  requireEqual(target.preparation_state, approval.target_preparation_state, `${approval.target_id} preparation state`)
  if (
    target.owner_user_id !== null
    || target.brand !== null
    || target.barcode !== null
    || target.source !== 'apex_cache'
  ) {
    throw new Error(`Reviewed target ${approval.target_id} is no longer an unbranded public apex_cache food`)
  }
  const fingerprint = fingerprintFromFood(target)
  assertFiniteFingerprint(fingerprint, `${approval.target_id} target`)
  return { target, fingerprint }
}

function reviewedDonor(records, approval) {
  const matches = records.filter((record) => record.id === approval.donor_id)
  if (matches.length !== 1) throw new Error(`Reviewed donor ${approval.donor_id} resolved ${matches.length} staged records`)
  const donor = matches[0]
  requireEqual(donor.source_key, approval.donor_source_key, `${approval.donor_id} source key`)
  requireEqual(String(donor.source_record_id), String(approval.donor_source_record_id), `${approval.donor_id} source record`)
  requireReviewedName(donor.canonical_name, approval.donor_name, `${approval.donor_id} donor name`)
  requireEqual(donor.basis_kind, 'per_100g', `${approval.donor_id} donor basis`)
  if (donor.brand !== null || donor.barcode !== null) {
    throw new Error(`Reviewed donor ${approval.donor_id} is branded or barcoded`)
  }
  return donor
}

function normalizedDonorPreparation(record) {
  const value = typeof record.preparation_state === 'string' ? record.preparation_state.trim().toLowerCase() : ''
  return value || 'unknown'
}

function sortedCounts(values) {
  return Object.fromEntries([...values.entries()].sort(([left], [right]) => left.localeCompare(right)))
}

export async function buildNaturalFoodEvidence({ crosswalk, catalogue, sourceDirectories, sourceRegistry }) {
  if (crosswalk?.schema_version !== 1 || !Array.isArray(crosswalk.approvals)) {
    throw new Error('Reviewed crosswalk must have schema_version 1 and an approvals array')
  }
  const approvals = crosswalk.approvals.toSorted((left, right) => (
    left.target_id.localeCompare(right.target_id)
    || left.target_provider_product_id.localeCompare(right.target_provider_product_id)
  ))
  const targetKeys = new Set()
  for (const approval of approvals) {
    const key = `${approval.target_id}\u0000${approval.target_provider_product_id}`
    if (targetKeys.has(key)) throw new Error(`Duplicate reviewed target identity ${approval.target_id} / ${approval.target_provider_product_id}`)
    targetKeys.add(key)
  }

  const sourceKeys = [...new Set(approvals.map((approval) => approval.donor_source_key))].sort()
  const sourceProvenance = []
  const recordsBySource = new Map()
  const nutrientsBySource = new Map()
  for (const sourceKey of sourceKeys) {
    const directory = sourceDirectories[sourceKey]
    if (!directory) throw new Error(`No staged directory supplied for ${sourceKey}`)
    sourceProvenance.push(await verifyStagedSource(sourceKey, directory, sourceRegistry))
    const ids = new Set(approvals.filter((approval) => approval.donor_source_key === sourceKey).map((approval) => approval.donor_id))
    recordsBySource.set(sourceKey, await readFilteredNDJSON(resolve(directory, 'records.ndjson'), ids, 'record'))
    nutrientsBySource.set(sourceKey, await readFilteredNDJSON(resolve(directory, 'nutrients.ndjson'), ids, 'nutrient'))
  }

  const targets = []
  const categoryCounts = new Map()
  const sourceCounts = new Map()
  const nutrientCoverage = new Map()
  for (const approval of approvals) {
    const { fingerprint: targetFingerprint } = reviewedTarget(catalogue, approval)
    const donor = reviewedDonor(recordsBySource.get(approval.donor_source_key) ?? [], approval)
    const donorRows = (nutrientsBySource.get(approval.donor_source_key) ?? []).filter((row) => row.record_id === donor.id)
    if (donorRows.length === 0) throw new Error(`Reviewed donor ${donor.id} has no staged nutrient observations`)
    const evidence = canonicalizeNutrientEvidence(donorRows, {
      sourceKey: approval.donor_source_key,
      sourceRecordId: String(approval.donor_source_record_id),
      targetFingerprint,
    })
    const donorFingerprint = fingerprintFromEvidence(evidence, `${donor.id} donor`)
    if (!fingerprintMatches(targetFingerprint, donorFingerprint)) {
      throw new Error(`Reviewed donor ${donor.id} no longer passes the target macro fingerprint for ${approval.target_id}`)
    }
    validateEvidenceBounds(evidence)
    const aliases = [
      {
        kind: 'target',
        id: approval.target_id,
        provider_product_id: approval.target_provider_product_id,
        nutrition_basis: approval.target_nutrition_basis,
        preparation_state: approval.target_preparation_state,
        fingerprint: targetFingerprint,
      },
      {
        kind: 'donor',
        id: donor.id,
        provider_product_id: `corpus:${approval.donor_source_key}:${approval.donor_source_record_id}`,
        nutrition_basis: donor.basis_kind,
        preparation_state: normalizedDonorPreparation(donor),
        fingerprint: donorFingerprint,
      },
    ]
    targets.push({
      aliases,
      category: approval.category,
      donor: {
        id: donor.id,
        name: donor.canonical_name,
        source_key: approval.donor_source_key,
        source_record_id: String(approval.donor_source_record_id),
      },
      evidence,
      target: {
        id: approval.target_id,
        name: approval.target_name,
        provider_product_id: approval.target_provider_product_id,
      },
    })
    categoryCounts.set(approval.category, (categoryCounts.get(approval.category) ?? 0) + 1)
    sourceCounts.set(approval.donor_source_key, (sourceCounts.get(approval.donor_source_key) ?? 0) + 1)
    for (const code of new Set(evidence.map((row) => row.nutrient_code))) {
      nutrientCoverage.set(code, (nutrientCoverage.get(code) ?? 0) + 1)
    }
  }

  const bundle = {
    schema_version: 1,
    sources: sourceProvenance.toSorted((left, right) => left.key.localeCompare(right.key)),
    targets,
  }
  const summary = {
    approved_count: targets.length,
    category_counts: sortedCounts(categoryCounts),
    nutrient_coverage: sortedCounts(nutrientCoverage),
    source_counts: sortedCounts(sourceCounts),
  }
  return { bundle, summary }
}

function parseTSV(text, filename) {
  const lines = text.replaceAll('\r\n', '\n').split('\n').filter((line) => line.length > 0)
  if (lines.length < 2) throw new Error(`${filename} is empty`)
  const headers = lines[0].split('\t')
  return lines.slice(1).map((line, rowIndex) => {
    const fields = line.split('\t')
    if (fields.length !== headers.length) {
      throw new Error(`${filename}:${rowIndex + 2} has ${fields.length} fields; expected ${headers.length}`)
    }
    return Object.fromEntries(headers.map((header, index) => [header, fields[index]]))
  })
}

function numericDelta(values, label) {
  const numbers = values.map((value) => Number(value))
  if (numbers.length !== 4 || numbers.some((value) => !Number.isFinite(value))) {
    throw new Error(`Invalid reviewed macro delta for ${label}`)
  }
  return { kcal_100: numbers[0], protein_100: numbers[1], carbs_100: numbers[2], fat_100: numbers[3] }
}

function normalizedCategory(category) {
  const mapping = {
    fruit: 'fruit',
    veg: 'vegetable_leaf',
    grain: 'grain_starch',
    legume: 'legume',
    nuts: 'nut_seed',
    dairy: 'plain_dairy',
  }
  const value = mapping[category]
  if (!value) throw new Error(`Unknown reviewed category ${category}`)
  return value
}

function animalCategory(name) {
  const normalized = name.toLowerCase()
  if (/yogh?urt|cottage cheese/.test(normalized)) return 'plain_dairy'
  if (/\begg\b/.test(normalized)) return 'egg'
  if (/salmon|\bcod\b|tilapia|tuna|trout|mackerel|halibut|swordfish|pollock|shrimp|squid|fish|shellfish/.test(normalized)) {
    return 'fish_shellfish'
  }
  return 'meat_poultry'
}

function plantApproval(row) {
  const tuple = row['delta(kcal,P,C,F)'].replace(/^\(/, '').replace(/\)$/, '').split(',')
  return {
    category: normalizedCategory(row.cat),
    target_id: row.target_uuid,
    target_provider_product_id: row.provider_id,
    target_name: row.target_name,
    target_nutrition_basis: 'per_100g',
    target_preparation_state: row.prep,
    donor_id: row.donor_uuid,
    donor_source_key: row.source_key,
    donor_source_record_id: row.source_record_id,
    donor_name: row.donor_name,
    reviewed_macro_delta: numericDelta(tuple, row.target_uuid),
    review_note: null,
    review_sources: ['plant-crosswalk.tsv'],
  }
}

function animalApproval(row) {
  return {
    category: animalCategory(row.target_name),
    target_id: row.target_uuid,
    target_provider_product_id: row.target_provider_id,
    target_name: row.target_name,
    target_nutrition_basis: 'per_100g',
    target_preparation_state: row.target_preparation,
    donor_id: row.donor_uuid,
    donor_source_key: row.donor_source_key,
    donor_source_record_id: row.donor_source_record_id,
    donor_name: row.donor_name,
    reviewed_macro_delta: numericDelta([
      row.delta_kcal, row.delta_protein_g, row.delta_carbs_g, row.delta_fat_g,
    ], row.target_uuid),
    review_note: row.review_note || null,
    review_sources: ['animal-crosswalk.tsv'],
  }
}

function regionalApproval(row) {
  if (row.decision !== 'addition') throw new Error(`Unsupported regional crosswalk decision ${row.decision}`)
  return {
    category: 'grain_starch',
    target_id: row.target_uuid,
    target_provider_product_id: row.target_provider_id,
    target_name: row.target_name,
    target_nutrition_basis: 'per_100g',
    target_preparation_state: row.target_preparation,
    donor_id: row.donor_uuid,
    donor_source_key: row.donor_source_key,
    donor_source_record_id: row.donor_source_record_id,
    donor_name: row.donor_name,
    reviewed_macro_delta: numericDelta([
      row.delta_kcal, row.delta_protein_g, row.delta_carbs_g, row.delta_fat_g,
    ], row.target_uuid),
    review_note: row.review_note || null,
    review_sources: ['regional-crosswalk.tsv'],
  }
}

function comparableApproval(approval) {
  const { review_note: _reviewNote, review_sources: _reviewSources, ...comparable } = approval
  return comparable
}

export async function normalizeReviewedCrosswalk(reviewDirectory) {
  const filenames = ['plant-crosswalk.tsv', 'animal-crosswalk.tsv', 'regional-crosswalk.tsv']
  const [plantText, animalText, regionalText] = await Promise.all(
    filenames.map((filename) => readFile(resolve(reviewDirectory, filename), 'utf8')),
  )
  const candidates = [
    ...parseTSV(plantText, filenames[0]).map(plantApproval),
    ...parseTSV(animalText, filenames[1]).map(animalApproval),
    ...parseTSV(regionalText, filenames[2]).map(regionalApproval),
  ]
  const unique = new Map()
  for (const candidate of candidates) {
    const key = `${candidate.target_id}\u0000${candidate.target_provider_product_id}`
    const existing = unique.get(key)
    if (!existing) {
      unique.set(key, candidate)
      continue
    }
    if (JSON.stringify(comparableApproval(existing)) !== JSON.stringify(comparableApproval(candidate))) {
      throw new Error(`Conflicting independent reviews for ${candidate.target_id} / ${candidate.target_provider_product_id}`)
    }
    existing.review_sources = [...new Set([...existing.review_sources, ...candidate.review_sources])].sort()
    existing.review_note = existing.review_note ?? candidate.review_note
  }
  return {
    schema_version: 1,
    review_sources: filenames,
    approvals: [...unique.values()].toSorted((left, right) => (
      left.target_id.localeCompare(right.target_id)
      || left.target_provider_product_id.localeCompare(right.target_provider_product_id)
    )),
  }
}

const REVIEWED_REJECTIONS = [
  ['10000000-0000-4000-8000-000000000002', 'White rice, dry', 'grain_starch', 'ambiguous_identity', 'Multiple grain-length, parboiling, and enrichment states pass the macro gate; the target does not distinguish them.'],
  ['10000000-0000-4000-8000-000000000003', 'White rice, cooked', 'grain_starch', 'ambiguous_identity', 'Multiple grain-length and enrichment states pass every gate.'],
  ['20000000-0000-4000-8000-000000000028', 'Brown rice, dry', 'grain_starch', 'ambiguous_identity', 'Long- and medium-grain official records both pass; the target does not distinguish them.'],
  ['20000000-0000-4000-8000-000000000412', 'Sweet corn kernels, raw', 'vegetable_leaf', 'ambiguous_identity', 'White and yellow corn donors both pass; the target omits colour.'],
  ['20000000-0000-4000-8000-000000000413', 'Sweet corn kernels, boiled', 'vegetable_leaf', 'ambiguous_identity', 'White and yellow cooked donors both pass.'],
  ['10000000-0000-4000-8000-000000000026', 'Organic whole-grain rolled oats', 'grain_starch', 'identity_mismatch', 'The macro-compatible record does not establish organic identity.'],
  ['10000000-0000-4000-8000-000000000004', 'Bulgur, dry', 'grain_starch', 'fingerprint_mismatch', 'The exact-name official donor exceeds the carbohydrate gate.'],
  ['20000000-0000-4000-8000-000000000026', 'Basmati rice, dry', 'grain_starch', 'no_exact_official_donor', 'No exact unbranded variety record was reviewed.'],
  ['20000000-0000-4000-8000-000000000027', 'Jasmine rice, dry', 'grain_starch', 'no_exact_official_donor', 'No exact unbranded variety record was reviewed.'],
  ['20000000-0000-4000-8000-000000000031', 'Wholegrain pasta, dry', 'grain_starch', 'fingerprint_mismatch', 'The exact official record exceeds protein, carbohydrate, and fat gates.'],
  ['10000000-0000-4000-8000-000000000061', 'Black sesame seeds', 'nut_seed', 'identity_mismatch', 'A generic sesame record does not establish the black variety.'],
  ['10000000-0000-4000-8000-000000000065', 'Cherry tomatoes, fresh', 'vegetable_leaf', 'identity_mismatch', 'Grape-tomato and generic red-tomato records are not exact cherry-tomato donors.'],
  ['20000000-0000-4000-8000-000000000470', 'White potato with skin, boiled', 'vegetable_leaf', 'preparation_mismatch', 'The compatible record describes flesh cooked in skin, not consumed skin.'],
  ['20000000-0000-4000-8000-000000000066', 'Salmon fillet, raw', 'fish_shellfish', 'species_mismatch', 'The compatible donor is explicitly farmed Atlantic salmon while the target is species-generic.'],
  ['20000000-0000-4000-8000-000000000233', 'Beef sirloin, raw', 'meat_poultry', 'cut_mismatch', 'Compatible donors narrow the target to top-sirloin cap with trim and grade qualifiers.'],
  ['20000000-0000-4000-8000-000000000238', 'Beef sirloin, grilled', 'meat_poultry', 'cut_mismatch', 'The official donor narrows the target to a qualified top-sirloin subcut.'],
  ['20000000-0000-4000-8000-000000000255', 'Lamb leg, raw', 'meat_poultry', 'cut_mismatch', 'Several shank-half, whole-leg, and regional donors pass; the target does not distinguish them.'],
  ['20000000-0000-4000-8000-000000000262', 'Lamb leg, roasted', 'meat_poultry', 'cut_mismatch', 'Several incompatible leg/cut identities remain plausible.'],
  ['20000000-0000-4000-8000-000000000022', 'Tuna, drained', 'fish_shellfish', 'identity_mismatch', 'The compatible donor specifies light tuna without salt; the target omits both qualifiers.'],
  ['20000000-0000-4000-8000-000000000179', 'Scallops, raw', 'fish_shellfish', 'species_mismatch', 'The Foundation candidate is frozen and wild-caught, while the SR mixed-species row fails the macro gate.'],
  ['20000000-0000-4000-8000-000000000184', 'Lobster, raw', 'fish_shellfish', 'species_mismatch', 'The macro-compatible donor specifies northern lobster; the target is generic.'],
  ['10000000-0000-4000-8000-000000000016', 'Chicken breast, air fryer, no added oil', 'meat_poultry', 'preparation_mismatch', 'No exact air-fryer donor exists; roasted macros cannot authorize a preparation transfer.'],
  ['10000000-0000-4000-8000-000000000015', 'Chicken breast, boiled', 'meat_poultry', 'preparation_mismatch', 'The adjacent official profile is stewed rather than boiled.'],
  ['10000000-0000-4000-8000-000000000067', 'Salmon, hot-smoked', 'fish_shellfish', 'preparation_mismatch', 'The generic smoked donor does not establish hot versus cold smoking.'],
  ['20000000-0000-4000-8000-000000000054', 'Omelette', 'egg', 'composite_excluded', 'Composite preparations are outside the one-whole-food donor boundary.'],
  ['20000000-0000-4000-8000-000000000056', 'Scrambled egg', 'egg', 'composite_excluded', 'Composite preparations are outside the one-whole-food donor boundary.'],
]

export function reviewedRejectionReport() {
  return {
    schema_version: 1,
    review_sources: [
      'plant-crosswalk-notes.md',
      'animal-crosswalk-notes.md',
      'regional-crosswalk-notes.md',
    ],
    rejections: REVIEWED_REJECTIONS.map(([target_id, target_name, category, reason_code, reason]) => ({
      target_id, target_name, category, reason_code, reason,
    })).toSorted((left, right) => left.target_id.localeCompare(right.target_id)),
  }
}

function parseArguments(argv) {
  const options = { sources: {} }
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index]
    const value = argv[index + 1]
    if (argument === '--source') {
      if (!value?.includes('=')) throw new Error('--source expects key=directory')
      const separator = value.indexOf('=')
      options.sources[value.slice(0, separator)] = value.slice(separator + 1)
      index += 1
    } else if (argument.startsWith('--')) {
      if (!value || value.startsWith('--')) throw new Error(`${argument} expects a value`)
      options[argument.slice(2).replaceAll('-', '_')] = value
      index += 1
    } else {
      throw new Error(`Unexpected argument ${argument}`)
    }
  }
  return options
}

async function writeGeneratedFile(path, value) {
  await writeFile(path, stableJSONStringify(value))
}

async function runCLI() {
  const options = parseArguments(process.argv.slice(2))
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
  const crosswalkPath = resolve(options.crosswalk ?? resolve(root, 'docs/food-corpus/natural-food-evidence-crosswalk.json'))
  const registryPath = resolve(options.registry ?? resolve(root, 'tools/food_corpus/sources.json'))
  const cataloguePath = resolve(options.catalogue ?? resolve(root, 'src/data/foodSeeds.ts'))
  const resourcePath = resolve(options.resource_out ?? resolve(root, 'shared/natural-food-evidence.json'))
  const manifestPath = resolve(options.manifest_out ?? resolve(root, 'docs/food-corpus/natural-food-evidence-manifest.json'))
  const rejectionPath = resolve(options.rejections_out ?? resolve(root, 'docs/food-corpus/natural-food-evidence-rejections.json'))
  const crosswalk = options.reviewed_dir
    ? await normalizeReviewedCrosswalk(resolve(options.reviewed_dir))
    : JSON.parse(await readFile(crosswalkPath, 'utf8'))
  if (options.reviewed_dir) await writeGeneratedFile(crosswalkPath, crosswalk)
  const rejectionReport = reviewedRejectionReport()
  await writeGeneratedFile(rejectionPath, rejectionReport)
  const sourceRegistry = JSON.parse(await readFile(registryPath, 'utf8'))
  const catalogueModule = await import(pathToFileURL(cataloguePath).href)
  if (!Array.isArray(catalogueModule.COMMON_FOODS)) throw new Error(`${cataloguePath} does not export COMMON_FOODS`)
  const result = await buildNaturalFoodEvidence({
    crosswalk,
    catalogue: catalogueModule.COMMON_FOODS,
    sourceDirectories: options.sources,
    sourceRegistry,
  })
  const resourceText = stableJSONStringify(result.bundle)
  await writeFile(resourcePath, resourceText)
  const resourceSHA256 = `sha256:${createHash('sha256').update(resourceText).digest('hex')}`
  const crosswalkSHA256 = await hashFile(crosswalkPath)
  const manifest = {
    schema_version: 1,
    generator: 'tools/food_corpus/build_natural_food_evidence.mjs',
    crosswalk: {
      path: relative(root, crosswalkPath),
      sha256: crosswalkSHA256,
    },
    resource: {
      bytes: Buffer.byteLength(resourceText, 'utf8'),
      path: relative(root, resourcePath),
      sha256: resourceSHA256,
    },
    source_provenance: result.bundle.sources,
    approved_count: result.summary.approved_count,
    rejected_count: rejectionReport.rejections.length,
    category_counts: result.summary.category_counts,
    nutrient_coverage: result.summary.nutrient_coverage,
    source_counts: result.summary.source_counts,
    regeneration_command: [
      'node tools/food_corpus/build_natural_food_evidence.mjs',
      '--crosswalk docs/food-corpus/natural-food-evidence-crosswalk.json',
      '--source usda-sr-legacy=$USDA_SR_LEGACY_DIR',
      '--source usda-foundation=$USDA_FOUNDATION_DIR',
      '--source dk-frida=$DK_FRIDA_DIR',
    ].join(' '),
  }
  await writeGeneratedFile(manifestPath, manifest)
  process.stdout.write(`${JSON.stringify({
    approved_count: result.summary.approved_count,
    manifest: relative(root, manifestPath),
    resource: relative(root, resourcePath),
    resource_bytes: manifest.resource.bytes,
    resource_sha256: resourceSHA256,
  })}\n`)
}

const invokedPath = process.argv[1] ? resolve(process.argv[1]) : ''
const modulePath = resolve(fileURLToPath(import.meta.url))
if (invokedPath === modulePath) {
  runCLI().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`)
    process.exitCode = 1
  })
}
