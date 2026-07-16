import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { entryRevealDelay } from '../src/lib/entryFlow.ts'
import { INTRO_COPY, LOGIN_COPY, localizedLoginError } from '../src/lib/introLanguage.ts'

const app = readFileSync(new URL('../src/App.tsx', import.meta.url), 'utf8')
const neutralEntry = readFileSync(new URL('../src/components/NeutralEntry.tsx', import.meta.url), 'utf8')
const login = readFileSync(new URL('../src/pages/Login.tsx', import.meta.url), 'utf8')
const store = readFileSync(new URL('../src/store/AppStore.tsx', import.meta.url), 'utf8')

test('the primary entry surface stays neutral and identity is authentication-gated', () => {
  assert.match(app, /entrySurface.*'neutral'.*'login'/s)
  assert.match(app, /<NeutralEntry/)
  assert.doesNotMatch(app, /entrySurface === 'profiles'|onBrowse=/)
  assert.doesNotMatch(neutralEntry, /PERSONAS|\.portrait|persona\.name/)
  assert.doesNotMatch(neutralEntry, /copy\.browse/)
  assert.match(neutralEntry, /data-testid="neutral-entry"/)
})

test('login reveals the authenticated persona only after successful authentication', () => {
  assert.match(login, /data-testid="neutral-login"/)
  assert.match(login, /setRevealedPersona\(result\.persona\)/)
  assert.match(login, /data-testid="authenticated-persona-reveal"/)
  assert.match(login, /onSuccessRef\.current\(revealedPersona\).*entryRevealDelay\(Boolean\(reduceMotion\)\)/s)
  assert.match(login, /export function Login\(\{ onBack, onSuccess \}/)
  assert.ok(entryRevealDelay(true) < entryRevealDelay(false))
})

test('authentication resolves account persona without exposing a profile mismatch', () => {
  assert.match(store, /setSelectedPersona\(accountPersona\)/)
  assert.match(store, /return \{ error: null, persona: accountPersona \}/)
  assert.doesNotMatch(store, /Those credentials belong to/)
  for (const language of ['en', 'ro', 'th'] as const) {
    const message = localizedLoginError('Those credentials belong to June. Choose that profile to continue.', language)
    assert.equal(message.includes('June'), false)
    assert.equal(localizedLoginError('Email not confirmed', language), localizedLoginError('Invalid login credentials', language))
  }
})

test('neutral entry and reveal copy is complete in every intro language', () => {
  for (const language of ['en', 'ro', 'th'] as const) {
    assert.ok(INTRO_COPY[language].neutralTitle)
    assert.ok(INTRO_COPY[language].enter)
    assert.ok(INTRO_COPY[language].browse)
    assert.ok(LOGIN_COPY[language].title)
    assert.ok(LOGIN_COPY[language].verified)
    assert.ok(LOGIN_COPY[language].ready)
  }
})
