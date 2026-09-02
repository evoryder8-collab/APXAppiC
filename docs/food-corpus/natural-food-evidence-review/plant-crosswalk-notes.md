# Plant crosswalk review notes

Reviewed 75 approved plant/dairy links: 16 fruit, 39 vegetables, 9 grains/starches, 3 legumes, 7 nuts/seeds, and 1 plain dairy. All donors are unbranded, `per_100g`, single-record, and preparation-compatible.

Conventions:

- Macro deltas are `donor − target` as `(kcal, protein g, carbs g, fat g)`.
- Compatibility uses `abs(delta) ≤ max(5 kcal, 3% target)` and `≤ max(0.5 g, 5% target)`.
- `keyVM` counts the 24 priority vitamin/mineral fields in the design: A/C/D/E/K, B1/B2/B3/B5/B6/B7/B9/B12, beta-carotene, Ca/Fe/Mg/P/K/Zn/Cu/Mn/Se/I.

The non-zero Foundation rows are intentionally eligible under the confirmed max-of-absolute/relative rule:

- Kiwi: unique Foundation record; carbohydrate delta `-0.66 g` is within the `0.733 g` relative allowance.
- Cauliflower, zucchini, and eggplant: low-calorie relative energy changes exceed 3%, but absolute changes remain below 5 kcal.
- Kale is the fifth Foundation link and is an exact zero-delta match.

Foundation exact-name ambiguity correctly fell back to SR Legacy for blueberries (2 Foundation rows), raspberries (2), strawberries (4), and broccoli (2).

## Rejected ambiguous targets

| Target | Passing candidates | Reason |
|---|---:|---|
| `10000000-0000-4000-8000-000000000002` White rice, dry | Foundation `2512381`; SR `168877`, `168879`, `168931`, `169756`, `169760` | Target does not specify grain length or enrichment. |
| `10000000-0000-4000-8000-000000000003` White rice, cooked | SR `168878`, `168880`, `168882`, `168930`, `168932`, `169757` | Multiple grain-length/enrichment states clear every macro gate. |
| `20000000-0000-4000-8000-000000000028` Brown rice, dry | SR `169703`, `169706` | Long- and medium-grain records both pass; target does not distinguish them. |
| `20000000-0000-4000-8000-000000000412` Sweet corn kernels, raw | SR `168538`, `169998` | White and yellow corn both pass; target omits color. |
| `20000000-0000-4000-8000-000000000413` Sweet corn kernels, boiled | SR `168539`, `169999` | White and yellow cooked donors both pass. |

## Other important fail-closed rejections

- `Rolled oats` (`…0001`): exact oat donors fail the carbohydrate fingerprint.
- `Organic whole-grain rolled oats` (`…0026`): SR `173904` matches macros but does not establish organic identity.
- `Bulgur, dry` (`…0004`): SR `170688` carbohydrate delta is `+12.47 g`.
- `Basmati rice, dry` (`200…0026`) and `Jasmine rice, dry` (`200…0027`): no exact unbranded USDA variety record.
- `Wholegrain pasta, dry` (`200…0031`): SR `169738` has deltas `(+4,-0.73,+8.57,+0.43)`.
- `Black sesame seeds` (`…0061`): SR `170150` is macro-exact generic sesame, but does not identify the black variety.
- `Cherry tomatoes, fresh` (`…0065`): Foundation grape tomato and SR generic red tomato are not exact cherry-tomato donors.
- `White potato with skin, boiled` (`200…0470`): macro-exact SR `170438` reports flesh cooked in skin, not flesh plus consumed skin.
- `Yoghurt, plain, 2% fat` (`200…0010`), low-fat quark, skyr, and high-protein yoghurt: no exact macro-compatible USDA record.

Mechanically generated steamed, grilled, roasted, air-fryer, pan-seared, and fried-with-oil variants were deliberately excluded. Generic duplicate cooked rows were also skipped when the catalogue contained the exact boiled state above.
