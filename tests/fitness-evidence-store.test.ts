import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const types = readFileSync(new URL('../src/lib/types.ts', import.meta.url), 'utf8')
const store = readFileSync(new URL('../src/store/AppStore.tsx', import.meta.url), 'utf8')
const local = readFileSync(new URL('../src/lib/local.ts', import.meta.url), 'utf8')
const nativeModels = readFileSync(new URL(
  '../ios/APEXNative/APEX/Core/Models/APEXModels.swift',
  import.meta.url,
), 'utf8')
const nativeService = readFileSync(new URL(
  '../ios/APEXNative/APEX/Core/Networking/SupabaseService.swift',
  import.meta.url,
), 'utf8')
const nativeSession = readFileSync(new URL(
  '../ios/APEXNative/APEX/App/AppSession.swift',
  import.meta.url,
), 'utf8')

test('web hydrates immutable evidence into account-scoped cache', () => {
  assert.match(types, /export interface FitnessEvidenceRecord/)
  assert.match(types, /fitness_evidence:\s*FitnessEvidenceRecord\[\]/)
  assert.match(types, /fitness_evidence:\s*\[\]/)
  assert.match(store, /from\(['"]fitness_evidence['"]\)[\s\S]{0,220}eq\(['"]user_id['"],\s*sessionUserId\)/)
  assert.match(store, /fitness_evidence:\s*value\.fitness_evidence\s*\?\?\s*\[\]/)
  assert.match(store, /table\s*===\s*['"]fitness_evidence['"]/)
})
test('web evidence writes use a durable RPC operation and never a generic table mutation', () => {
  const listTableSection = store.slice(store.indexOf('export type ListTable'), store.indexOf('const LIST_TABLES'))
  assert.doesNotMatch(listTableSection, /fitness_evidence/)
  assert.match(local, /type:\s*['"]upsert['"]\s*\|\s*['"]delete['"]\s*\|\s*['"]rpc['"]/)
  assert.match(local, /rpc_function\??:/)
  assert.match(store, /recordFitnessEvidence/)
  assert.match(store, /record_user_fitness_evidence/)
  assert.match(store, /syncClient\.rpc\(op\.rpc_function/)
  assert.doesNotMatch(store, /from\(['"]fitness_evidence['"]\)\.(?:upsert|insert|update|delete)/)
})

test('native dashboard hydration is read-only and user recording uses the RPC outbox', () => {
  assert.match(nativeModels, /struct FitnessEvidenceRecord:\s*Codable/)
  assert.match(nativeModels, /var fitnessEvidence:\s*\[FitnessEvidenceRecord\]\?\s*=\s*\[\]/)
  assert.match(nativeService, /from\(['"]fitness_evidence['"]\)\.select\(\)/)
  assert.match(nativeService, /recordUserFitnessEvidence/)
  assert.match(nativeService, /rpc\(['"]record_user_fitness_evidence['"]/)
  assert.match(nativeSession, /OfflineOperation\.rpc\(['"]record_user_fitness_evidence['"]/)
  assert.doesNotMatch(nativeService, /upsert\([^\n]*table:\s*['"]fitness_evidence['"]/)
})
