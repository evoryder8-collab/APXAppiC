# Frida and Swiss regional crosswalk review notes

Reviewed the staged, checksum-verified Frida 6.1 and Swiss FSVO 7.1 records against `COMMON_FOODS` and the reviewed USDA plant/animal crosswalks. The same whole-record, basis, identity, preparation, brand, and macro gates were applied. Deltas below are donor minus target. Priority coverage is the 24-field vitamin/mineral set in the design.

## Approved mapping

- `10000000-0000-4000-8000-000000000001` / `apex-common:10000000-0000-4000-8000-000000000001` — **Rolled oats** (`as_sold`) may use Frida record `59`, UUID `3b5e484f-c347-5f3a-a042-569a542614c4`, **Oats, rolled, average values**. Both sides are unbranded and `per_100g`; the official donor is the generic/unspecified rolled-oat record rather than an enrichment-specific subtype. Macro deltas are `(-5.552 kcal, -0.618 g protein, -0.389 g carbohydrate, -0.120 g fat)`, within allowances `(11.160 kcal, 0.675 g, 2.935 g, 0.500 g)`. The donor reports all 24 priority fields, including measured biotin (`19 µg/100 g`) and iodine (`0.5 µg/100 g`). Because the USDA audit approved no donor for this target, all 24 fields are additions.

No existing USDA-approved mapping has a safe regional replacement. Every exact or near-exact regional candidate either narrows net priority coverage, fails at least one macro gate, or adds an identity/preparation qualifier absent from the target.

## Ambiguity and exactness rejections

- **White rice, dry** (`…0002`): Swiss `generic-foods:427` (**Rice polished, raw**) clears the macro gates with deltas `(-8 kcal, +0.4 g, -1.0 g, +0.2 g)`, but Swiss `generic-foods:419` (**Rice parboiled, raw**) also clears them with `(-4 kcal, +0.5 g, -0.4 g, +0.3 g)`. The target does not say whether it is parboiled and still does not establish enrichment or grain length, so the USDA ambiguity is not safely resolved.
- **Rolled oats enrichment-specific alternative**: Frida `480` (**Oats, rolled, not enriched**) also passes the fingerprint, but “not enriched” is a material qualifier absent from the target. It was rejected in favor of Frida `59`, the publisher's explicit generic “average values” record. Frida `444` (**enriched**) fails the fat gate by approximately `0.008 g` beyond the `0.5 g` allowance.
- **Whole egg, raw** (`…0030`): Swiss `generic-foods:290` (**Egg, raw**) is macro-compatible, but it reports 20 priority fields versus 22 on the approved USDA donor. It adds iodine while losing vitamin K, copper, and manganese, so it is not materially broader. The only macro-compatible Frida egg is explicitly from free-range indoor hens and is not exact for the production-system-unspecified target.
- **Atlantic cod fillet, raw** (`…0088`): Swiss `generic-foods:285` (**Cod, raw**) is macro-compatible but has 20 priority fields versus the USDA donor's 22. Replacing it would lose net coverage.
- **Salmon, hot-smoked** (`…0067`): Swiss `generic-foods:193` (**Salmon, smoked**) passes the macro gates but does not establish hot versus cold smoking. Frida distinguishes cold- and hot-smoked Atlantic salmon; its hot-smoked record `1553` fails by `+95.749 kcal`, `-2.888 g protein`, and `+11.900 g fat`. The generic Swiss smoke state cannot be used to bridge that distinction.
- **Turkey breast, raw** (`200…0018`): Swiss `generic-foods:713` passes the fingerprint, but its identity is explicitly “breast (schnitzel, ground)” and the target omits form. It is also the less-specific duplicate of the already reviewed skinless turkey-breast target, so it was not added.
- **Sweet potato, steamed** (`200…0479`): Swiss `generic-foods:13407` is preparation- and macro-compatible at the inclusive `+5 kcal` boundary, but this catalogue row is a mechanically generated cooking-method duplicate. The initial-coverage contract says such labels do not count as distinct coverage; the canonical raw/boiled identity remains governed by the reviewed USDA rows.
- **Sardines in oil, drained**, Swiss kebab, and compatible rendered-fat rows were excluded respectively as an oil-added variant, a recipe/mixture, and outside the bounded initial natural-food categories.

## Broader-coverage candidates that failed the fingerprint

- Swiss exact raw cauliflower, zucchini, and eggplant records each report 20 priority fields, which could have improved the 10-field USDA Foundation donors, but their carbohydrate deltas are `-2.87 g`, `-1.31 g`, and `-3.48 g` respectively; every one exceeds its `0.5 g` allowance.
- Swiss chicken breast without skin, raw reports 20 priority fields versus 8 on USDA Foundation `2646170`, but its deltas against the target are `(+1 kcal, +2.1 g protein, 0 g carbohydrate, -0.93 g fat)`, failing both protein and fat.
- Swiss raw/cooked shrimp records would broaden the 8-field USDA shrimp rows, but the raw donor is `-11 kcal` and `-3.5 g protein`, while the cooked donor is `-13 kcal`, `-5 g protein`, and `+0.8 g fat`; neither is compatible.
- Regional rabbit, deer/venison, lamb-leg, goat, and veal records either identify a different cut/state or fail energy/fat/protein gates, so none can replace the lower-coverage USDA game-meat rows.

## Important unresolved USDA rejections

- Organic whole-grain rolled oats: neither regional source establishes the organic target identity.
- White rice cooked, brown rice dry, basmati rice, jasmine rice, bulgur dry, and wholegrain pasta dry: exact or generic regional rows fail the fingerprint, and the white-rice state remains ambiguous as noted above.
- Black sesame and cherry tomatoes: neither staged source has an exact, macro-compatible variety record.
- White potato with consumed skin, boiled: the Swiss new-potato-with-skin row and Frida boiled-potato row both fail the carbohydrate/energy fingerprint; the Frida name also does not establish consumed skin.
- Low-fat quark, plain skyr, plain 2%-fat yoghurt, and high-protein yoghurt: the identity-adjacent Frida/Swiss rows fail the macro gates or assert a different style/fat state.
- Generic salmon raw, scallops, lobster, crab, pangasius, cooked chicken hearts, and method-specific cooked fish/meat rows remain unresolved for the same species/cut/preparation reasons recorded by the USDA audits.

The approved TSV contains one donor per target and no blended values, branded rows, retailer copies, recipes, or generated oil-added preparations.
