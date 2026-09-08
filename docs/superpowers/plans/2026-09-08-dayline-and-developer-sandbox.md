# Dayline and Developer Sandbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement task-by-task.

**Goal:** Restore native Dayline visual parity, simplify Simple insights, and let the owner audit isolated account experiences.

**Architecture:** Keep presentation-only Dayline geometry separate from timestamps. Use a separately constructed local sandbox session/transport for role previews, never mutate the authenticated account's role or data.

**Tech Stack:** SwiftUI, TypeScript/React, existing app-session/coach/onboarding infrastructure.

**Spec:** docs/superpowers/specs/2026-09-08-dayline-and-developer-sandbox-design.md

## Global Constraints

- Same checkout and branch; preserve all account data. Only APEX simulator lane 6907359A-18D1-46B0-87F1-13CED5CE1C46.
- No sandbox Health, Watch, production persistence, notifications, location, purchases or remote writes.
- Native nine languages and web three languages for new UI copy; no truncation.
- Focused necessary checks, no full-suite reruns. Root owns commit/push/device delivery.

### Task 1: Dayline cables and progressive insights

**Files:** Native NutritionParityViews.swift, SimpleHomeView.swift, WorkoutInsightsCard.swift; web SimpleHome.tsx and WorkoutInsightsCard.tsx; relevant UI tests.
**Consumes:** existing actual minutes and separated label positions.
**Produces:** truthful curved connectors and collapsed-on-entry insights without changing domain state.

- [ ] Add a focused UI test: insights export controls absent initially; tap Workout insights, export visible; collapse, controls absent. Wearable card precedes insights. Observe failure first.
- [ ] Draw decorative curved connectors from actual rail Y to separated row Y for meals/workouts. Recorded solid, planned dashed; preserve hit testing and drag semantics. Respect Reduce Motion and do not add continuous animation.
- [ ] Move wearable above insights in Simple; add accessible transient disclosure wrapper on native/web. Leave other pages expanded unless explicitly configured.
- [ ] Run only affected UI test and production builds, inspect Dayline screenshot. Review diff, append REPAIR-NOTES and commit/push/verify Pages.

### Task 2: Isolated developer experiences

**Files:** New focused sandbox session/coordinator and Settings control; existing AppSession/RootView/coach/transport boundaries as needed; developer sandbox tests; locale resources.
**Consumes:** existing real onboarding, plan builder, coach, sponsored capability views.
**Produces:** My account / Individual / Coach / Invited client selector with isolated state and unconditional return.

- [ ] Inspect session construction and side-effect boundaries. Prefer existing local fixture transport only if available in signed Release and safe; do not toggle debug process flags globally.
- [ ] Add failing isolation tests: preview edits cannot change real account; role switch resets appropriate local state; return restores actual owner; prohibited remote/Health side effects never execute.
- [ ] Implement owner-gated Settings selector and local preview coordinator with independent sandbox owner, storage and service dependencies. Individual starts onboarding; coach/client fixtures supply real interactive routes. Show persistent preview/return affordance.
- [ ] Author locale strings, run isolated session tests and one UI role-switch journey. Root reviews isolation boundary and builds signed release; append notes, commit/push/Pages and install. Do not claim completion with a fake static role mockup.
