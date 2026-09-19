# Temporary UI Mode preview slice

Scope: extend the existing native developer sandbox, available only to the authorized owner; no commercial entitlement, real account, device/Health or backend changes.

<flows>
F1: Real bespoke Settings → UI Mode → Individual subscribed user → initial setup → My account; Coach/PT Interface → workspace → sample invitation → visible sharing confirmation → My account.
F2: UI Mode → Coach's client → Settings shows coach-sponsored access (not founding) → coach plan → acknowledge → activate → runnable coach workouts → My account. Personal builders remain restricted; nutrition and Avatar stay available.
F3: UI Mode → Trial / non-subscribed → active-trial setup → My account → non-subscribed access recovery → retry gives honest unchanged-access feedback → My account. No private portal is visible behind the gate and no real entitlement changes.
</flows>

Checks: existing sandbox isolation/local CRUD/coach publish-client activate tests plus the new access distinction; focused UI flows with screenshots, no broad regression suite. A prior fresh-onboarding journey is retained; this gated slice does not claim another full unseeded app audit.

Human discoverability: Find UI Mode in Settings; distinguish a sponsored client from a paying individual; switch trial/access states; return to the untouched bespoke account. Note any hesitation. Automated reachability does not rate ease of use.

## Verification outcome

F1–F3 pass in two focused UI tests, including invitation Close clearance, client plan acknowledgement/activation, opening the published workout's session controls, and returning to Constantine. Eight sandbox behavior tests and the nine-language compact-table test also pass. Seventeen changed string tables validate. Screenshots: ignored `build/ui-mode-396-captures`.

The walkthrough found and corrected preview chrome obscuring Back/Close and hidden/misleading preview membership. The owner should still assess discoverability and wording on the phone. No real purchases, emails, client account mutations or Apple Health writes were exercised; production coach synchronization and commercial rollout remain separate roadmap gates.
