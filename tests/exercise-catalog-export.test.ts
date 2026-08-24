import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import test from 'node:test'
import {
  EXERCISE_CATALOG_EXPORT_HEADERS,
  EXERCISE_CATALOG_EXPORT_PATH,
  EXERCISE_CATALOG_EXPORT_ROWS,
  renderExerciseCatalogCsv,
} from '../tools/export-exercise-catalog.mts'

function column(name: typeof EXERCISE_CATALOG_EXPORT_HEADERS[number]): number {
  return EXERCISE_CATALOG_EXPORT_HEADERS.indexOf(name)
}

test('the owner catalogue export contains every selectable app item exactly once', () => {
  assert.equal(EXERCISE_CATALOG_EXPORT_ROWS.length, 549)
  assert.equal(new Set(EXERCISE_CATALOG_EXPORT_ROWS.map((row) => row[column('id')])).size, 549)
  assert.equal(EXERCISE_CATALOG_EXPORT_ROWS.filter((row) => row[column('record_type')] === 'movement').length, 534)
  assert.equal(EXERCISE_CATALOG_EXPORT_ROWS.filter((row) => row[column('record_type')] === 'cardio_modality').length, 15)
  assert.equal(EXERCISE_CATALOG_EXPORT_ROWS.filter((row) => row[column('owner_csv_exact_match')] === 'yes').length, 219)
  assert.equal(EXERCISE_CATALOG_EXPORT_ROWS.filter((row) => row[column('owner_csv_disposition')] === 'already_canonical').length, 10)
  assert.equal(EXERCISE_CATALOG_EXPORT_ROWS.filter((row) => row[column('owner_csv_disposition')] === 'enriched_from_review_queue').length, 209)
})

test('the checked-in CSV is an exact generated view of the live catalogue', () => {
  assert.equal(existsSync(EXERCISE_CATALOG_EXPORT_PATH), true, `${EXERCISE_CATALOG_EXPORT_PATH} is missing`)
  if (!existsSync(EXERCISE_CATALOG_EXPORT_PATH)) return
  assert.equal(readFileSync(EXERCISE_CATALOG_EXPORT_PATH, 'utf8'), renderExerciseCatalogCsv())
})

test('HYROX rows carry all eight official station numbers without gaps', () => {
  const stations = EXERCISE_CATALOG_EXPORT_ROWS
    .filter((row) => typeof row[column('hyrox_station_order')] === 'number')
    .sort((left, right) => Number(left[column('hyrox_station_order')]) - Number(right[column('hyrox_station_order')]))
  assert.deepEqual(stations.map((row) => row[column('hyrox_station_order')]), [1, 2, 3, 4, 5, 6, 7, 8])
  assert.deepEqual(
    stations.map((row) => row[column('id')]),
    ['ski_erg', 'sled_push', 'sled_pull', 'burpee_broad_jump', 'row_erg', 'farmers_carry', 'sandbag_lunge', 'wall_ball'],
  )
})
