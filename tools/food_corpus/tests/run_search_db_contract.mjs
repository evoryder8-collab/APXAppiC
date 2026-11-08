// Use a fresh local database: createdb fitr_food_search_test
// PGHOST/PGPORT select the local test server; no production credentials are needed.
// Run: node tools/food_corpus/tests/run_search_db_contract.mjs
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const read = path => readFileSync(new URL(`../../../${path}`, import.meta.url), 'utf8');
const args = ['-X', '-v', 'ON_ERROR_STOP=1', '-d', 'fitr_food_search_test'];
const existing = execFileSync('psql', [...args, '-Atc',
  "select count(*) from pg_tables where schemaname = 'public'"], { encoding: 'utf8' }).trim();
if (existing !== '0') throw new Error('Use an empty, isolated fitr_food_search_test database.');

const old = read('supabase/migrations/044_nutrient_evidence_and_patterns.sql')
  .match(/create or replace function public\.food_corpus_search_catalog\([\s\S]*?\$\$;/i)[0];
const columns = old.match(/returns table \(([\s\S]*?)\)\nlanguage/)[1];
const helpers = read('supabase/migrations/043_food_search_relevance.sql')
  .split('create or replace function public.search_food_catalog')[0];
const schema = `
create schema extensions;
create extension pg_trgm;
create extension fuzzystrmatch with schema extensions;
create table public.food_corpus_sources (source_key text primary key, ingest_status text);
create table public.food_corpus_batches (id uuid primary key, status text);
create table public.food_corpus_records (id uuid primary key, batch_id uuid);
create table public.food_corpus_search (${columns}, search_text text, source_priority integer);
create index idx_food_corpus_search_document on public.food_corpus_search using gin(to_tsvector('simple', search_text));
create index idx_food_corpus_search_trgm on public.food_corpus_search using gin(search_text gin_trgm_ops);
`;
const migration = read('supabase/migrations/20261108120101_rank_plain_steak.sql');
const assertions = read('tests/food-search-corpus-db-integration.sql')
  .replace(/^begin;\s*$/m, '').replace(/^rollback;\s*$/m, '');
execFileSync('psql', args, {
  input: `begin;\n${schema}\n${helpers}\n${migration}\n${assertions}\nrollback;\n`,
  cwd: root,
  stdio: ['pipe', 'inherit', 'inherit'],
});
