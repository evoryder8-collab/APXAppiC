# Repository Working Rules

## Definition of done

For every user-requested task, fix, or feature implementation in this repository:

1. Implement and verify the change locally.
2. Commit the completed change and push it to GitHub.
3. Publish the latest working version through GitHub Pages.
4. Confirm that the GitHub Pages deployment succeeded and report the live URL.

Do not describe an implementation as complete while its required GitHub Pages deployment is still pending or failing. If publishing is blocked by credentials, repository settings, an external outage, or a failing build, report the blocker clearly and continue pursuing safe in-scope remedies.

## Autonomous execution

Proceed autonomously on user-requested work without asking for routine permission, approval, confirmation, or implementation preferences. Make reasonable assumptions, choose sensible defaults, and carry each request through implementation, verification, GitHub publication, and GitHub Pages deployment without requiring ongoing user input.

Treat the user's request as authorization for normal, non-destructive actions needed to complete it, including editing files, running checks, installing project dependencies, committing the scoped changes, pushing them to GitHub, and monitoring the deployment. Preserve unrelated work and keep decisions within the requested scope.

Ask the user only when progress genuinely requires information or authority that cannot safely be inferred—for example, unavailable credentials, a required platform security prompt, a destructive or irreversible operation, access to a new external system, or a material expansion or change of scope. If the environment itself requires an approval prompt, use it; repository instructions cannot bypass platform security controls.
