# Week 5: Continuous Integration with Jenkins (KijaniKiosk Payments)

Branch: `feature/week5-ci-pipeline`, PR into `develop`. The pipeline definition is the `Jenkinsfile` in the repo root. The service it builds is in `payments/`.

## Environment

| Component | What I used |
|---|---|
| Host | Ubuntu 24.04 laptop (HP ProBook), no cloud VM |
| CI server | Jenkins 2.580.1 LTS, installed natively with apt, Java 21 |
| Build environment | Docker agent pinned to `node:22.23.3-alpine` (from Thursday) |
| Artifact registry | Nexus Repository 3 in Docker on port 8081, hosted npm repository `npm-kijanikiosk` |
| Trigger | SCM polling, `H/5 * * * *` (Jenkins on a laptop cannot receive GitHub webhooks) |
| Service | `payments/`: Express app, Jest tests (JUnit XML via jest-junit), ESLint, build script writing `dist/` |

## Day by day

### Monday: Jenkins installed and the first pipeline
1. Freed disk space (3.3 GB to 8.2 GB free) by removing finished Vagrant VMs and caches.
2. Installed Java 21 and Jenkins LTS from the official apt repository, plus Node.js and npm for the built-in agent; added the `jenkins` user to the `docker` group.
3. Completed the setup wizard with the suggested plugins and created an admin user.
4. Added the `payments/` service to the repo and verified lint, build and tests locally.
5. Created the `kijanikiosk-payments` Pipeline job: Pipeline script from SCM, branch `*/feature/week5-ci-pipeline`, Script Path `Jenkinsfile`, Poll SCM every 5 minutes.
6. Pushed a one-stage Jenkinsfile (Environment Check), then broke it on purpose and fixed it.

Evidence: build #2 red (exit code 127, command not found), build #4 green. Folder: `week5/monday/`.

### Tuesday: Build, Test, Archive
1. Replaced the Jenkinsfile with a skeleton using `environment`, `options` (timeout, log rotation, no concurrent builds) and a `post` block.
2. Build stage: `npm ci`, `npm run build`, and a check that `dist/` exists.
3. Test stage: `npm test` with `set -e`, and JUnit results published from the stage's `post { always }`.
4. Archive stage: `archiveArtifacts` with fingerprinting, only on success.
5. Confirmed polling works ("Started by an SCM change").
6. Proved the test stage can fail: a deliberate failing test turned the build red with Archive skipped, then a revert turned it green.

Evidence: build #6 red (exit code 1, Archive skipped), build #7 green with archived artifact. Folder: `week5/tuesday/`.

### Wednesday: Nexus and credentials
1. Started Nexus in Docker, completed setup, disabled anonymous access, and created the hosted npm repository `npm-kijanikiosk`.
2. Published version 1.0.0 manually from the terminal first, to test Nexus on its own before automating it.
3. Stored the Nexus login in the Jenkins credentials store as `nexus-credentials`.
4. Added the version string `<package.json version>-<git short SHA>` to the `environment` block.
5. Added a Publish stage using `withCredentials`, writing and deleting `.npmrc` inside the same shell step.
6. Verified masking with a temporary test stage, then removed it.
7. Ran a five-check credential audit on the Jenkinsfile, git history and every build log.

Evidence: build #9 (`Pass: ****`), build #10 published `1.0.0-03c4531`. Folder: `week5/wednesday/`.

### Thursday: Docker agent, parallel stages, fault injection
1. Installed the Docker Pipeline plugin.
2. Replaced `agent any` with a Docker agent pinned to `node:22.23.3-alpine`.
3. Reordered the stages for fail-fast: Lint first, then Build, then a parallel Verify stage (Test and Security Audit), then Archive and Publish.
4. Added `failure` and `changed` post conditions.
5. Faulted each of the five stages one at a time and restored green after each.
6. Reviewed the pipeline against the five design principles.

Evidence: build #12 (first Docker-agent run, 38 s), faults #14 to #23 in `week5/thursday/faults/`, `pipeline-design-review.md`, `fault-injection-log.md`.

### Friday: board-ready delivery
1. Captured the final green run (#23, 35 seconds).
2. Recorded the Nexus versions.
3. Re-ran the credential audit against the final Jenkinsfile.
4. Wrote the board document for Nia, the fault injection log and the reflection.

Full summary of the week, including the problems I hit and how I solved each one: `week5/friday/README.md`.

## Where to find everything

| Day | Folder | Key builds |
|---|---|---|
| Monday | `week5/monday/` | #2 red, #4 green |
| Tuesday | `week5/tuesday/` | #6 red, #7 green |
| Wednesday | `week5/wednesday/` | #9 masking check, #10 publish |
| Thursday | `week5/thursday/` | #12 Docker agent, #14 to #23 faults |
| Friday | `week5/friday/` | #23 final green run |
| Extra | `week5/screenshots/` | Additional screenshots, named by day and build number |

Note on build records: the Jenkinsfile keeps the last 10 builds (`logRotator(numToKeepStr: '10')`), so builds #1 to #13 are no longer in Jenkins. Their console logs were saved to this repo before rotation, and `week5/tuesday/pipeline-screenshots/build-history-red-6-green-7.png` shows #6 red and #7 green in the build history. For long-term evidence, the registry (Nexus) is the store of record, not Jenkins.
