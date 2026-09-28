# DevOps Delivery Notes: KijaniKiosk

## The delivery problem
KijaniKiosk builds features continuously but releases once a month. Deployments need weekend war-room coordination, and production incidents often follow a release. The workflow in this repository is a small-scale answer to that problem. Each section below states the problem, what the workflow does about it, and how the team would know it is working.

## Branching model
- `main`: production-ready state. Every commit should be deployable, and releases are tagged (for example `v0.1`).
- `develop`: integration branch. Finished features land here first, so problems show up before they reach `main`.
- `feature/*`: one short-lived branch per change, for example `feature/starter-kit-files`.

Path of a change: `feature/*` -> pull request -> `develop` -> release -> `main`.

Trade-off: `develop` adds one extra merge step. It is used here because KijaniKiosk currently releases in batches and needs a place to integrate and check work before `main`. If the team later deploys several times a day, GitHub Flow (short branches straight into `main`) would remove that step.

## Flow: reducing delay between development and production
- Problem: finished work waits for the monthly release, so each release is a large batch and large batches are risky. This is what creates the war rooms.
- Practice: one small, single-purpose branch per change, merged into `develop` as soon as it is reviewed. Work in progress is visible as open pull requests.
- Effect: the unit of delivery shrinks from "a month of changes" to "one pull request".
- How to measure: lead time from first commit to merge, deployment frequency, and the age of open pull requests.
- Next step: release from `develop` to `main` weekly, then on every merged pull request as confidence grows.

## Feedback: detecting problems earlier
- Problem: incidents currently appear after release, when they cost the most to fix.
- Practice: three feedback points before anything reaches production.
  1. Pull request review: a second person reads the change and its description.
  2. Automated CI: the Week 1 repository already runs a workflow that fails when required files are missing (`README.md`, `notes.md`, `RUNBOOK.md`). The same check should run in this repository on pull requests into `develop`.
  3. Merge conflicts: they surface when a branch is merged into `develop`, not during a release weekend (this was practiced in the merge conflict lab).
- Gap: the current CI checks that files exist. It does not run tests, linting, or a build.
- Next step: add a Markdown lint and link check, then tests and a build once there is application code. Add branch protection so a pull request cannot merge without a passing check.
- How to measure: change failure rate (releases that cause an incident) and time to detect a problem.

## Learning: improving the system after incidents
- Problem: after an incident, knowledge stays with the people who handled it, so the same failure can repeat.
- Practice:
  - `RUNBOOK.md` from the Week 1 lab records recovery steps for failed deployments, and CI fails if it is missing. An incident becomes a guardrail.
  - The decisions in this starter kit (why PaaS, why multi-AZ, why this IAM policy, why this subnet layout) are written down with reasons, so the reasoning survives team changes.
  - Incident reviews are blameless. Each review records the cause, the timeline, and the check that would have caught it, and ends with one concrete change such as a CI check, a runbook step, or an alert.
- How to measure: how many incidents produced a guardrail, how many incidents repeat, and time to recover.

## How the three ways connect
Flow shortens the path from commit to production. Feedback makes that shorter path safe by catching problems early. Learning feeds what went wrong back into Flow and Feedback, for example a new CI check after an incident. Removing any one of them weakens the others: faster flow without feedback increases incidents, and feedback without learning repeats the same alerts.

## Current limitations
- CI only checks repository structure.
- There is no production deployment yet, so the Observe stage of the pipeline is not exercised.
- This project is worked on by one person, so the pull request demonstrates the mechanism but not an independent review. In a team, branch protection would require an approving reviewer.
