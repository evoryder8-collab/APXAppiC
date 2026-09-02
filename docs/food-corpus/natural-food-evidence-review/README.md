# Natural-food evidence review inputs

This directory is the committed source of truth for the natural-food evidence generator. The three crosswalk TSVs contain approved target-to-donor decisions and their reviewed donor-minus-target macro deltas. `rejections.tsv` contains the explicit rejected targets and reason codes. The matching Markdown files retain the human review rationale.

Generated files live one directory above:

- `natural-food-evidence-crosswalk.json`
- `natural-food-evidence-rejections.json`
- `natural-food-evidence-manifest.json`

Raw publisher bundles and staged nutrient records are deliberately not committed. They must be supplied externally and are accepted only when their staged checksums, source identity, and artifact filename match `tools/food_corpus/sources.json`.
