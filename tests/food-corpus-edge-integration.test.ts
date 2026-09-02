import assert from 'node:assert/strict'
import { execFileSync, spawnSync } from 'node:child_process'
import { createHash, randomInt } from 'node:crypto'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import { normalizeFoodCorpusSearchResult } from '../shared/foodCorpus.ts'
import { renderNaturalFoodEvidenceMigration } from '../tools/food_corpus/build_natural_food_evidence.mjs'
import { expandedReviewedNutrientIdentityCases } from '../tools/food_corpus/tests/reviewed_nutrient_identity_cases.mjs'

const edgeFunctionPath = new URL('../supabase/functions/food-lookup/index.ts', import.meta.url)
const activationMigrationPath = new URL(
  '../supabase/migrations/035_food_corpus_batch_activation.sql',
  import.meta.url,
)
const servingProjectionMigrationPath = new URL(
  '../supabase/migrations/037_food_corpus_serving_projection.sql',
  import.meta.url,
)
const naturalFoodEvidenceBundlePath = new URL(
  '../shared/natural-food-evidence.json',
  import.meta.url,
)
const naturalFoodEvidenceMigrationPath = new URL(
  '../supabase/migrations/048_natural_food_micronutrient_evidence.sql',
  import.meta.url,
)
const nutrientUnitHardeningMigrationPath = new URL(
  '../supabase/migrations/049_nutrient_evidence_unit_hardening.sql',
  import.meta.url,
)
const naturalFoodEvidenceManifestPath = new URL(
  '../docs/food-corpus/natural-food-evidence-manifest.json',
  import.meta.url,
)

test('natural-food evidence migration is the deterministic deployment of the reviewed bundle', () => {
  const bundle = JSON.parse(readFileSync(naturalFoodEvidenceBundlePath, 'utf8'))
  const expected = renderNaturalFoodEvidenceMigration(bundle)
  const manifest = JSON.parse(readFileSync(naturalFoodEvidenceManifestPath, 'utf8'))

  assert.equal(existsSync(naturalFoodEvidenceMigrationPath), true)
  assert.equal(readFileSync(naturalFoodEvidenceMigrationPath, 'utf8'), expected)
  assert.deepEqual(manifest.migration, {
    path: 'supabase/migrations/048_natural_food_micronutrient_evidence.sql',
    sha256: `sha256:${createHash('sha256').update(expected).digest('hex')}`,
  })
  assert.equal(bundle.targets.length, 111)
  assert.equal(new Set(bundle.targets.map((target: { target: { id: string } }) => target.target.id)).size, 111)
})

function postgresToolAvailable(tool: string) {
  return spawnSync(tool, ['--version'], { stdio: 'ignore' }).status === 0
}

function sqlText(value: string) {
  return `'${value.replaceAll("'", "''")}'`
}

test('natural-food evidence migration is idempotent and updates only an eligible exact global row', {
  skip: !['initdb', 'pg_ctl', 'psql'].every(postgresToolAvailable),
}, () => {
  const bundle = JSON.parse(readFileSync(naturalFoodEvidenceBundlePath, 'utf8'))
  const migration = readFileSync(naturalFoodEvidenceMigrationPath, 'utf8')
  const targets = bundle.targets.slice(0, 11).map((entry: {
    aliases: Array<{
      kind: string
      id: string
      provider_product_id: string
      nutrition_basis: string
      preparation_state: string
      fingerprint: { kcal_100: number; protein_100: number; carbs_100: number; fat_100: number }
    }>
    evidence: unknown[]
  }) => ({
    ...entry.aliases.find((alias) => alias.kind === 'target'),
    evidence: entry.evidence,
  }))
  assert.equal(targets.length, 11)

  const cases = [
    { label: 'eligible', target: targets[0] },
    { label: 'existing', target: targets[1], evidence: [{ nutrient_code: 'KEEP' }] },
    { label: 'private', target: targets[2], owner: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' },
    { label: 'branded', target: targets[3], brand: 'Not generic' },
    { label: 'barcoded', target: targets[4], barcode: '12345678' },
    { label: 'macro_drift', target: targets[5], kcalDelta: 1 },
    { label: 'provider_drift', target: targets[6], providerSuffix: ':changed' },
    { label: 'source_drift', target: targets[7], source: 'open_food_facts' },
    {
      label: 'basis_drift', target: targets[8],
      nutritionBasis: targets[8].nutrition_basis === 'per_100g' ? 'per_100ml' : 'per_100g',
    },
    {
      label: 'preparation_drift', target: targets[9],
      preparationState: targets[9].preparation_state === 'cooked' ? 'as_sold' : 'cooked',
    },
  ]
  const rowSQL = cases.map((fixture) => {
    const fingerprint = fixture.target.fingerprint
    return `(
      ${sqlText(fixture.target.id)}::uuid,
      ${fixture.owner ? `${sqlText(fixture.owner)}::uuid` : 'null'},
      ${sqlText(fixture.label)},
      ${fixture.brand ? sqlText(fixture.brand) : 'null'},
      ${fixture.barcode ? sqlText(fixture.barcode) : 'null'},
      ${sqlText(fixture.source ?? 'apex_cache')}::apex_food_source,
      ${sqlText(`${fixture.target.provider_product_id}${fixture.providerSuffix ?? ''}`)},
      ${sqlText(fixture.nutritionBasis ?? fixture.target.nutrition_basis)}::apex_nutrition_basis,
      ${sqlText(fixture.preparationState ?? fixture.target.preparation_state)}::apex_preparation_state,
      ${fingerprint.kcal_100 + (fixture.kcalDelta ?? 0)},
      ${fingerprint.protein_100},
      ${fingerprint.carbs_100},
      ${fingerprint.fat_100},
      ${sqlText(JSON.stringify(fixture.evidence ?? []))}::jsonb,
      '2026-01-02T03:04:05Z'::timestamptz
    )`
  }).join(',\n')
  const eligibleEvidence = sqlText(JSON.stringify(targets[0].evidence))
  const protectedIDs = cases.slice(1).map((fixture) => `${sqlText(fixture.target.id)}::uuid`).join(', ')
  const nonApproved = targets[10]
  const integrationSQL = `
    \\set ON_ERROR_STOP on
    begin;
    create type apex_food_source as enum ('open_food_facts', 'private', 'apex_cache');
    create type apex_nutrition_basis as enum ('per_100g', 'per_100ml');
    create type apex_preparation_state as enum ('dry', 'cooked', 'prepared', 'drained', 'as_sold', 'unknown');
    create table public.foods (
      id uuid primary key,
      owner_user_id uuid,
      name text not null,
      brand text,
      barcode text,
      source apex_food_source not null,
      provider_product_id text,
      nutrition_basis apex_nutrition_basis not null,
      preparation_state apex_preparation_state not null,
      kcal_100 numeric,
      protein_100 numeric,
      carbs_100 numeric,
      fat_100 numeric,
      nutrient_evidence jsonb not null default '[]'::jsonb,
      updated_at timestamptz not null
    );
    create function public.apex_valid_nutrient_evidence(value jsonb)
    returns boolean language sql immutable as $$
      select jsonb_typeof(value) = 'array'
        and jsonb_array_length(value) between 1 and 96
        and octet_length(value::text) <= 65536
    $$;
    insert into public.foods values
    ${rowSQL},
    (
      ${sqlText(nonApproved.id.replace(/.$/, 'f'))}::uuid, null, 'non_approved', null, null,
      'apex_cache', 'apex-curated:not-approved',
      ${sqlText(nonApproved.nutrition_basis)}::apex_nutrition_basis,
      ${sqlText(nonApproved.preparation_state)}::apex_preparation_state,
      ${nonApproved.fingerprint.kcal_100}, ${nonApproved.fingerprint.protein_100},
      ${nonApproved.fingerprint.carbs_100}, ${nonApproved.fingerprint.fat_100},
      '[]'::jsonb, '2026-01-02T03:04:05Z'::timestamptz
    );
    create temp table before_migration as table public.foods;

    ${migration}
    create temp table after_first_run as table public.foods;
    ${migration}

    do $$
    begin
      if not exists (
        select 1 from public.foods
        where id = ${sqlText(targets[0].id)}::uuid
          and nutrient_evidence = ${eligibleEvidence}::jsonb
          and updated_at = '2026-01-02T03:04:05Z'::timestamptz
      ) then
        raise exception 'eligible exact global row was not enriched without changing updated_at';
      end if;
      if exists (
        select 1 from public.foods
        where id in (${protectedIDs})
          and id <> ${sqlText(targets[1].id)}::uuid
          and nutrient_evidence <> '[]'::jsonb
      ) then
        raise exception 'an ineligible natural-food row was enriched';
      end if;
      if not exists (
        select 1 from public.foods
        where id = ${sqlText(targets[1].id)}::uuid
          and nutrient_evidence = '[{"nutrient_code":"KEEP"}]'::jsonb
      ) then
        raise exception 'existing nutrient evidence was overwritten';
      end if;
      if exists (
        (select * from public.foods except select * from after_first_run)
        union all
        (select * from after_first_run except select * from public.foods)
      ) then
        raise exception 'second migration run changed food rows';
      end if;
      if (select count(*) from public.foods food join before_migration before using (id)
          where food.nutrient_evidence is distinct from before.nutrient_evidence) <> 1 then
        raise exception 'migration changed other than the one eligible row';
      end if;
      if exists (
        select 1 from public.foods food join before_migration before using (id)
        where food.id <> ${sqlText(targets[0].id)}::uuid
          and food is distinct from before
      ) then
        raise exception 'private, branded, barcode, drifted, or non-approved data changed';
      end if;
    end
    $$;
    rollback;
  `

  const temporaryRoot = mkdtempSync(join(tmpdir(), 'apex-natural-food-pg-'))
  const dataDirectory = join(temporaryRoot, 'data')
  const socketDirectory = join(temporaryRoot, 'socket')
  const sqlPath = join(temporaryRoot, 'integration.sql')
  const port = randomInt(40_000, 59_000)
  let started = false
  try {
    mkdirSync(socketDirectory)
    writeFileSync(sqlPath, integrationSQL)
    execFileSync('initdb', [
      '-D', dataDirectory, '--auth=trust', '--no-locale', '--encoding=UTF8', '--username=postgres',
    ], { stdio: 'pipe' })
    execFileSync('pg_ctl', [
      '-D', dataDirectory, '-l', join(temporaryRoot, 'postgres.log'),
      '-o', `-F -k ${socketDirectory} -p ${port}`, '-w', 'start',
    ], { stdio: 'pipe' })
    started = true
    execFileSync('psql', [
      '-h', socketDirectory, '-p', String(port), '-U', 'postgres', '-d', 'postgres',
      '-v', 'ON_ERROR_STOP=1', '-f', sqlPath,
    ], { stdio: 'pipe' })
  } finally {
    if (started) {
      execFileSync('pg_ctl', ['-D', dataDirectory, '-m', 'immediate', '-w', 'stop'], { stdio: 'pipe' })
    }
    rmSync(temporaryRoot, { recursive: true, force: true })
  }
})

test('nutrient-unit hardening repairs legacy rows, normalizes writes, and filters corpus projection', {
  skip: !['initdb', 'pg_ctl', 'psql'].every(postgresToolAvailable),
}, () => {
  const migration = readFileSync(nutrientUnitHardeningMigrationPath, 'utf8')
  const expectedIdentityValues = expandedReviewedNutrientIdentityCases().map((identity) => (
    `(${sqlText(identity.sourceKey)}, ${sqlText(identity.sourceCode)}, ${sqlText(identity.code)})`
  )).join(',\n')
  const legacy = JSON.stringify([
    {
      nutrient_code: 'VITC', name: 'Vitamin C', value_per_100: 40, unit: 'MG / 100g',
      observation_status: 'measured', original_value_text: '40', derivation_method: null,
      source_key: 'fixture', source_reference: 'vitc',
    },
    {
      nutrient_code: 'VITA', name: 'Vitamin A', value_per_100: 10, unit: 'RE (ug/100 g)',
      observation_status: 'measured', original_value_text: '10', derivation_method: null,
      source_key: 'fixture', source_reference: 'vita',
    },
    {
      nutrient_code: 'FE', name: 'Iron', value_per_100: 99, unit: 'publisher score',
      observation_status: 'measured', original_value_text: '99', derivation_method: null,
      source_key: 'fixture', source_reference: 'opaque',
    },
  ])
  const integrationSQL = `
    \\set ON_ERROR_STOP on
    begin;
    create role anon;
    create role authenticated;
    create role service_role;
    create table public.foods (
      id uuid primary key,
      nutrient_evidence jsonb not null default '[]'::jsonb,
      updated_at timestamptz not null default now()
    );
    create table public.logged_food_entries (
      id uuid primary key,
      snapshot_nutrient_evidence jsonb not null default '[]'::jsonb
    );
    create function public.apex_valid_nutrient_evidence(p_value jsonb)
    returns boolean language sql immutable as $$ select jsonb_typeof(p_value) = 'array' $$;
    alter table public.foods add constraint foods_nutrient_evidence_valid
      check (public.apex_valid_nutrient_evidence(nutrient_evidence));
    alter table public.logged_food_entries add constraint logged_food_entries_nutrient_evidence_valid
      check (public.apex_valid_nutrient_evidence(snapshot_nutrient_evidence));

    create table public.food_corpus_sources (source_key text primary key, ingest_status text not null);
    create table public.food_corpus_batches (id uuid primary key, status text not null);
    create table public.food_corpus_records (
      id uuid primary key, source_key text not null references public.food_corpus_sources,
      batch_id uuid not null references public.food_corpus_batches,
      basis_kind text not null, basis_amount numeric not null, source_metadata jsonb not null default '{}'::jsonb
    );
    create table public.food_corpus_nutrients (
      id uuid primary key, record_id uuid not null references public.food_corpus_records,
      nutrient_code text not null, source_nutrient_code text not null, original_nutrient_name text not null,
      observation_status text not null, value numeric, unit text not null,
      original_value_text text, derivation_method text, source_reference text
    );

    insert into public.foods values (
      '10000000-0000-4000-8000-000000000001', ${sqlText(legacy)}::jsonb, '2026-01-01T00:00:00Z'
    );
    insert into public.logged_food_entries values (
      '20000000-0000-4000-8000-000000000001', ${sqlText(legacy)}::jsonb
    );
    insert into public.food_corpus_sources values
      ('usda-sr-legacy', 'active'),
      ('usda-foundation', 'active'),
      ('dk-frida', 'active'),
      ('unrelated-source', 'active');
    insert into public.food_corpus_batches values ('30000000-0000-4000-8000-000000000001', 'active');
    insert into public.food_corpus_records values
      ('40000000-0000-4000-8000-000000000001', 'usda-sr-legacy',
       '30000000-0000-4000-8000-000000000001', 'per_100g', 100, '{}'),
      ('40000000-0000-4000-8000-000000000002', 'usda-foundation',
       '30000000-0000-4000-8000-000000000001', 'per_100g', 100, '{}'),
      ('40000000-0000-4000-8000-000000000003', 'dk-frida',
       '30000000-0000-4000-8000-000000000001', 'per_100g', 100, '{}'),
      ('40000000-0000-4000-8000-000000000004', 'unrelated-source',
       '30000000-0000-4000-8000-000000000001', 'per_100g', 100, '{}');
    insert into public.food_corpus_nutrients values
      ('50000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001',
       '1162', '1162', 'Vitamin C', 'measured', 40, 'MG', '40', null, 'sr-vitc'),
      ('50000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000001',
       '1089', '1089', 'Iron', 'measured', 9, 'MG', '9', null, 'sr-fe'),
      ('50000000-0000-4000-8000-000000000003', '40000000-0000-4000-8000-000000000001',
       '1106', '1106', 'Vitamin A, RAE', 'measured', 700, 'UG', '700', null, 'sr-vita'),
      ('50000000-0000-4000-8000-000000000004', '40000000-0000-4000-8000-000000000001',
       '1406', '1406', 'PUFA 20:4 n-6', 'measured', 0.01, 'G', '0.01', null, 'sr-aa'),
      ('50000000-0000-4000-8000-000000000005', '40000000-0000-4000-8000-000000000001',
       '999999', '999999', 'Publisher mystery', 'measured', 1, 'MG', '1', null, 'sr-unknown'),
      ('50000000-0000-4000-8000-000000000006', '40000000-0000-4000-8000-000000000002',
       '1106', '1106', 'Vitamin A, RAE', 'measured', 600, 'UG', '600', null, 'foundation-vita'),
      ('50000000-0000-4000-8000-000000000007', '40000000-0000-4000-8000-000000000002',
       '1406', '1406', 'PUFA 20:3 n-6', 'measured', 0.02, 'G', '0.02', null, 'foundation-1406'),
      ('50000000-0000-4000-8000-000000000008', '40000000-0000-4000-8000-000000000003',
       '12', '12', 'Vitamin A', 'measured', 500, 'RE (µg/100g)', '500', null, 'frida-vita'),
      ('50000000-0000-4000-8000-000000000009', '40000000-0000-4000-8000-000000000004',
       '1162', '1162', 'Unrelated publisher value', 'measured', 3, 'MG', '3', null, 'unrelated-1162'),
      ('50000000-0000-4000-8000-000000000011', '40000000-0000-4000-8000-000000000001',
       '1104', '1104', 'Vitamin A, IU', 'measured', 2300, 'IU', '2300', null, 'sr-vita-iu');

    ${migration}
    ${migration}

    create temp table expected_nutrient_identities (
      source_key text not null,
      source_nutrient_code text not null,
      canonical_code text not null,
      primary key (source_key, source_nutrient_code)
    );
    insert into expected_nutrient_identities values
      ${expectedIdentityValues};

    insert into public.food_corpus_nutrients values (
      '50000000-0000-4000-8000-000000000010', '40000000-0000-4000-8000-000000000001',
      '1170', '1170', 'Pantothenic acid', 'measured', 2, 'MG', '2', null, 'future-sr-vitb5'
    );

    grant insert on public.foods to authenticated;
    set role authenticated;
    insert into public.foods values (
      '10000000-0000-4000-8000-000000000002', ${sqlText(legacy)}::jsonb, now()
    );
    reset role;

    do $$
    declare
      expected jsonb := '[
        {"nutrient_code":"VITC","name":"Vitamin C","value_per_100":40,"unit":"mg","observation_status":"measured","original_value_text":"40","derivation_method":null,"source_key":"fixture","source_reference":"vitc"},
        {"nutrient_code":"VITA","name":"Vitamin A","value_per_100":10,"unit":"µg RE","observation_status":"measured","original_value_text":"10","derivation_method":null,"source_key":"fixture","source_reference":"vita"}
      ]'::jsonb;
      sr_projected jsonb;
      foundation_projected jsonb;
      frida_projected jsonb;
      unrelated_projected jsonb;
    begin
      if (select nutrient_evidence from public.foods where id = '10000000-0000-4000-8000-000000000001') <> expected
        or (select nutrient_evidence from public.foods where id = '10000000-0000-4000-8000-000000000002') <> expected
        or (select snapshot_nutrient_evidence from public.logged_food_entries where id = '20000000-0000-4000-8000-000000000001') <> expected
      then raise exception 'legacy rows or trigger writes were not canonicalized';
      end if;
      if public.apex_valid_nutrient_evidence('[{"nutrient_code":"FE","name":"Iron","unit":"opaque","observation_status":"measured"}]'::jsonb)
      then raise exception 'opaque unit passed the hardened validator';
      end if;
      if public.apex_canonical_nutrient_unit('kcal/100 g') <> 'kcal'
        or public.apex_canonical_nutrient_unit('alfa-TE') <> 'mg α-TE'
        or public.apex_canonical_nutrient_unit('I.U.') <> 'IU'
      then raise exception 'recognized units were not canonicalized';
      end if;
      if public.apex_canonical_corpus_nutrient_unit('usda-sr-legacy', '1106', 'VITA', 'UG') <> 'µg RAE'
        or public.apex_canonical_corpus_nutrient_unit('usda-sr-legacy', '1104', 'VITA', 'IU') <> 'IU'
        or public.apex_canonical_corpus_nutrient_unit('usda-foundation', '1110', 'VITD', 'IU') <> 'IU'
        or public.apex_canonical_corpus_nutrient_unit('usda-foundation', '1114', 'VITD', 'UG') <> 'µg'
        or public.apex_canonical_corpus_nutrient_unit('dk-frida', '12', 'VITA', 'RE (µg/100g)') <> 'µg RE'
        or public.apex_canonical_corpus_nutrient_unit('dk-frida', '135', 'VITE', 'alfa-TE') <> 'mg α-TE'
        or public.apex_canonical_corpus_nutrient_unit('unrelated-source', '1106', 'VITA', 'UG') <> 'µg'
      then raise exception 'source-specific nutrient unit semantics were conflated or lost';
      end if;
      if exists (
        select 1
        from expected_nutrient_identities expected
        where public.apex_canonical_corpus_nutrient_code(
          expected.source_key,
          expected.source_nutrient_code,
          expected.source_nutrient_code
        ) is distinct from expected.canonical_code
      ) then raise exception 'server corpus identity map diverged from the reviewed generator projection';
      end if;
      sr_projected := public.apex_corpus_nutrient_evidence('40000000-0000-4000-8000-000000000001');
      foundation_projected := public.apex_corpus_nutrient_evidence('40000000-0000-4000-8000-000000000002');
      frida_projected := public.apex_corpus_nutrient_evidence('40000000-0000-4000-8000-000000000003');
      unrelated_projected := public.apex_corpus_nutrient_evidence('40000000-0000-4000-8000-000000000004');

      if jsonb_array_length(sr_projected) <> 6
        or not sr_projected @> '[
          {"nutrient_code":"VITC","unit":"mg","source_reference":"sr-vitc"},
          {"nutrient_code":"FE","unit":"mg","source_reference":"sr-fe"},
          {"nutrient_code":"VITA","unit":"µg RAE","source_reference":"sr-vita"},
          {"nutrient_code":"OMEGA6_AA","unit":"g","source_reference":"sr-aa"},
          {"nutrient_code":"999999","unit":"mg","source_reference":"sr-unknown"},
          {"nutrient_code":"VITB5","unit":"mg","source_reference":"future-sr-vitb5"}
        ]'::jsonb
        or sr_projected @> '[{"source_reference":"sr-vita-iu"}]'::jsonb
      then raise exception 'SR Legacy projection did not canonicalize exact known identities and preserve unknowns: %', sr_projected;
      end if;
      if jsonb_array_length(foundation_projected) <> 2
        or not foundation_projected @> '[
          {"nutrient_code":"VITA","unit":"µg RAE","source_reference":"foundation-vita"},
          {"nutrient_code":"1406","unit":"g","source_reference":"foundation-1406"}
        ]'::jsonb
        or foundation_projected @> '[{"nutrient_code":"OMEGA6_AA"}]'::jsonb
      then raise exception 'Foundation projection invented an SR-only identity: %', foundation_projected;
      end if;
      if frida_projected <> '[{
        "nutrient_code":"VITA","name":"Vitamin A","value_per_100":500,"unit":"µg RE",
        "observation_status":"measured","original_value_text":"500","source_key":"dk-frida",
        "source_reference":"frida-vita"
      }]'::jsonb
      then raise exception 'Frida vitamin A semantics were not preserved: %', frida_projected;
      end if;
      if jsonb_array_length(unrelated_projected) <> 1
        or unrelated_projected->0->>'nutrient_code' <> '1162'
        or unrelated_projected->0->>'unit' <> 'mg'
      then raise exception 'same numeric code from an unrelated source was invented as Vitamin C: %', unrelated_projected;
      end if;
    end
    $$;
    rollback;
  `

  const temporaryRoot = mkdtempSync(join(tmpdir(), 'apex-nutrient-unit-pg-'))
  const dataDirectory = join(temporaryRoot, 'data')
  const socketDirectory = join(temporaryRoot, 'socket')
  const sqlPath = join(temporaryRoot, 'integration.sql')
  const port = randomInt(40_000, 59_000)
  let started = false
  try {
    mkdirSync(socketDirectory)
    writeFileSync(sqlPath, integrationSQL)
    execFileSync('initdb', [
      '-D', dataDirectory, '--auth=trust', '--no-locale', '--encoding=UTF8', '--username=postgres',
    ], { stdio: 'pipe' })
    execFileSync('pg_ctl', [
      '-D', dataDirectory, '-l', join(temporaryRoot, 'postgres.log'),
      '-o', `-F -k ${socketDirectory} -p ${port}`, '-w', 'start',
    ], { stdio: 'pipe' })
    started = true
    execFileSync('psql', [
      '-h', socketDirectory, '-p', String(port), '-U', 'postgres', '-d', 'postgres',
      '-v', 'ON_ERROR_STOP=1', '-f', sqlPath,
    ], { stdio: 'pipe' })
  } finally {
    if (started) {
      execFileSync('pg_ctl', ['-D', dataDirectory, '-m', 'immediate', '-w', 'stop'], { stdio: 'pipe' })
    }
    rmSync(temporaryRoot, { recursive: true, force: true })
  }
})

test('corpus search evidence maps to a decodable Food without inventing values', () => {
  const normalized = normalizeFoodCorpusSearchResult({
    record_id: '716ed368-cabf-5a42-b17e-72a20a8397bf',
    source_key: 'ca-cnf',
    source_record_id: '571',
    name: 'Chicken, broiler, giblets, raw',
    names_i18n: { en: 'Chicken, broiler, giblets, raw' },
    aliases: ['Broiler giblets'],
    brand: null,
    barcode: null,
    market: 'Canada',
    basis_kind: 'per_100g',
    preparation_state: 'raw',
    kcal: 124,
    protein_g: 17.88,
    carbs_g: 1.8,
    fat_g: 4.47,
    fibre_g: null,
    sugar_g: 0,
    saturated_fat_g: 1.36,
    salt_g: null,
    water_g: 74.87,
    nutrient_evidence: [{
      nutrient_code: 'FE', name: 'Iron', value_per_100: 1.4, unit: 'mg',
      observation_status: 'measured', original_value_text: '1.4',
      derivation_method: null, source_key: 'ca-cnf', source_reference: '571',
    }],
  })

  assert.ok(normalized)
  assert.equal(normalized.id, '716ed368-cabf-5a42-b17e-72a20a8397bf')
  assert.equal(normalized.provider_product_id, 'corpus:ca-cnf:571')
  assert.equal(normalized.nutrition_basis, 'per_100g')
  assert.equal(normalized.preparation_state, 'unknown')
  assert.equal(normalized.kcal_100, 124)
  assert.equal(normalized.fibre_100, null)
  assert.equal(normalized.sugar_100, 0)
  assert.equal(normalized.water_ml_100, 74.87, 'one gram of food water projects to one millilitre of hydration')
  assert.equal(normalized.water_basis, 'provider_reported')
  assert.equal(normalized.water_source_id, 'corpus:ca-cnf:571:WATER')
  assert.equal(normalized.confidence, 'provider_verified')
  assert.deepEqual(normalized.nutrient_evidence, [{
    nutrient_code: 'FE', name: 'Iron', value_per_100: 1.4, unit: 'mg',
    observation_status: 'measured', original_value_text: '1.4',
    derivation_method: null, source_key: 'ca-cnf', source_reference: '571',
  }])
})

test('serving evidence uses its published gram weight without pretending the serving is 100 g', () => {
  const normalized = normalizeFoodCorpusSearchResult({
    record_id: '95bd0b7e-15ed-50e1-b8b0-a05616d9b6a5',
    source_key: 'wingstop-official',
    source_record_id: 'classic-bone-in-wings-atomic-1ea-39g',
    name: 'Wingstop Atomic Classic (Bone-In) Wings',
    names_i18n: { en: 'Wingstop Atomic Classic (Bone-In) Wings' },
    aliases: [],
    brand: 'Wingstop',
    barcode: null,
    market: 'United States',
    basis_kind: 'per_serving',
    basis_amount: 1,
    basis_unit: 'serving',
    source_metadata: { published_serving: '1ea (39g)' },
    preparation_state: 'as_sold',
    kcal: '90',
    protein_g: '10',
    carbs_g: '1',
    fat_g: '5',
    fibre_g: '0',
    sugar_g: '0',
    saturated_fat_g: '1.5',
    salt_g: null,
    water_g: null,
  })

  assert.ok(normalized)
  assert.equal(normalized.nutrition_basis, 'per_100g')
  assert.equal(normalized.serving_amount, 1)
  assert.equal(normalized.serving_unit, 'serving')
  assert.equal(normalized.serving_grams_or_ml, 39)
  assert.ok(Math.abs(normalized.kcal_100 * 0.39 - 90) < 0.000001)
  assert.ok(Math.abs(normalized.protein_100 * 0.39 - 10) < 0.000001)
  assert.equal(normalized.salt_100, null)
})

test('client food projection rejects unsupported or unweighted bases instead of mixing units', () => {
  assert.equal(
    normalizeFoodCorpusSearchResult({
      record_id: '716ed368-cabf-5a42-b17e-72a20a8397bf',
      source_key: 'example',
      source_record_id: 'one-serving',
      name: 'Serving-only evidence',
      names_i18n: {},
      aliases: [],
      brand: null,
      barcode: null,
      market: null,
      basis_kind: 'per_portion',
      basis_amount: 1,
      basis_unit: 'portion',
      source_metadata: {},
      preparation_state: null,
      kcal: 200,
      protein_g: null,
      carbs_g: null,
      fat_g: null,
      fibre_g: null,
      sugar_g: null,
      saturated_fat_g: null,
      salt_g: null,
      water_g: null,
    }),
    null,
  )
})

test('Food Lookup merges the local catalogue and canonical corpus before the public provider', () => {
  const edge = readFileSync(edgeFunctionPath, 'utf8')
  assert.match(edge, /food_corpus_search_catalog/)
  assert.match(edge, /food_corpus_search_catalog_v3/)
  assert.match(edge, /normalizeFoodCorpusSearchResult/)
  assert.match(edge, /Promise\.all/)
  assert.match(
    edge,
    /admin\s*\.from\(['"]foods['"]\)\s*\.upsert/,
    'canonical search results must exist in foods before a meal can reference them',
  )
})

test('serving projection adds source basis evidence without replacing the original search RPC', () => {
  assert.equal(existsSync(servingProjectionMigrationPath), true)
  const migration = readFileSync(servingProjectionMigrationPath, 'utf8')
  assert.match(migration, /food_corpus_search_catalog_v2/i)
  assert.match(migration, /basis_amount/i)
  assert.match(migration, /basis_unit/i)
  assert.match(migration, /source_metadata/i)
  assert.doesNotMatch(migration, /drop\s+function|drop\s+table|truncate\s+table|delete\s+from/i)
})

test('only the active validated source batch is readable and searchable', () => {
  const migration = readFileSync(activationMigrationPath, 'utf8')
  assert.match(migration, /alter policy food_corpus_records_authenticated_read/i)
  assert.match(migration, /food_corpus_batches/i)
  assert.match(migration, /batch\.status = 'active'/i)
  assert.match(migration, /record\.batch_id = batch\.id/i)
  assert.doesNotMatch(migration, /\bdelete\s+from\b|\btruncate\b|\bdrop\s+(?:table|column)\b/i)
})

test('search ranks complete macro evidence ahead of source priority without deriving blanks', () => {
  const migration = readFileSync(activationMigrationPath, 'utf8')
  const completenessOrder = migration.indexOf(
    'when search.kcal is not null and search.protein_g is not null and search.carbs_g is not null and search.fat_g is not null then 0',
  )
  const sourcePriorityOrder = migration.indexOf('search.source_priority')

  assert.notEqual(completenessOrder, -1)
  assert.ok(completenessOrder < sourcePriorityOrder)
  assert.doesNotMatch(migration, /(?:kcal|protein_g|carbs_g|fat_g)\s*=\s*coalesce\([^)]*,\s*0\)/i)
})
