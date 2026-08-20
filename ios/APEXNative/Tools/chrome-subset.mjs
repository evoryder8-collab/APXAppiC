/*
 * Splits the translatable strings into chrome and content.
 *
 * Chrome is what a person reads in order to operate the app: buttons, labels,
 * headings, status, empty states. Content is the material the app is about:
 * exercise names, food items, coaching paragraphs, evidence citations.
 *
 * The distinction matters because the two need different treatment. Chrome is
 * finite, high traffic and worth translating by hand; content is thousands of
 * strings where a wrong word is a factual error, not an awkward one, and it
 * belongs with a translator who knows the domain.
 *
 * Classification is by where a string is used, not by how it looks: a literal
 * that appears in a view file is chrome, one that only ever appears in an
 * engine's data tables is content.
 *
 *   node ios/APEXNative/Tools/chrome-subset.mjs            counts
 *   node ios/APEXNative/Tools/chrome-subset.mjs --list de  what German still needs
 */
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = new URL('../APEX', import.meta.url).pathname

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) return swiftFiles(path)
    return path.endsWith('.swift') ? [path] : []
  })
}

function tableKeys(language) {
  const source = readFileSync(
    join(ROOT, 'Resources', `${language}.lproj`, 'Localizable.strings'), 'utf8'
  )
  const keys = new Set()
  for (const m of source.matchAll(/^\s*"((?:[^"\\]|\\.)*)"\s*=/gm)) keys.add(m[1])
  return keys
}

/* Every literal in every file, with the files it appears in. */
const usage = new Map()
for (const file of swiftFiles(ROOT)) {
  const source = readFileSync(file, 'utf8')
  const relative = file.replace(ROOT, 'APEX')
  for (const m of source.matchAll(/"((?:[^"\\\n]|\\.)*)"/g)) {
    if (!usage.has(m[1])) usage.set(m[1], new Set())
    usage.get(m[1]).add(relative)
  }
}

/* A view file draws things on screen. An engine computes them. */
const isView = (path) =>
  path.startsWith('APEX/Features/') || path.startsWith('APEX/Core/DesignSystem/')

const reference = tableKeys('ro')
const chrome = []
const content = []
for (const key of reference) {
  const files = usage.get(key)
  /* A string in no source file is reached through data rather than code, which
     puts it with the content. */
  const inView = files ? [...files].some(isView) : false
  /* A paragraph is content wherever it appears: it is prose to be written, not
     a label to be matched. */
  ;(inView && key.length <= 60 ? chrome : content).push(key)
}

const language = process.argv[3]
if (process.argv.includes('--list') && language) {
  const done = tableKeys(language)
  const missing = chrome.filter((key) => !done.has(key)).sort()
  console.log(`${language}: ${chrome.length - missing.length}/${chrome.length} chrome translated`)
  for (const key of missing) console.log(JSON.stringify(key))
} else {
  console.log(`chrome   ${chrome.length}`)
  console.log(`content  ${content.length}`)
  for (const code of ['de', 'de-CH', 'it', 'es', 'ja', 'pt']) {
    const done = tableKeys(code)
    const have = chrome.filter((key) => done.has(key)).length
    const percent = ((have / chrome.length) * 100).toFixed(0)
    console.log(`  ${code.padEnd(6)} ${String(have).padStart(4)}/${chrome.length} chrome (${percent}%)`)
  }
}
