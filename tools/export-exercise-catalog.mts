import { createHash } from 'node:crypto'
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import {
  EXERCISE_CATALOG,
  type ExerciseCatalogItem,
} from '../src/data/exerciseCatalog.ts'
import {
  CARDIO_MODALITIES,
  MOVEMENT_BY_ID,
  MOVEMENTS,
} from '../src/data/movements.ts'
import { HYROX_STATIONS } from '../src/lib/eventCampaign.ts'
import {
  buildReviewCandidates,
  parseExerciseImportCsv,
} from './exercise-import-review.mjs'

export const EXERCISE_CATALOG_EXPORT_PATH = 'docs/APEX-CURRENT-EXERCISE-CATALOG.csv'

export const EXERCISE_CATALOG_EXPORT_HEADERS = [
  'catalog_order',
  'id',
  'name_en',
  'name_ro',
  'name_th',
  'record_type',
  'primary_category',
  'all_categories',
  'disciplines',
  'hyrox_station_order',
  'hyrox_station_name',
  'equipment',
  'equipment_required',
  'equipment_any_of',
  'muscles',
  'primary_muscles',
  'secondary_muscles',
  'stabilizer_muscles',
  'hologram_muscles',
  'movement_pattern',
  'entity_type',
  'prescription_mode',
  'default_sets',
  'default_reps_or_duration',
  'unit',
  'default_rest_seconds',
  'per_side',
  'loadable',
  'increment_kg',
  'can_fail_safely',
  'needs_spotter',
  'needs_safeties',
  'contraindications',
  'technical_complexity',
  'stability_demand',
  'impact_level',
  'space_requirement',
  'requires_bail_skill',
  'fail_safe_conditions',
  'coached_only',
  'adult_auto_assignable',
  'youth_auto_assignable',
  'role',
  'fatigue_cost',
  'tempo_applies',
  'tempo_class',
  'review_status',
  'evidence_source_ids',
  'owner_csv_exact_match',
  'owner_csv_disposition',
  'owner_csv_source_name',
  'english_aliases',
  'notes',
] as const

export type ExerciseCatalogExportCell = string | number | boolean | null

const ownerImportURL = new URL('../data/imports/exercise_extra_encyclopedia_with_sport_tags.csv', import.meta.url)
const ownerImport = readFileSync(ownerImportURL, 'utf8')
const ownerSourceSha256 = createHash('sha256')
  .update(ownerImport.replaceAll('\n', '\r\n'))
  .digest('hex')
const exactOwnerRows = new Map(
  buildReviewCandidates(
    parseExerciseImportCsv(ownerImport),
    [
      ...MOVEMENTS.map(({ id, name }) => ({ id, name })),
      ...CARDIO_MODALITIES.map(({ id, name }) => ({ id, name })),
    ],
    ownerSourceSha256,
  )
    .filter((candidate) => candidate.matchStatus === 'canonical_exact')
    .map((candidate) => [candidate.matchedMovementId, candidate.name]),
)

const cardioByID = new Map(CARDIO_MODALITIES.map((modality) => [modality.id, modality]))
const hyroxByID = new Map(HYROX_STATIONS.map((station) => [
  station.movementId ?? station.cardio!.modality,
  station,
]))

function exportRow(item: ExerciseCatalogItem, index: number): ExerciseCatalogExportCell[] {
  const movement = MOVEMENT_BY_ID.get(item.id)
  const cardio = cardioByID.get(item.id)
  const station = hyroxByID.get(item.id)
  const exactOwnerName = exactOwnerRows.get(item.id) ?? ''
  const ownerName = movement?.importSourceName ?? exactOwnerName
  const ownerDisposition = movement?.importSourceName
    ? 'enriched_from_review_queue'
    : exactOwnerName ? 'already_canonical' : ''
  return [
    index + 1,
    item.id,
    item.names.en,
    item.names.ro,
    item.names.th,
    movement ? 'movement' : 'cardio_modality',
    item.category,
    item.categories.join('; '),
    movement?.disciplines.join('; ') ?? 'cardio',
    station?.order ?? null,
    station?.name ?? '',
    item.equipment,
    (movement?.equipment ?? cardio?.equipment ?? []).join('; '),
    movement?.equipmentAnyOf.map((group) => group.join(' | ')).join('; ') ?? '',
    movement
      ? [...new Set([...movement.primaryMuscles, ...movement.secondaryMuscles])].join('; ')
      : item.muscles.join('; '),
    movement?.primaryMuscles.join('; ') ?? '',
    movement?.secondaryMuscles.join('; ') ?? '',
    movement?.stabilizerMuscles.join('; ') ?? '',
    item.muscles.join('; '),
    movement?.pattern ?? 'cardio',
    movement?.entityType ?? 'cardio_modality',
    movement?.prescriptionMode ?? 'interval',
    item.sets,
    item.reps,
    item.unit,
    item.rest,
    item.perSide,
    item.loadable,
    item.incrementKG,
    movement?.canFailSafely ?? null,
    movement?.needsSpotter ?? null,
    movement?.needsSafeties ?? null,
    (movement?.contraindications ?? cardio?.contraindications ?? []).join('; '),
    movement?.technicalComplexity ?? null,
    movement?.stabilityDemand ?? null,
    movement?.impact ?? null,
    movement?.spaceRequirement ?? '',
    movement?.requiresBailSkill ?? null,
    movement?.failSafeConditions.join('; ') ?? '',
    movement?.coachedOnly ?? null,
    movement?.adultAutoAssignable ?? null,
    movement?.youthAutoAssignable ?? null,
    movement?.role ?? '',
    movement?.fatigueCost ?? null,
    movement?.tempoApplies ?? null,
    movement?.tempoClass ?? '',
    movement?.reviewStatus ?? 'catalogued_cardio_modality',
    movement?.evidenceSourceIds.join('; ') ?? '',
    ownerName ? 'yes' : 'no',
    ownerDisposition,
    ownerName,
    item.aliases.en.join('; '),
    movement?.notes ?? cardio?.notes ?? '',
  ]
}

export const EXERCISE_CATALOG_EXPORT_ROWS = EXERCISE_CATALOG.map(exportRow)

function csvCell(value: ExerciseCatalogExportCell): string {
  if (value == null) return ''
  const text = String(value)
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text
}

export function renderExerciseCatalogCsv(
  rows: ExerciseCatalogExportCell[][] = EXERCISE_CATALOG_EXPORT_ROWS,
  headers: readonly string[] = EXERCISE_CATALOG_EXPORT_HEADERS,
): string {
  return [headers, ...rows]
    .map((row) => row.map(csvCell).join(','))
    .join('\n') + '\n'
}

/** Full owner download, preserving both platforms' authored display labels. */
export function renderExerciseLibraryCsv(): string {
  const native: { exercises: Array<{ id: string; names: Record<string, string>; aliases: Record<string, string[]> }> } = JSON.parse(
    readFileSync(new URL('../ios/APEXNative/APEX/Resources/exercise-catalog.json', import.meta.url), 'utf8'),
  )
  const nativeByID = new Map(native.exercises.map((item) => [item.id, item]))
  const webIDs = new Set(EXERCISE_CATALOG.map((item) => item.id))
  if (webIDs.size !== EXERCISE_CATALOG.length || nativeByID.size !== native.exercises.length
    || nativeByID.size !== webIDs.size || [...webIDs].some((id) => !nativeByID.has(id))) {
    throw new Error('Web and iOS exercise libraries differ; reconcile them before exporting.')
  }
  const languages = [...new Set(native.exercises.flatMap((item) => [...Object.keys(item.names), ...Object.keys(item.aliases)]))]
  const headers = [
    ...EXERCISE_CATALOG_EXPORT_HEADERS,
    'canonical_name', 'movement_id', 'day_type', 'romanian_aliases', 'thai_aliases',
    ...languages.map((language) => `ios_name_${language}`),
    ...languages.map((language) => `ios_aliases_${language}`),
  ]
  const rows = EXERCISE_CATALOG.map((item, index) => {
    const ios = nativeByID.get(item.id)!
    return [
      ...EXERCISE_CATALOG_EXPORT_ROWS[index],
      item.name, item.movementID, item.dayType, item.aliases.ro.join('; '), item.aliases.th.join('; '),
      ...languages.map((language) => ios.names[language] ?? ''),
      ...languages.map((language) => (ios.aliases[language] ?? []).join('; ')),
    ]
  })
  return renderExerciseCatalogCsv(rows, headers)
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const outputArgument = process.argv.indexOf('--output')
  if (outputArgument !== -1) {
    const outputPath = process.argv[outputArgument + 1]
    if (!outputPath || outputPath.startsWith('--')) throw new Error('--output requires a file path')
    writeFileSync(outputPath, renderExerciseLibraryCsv(), 'utf8')
    process.stdout.write(`Exported ${EXERCISE_CATALOG_EXPORT_ROWS.length} exercises to ${outputPath}\n`)
  } else {
    process.stdout.write(renderExerciseCatalogCsv())
  }
}
