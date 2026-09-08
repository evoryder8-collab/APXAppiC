# Focused onboarding progression repair

Scope: reproduce the reported Normal week dead-end in the real Individual preview, repair missing-answer guidance without skipping required facts, and navigate the remaining onboarding and initial plan creation. Do not run the whole regression suite or mutate real Health/account data.

<flows>
<flow id="individual-onboarding">
Settings → Developer Mode → Individual subscriber → consent → measured body facts → goal → Normal week.
Choose a daily activity answer, then press Continue. The next unanswered question must be visible and understandable, not a silent disabled control. Complete training recency. On movement and setup, Continue must similarly lead to the next missing answer rather than silently stop. Complete safety → inspect starting map → build plan → optional device permissions → portal. Open the generated plan and return; return to My account without changing the real profile.
Least-discoverable action: knowing a second required question exists below the fold, or that all four movement tabs need answers.
</flow>

Verification: one retained XCUITest journey with screenshots, first reproducing the reported dead-end, then driving the fixed flow. Inspect the changed navigation edges and validation behavior; build the signed release and publish through the normal repository workflow. Human-facing checklist: is the next unanswered question clear, does Back retain answers, and does plan completion land where expected?
