import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import { authoredVoiceLocales, authoredVoiceRows } from './native-voice-copy.mjs'

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url))
const resources = path.resolve(toolsDirectory, '../APEX/Resources')

function escapeStrings(value) {
  return value
    .replaceAll('\\', '\\\\')
    .replaceAll('"', '\\"')
    .replaceAll('\n', '\\n')
    .replaceAll('\r', '\\r')
}

let replacements = 0
for (const locale of authoredVoiceLocales.filter((value) => value !== 'en')) {
  const file = path.join(resources, `${locale}.lproj/Localizable.strings`)
  const lines = fs.readFileSync(file, 'utf8').split('\n')

  for (const row of authoredVoiceRows) {
    const prefix = `"${escapeStrings(row.key)}" = `
    const matches = lines
      .map((line, index) => (line.startsWith(prefix) ? index : -1))
      .filter((index) => index >= 0)
    if (matches.length !== 1) {
      throw new Error(
        `${locale} expected exactly one runtime row for "${row.key}", found ${matches.length}.`,
      )
    }
    lines[matches[0]] = `${prefix}"${escapeStrings(row.copy[locale])}";`
    replacements += 1
  }

  fs.writeFileSync(file, lines.join('\n'))
}

console.log(
  `Applied ${authoredVoiceRows.length} authored voice entries across ${authoredVoiceLocales.length - 1} translated locales (${replacements} runtime rows).`,
)
