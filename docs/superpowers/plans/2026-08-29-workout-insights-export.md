# Workout insights and export implementation plan

1. Add red aggregation contracts for account/range isolation, linked-workout deduplication, missing facts, load volume, duration priority, and 1/5/10-year anniversary eligibility.
2. Implement matching pure aggregation engines in TypeScript and Swift.
3. Add localized web and native workout-insight cards with day, week, year, and custom controls.
4. Add high-resolution rounded PNG renderers and share/download controls without persisting generated images as account data.
5. Place insights beside Finished Workouts on Simple and phase pages while preserving the requested phase hierarchy.
6. Run focused and full web/native/localization/UI verification, install the exact signed build on the connected iPhone and Watch, append repair notes, commit, push both refs, and confirm GitHub Pages and the live bundle.
