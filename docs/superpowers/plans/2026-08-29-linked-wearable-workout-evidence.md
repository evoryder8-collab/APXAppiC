# Linked wearable workout evidence implementation plan

## 1. Lock the association rules in tests

- Add native and web tests for the five-minute boundary, required overlap, owner/day isolation, hidden/APEX-mirror rejection, one-candidate automatic matching, multiple-candidate ambiguity, explicit selection, and newest-first same-day choices.
- Add reconciliation tests proving a HealthKit refresh preserves an external link.
- Add history tests proving linked evidence nests under one APEX receipt and never appears twice.

## 2. Add the shared association engine

- Add immutable-copy support for linking/unlinking `ImportedActivity`.
- Implement pure automatic and manual candidate resolution in Swift and TypeScript.
- Restrict mirror deduplication to APEX bundle identities so an externally sourced linked row is not erased.
- Apply automatic association both when an APEX session completes and when a later HealthKit event arrives.
- Persist imported-row changes with the existing owner-scoped offline-aware path.

## 3. Render one combined receipt

- Attach the selected imported activity to native and web APEX history items.
- Render a localized read-only wearable evidence panel in the expanded APEX card.
- Preserve APEX editing/deletion, standalone external hiding, and non-additive energy behavior.

## 4. Add the recovery flow

- Add `Already finished?` to native and web guided players.
- Pause safely, restore state on cancellation, show same-day choices newest first, and explain empty/denied states honestly.
- Complete through the existing session persistence boundary with only already recorded facts and an optional selected imported-activity id.
- Open the normal combined receipt after completion.

## 5. Localize and verify

- Author all new full strings in every offered native language and English/Romanian/Thai web copy.
- Add compact forms only where a constrained control requires them.
- Run focused association, history, player, HealthKit, account-isolation, localization, and UI tests, then the full native/web suites and production build.
- Verify on the dedicated APEX simulator lane, then with the connected iPhone and Watch; never use BA-Studio or Finalova lanes.
- Append `REPAIR-NOTES.md`, commit this increment alone, push both refs, wait for Pages, and verify the live site.
