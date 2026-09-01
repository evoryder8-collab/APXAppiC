# Nutrient evidence and patterns design

## Outcome

APEX keeps food logging visually simple while making the underlying publisher evidence available on demand. A circled information control in every configured-food sheet opens a detailed, accessible nutrient record. The Nutrition page also summarizes the user's own observed vitamin, mineral, fatty-acid, sugar, fibre, cholesterol, and electrolyte intake over a day, seven days, or calendar month.

This is an intake record, not a blood test or diagnosis. APEX must not label a user deficient, excessive, safe, or unsafe without an appropriate personal reference and clinical context.

## Evidence contract

Each food may carry a bounded `nutrient_evidence` array. Every observation retains:

- canonical nutrient code and publisher name;
- normalized value per 100 g or 100 mL when the source basis can be converted safely;
- original unit, source value text, observation status, derivation method, source key, and reference;
- `null` for trace, below-detection, not-measured, missing, or unconvertible values.

Measured, calculated, and estimated values remain visibly distinct. Trace and not-reported values never become zero. Units are never merged or converted unless the conversion is explicit and deterministic. Search responses cap the evidence payload per food; the raw publisher archives remain server-side.

When a food is logged, its evidence array is copied into `logged_food_entries.snapshot_nutrient_evidence`. Later corpus corrections therefore cannot rewrite a person's historical intake.

## Food detail interaction

The amount sheet remains the primary surface. A 44-point circled **i** beside the food identity opens a secondary sheet/dialog with:

- the exact basis and preparation state;
- energy, macros, fibre, sugars, saturated/mono/polyunsaturated fat, cholesterol, vitamins, minerals, and electrolytes when reported;
- status language for estimated, calculated, trace, below detection, not measured, and missing observations;
- source/provenance and a reminder that branded products can change.

The detail is scrollable, supports Dynamic Type, VoiceOver, keyboard dismissal, Reduce Motion, and long localized names without truncation. If a source has no micronutrient evidence, the sheet says so and still shows the available label-level facts.

## Observed nutrient patterns

The Nutrition page offers Day, 7 days, and Month. For each window APEX:

1. filters meals and entries to the active account;
2. scales immutable per-100 evidence by the logged equivalent amount;
3. groups only identical canonical nutrient and unit pairs;
4. averages across days with at least one logged food, never pretending an unlogged day was zero intake;
5. reports evidence coverage as foods with usable nutrient evidence divided by logged foods, plus observed days out of calendar days;
6. draws relative bars against the largest observed value in the current group, not against a recommended allowance.

The board never calls a result a deficiency or excess. Its footer explicitly says that food-database coverage and personal needs vary and that the bars compare the user's recorded pattern, not a health target.

## Offline and privacy behavior

Evidence already attached to a food and every logged snapshot remains available offline. Search may return foods without extended evidence during an outage; logging still works and the coverage indicator remains honest. Nutrient history is account-owned, participates in the existing meal sync boundary, and is cleared from memory on account switching with the rest of the dashboard.

## Non-goals

- No supplement or medical recommendation engine.
- No diagnosis of deficiency, toxicity, anaemia, or disease.
- No invented micronutrients for foods whose source omits them.
- No shipping the raw Food Knowledge Corpus inside the app.
