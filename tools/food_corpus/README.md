# Food Knowledge Corpus tooling

This directory contains deterministic, source-specific adapters for staging food-composition evidence. Raw publisher bundles and generated staging files must stay outside the repository and outside every app target.

## Runtime

- Python 3.11 or newer
- `openpyxl` from `requirements.txt` for spreadsheet sources
- LibreOffice `soffice` for the legacy CIQUAL `.xls` conversion

Install the Python dependency into an isolated environment, then verify the supplied bundle before parsing it:

```sh
python3 -m venv /tmp/apex-food-corpus-venv
/tmp/apex-food-corpus-venv/bin/pip install -r tools/food_corpus/requirements.txt
/tmp/apex-food-corpus-venv/bin/python tools/food_corpus/import_food_corpus.py validate-registry \
  --source-root /absolute/path/to/food-composition-tables
```

Stage one approved source at a time into an external directory:

```sh
/tmp/apex-food-corpus-venv/bin/python tools/food_corpus/import_food_corpus.py stage-source \
  --source-root /absolute/path/to/food-composition-tables \
  --source usda-foundation \
  --output /absolute/external/staging/path
```

Each staged source includes its source, batch, canonical record, multilingual name, nutrient-evidence, and bounded search-projection rows plus a manifest. Trace, below-detection, not-measured, and missing observations retain a null numeric value and their original evidence text. Staging never derives a nutrient merely to fill a blank.

`sources.json` is the licence and provenance gate. Quarantined entries cannot be staged. Open Food Facts remains isolated because its ODbL share-alike obligations must not be blended into the permissive corpus, and the FAO bundles remain quarantined pending source-specific redistribution review.

## Production projection and evidence archives

Production keeps the searchable record/name/macro projection in Postgres and the complete nutrient evidence in the private `food-corpus-evidence` Storage bucket. Generate both from the same checksum-validated staging directory:

```sh
/tmp/apex-food-corpus-venv/bin/python tools/food_corpus/import_food_corpus.py emit-remote-sql \
  --stage-dir /absolute/external/staging/path \
  --output-dir /absolute/external/transfer/path \
  --base-url https://temporary-transfer.example/source \
  --compact-evidence
```

Compact mode writes a deterministic `evidence/nutrients.ndjson.gz` archive with a zero gzip timestamp. Its object path, SHA-256 checksum, media type, and preserved observation count are recorded in both the transfer manifest and the source metadata. Upload that exact archive to the manifest's `object_path`; the bucket must remain private. The generated SQL deliberately omits row-wise `food_corpus_nutrients` inserts, but still validates record, name, and search counts before activating the source batch.

Keep staging, transfer payloads, archives, and any temporary HTTPS server outside the repository. Verify the archive checksum before upload, execute registration and load scripts in lexical order, run `999-activate.sql` last, and retire the temporary transfer endpoint immediately afterward.

## Reviewed natural-food evidence

The human-reviewed approval TSVs, review notes, and rejection decisions are committed under `docs/food-corpus/natural-food-evidence-review/`. They are generator inputs. The normalized crosswalk, rejection report, provenance manifest, and shared evidence resource beside them are generated artifacts.

Run the focused integrity suite from a clean checkout with only committed fixtures and review inputs:

```sh
npm run test:natural-food-evidence
```

Regenerate from the committed review inputs plus externally staged, checksum-verified publisher data:

```sh
node tools/food_corpus/build_natural_food_evidence.mjs \
  --reviewed-dir docs/food-corpus/natural-food-evidence-review \
  --crosswalk docs/food-corpus/natural-food-evidence-crosswalk.json \
  --source usda-sr-legacy=$USDA_SR_LEGACY_DIR \
  --source usda-foundation=$USDA_FOUNDATION_DIR \
  --source dk-frida=$DK_FRIDA_DIR
```

The generator pairs each staged manifest's artifact filename with the approved registry path and checksum, preserves the reviewed macro delta when choosing Foundation energy methods, and derives the JSON rejection report from `rejections.tsv`.

## Search checks after a large corpus load

After activating a source batch, refresh planner statistics for the affected corpus projection tables with targeted maintenance (never a database-wide rebuild):

```sql
ANALYZE public.food_corpus_sources;
ANALYZE public.food_corpus_batches;
ANALYZE public.food_corpus_records;
ANALYZE public.food_corpus_search;
ANALYZE public.food_corpus_nutrients;
```

The search RPC first uses `idx_food_corpus_search_document` for whole-word matches in any order. `seed`, `seeds`, and `seeded` share a small explicit word family; this does not match unrelated `breadnut` or `breadcrumbs` when the query asks for `bread`. The existing typo/connected-word fallback runs only when no active source and active batch provide a strong match. Do not replace it with a broad first-token scan, expand the client wait indefinitely, or increase the authenticated statement timeout.

Validate `bread seeds`, `BRead sunflower`, a supported typo such as `strawbery`, and a basic food under the existing authenticated 8-second statement timeout. Check that the indexed branch runs and the broad fallback has zero loops for strong matches. A successful administrator query without that time limit does not prove the user path is healthy. Keep full Edge-request verification separate from direct RPC evidence; it requires an existing test-account session.
