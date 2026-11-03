# Week 5 Friday Reflection

## 1. Two requirements in tension

The fail-fast principle says Lint should run before Build, and the Canvas skeleton puts `npm ci` inside the Build stage. Those two cannot both be true for this service: ESLint is a project dependency, so it does not exist on the agent until `npm ci` has run. With Lint first and `npm ci` in Build, Lint would fail every time with "eslint: not found". I chose to keep the fail-fast order and move `npm ci` into the Lint stage, with Build reusing the installed modules. The cost is that Lint is no longer a 2-second check: in build #12 it took 19 seconds, almost all of it dependency installation. I still think this is the right call, because a lint failure still stops the run before build, tests, audit and publish, and fault #14 shows exactly that. A second, smaller tension was between "show masked credentials in the build log" and "never print credentials". I removed command echo with `set +x` in the Publish step, so the final log shows no credential line at all, and I kept the Wednesday masking test (build #9) as the separate proof that masking works.

## 2. One sentence, two audiences

Board document: "No outside building block the service uses has a known serious flaw."

Technical version: "The Security Audit branch of the parallel Verify stage runs `npm audit --audit-level=high` against `payments/package-lock.json` inside `node:22.23.3-alpine`; any advisory rated high or critical makes the command exit non-zero, which fails Verify so Archive and Publish are skipped."

What stays the same is the fact being promised: dependencies are checked for known serious vulnerabilities before anything is stored. What changes is everything Osei needs to verify or change it: the tool, the file it reads, the severity threshold, where it runs and the exact consequence of a failure. The board version also hides a judgement call that the technical version makes visible: "serious" means high or critical, and moderate advisories (19 of them today, all in test tooling) do not block a release.

## 3. From four developers to forty

The first thing to break would be build capacity. Every build runs one at a time on the single Jenkins machine, and `disableConcurrentBuilds` queues each new build until the previous one finishes. Today a run takes about 40 seconds, which is fine for four people. With forty developers each pushing five or six times a day, that is over 200 builds a day through one queue. Builds from busy hours would stack up, and with SCM polling adding up to five minutes before a build even starts, feedback could easily take longer than the 10-minute rule allows. I would change three things: add dedicated build agents so several builds can run at once (the controller should only schedule, not build), switch from polling to GitHub webhooks so builds start within seconds, and move to a multibranch pipeline so each feature branch is built separately instead of everyone sharing one branch job. The shared Nexus admin login would also need to become a dedicated publish-only user with its own rotation schedule.
