# Hydration system design

Date: 2026-08-25
Status: approved by the owner, including the Watch settings addendum

## Outcome

APEX uses one hydration ledger across iPhone, Apple Watch, HealthKit and the web client. The UI can
show the total and its composition without polling, double counting, or losing provenance. Watch
controls remain quick to use and battery-conscious. Barcode-scanned foods become first-class Food
Memory recents in a separate follow-up commit.

## Product rules

- A hydration entry is an event, not an edit to an opaque daily total.
- Every event carries amount, time, source, beverage kind, presentation token and its HealthKit
  identifier when one exists.
- Food-derived water remains identifiable as food water. It contributes to the displayed total but
  is not silently rewritten as a manually consumed drink.
- The visible daily total is resolved from canonical events; the same HealthKit-backed event is
  included once.
- Presets and preferences are account-scoped. A different account on the same device must not
  inherit them.
- The Watch updates when opened or when an actual setting/entry change is delivered. There is no
  periodic background polling or animation while inactive.
- Targets and reminders are wellness conveniences, not medical prescriptions. Users subject to a
  clinician-directed fluid restriction must follow that advice.

## Shared data

### Hydration event

`HydrationEvent` contains:

- stable UUID
- owner UUID
- amount in millilitres
- timestamp and local-day key
- kind: water, coffee, tea, juice, shake, other, food or external
- palette token and SF Symbol token
- source: iPhone, Watch, web, food or external HealthKit writer
- optional HealthKit sample UUID
- creation/update timestamps

The server table is owner-scoped with RLS. HealthKit metadata stores the APEX event UUID so
reconciliation is idempotent. External HealthKit water samples receive deterministic local IDs and
retain their source instead of being copied into a second APEX-written sample.

### Preset

`HydrationPreset` contains a stable ID, account owner, name, amount in millilitres, beverage kind,
palette token, icon token, sort order and enabled state. Default presets seed an empty account once;
users may edit, reorder, hide or remove them.

Hydration logging records fluid volume only. Coffee, juice and shakes do not silently create calorie
or macro entries; users log nutritional content through Food Memory when relevant.

### Preferences

`HydrationPreferences` contains:

- exact target in millilitres
- display unit: litres or US gallons
- show preset names
- confirmation haptics
- motion intensity: off, subtle or full (Reduce Motion always overrides it)
- reminder enabled state
- reminder inactivity interval: 60, 90 or 120 minutes
- quiet-hours start and end

The default target remains the account's current target. Exact entry is supported and the UI offers
0.1 L stepping. Accepted target range is 1.0-6.0 L, with validation rather than silent clamping.

## Reminder policy

Reminders are opt-in and default off. There is no scientifically defensible universal hourly rule:
needs vary and both food and beverages contribute to intake. The default policy therefore schedules
at most three reminders per day only when both conditions hold:

1. no drink event has been recorded for 90 minutes; and
2. the resolved total is at least 250 mL behind the time-proportional personal target.

Default quiet hours are 21:30-08:00. Pending reminders are cancelled when the goal is met. Each new
event or settings change replaces the small set of pending notifications; no background timer runs.
The iPhone owns notification scheduling so the system mirrors notifications to a worn Watch without
creating duplicate iPhone and Watch alerts. Watch settings changes are sent to the phone immediately
when reachable and queued by WatchConnectivity otherwise.

Reminder copy states the gap and stays neutral, for example: “A gentle hydration check — 300 mL
behind your current pace.” It avoids streaks, shame, urgency and medical claims.

## Watch experience

- Use the native navigation bar: the title aligns with the system time and cannot drift inside the
  scroll view. A labelled gear toolbar button opens settings.
- Disable bounce when content fits and remove the dead top margin.
- Keep the shared APEX silhouette. Its fill is split into proportional, labelled beverage bands.
- Increase the main amount, percentage, target, preset and utility-button typography while retaining
  Dynamic Type and VoiceOver labels.
- The amount reads as one value, for example `2.15 L`; no detached unit or redundant “Today” label.
- Use one active-scene animation clock for subtle float/breathing and a low-cost progress gleam.
  Reduce Motion substitutes opacity. Low-luminance/Always On pauses decorative motion.
- History entries open a confirmation dialog with Remove and Cancel. Deletion removes the canonical
  event and its owned HealthKit sample, then refreshes the resolved total.
- Settings expose target, units, reminders, inactivity interval, quiet hours, preset-label
  visibility, haptics and motion intensity.

## iPhone experience

- The hydration sheet uses the same event and preset model.
- Users create, edit, reorder, hide and remove preset buttons, including name, amount, icon and
  palette. Defaults include water, coffee, tea, juice and shake examples without forcing them.
- The silhouette uses the same composition bands as Watch. Color is never the only differentiator:
  icons and accessible labels identify each kind.
- HealthKit reads are best-effort per metric. A denied or temporarily unavailable metric does not
  discard valid steps, activity or hydration from other queries.
- Launch and foreground refresh are coalesced. Protected-data failures retry on the next foreground
  transition; an empty readable result is not mislabelled as “disconnected.”

## Complications

Offer four configurable variants from one provider: percentage, litres, US gallons and bar-only.
The progress line is an outlined capsule filled from the leading edge, with no dot. Full-color faces
use beverage composition; tinted faces preserve segment boundaries with opacity and pattern changes.
Complications read the shared cache and reload only after an entry, deletion, target or preset change.

## Food Memory follow-up

Barcode scans must enter the same account-scoped recency stream as search/manual selections. A
confirmed scan writes a Food Memory use event only after the item is actually logged. The iOS and web
clients sort by last successful use and deduplicate by canonical food identity, so yesterday's Aldi
scan appears alongside manually chosen recent foods.

## Verification

- Pure model tests: preference validation, target conversion, reminder eligibility/caps/quiet hours,
  event reconciliation, composition and preset persistence.
- HealthKit tests: per-metric partial failure, owned-sample deletion and external-sample dedup.
- Watch source/UI contracts plus physical Watch build/install/launch and screenshots.
- Food Memory behavioral tests proving a scanned item becomes recent and a dismissed scan does not.
- Full native and web suites, production web build, exact-SHA iPhone and Watch installs, GitHub push,
  successful Pages deployment and live HTTP verification.

## Evidence basis

- EFSA dietary reference values treat total water as water from food and all beverages and describe
  adequate intakes rather than a universal prescription.
- NHS and CDC guidance likewise note that needs vary and that food and non-alcoholic beverages
  contribute to hydration.
- Apple documents HealthKit's privacy rule: an app cannot infer read denial from an empty query.
- Apple recommends native Watch toolbar/navigation placement and reduced, efficient motion.
