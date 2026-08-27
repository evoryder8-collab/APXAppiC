# APEX localisation policy

The files in `policies/` are the release contract for the nine offered languages.
Each policy records:

- the exact market variant (`pt` is European Portuguese, `pt-PT`);
- the local source used to decide how exercise names are written;
- every canonical exercise name, classified as `english`, `native`, `hybrid`, or
  `transliterated`;
- authored compact forms for labels that appear in width-constrained controls.

An English exercise name is intentional only when its language policy classifies
it as `english`. Unsupported variants stay English instead of receiving an
invented literal translation. Swiss German UI copy uses written Standard German
with Swiss spelling. Japanese follows the NSCA Japan convention, which commonly
uses katakana exercise names.

`tests/exercise-localisation-policy.test.ts` keeps all 549 catalogue records in
lockstep with these policies. `tests/localisation-coverage-policy.test.ts` keeps
interface-copy coverage at the same denominator for all nine languages and
prevents storage keys or source-code fragments from inflating that denominator.
