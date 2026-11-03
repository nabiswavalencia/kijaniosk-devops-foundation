# Pipeline Design Review: Five Principles

Final Jenkinsfile (repo root), first green run with this design: build #12, 38 seconds.

| # | Principle | Verdict | Evidence |
|---|---|---|---|
| 1 | Fail fast | PASS | Lint runs first. Fault #14 (syntax error) stopped the pipeline at Lint and skipped every later stage. `npm ci` lives in Lint because ESLint is a project dependency and must be installed before it can run; Build reuses the installed modules. |
| 2 | Declare, don't inherit | PASS, with one gap | Runtime pinned to `node:22.23.3-alpine` instead of the host's Node 18.19.1. All paths and names are in the `environment` block. The Nexus credential comes from the Jenkins store. Gap: `NEXUS_URL` uses the Docker bridge address `172.17.0.1`, which is specific to a Linux host running Docker; on another agent it would need to come from a Jenkins global variable. |
| 3 | Clean up after every build | PASS | `cleanWs()` runs in `post { always }`. The `.npmrc` holding the Nexus token is created and deleted in the same `sh` step, with `trap 'rm -f .npmrc' EXIT` so it is removed even if publish fails. |
| 4 | Diagnostic output on failure | PASS | JUnit results are published from the Test stage's own `post { always }`, so they appear even when tests fail. The parallel Verify stage leaves `failFast` off: in fault #18 the Security Audit still finished and reported while Test failed. |
| 5 | The 10-minute rule | PASS | Full run (lint, build, parallel test and audit, archive, publish) takes about 35 seconds (build #23). |

## Improvement implemented: declare the build environment

Before Thursday the pipeline used `agent any` and inherited whatever Node.js was installed on my laptop (18.19.1). That version is end of life, and the test tooling (Jest 30, jest-junit 17) declares that it needs Node 20 or later, so every run printed `EBADENGINE` warnings. I replaced it with a Docker agent pinned to an exact image tag, `node:22.23.3-alpine`, which I chose by pulling `node:22-alpine`, reading its exact version and pinning that. Build #12 shows `docker run ... node:22.23.3-alpine` and `node --version` returning v22.23.3 while the host still has v18.19.1.

Two problems appeared once the build ran inside the container, and both are now handled in the Jenkinsfile:

- The container runs as the `jenkins` user, which has no home directory inside the image, so `npm ci` would try to write its cache to `/.npm`. I set `NPM_CONFIG_CACHE` to a folder in the workspace.
- The Alpine image has no `git`, so `git rev-parse --short HEAD` fails inside it. `GIT_SHORT` falls back to the first seven characters of `GIT_COMMIT`, which Jenkins sets during checkout. Build #12 shows the fallback producing `bfeddba`.

## Other decisions

- **Concurrency:** I kept `disableConcurrentBuilds`, written as `disableConcurrentBuilds(abortPrevious: false)`. By default it queues a second build until the first finishes rather than cancelling it, so no push is dropped. The cost is waiting time when many developers push at once, which I discuss in the Friday reflection.
- **Credentials in logs:** Jenkins runs `sh` steps with `-x`, which prints each command after variables are expanded. The base64 form of the Nexus credential is not masked by Jenkins, so the Publish step starts with `set +x`. My credential audit checks for the base64 form as well as the plain password.
- **Security audit threshold:** with Jest 29, `npm audit --audit-level=high` failed on a high-severity `braces` advisory in its dependencies. I upgraded to Jest 30, which leaves only moderate advisories, so the gate stays at `high` without being weakened.
