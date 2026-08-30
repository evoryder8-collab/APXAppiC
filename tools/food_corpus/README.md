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
