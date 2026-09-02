# Animal-food donor crosswalk review notes

Reviewed 36 unambiguous target-to-single-donor mappings. Deltas in `animal-crosswalk.tsv` are donor minus target in the order kcal / protein g / carbs g / fat g. `key_vitamin_mineral_count` is the number of distinct reported nutrients among the design's 14 vitamin/beta-carotene codes plus 10 mineral codes. The dual tolerance used the usual absolute-or-relative rule, inclusively.

For chicken Foundation record `2646170`, the matching energy observation is the explicit USDA nutrient `2047` (`Atwater General Factors`), 106.034 kcal. The same donor also has 112.202 kcal from specific factors. Canonicalization must select the method explicitly and must not select energy by row order.

## Rejected ambiguous or inexact targets

- `20000000-0000-4000-8000-000000000066` (`salmon-fillet-raw`): Foundation `2684441` matches macros but is explicitly Atlantic, farm-raised; target species-generic while separate sockeye exists. Fail closed.
- `20000000-0000-4000-8000-000000000233`, `20000000-0000-4000-8000-000000000238` (beef sirloin raw/grilled): donors specifically top-sirloin cap with trim/grade; raw has two tolerance-compatible candidates. Target does not preserve subcut/grade.
- `20000000-0000-4000-8000-000000000255`, `20000000-0000-4000-8000-000000000262` (lamb leg raw/roasted): multiple compatible shank-half, whole-leg, and New Zealand donors. Target does not preserve those distinctions.
- `20000000-0000-4000-8000-000000000022` (tuna drained): exact macro donor is light tuna without salt; target omits class/salt.
- `20000000-0000-4000-8000-000000000179` (scallops raw): Foundation `2747667` is frozen wild-caught; target says only raw. The SR raw mixed-species row is macro-incompatible.
- `20000000-0000-4000-8000-000000000184` (lobster raw): macro donor is northern lobster; target is generic. Foundation alternative is tail-only frozen and macro-incompatible.
- Fish cooked canonical rows `20000000-0000-4000-8000-000000000067`, `20000000-0000-4000-8000-000000000078`, `20000000-0000-4000-8000-000000000089`, `20000000-0000-4000-8000-000000000100`, `20000000-0000-4000-8000-000000000111`, `20000000-0000-4000-8000-000000000122`, `20000000-0000-4000-8000-000000000133`, `20000000-0000-4000-8000-000000000144`, `20000000-0000-4000-8000-000000000155`, `20000000-0000-4000-8000-000000000166`: donors say cooked dry heat; no target has a dry-heat signature, so a generic donor cannot hydrate baked/roasted/grilled/air-fryer/pan-seared methods.
- `20000000-0000-4000-8000-000000000177` (shrimp steamed): only generic cooked donor.
- `20000000-0000-4000-8000-000000000180` (sea scallops steamed): donor combines bay and sea scallops.
- `20000000-0000-4000-8000-000000000185` (lobster boiled): donor says only cooked moist heat.
- `20000000-0000-4000-8000-000000000186` (crab steamed): donor is Alaska king crab with generic moist heat.
- `20000000-0000-4000-8000-000000000218` (turkey breast roasted): compatible donors have added solution; target is plain.
- `20000000-0000-4000-8000-000000000223`, `20000000-0000-4000-8000-000000000231` (ground beef cooked/pan-seared): donor is crumbles, pan-browned; form/method mismatch.
- `10000000-0000-4000-8000-000000000008` (generic chicken cooked) is superseded by the exact roasted target `20000000-0000-4000-8000-000000000196`.
- `10000000-0000-4000-8000-000000000015` (chicken boiled) matches a stewed profile, not boiled.
- `10000000-0000-4000-8000-000000000016` (air-fryer) reuses roasted macros and has no exact donor.
- `10000000-0000-4000-8000-000000000069` (chicken hearts cooked) matches a simmered donor but the target method is generic.
- `10000000-0000-4000-8000-000000000067` (hot smoked salmon), `10000000-0000-4000-8000-000000000068` (pangasius): no exact donor.
- `20000000-0000-4000-8000-000000000008` (low-fat quark), `20000000-0000-4000-8000-000000000009` (skyr): no exact donor.
- `20000000-0000-4000-8000-000000000010` (yoghurt 2%), `20000000-0000-4000-8000-000000000011` (high-protein yoghurt): fail the macro fingerprint.
- `20000000-0000-4000-8000-000000000054` (omelette), `20000000-0000-4000-8000-000000000056` (scrambled egg): composite preparations, rejected.
- `10000000-0000-4000-8000-000000000007` (whole egg), `20000000-0000-4000-8000-000000000018` (turkey breast raw): duplicate less-specific identities; the explicit targets in the TSV were selected instead.
- All retailer copies, branded milk/tuna/Ayran, fried/oil-added/breaded variants, sardine/anchovy-in-oil rows, and recipes were excluded.
