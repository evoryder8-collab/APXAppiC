import { asianVoiceCopy } from './native-voice-copy-asian.mjs'
import { germanVoiceCopy } from './native-voice-copy-german.mjs'
import { romanceVoiceCopy } from './native-voice-copy-romance.mjs'
import { romanianVoiceCopy } from './native-voice-copy-romanian.mjs'
import { nativeVoiceMeanings } from './native-voice-meanings.mjs'

export const authoredVoiceLocales = ['en', 'de', 'de-CH', 'it', 'es', 'pt', 'ja', 'ro', 'th']

const localeCopy = {
  de: germanVoiceCopy.de,
  'de-CH': germanVoiceCopy['de-CH'],
  it: romanceVoiceCopy.it,
  es: romanceVoiceCopy.es,
  pt: romanceVoiceCopy.pt,
  ja: asianVoiceCopy.ja,
  ro: romanianVoiceCopy,
  th: asianVoiceCopy.th,
}

const expectedKeys = new Set(nativeVoiceMeanings.map(({ key }) => key))
if (expectedKeys.size !== nativeVoiceMeanings.length) {
  throw new Error('The authored voice corpus contains a duplicate runtime key.')
}

for (const locale of authoredVoiceLocales.filter((value) => value !== 'en')) {
  const values = localeCopy[locale]
  if (!values) throw new Error(`Missing authored voice map for ${locale}.`)
  const actualKeys = Object.keys(values)
  const missing = [...expectedKeys].filter((key) => !(key in values))
  const unexpected = actualKeys.filter((key) => !expectedKeys.has(key))
  if (missing.length || unexpected.length) {
    throw new Error(
      `${locale} authored voice keys do not match the meaning corpus. Missing: ${missing.join(' | ') || 'none'}. Unexpected: ${unexpected.join(' | ') || 'none'}.`,
    )
  }
}

export const authoredVoiceRows = nativeVoiceMeanings.map((row) => ({
  ...row,
  copy: Object.fromEntries(
    authoredVoiceLocales.map((locale) => [
      locale,
      locale === 'en' ? row.key : localeCopy[locale][row.key],
    ]),
  ),
}))
