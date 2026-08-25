# Hydration system implementation plan

Date: 2026-08-25
Design: `docs/plans/2026-08-25-hydration-system-design.md`

Each numbered item is its own red-green-refactor cycle and commit. After every item: append
`docs/REPAIR-NOTES.md`, run the focused and relevant regression suites, push, confirm Pages, and
install the exact SHA on the connected iPhone; Watch items also require the physical Watch install.

## 1. Watch shell, settings and battery-safe presentation

- Add behavioral/source tests that require a native pinned navigation title, labelled gear button,
  bounce based on content size, no duplicate “Today”, larger semantic typography, one animation
  clock, Reduce Motion/active-scene gates and a progress gleam.
- Add a small Codable preference model with validated target, units, labels, haptics, motion and
  reminder fields.
- Add a dedicated settings view with exact target entry, unit selection, reminder toggle/cadence,
  quiet hours, labels, haptics and motion.
- Cache preferences locally and make `WatchHydrationStore` use the configured target.
- Verify on a Watch simulator and physical Apple Watch Ultra 3.

## 2. HealthKit partial-failure resilience

- Add a HealthKit query abstraction test in which one metric throws while steps and active energy
  succeed.
- Resolve each metric independently and preserve successful values.
- Coalesce bootstrap/foreground refreshes and represent “no samples” separately from authorization
  failure.
- Verify launch, background/foreground and protected-data retry behavior.

## 3. Canonical hydration events, presets and synchronization

- Add a Supabase migration for owner-scoped hydration events and presets with RLS, uniqueness and
  indexes. Add canonical TypeScript/Swift fixtures.
- Add reconciliation tests for APEX-owned HealthKit samples, external samples and food-derived water.
- Implement account-scoped native/web repositories and migrate aggregate-only reads lazily without
  fabricating event provenance.
- Add WatchConnectivity application-context synchronization; no polling.
- Add iPhone preset management, shared composition bands and event-based history deletion.
- Apply and verify the migration against the configured project, including cross-account denial.

## 4. Reminder scheduler and complication variants

- Unit-test opt-in default, inactivity+pace eligibility, quiet hours, three-per-day cap, goal
  cancellation and rescheduling after an event.
- Implement iPhone-owned local notification scheduling and Watch setting transfer.
- Replace the complication gauge with a leading-fill outlined bar and add bar-only alongside percent,
  litres and gallons modes. Test display intent mappings and target cache behavior.
- Verify complication previews and a physical Watch refresh after add/delete/target change.

## 5. Barcode scans in Food Memory recency

- Reproduce iOS and web behavior with tests: a successfully logged barcode item is absent from
  recents before the fix, while a cancelled scan must remain absent.
- Route successful barcode logging through the same canonical use-event path as manual food picks.
- Deduplicate by canonical food identity and sort by most recent successful use.
- Verify yesterday's scanned food remains in recents after relaunch/sync.

## 6. Final integrated verification

- Run all native, Watch-focused and web tests plus the production build.
- Install and launch the exact final SHA on iPhone and Watch.
- Push the integration branch and both required remote refs, confirm Pages success, verify the live
  URL returns HTTP 200, and round-trip one non-destructive shared record if schema changed.
