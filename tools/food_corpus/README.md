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
