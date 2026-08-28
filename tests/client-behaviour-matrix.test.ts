import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import test from 'node:test'

const repository = process.cwd()
const matrixPath = join(repository, 'docs', 'PARITY-MATRIX.json')

// Roadmap 2.5 names these thirteen behaviour areas. Adding or removing an area
// is a product decision, so the contract is pinned here rather than inferred.
const requiredAreas = [
  'auth_identity',
  'languages',
  'simple_advanced_modes',
  'date_calendar',
  'nutrition_targets',
  'activity_estimator',
  'meal_composer_memory',
  'hydration',
  'supplements',
  'recovery_wearables',
  'avatar',
  'orbit',
  'settings',
].sort()

const requiredDimensions = [
  'behaviour',
  'calculations',
  'database_reads',
  'database_writes',
  'ownership',
  'offline',
  'errors',
  'localisation',
  'date_handling',
].sort()

test('roadmap parity matrix pins every required behaviour area and comparison dimension', () => {
  assert.ok(
    existsSync(matrixPath),
    'Roadmap 2.5 requires docs/PARITY-MATRIX.json; add the executed behaviour matrix before closing the task.',
  )

  const matrix = JSON.parse(readFileSync(matrixPath, 'utf8'))
  assert.equal(matrix.schema_version, 1)
  assert.deepEqual([...matrix.comparison_dimensions].sort(), requiredDimensions)
  assert.deepEqual(matrix.areas.map((area: { id: string }) => area.id).sort(), requiredAreas)

  for (const area of matrix.areas) {
    assert.ok(
      ['matched', 'intentional_platform_difference'].includes(area.status),
      `${area.id} must be resolved or document an intentional platform difference; gaps cannot close 2.5.`,
    )
    assert.ok(area.observations.length > 0, `${area.id} needs a concrete behavioural observation.`)
    assert.deepEqual(Object.keys(area.dimensions).sort(), requiredDimensions, `${area.id} must assess every comparison dimension.`)

    for (const [dimension, assessment] of Object.entries(area.dimensions) as Array<
      [string, { verdict: string; evidence: string }]
    >) {
      assert.ok(
        ['shared', 'platform_specific', 'not_applicable'].includes(assessment.verdict),
        `${area.id}.${dimension} has an unresolved verdict.`,
      )
      assert.ok(assessment.evidence.trim().length > 0, `${area.id}.${dimension} needs evidence or an explicit reason.`)
    }

    for (const client of ['web', 'native']) {
      const evidence = area.evidence[client]
      assert.ok(evidence.tests.length > 0, `${area.id} needs ${client} behavioural tests.`)
      assert.ok(evidence.sources.length > 0, `${area.id} needs ${client} production-source evidence.`)

      for (const relativePath of [...evidence.tests, ...evidence.sources]) {
        assert.ok(!/screenshot/i.test(relativePath), `${area.id} cannot use screenshots as parity evidence.`)
        assert.ok(existsSync(join(repository, relativePath)), `${area.id} evidence is missing: ${relativePath}`)
      }

      for (const relativePath of evidence.tests) {
        const body = readFileSync(join(repository, relativePath), 'utf8')
        assert.match(body, /(?:\btest\s*\(|func\s+test)/, `${relativePath} does not contain executable tests.`)
      }
    }
  }
})
