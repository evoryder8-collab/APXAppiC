# Premium information hierarchy and Fitness Plan disclosure

Date: 2026-08-28

## Objective

Repair four related hierarchy problems without changing any destination, programme, account data, camera privacy, or existing feature:

1. Make the Settings identity card show a readable name without a redundant persona label.
2. Place the four Simple Mode quick actions between Nutrition at a glance and the Live Metabolic Dayline.
3. Place Private Visual Progress directly below the Avatar portrait.
4. Lead Advanced Mode with Avatar, then Nutrition, and replace separate top-level Transition and Main tiles with one premium, inline Fitness Plan disclosure.

The result must be implemented on native iOS and web wherever the equivalent surface exists.

## Settings identity

The identity card keeps `ACTIVE IDENTITY`, the profile portrait, the display name, the profile note, and nutrition metrics. The display name is the single primary identity inside the card.

- Native gives the name a dedicated flexible row with no competing trailing badge, then keeps it to one tightened line with tail truncation only for a pathological length. It does not use `minimumScaleFactor`, preserving the repository's Dynamic Type layout contract.
- Web uses a dedicated flexible row and a no-hyphen, single-line responsive treatment with the same intent.
- A persona chip is omitted when its normalized text is the same as the display name.
- If the persona and display name genuinely differ, the persona remains available as secondary metadata below the name rather than occupying the trailing edge of the row.
- The top-bar account chip remains unchanged because it identifies the active account globally; it is not part of the identity-card content hierarchy.

## Simple Mode order

The canonical visual order becomes:

1. Nutrition at a glance
2. Water, Supps, Stats, and Training quick-action strip
3. Live Metabolic Dayline

Native moves the existing quick-action view to this location without recreating it. Web changes the canonical block order. An absent order gets the new default; a saved order matching the former stock order is upgraded once; a genuinely customized drag order remains untouched. All actions, sheets, values, accessibility labels, and the user's ability to customize other Simple Mode blocks remain intact.

## Avatar order

Private Visual Progress sits immediately after the portrait hero and before body-index content. Native moves the existing link; web already has the requested order and receives a regression contract to prevent drift. Capture, comparison, storage, privacy, and sync behavior do not change.

## Advanced Mode order

The top-level order becomes:

1. Avatar/profile
2. Nutrition
3. Fitness Plan
4. Custom Workouts, when available
5. APEX Orbit

Fitness Plan is a disclosure button, not a navigation destination. It has a dual teal-violet premium treatment and no chevron. Its subtitle uses the already-localized Transition Phase and Main Phase names, making the grouping understandable without adding explanatory prose.

Tapping Fitness Plan toggles an inset glass tray directly beneath it. The tray contains two vertically stacked, compact destination cards:

- Transition Phase, teal, leading to the existing Transition route.
- Main Phase, violet, leading to the existing Main route.

The existing routes, programme availability, programme names, plan recovery, installed plans, workout history, and destination screens remain unchanged. The disclosure state is local to the Advanced page and resets when that page is reconstructed.

## Premium motion and presentation

The tray reveals with a short clipped expansion, soft opacity transition, and subtle stagger between the two destination cards. The treatment uses restrained glass depth, a thin luminous connector, and phase-specific glow; it must feel deliberate rather than playful. The parent tile gains a slightly stronger dual-tone wash while open but does not gain an arrow.

Reduce Motion replaces movement and stagger with an immediate opacity change. Touch targets remain at least 44 points, phase cards remain vertically stacked so longer translations are not compressed, and native/web accessibility exposes the disclosure's expanded or collapsed state.

## One-time phase guidance

The first time an account expands Fitness Plan, both phase cards summon a short guidance subtitle beneath their titles:

- Transition intent: for someone returning after a long period without training.
- Main intent: for someone fit enough to begin the main journey.

The English source copy is:

- `If you haven't trained in a long time.`
- `Fit enough to start the main journey.`

Those subtitles stay visible for that entire first expansion. They never share the phase cards with the information controls.

Opening the disclosure captures a local `showsIntroductionForCurrentExpansion` value before any persistence occurs. After the reveal animation has completed with both subtitles visible, the app optimistically persists `fitness_plan_intro_seen` in the existing account-owned settings add-ons. That write does not replace the subtitles during the current expansion. Collapsing clears the captured presentation; the next expansion reads the now-seen flag and shows information controls. If the disclosure is closed or the page leaves before both cards finish appearing, the flag is not written and the introduction remains due. Offline persistence uses the existing settings outbox, and the shared key means seeing the introduction on one platform suppresses it on the other after sync.

On every later expansion, each phase card shows a compact circled `i` control instead of the subtitle. The control has a restrained recurring gleam; Reduce Motion shows a static luminous treatment. Tapping it opens one short, anchored explanation of that phase. Only one explanation can be open at a time, and it closes on outside tap, disclosure collapse, or navigation. The explanation remains until dismissed rather than disappearing on a timer, so VoiceOver and slower readers are not penalized.

Tooltip meaning:

- Transition rebuilds consistency, movement quality, and training tolerance after a long break before harder work.
- Main develops strength, muscle, and performance for someone whose regular training base already supports progressive work.

The English source copy is:

- `Return here after a long break to rebuild consistency, movement quality and training tolerance.`
- `Choose this when regular training feels manageable and you're ready to build strength, muscle and performance.`

## Localization

Every new visible or accessibility string is authored in each offered language in the same implementation commit. Native coverage is English, Romanian, Thai, Japanese, German, Swiss German, Spanish, Portuguese, and Italian. Web coverage follows every language offered by its selector.

Copy is written from the situation and gym register of each language, not translated sentence-by-sentence from English. `Fitness Plan`, `Transition Phase`, `Main Phase`, and every new width-constrained phase string receive authored compact forms in each native `LocalizableShort.strings` table. Existing full localized Transition and Main names are reused wherever possible.

## State and failure behavior

- No database migration or new table is required; the introduction flag is an additive value in the existing settings add-ons.
- Missing or malformed flags mean the introduction is due.
- A failed remote settings write leaves the optimistic local value and durable outbox responsible for replay, matching current settings behavior.
- The information tooltip is presentation-only and never changes plan selection or account data.
- Opening a phase uses the same route and installed plan as before.

## Verification

Tests are written before implementation and cover:

- a pure native and web disclosure-state contract proving first-open subtitles and later-open info controls are mutually exclusive;
- persistence only after both introductory cards have appeared;
- native and web Advanced ordering and the inline grouping of the two existing routes;
- native and web Settings name layout and duplicate-persona suppression;
- native and web Avatar placement;
- native fixed Simple ordering plus web default-order upgrade that preserves a custom drag order;
- complete full and compact localization coverage for all offered languages.

Completion requires focused regressions, the full native unit suite, the full web/repository suite, a production web build, localization-table validation, a clean diff, a scoped commit pushed to both required branches, and a successful GitHub Pages deployment. Work pauses after delivery as requested.
