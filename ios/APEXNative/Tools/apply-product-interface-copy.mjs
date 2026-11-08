import { readFileSync, writeFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { interfaceLocales, productInterfaceCopy } from '../../../shared/productInterfaceCopy.ts'

const escape = value => value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')

export function applyProductInterfaceCopy(resources = new URL('../APEX/Resources/', import.meta.url), check = false) {
  for (const [index, locale] of interfaceLocales.entries()) {
    if (locale === 'en') continue
    const file = new URL(`${locale}.lproj/Localizable.strings`, resources)
    const original = readFileSync(file, 'utf8')
    const authored = new Map()
    for (const row of productInterfaceCopy) {
      if (row.length !== interfaceLocales.length || row.some(value => !value.trim())) throw new Error(`Incomplete interface copy: ${row[0]}`)
      const key = escape(row[0])
      authored.set(key, `"${key}" = "${escape(row[index])}";`)
    }
    const missing = new Set(authored.keys())
    const lines = original.trimEnd().split('\n').map(line => {
      const key = line.match(/^"((?:[^"\\]|\\.)*)"\s*=/)?.[1]
      if (!authored.has(key)) return line
      missing.delete(key)
      return authored.get(key)
    })
    for (const key of missing) lines.push(authored.get(key))
    const output = lines.join('\n') + '\n'
    if (check && original !== output) throw new Error(`Regenerate ${locale} interface copy`)
    if (!check && original !== output) writeFileSync(file, output)
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  applyProductInterfaceCopy(undefined, process.argv.includes('--check'))
}
