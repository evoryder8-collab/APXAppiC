# Natural Food Micronutrient Enrichment Design

## Outcome

APEX should show source-backed vitamins, minerals, fatty-acid details, carbohydrate details, and water for the essential generic natural foods already present in Food Memory. A familiar local food such as **Strawberries, fresh** remains the visible result; its detailed nutrition sheet gains evidence from one approved official composition record.

## Evidence boundary

- Values come only from checksum-verified, approved food-composition datasets registered in `tools/food_corpus/sources.json`.
- One target food receives one whole donor record. APEX never fills gaps by blending values from several databases.
- Trace, below-detection, not-measured, and missing values remain distinct from numeric zero.
- Every approved link must match mass/volume basis, ingredient identity, and preparation. Energy, protein, carbohydrate, and fat must also pass the documented fingerprint tolerance.
- Ambiguity fails closed. Search similarity can create a review candidate but can never approve a link.
- User-created foods, private foods, barcode products, branded label records, recipes, mixtures, oil-added preparations, and historical meal snapshots are not rewritten.

## Initial coverage

The first production pass targets the canonical identities behind the existing generic fruits, vegetables and leaves, meat and poultry, fish and shellfish, eggs, plain dairy, legumes, grains and starches, nuts, and seeds. Retailer-reference copies and mechanically generated cooking-method labels do not count as distinct coverage.

Approval requires an exact reviewed source link. Foods that cannot be linked safely remain honest macro-only records and appear in a rejection report rather than receiving guessed micronutrients.

## Architecture

1. The existing deterministic corpus importer stages official source bundles outside the repository.
2. A new generator reads the client catalogue plus staged official records, creates strict candidates, canonicalizes the essential vitamin/mineral/fat/carbohydrate codes, and emits:
   - a human-reviewable manifest;
   - a bounded SQL evidence payload for approved curated provider IDs;
   - an explicit rejection report.
3. The production migration applies evidence only to an empty, global curated food row whose provider ID, basis, preparation signature, brand state, and macro fingerprint still equal the reviewed target. It deliberately does not change `updated_at`.
4. Web and native search coalesce an evidence-rich server copy into the matching local read model before duplicate removal. The local identity, translated names, portions, macros, water settings, rank, and preferences remain unchanged.
5. Successful enrichment is cached through the existing local food snapshot paths. New meal logs snapshot the effective evidence; old receipts stay immutable.

## Runtime identity and precedence

Runtime transfer requires the same non-empty `provider_product_id` and the same public food ID. Basis, preparation state, brand, and macro fingerprint must still match. Runtime never transfers evidence using name similarity.

Precedence is:

1. Existing explicit target evidence.
2. The exact compatible server copy for the same curated provider ID.
3. Existing coarse macro/fibre/water fallback.

## Nutrient projection

The bounded projection prioritizes user-facing nutrition facts and essential micronutrients: calories, protein, total carbohydrate, fibre, sugars, starch, total/saturated/trans/mono/polyunsaturated fat, omega-3/6, cholesterol, sodium/salt, water, vitamins A/C/D/E/K and B1/B2/B3/B5/B6/B7/B9/B12, beta-carotene, and calcium, iron, magnesium, phosphorus, potassium, zinc, copper, manganese, selenium, and iodine when the chosen source actually reports them.

Source-specific codes are canonicalized without altering the original name, unit, source text, status, source key, or source reference.

## Verification

- Cross-platform contract fixtures cover strawberry plus every natural-food category.
- Negative fixtures prove raw/cooked, dry/cooked, oil/no-oil, brand, account ownership, macro, and ambiguity guards.
- The detailed sheet must visibly contain a Vitamins section for an enriched strawberry and must preserve its existing compact macros.
- Full web, native, localization, Food Memory, nutrient-pattern, persistence, and UI suites must pass.
- Production verification checks approved/rejected counts, source provenance, live search payloads, and the physical iPhone flow.
