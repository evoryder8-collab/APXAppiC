#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { createReadStream } from 'node:fs'
import { readFile, writeFile } from 'node:fs/promises'
import { createInterface } from 'node:readline'
import { basename, dirname, relative, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import process from 'node:process'

const MAX_EVIDENCE_ROWS = 96
const MAX_EVIDENCE_BYTES = 65_536
const MAX_EVIDENCE_VALUE_PER_100 = 1_000_000_000_000
const REVIEWED_DELTA_TOLERANCE = 0.0005 + Number.EPSILON
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
  { code: 'OMEGA6_AA', candidates: { 'usda-sr-legacy': ['1406'] } },
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

export function canonicalNutrientCodeForSource(sourceKey, sourceNutrientCode) {
  const sourceCode = String(sourceNutrientCode)
  for (const projection of NUTRIENT_PROJECTION) {
    if (projection.candidates[sourceKey]?.includes(sourceCode)) return projection.code
  }
  return sourceCode
}

function isFiniteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value)
}

export function canonicalizeEvidenceUnit(unit, {
  canonicalCode = '', sourceKey = '', sourceNutrientCode = '',
} = {}) {
  const trimmed = unit.trim()
  const normalized = trimmed.replaceAll('μ', 'µ').replace(/\s+/g, ' ')
  const code = canonicalCode.toUpperCase()
  const sourceCode = String(sourceNutrientCode)

  // Frida publishes these equivalent-based values per 100 g. The numeric
  // values already use the stated magnitude, so only the UI unit/basis syntax
  // is canonicalized; no conversion is performed.
  if (sourceKey === 'dk-frida' && code === 'VITA' && /^RE\s*\(\s*µg\s*\/\s*100\s*g\s*\)$/i.test(normalized)) {
    return 'µg RE'
  }
  if (sourceKey === 'dk-frida' && code === 'VITE' && /^(?:alfa|alpha|α)-?TE$/i.test(normalized)) {
    return 'mg α-TE'
  }

  const withoutBasis = normalized.replace(/\s*(?:\/\s*100\s*g|per\s+100\s*g)\s*$/i, '').trim()
  switch (withoutBasis.toLowerCase()) {
    case 'g': return 'g'
    case 'mg': return 'mg'
    case 'ug':
    case 'µg':
      return code === 'VITA' && USDA_SOURCES.includes(sourceKey) && sourceCode === '1106' ? 'µg RAE' : 'µg'
    case 'kcal': return 'kcal'
    case 'iu':
      if (code === 'VITA' || code === 'VITD') return 'IU'
      break
  }
  throw new Error(`Unsupported evidence unit ${trimmed} for ${sourceKey}:${sourceCode}:${code}`)
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

function deploymentTarget(entry) {
  const alias = entry?.aliases?.find((candidate) => candidate?.kind === 'target')
  if (
    !alias
    || typeof alias.id !== 'string'
    || typeof alias.provider_product_id !== 'string'
    || typeof alias.nutrition_basis !== 'string'
    || typeof alias.preparation_state !== 'string'
  ) {
    throw new Error('Natural-food deployment entry lacks one complete target alias')
  }
  assertFiniteFingerprint(alias.fingerprint, `${alias.id} deployment target`)
  if (!Array.isArray(entry.evidence) || entry.evidence.length === 0) {
    throw new Error(`Natural-food deployment entry ${alias.id} has no evidence`)
  }
  validateEvidenceBounds(entry.evidence)
  return {
    carbs_100: alias.fingerprint.carbs_100,
    evidence: entry.evidence,
    fat_100: alias.fingerprint.fat_100,
    kcal_100: alias.fingerprint.kcal_100,
    nutrition_basis: alias.nutrition_basis,
    preparation_state: alias.preparation_state,
    protein_100: alias.fingerprint.protein_100,
    provider_product_id: alias.provider_product_id,
    target_id: alias.id,
  }
}

export function renderNaturalFoodEvidenceMigration(bundle) {
  if (bundle?.schema_version !== 1 || !Array.isArray(bundle.targets) || bundle.targets.length === 0) {
    throw new Error('Natural-food deployment bundle must have schema_version 1 and at least one target')
  }
  const payload = bundle.targets.map(deploymentTarget).toSorted((left, right) => (
    left.target_id.localeCompare(right.target_id)
    || left.provider_product_id.localeCompare(right.provider_product_id)
  ))
  const identities = new Set(payload.map((target) => `${target.target_id}\u0000${target.provider_product_id}`))
  const targetIDs = new Set(payload.map((target) => target.target_id))
  const providerIDs = new Set(payload.map((target) => target.provider_product_id))
  if (identities.size !== payload.length || targetIDs.size !== payload.length || providerIDs.size !== payload.length) {
    throw new Error('Natural-food deployment bundle contains duplicate target or provider identity')
  }
  const payloadText = stableJSONStringify(payload).trimEnd()
  const payloadDelimiter = '$apex_natural_food_payload$'
  if (payloadText.includes(payloadDelimiter)) throw new Error('Natural-food deployment payload contains the SQL delimiter')

  return `-- Generated by tools/food_corpus/build_natural_food_evidence.mjs.
-- Reviewed natural-food evidence only: never edit this payload by hand.
-- Adds evidence to unchanged, global, unbranded curated rows and deliberately
-- preserves macros, ownership, timestamps, and every historical meal snapshot.

do $apex_natural_food_migration$
declare
  v_payload constant jsonb := ${payloadDelimiter}${payloadText}${payloadDelimiter}::jsonb;
  v_expected_count constant integer := ${payload.length};
  v_payload_count integer;
  v_distinct_target_count integer;
  v_distinct_provider_count integer;
  v_updated_count integer;
  v_timestamp_change_count integer;
begin
  if jsonb_typeof(v_payload) <> 'array' then
    raise exception 'Natural-food evidence payload is not an array';
  end if;

  select
    count(*),
    count(distinct payload.target_id),
    count(distinct payload.provider_product_id)
  into v_payload_count, v_distinct_target_count, v_distinct_provider_count
  from jsonb_to_recordset(v_payload) as payload(
    target_id uuid,
    provider_product_id text,
    nutrition_basis text,
    preparation_state text,
    kcal_100 numeric,
    protein_100 numeric,
    carbs_100 numeric,
    fat_100 numeric,
    evidence jsonb
  );

  if v_payload_count <> v_expected_count
     or v_distinct_target_count <> v_expected_count
     or v_distinct_provider_count <> v_expected_count then
    raise exception 'Natural-food evidence payload identity assertion failed';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(v_payload) as payload(
      target_id uuid,
      provider_product_id text,
      nutrition_basis text,
      preparation_state text,
      kcal_100 numeric,
      protein_100 numeric,
      carbs_100 numeric,
      fat_100 numeric,
      evidence jsonb
    )
    where payload.target_id is null
       or nullif(payload.provider_product_id, '') is null
       or payload.nutrition_basis not in ('per_100g', 'per_100ml')
       or nullif(payload.preparation_state, '') is null
       or payload.kcal_100 is null
       or payload.protein_100 is null
       or payload.carbs_100 is null
       or payload.fat_100 is null
       or jsonb_typeof(payload.evidence) <> 'array'
       or jsonb_array_length(payload.evidence) = 0
       or not public.apex_valid_nutrient_evidence(payload.evidence)
  ) then
    raise exception 'Natural-food evidence payload validation failed';
  end if;

  with payload as (
    select *
    from jsonb_to_recordset(v_payload) as reviewed(
      target_id uuid,
      provider_product_id text,
      nutrition_basis text,
      preparation_state text,
      kcal_100 numeric,
      protein_100 numeric,
      carbs_100 numeric,
      fat_100 numeric,
      evidence jsonb
    )
  ), eligible as materialized (
    select
      food.id,
      food.updated_at as original_updated_at,
      payload.evidence
    from public.foods food
    join payload on payload.target_id = food.id
                and payload.provider_product_id = food.provider_product_id
    where food.owner_user_id is null
      and food.source::text = 'apex_cache'
      and food.brand is null
      and food.barcode is null
      and food.nutrition_basis::text = payload.nutrition_basis
      and food.preparation_state::text = payload.preparation_state
      and food.kcal_100 is not distinct from payload.kcal_100
      and food.protein_100 is not distinct from payload.protein_100
      and food.carbs_100 is not distinct from payload.carbs_100
      and food.fat_100 is not distinct from payload.fat_100
      and food.nutrient_evidence = '[]'::jsonb
  ), updated as (
    update public.foods food
    set nutrient_evidence = eligible.evidence,
        updated_at = food.updated_at
    from eligible
    where food.id = eligible.id
      and food.nutrient_evidence = '[]'::jsonb
    returning food.id, food.updated_at
  )
  select
    count(*),
    count(*) filter (where updated.updated_at is distinct from eligible.original_updated_at)
  into v_updated_count, v_timestamp_change_count
  from updated
  join eligible using (id);

  if v_timestamp_change_count <> 0 then
    raise exception 'Natural-food evidence migration changed updated_at';
  end if;

  raise notice 'Natural-food evidence rows enriched: % of % reviewed targets',
    v_updated_count, v_expected_count;
end
$apex_natural_food_migration$;
`
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

function deterministicRow(rows, candidateCodes, canonicalCode, sourceKey, targetFingerprint, reviewedMacroDelta) {
  const candidates = rows.filter((row) => candidateCodes.includes(String(row.source_nutrient_code)))
  if (candidates.length === 0) return null

  if (canonicalCode === 'ENERC_KCAL' && sourceKey === 'usda-foundation') {
    const targetEnergy = targetFingerprint.kcal_100
    const numeric = candidates.filter((row) => isFiniteNumber(row.value))
    if (numeric.length === 0) return candidates.toSorted((left, right) => (
      candidateCodes.indexOf(String(left.source_nutrient_code)) - candidateCodes.indexOf(String(right.source_nutrient_code))
      || String(left.source_reference ?? '').localeCompare(String(right.source_reference ?? ''))
    ))[0]
    const reviewedEnergyDelta = reviewedMacroDelta?.kcal_100
    if (!isFiniteNumber(reviewedEnergyDelta)) {
      throw new Error('Foundation energy canonicalization requires a finite reviewed kcal delta')
    }
    const reviewedEnergy = targetEnergy + reviewedEnergyDelta
    const matchingReview = numeric.filter((row) => Math.abs(row.value - reviewedEnergy) <= REVIEWED_DELTA_TOLERANCE)
    if (matchingReview.length === 0) {
      throw new Error(`No Foundation energy observation preserves reviewed macro delta ${reviewedEnergyDelta}`)
    }
    return matchingReview.toSorted((left, right) => (
      Math.abs(left.value - reviewedEnergy) - Math.abs(right.value - reviewedEnergy)
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
  if (row.value !== null && (
    !isFiniteNumber(row.value)
    || row.value < 0
    || row.value > MAX_EVIDENCE_VALUE_PER_100
  )) {
    throw new Error(`Nutrient value outside 0...1e12 for ${sourceKey}:${sourceRecordId}:${row.source_nutrient_code}`)
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
  const resolvedCanonicalCode = canonicalNutrientCodeForSource(sourceKey, row.source_nutrient_code)
  if (resolvedCanonicalCode !== canonicalCode) {
    throw new Error(`Nutrient projection drift for ${sourceKey}:${row.source_nutrient_code}`)
  }
  return {
    nutrient_code: resolvedCanonicalCode,
    name: row.original_nutrient_name,
    value_per_100: row.value,
    unit: canonicalizeEvidenceUnit(row.unit, {
      canonicalCode: resolvedCanonicalCode,
      sourceKey,
      sourceNutrientCode: row.source_nutrient_code,
    }),
    observation_status: row.observation_status,
    original_value_text: row.original_value_text,
    derivation_method: row.derivation_method ?? null,
    source_key: sourceKey,
    source_reference: sourceReference,
  }
}

export function canonicalizeNutrientEvidence(rows, { sourceKey, sourceRecordId, targetFingerprint, reviewedMacroDelta }) {
  assertFiniteFingerprint(targetFingerprint, 'Reviewed target')
  const evidence = []
  for (const projection of NUTRIENT_PROJECTION) {
    const candidates = projection.candidates[sourceKey]
    if (!candidates) continue
    const row = deterministicRow(rows, candidates, projection.code, sourceKey, targetFingerprint, reviewedMacroDelta)
    if (row) evidence.push(evidenceRow(row, projection.code, sourceKey, sourceRecordId))
  }
  validateEvidenceBounds(evidence)
  return evidence
}

export function validateEvidenceBounds(evidence) {
  if (evidence.length > MAX_EVIDENCE_ROWS) {
    throw new Error(`Evidence array exceeds the 96-row cap (${evidence.length})`)
  }
  for (const observation of evidence) {
    const value = observation?.value_per_100
    if (value !== null && (
      !isFiniteNumber(value)
      || value < 0
      || value > MAX_EVIDENCE_VALUE_PER_100
    )) {
      throw new Error('Evidence value_per_100 must be null or inside the inclusive 0...1e12 domain')
    }
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

function requireReviewedMacroDelta(target, donor, reviewed, label) {
  if (!reviewed || typeof reviewed !== 'object') {
    throw new Error(`${label} lacks a reviewed macro delta`)
  }
  for (const [field] of FINGERPRINT_FIELDS) {
    const expected = reviewed[field]
    const actual = donor[field] - target[field]
    if (!isFiniteNumber(expected) || Math.abs(actual - expected) > REVIEWED_DELTA_TOLERANCE) {
      throw new Error(`${label} reviewed macro delta mismatch for ${field}: expected ${String(expected)}, received ${actual}`)
    }
  }
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
  if (typeof registered.path !== 'string' || !registered.path.trim()) {
    throw new Error(`${sourceKey} registry path is missing`)
  }
  requireEqual(manifest.artifact, basename(registered.path), `${sourceKey} artifact`)
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
      reviewedMacroDelta: approval.reviewed_macro_delta,
    })
    const donorFingerprint = fingerprintFromEvidence(evidence, `${donor.id} donor`)
    requireReviewedMacroDelta(targetFingerprint, donorFingerprint, approval.reviewed_macro_delta, `${approval.target_id} / ${donor.id}`)
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

const REVIEW_CATEGORIES = new Set([
  'egg', 'fish_shellfish', 'fruit', 'grain_starch', 'legume',
  'meat_poultry', 'nut_seed', 'plain_dairy', 'vegetable_leaf',
])
const REJECTION_REASON_CODES = new Set([
  'ambiguous_identity', 'composite_excluded', 'cut_mismatch', 'fingerprint_mismatch',
  'identity_mismatch', 'no_exact_official_donor', 'preparation_mismatch', 'species_mismatch',
])

export async function reviewedRejectionReport(reviewDirectory) {
  const filename = 'rejections.tsv'
  const rows = parseTSV(await readFile(resolve(reviewDirectory, filename), 'utf8'), filename)
  const rejections = []
  const targetIDs = new Set()
  for (const row of rows) {
    for (const field of ['target_id', 'target_name', 'category', 'reason_code', 'reason']) {
      if (typeof row[field] !== 'string' || !row[field].trim()) {
        throw new Error(`${filename} has an empty ${field}`)
      }
    }
    if (targetIDs.has(row.target_id)) throw new Error(`${filename} has duplicate target ${row.target_id}`)
    if (!REVIEW_CATEGORIES.has(row.category)) throw new Error(`${filename} has unknown category ${row.category}`)
    if (!REJECTION_REASON_CODES.has(row.reason_code)) throw new Error(`${filename} has unknown reason code ${row.reason_code}`)
    targetIDs.add(row.target_id)
    rejections.push({
      target_id: row.target_id,
      target_name: row.target_name,
      category: row.category,
      reason_code: row.reason_code,
      reason: row.reason,
    })
  }
  return {
    schema_version: 1,
    review_sources: [filename],
    rejections: rejections.toSorted((left, right) => left.target_id.localeCompare(right.target_id)),
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
  const reviewDirectory = resolve(options.reviewed_dir ?? resolve(root, 'docs/food-corpus/natural-food-evidence-review'))
  const registryPath = resolve(options.registry ?? resolve(root, 'tools/food_corpus/sources.json'))
  const cataloguePath = resolve(options.catalogue ?? resolve(root, 'src/data/foodSeeds.ts'))
  const resourcePath = resolve(options.resource_out ?? resolve(root, 'shared/natural-food-evidence.json'))
  const manifestPath = resolve(options.manifest_out ?? resolve(root, 'docs/food-corpus/natural-food-evidence-manifest.json'))
  const rejectionPath = resolve(options.rejections_out ?? resolve(root, 'docs/food-corpus/natural-food-evidence-rejections.json'))
  const migrationPath = resolve(options.migration_out ?? resolve(root, 'supabase/migrations/048_natural_food_micronutrient_evidence.sql'))
  const crosswalk = await normalizeReviewedCrosswalk(reviewDirectory)
  await writeGeneratedFile(crosswalkPath, crosswalk)
  const rejectionReport = await reviewedRejectionReport(reviewDirectory)
  const rejectionText = stableJSONStringify(rejectionReport)
  await writeFile(rejectionPath, rejectionText)
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
  const migrationText = renderNaturalFoodEvidenceMigration(result.bundle)
  await writeFile(migrationPath, migrationText)
  const resourceSHA256 = `sha256:${createHash('sha256').update(resourceText).digest('hex')}`
  const migrationSHA256 = `sha256:${createHash('sha256').update(migrationText).digest('hex')}`
  const crosswalkSHA256 = await hashFile(crosswalkPath)
  const rejectionSHA256 = `sha256:${createHash('sha256').update(rejectionText).digest('hex')}`
  const reviewInputFiles = [
    'animal-crosswalk.tsv', 'plant-crosswalk.tsv', 'regional-crosswalk.tsv', 'rejections.tsv',
  ]
  const reviewInputChecksums = Object.fromEntries(await Promise.all(reviewInputFiles.map(async (filename) => (
    [filename, await hashFile(resolve(reviewDirectory, filename))]
  ))))
  const manifest = {
    schema_version: 1,
    generator: 'tools/food_corpus/build_natural_food_evidence.mjs',
    migration: {
      path: relative(root, migrationPath),
      sha256: migrationSHA256,
    },
    crosswalk: {
      path: relative(root, crosswalkPath),
      sha256: crosswalkSHA256,
    },
    resource: {
      bytes: Buffer.byteLength(resourceText, 'utf8'),
      path: relative(root, resourcePath),
      sha256: resourceSHA256,
    },
    rejections: {
      path: relative(root, rejectionPath),
      sha256: rejectionSHA256,
    },
    review_inputs: {
      directory: relative(root, reviewDirectory),
      file_sha256: reviewInputChecksums,
    },
    source_provenance: result.bundle.sources,
    approved_count: result.summary.approved_count,
    rejected_count: rejectionReport.rejections.length,
    category_counts: result.summary.category_counts,
    nutrient_coverage: result.summary.nutrient_coverage,
    source_counts: result.summary.source_counts,
    regeneration_command: [
      'node tools/food_corpus/build_natural_food_evidence.mjs',
      '--reviewed-dir docs/food-corpus/natural-food-evidence-review',
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
    migration: relative(root, migrationPath),
    migration_sha256: migrationSHA256,
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
