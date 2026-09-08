# Focused onboarding walkthrough — 2026-09-08

## Navigation findings

- DEAD-END: Normal week collected activity and training recency on one scrollable page, but Continue silently disabled until both were selected. Recency was below the fold; the button still appeared brightly actionable. Continue now names and reveals the missing question while preserving required-answer validation.
- The same hidden-answer pattern affected the four movement tabs, setup frequency/time, and safety acknowledgment. Continue now selects the first unanswered movement tab or scrolls to the relevant choice. Safety guidance explicitly offers concerns or None; no answer is inferred.
- REACHABILITY: the standalone Individual-preview presentation did not expose the keyboard toolbar's Previous/Next/Done controls. Those controls now live in the onboarding footer while a body-entry field has focus, so they do not depend on a navigation toolbar host.
- Each new stage starts at the top of its scroll content. Existing answers remain in the input state, independent of scroll-view identity.

## Driven journey

One XCUITest uses the actual Developer Mode Individual session with blank onboarding answers, rather than the old seeded induction shortcut. It accepts consent, enters female/64.5 kg/169 cm/18 March 1994, chooses general fitness, mixed activity and a 6–12 month break, answers all movement domains, selects home/3 days/45 minutes, acknowledges no safety concerns, inspects the starting map, creates the plan, declines device integration by continuing, reaches the portal, and returns to the real-account Settings presentation.

- First run reproduced missing keyboard controls.
- After the keyboard repair, the same test reproduced inert Continue on Normal week.
- Fixed flow passed; final same-journey run also verifies the safety choice is revealed without manual searching. No broad regression suite was run.
- Reviewed screenshots show the formerly hidden recency question and all its choices visible after Continue. The generated-plan home is populated, not blank. This establishes onboarding-to-home reachability, not every subsequent workout action or purchase/backend onboarding path.
- Evidence: retained APEX lane result bundles and `/tmp/apex-onboarding-green-captures/`. The existing nutrition summary title still truncates on this viewport; that is recorded as a separate visual follow-up, not silently claimed fixed by this progression hotfix.

## Human discoverability check

On the delivered build, choose only your normal daily activity then tap Continue: is the next required question obvious? On movement questions, use Continue after each answer: is the next domain clear? Note any hesitation. Automated reachability passed; independent human comfort ratings remain uncollected.
