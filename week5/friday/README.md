# Week 5 Friday: KijaniKiosk CI Pipeline, Board-Ready Delivery

## Deliverables in this folder

| File | Contents |
|---|---|
| `../../Jenkinsfile` (repo root) | Final pipeline: Docker agent, Lint, Build, parallel Verify, Archive, Publish, post conditions |
| `green-pipeline-run.txt` | Full log of build #23, final green run, 35 seconds, with total duration appended |
| `nexus-versions-screenshot.png` | Nexus browse view showing the published versions |
| `fault-injection-log.md` | All five stages faulted, observed behaviour and design rationale per row |
| `ci-pipeline-board-document.md` | Plain-language document for Nia (761 words) |
| `credential-audit.txt` | Five audit checks against the final Jenkinsfile, git history and all build logs |
| `reflection.md` | Answers to the three Friday reflection questions |

## What the final pipeline does

When a change is pushed to `feature/week5-ci-pipeline`, Jenkins notices it within five minutes and runs:

1. **Checkout** of the commit that triggered the build.
2. **Start the build container** `node:22.23.3-alpine`. Every following step runs inside it.
3. **Compute the version** `1.0.0-<short SHA>` from `package.json` and the commit.
4. **Lint:** `npm ci` (clean install from the lockfile), then ESLint.
5. **Build:** `npm run build`, check that `dist/` is not empty, and stash the output.
6. **Verify, in parallel:**
   - **Test:** unstash and run Jest, publishing JUnit results even on failure.
   - **Security Audit:** `npm audit --audit-level=high`.
7. **Archive:** keep `dist/` in Jenkins with a fingerprint.
8. **Publish:** take the Nexus login from the credentials store, write a temporary `.npmrc`, set the version, `npm publish`, and delete `.npmrc`.
9. **Post:**
   - success prints the version and the Nexus URL
   - failure prints a failure notice
   - changed reports when the status flips
   - always cleans the workspace

## Steps I followed this week

1. Freed disk space, then installed Java 21, Jenkins LTS, Node.js and npm on my laptop.
2. Added the `payments/` service and confirmed lint, build and tests pass locally.
3. Created the Jenkins Pipeline job reading the Jenkinsfile from my branch, with SCM polling.
4. Monday: one-stage pipeline, deliberately broken (#2) and fixed (#4).
5. Tuesday: Build, Test and Archive stages; failing test proven (#6 red, #7 green).
6. Wednesday: Nexus in Docker and a manual publish first; the Jenkins credential; the Publish stage with `withCredentials`; masking check (#9); publish (#10); credential audit.
7. Thursday: Docker Pipeline plugin; pinned Docker agent; Lint first; parallel Verify; `failure` and `changed` post blocks (#12).
8. Thursday: faulted Lint, Build, Test, Archive and Publish one at a time with a revert after each (#14 to #23).
9. Friday: saved the final run (#23), checked the Nexus versions, re-ran the credential audit, and wrote the documents.

## Challenges and how I approached them

| # | Challenge | What I saw | How I approached it |
|---|---|---|---|
| 1 | Not enough disk space | 3.3 GB free (91% used); Nexus, Jenkins and the Node image need about 3 GB | Found the space with `du`, destroyed two Vagrant VMs I had finished with (3.5 GB) and cleared caches. Result: 8.2 GB free. |
| 2 | My old Jenkins container was gone | `docker ps -a` showed no Jenkins. The class container had no volume, so its data went when it was removed | Installed Jenkins natively with apt, as Canvas does, so Docker agents work without extra socket configuration. |
| 3 | Canvas install commands were out of date | Canvas uses Java 17 and the `jenkins.io-2023.key` repository key | Checked the current Jenkins documentation: Jenkins now requires Java 21 and uses `jenkins.io-2026.key`. Used those. |
| 4 | No payments repository was provided | Canvas assumes `kijanikiosk-payments` exists with build and test scripts | Created `payments/` in my repo (Express, Jest, ESLint, build to `dist/`, committed lockfile) and used `dir('payments')` in the Jenkinsfile. |
| 5 | Jenkins cannot receive webhooks | The laptop has no public address | Used SCM polling. Confirmed it with a build marked "Started by an SCM change". Used Build Now for fault injection to avoid waiting. |
| 6 | Canvas test command does not fit Jest | `--reporter=junit` is a Mocha flag; Jest rejects it | Configured `jest-junit` in `package.json`, so plain `npm test` writes `test-results/junit.xml`. |
| 7 | Security audit failed with Jest 29 | `npm audit --audit-level=high` reported a high-severity `braces` advisory inside Jest's dependencies | Upgraded to Jest 30, leaving only moderate advisories. The threshold stays at `high` instead of being lowered. |
| 8 | Nexus rejected the Canvas auth line | Canvas puts base64 `user:password` in `_authToken`, which npm sends as a Bearer token | Used `_auth=` instead, which sends basic auth. Tested by a manual publish before using it in Jenkins. |
| 9 | Credential could leak through command echo | Jenkins runs `sh` with `-x`, so `NEXUS_TOKEN=...` (base64, not masked) would be printed | Started the Publish shell with `set +x` and used `base64 -w0`. Audit check 5 confirms the base64 form is in no build log. |
| 10 | Username not masked | Build #9 showed `User: admin Pass: ****` | Jenkins only masks the password unless "Treat username as secret" is ticked. Noted it; the password and token never appear. |
| 11 | Node version mismatch | `EBADENGINE` warnings: the test tools need Node 20+, the laptop has 18.19.1 (end of life) | Moved the build into a Docker agent pinned to an exact tag, `node:22.23.3-alpine`. |
| 12 | Docker Pipeline plugin missing | Not in the installed plugins list | Installed it before pushing the Docker agent Jenkinsfile. |
| 13 | `localhost` inside a container | Inside the build container, `localhost` is the container, not Nexus | Used the Docker bridge address `172.17.0.1`. Tested it from a container with `wget` before using it. |
| 14 | npm cache and git inside Alpine | The container user has no home directory, and the image has no `git` | Set `NPM_CONFIG_CACHE` in the workspace. Fell back to `$GIT_COMMIT` for the short SHA (build #12 shows the fallback working). |
| 15 | Lint before Build conflicts with `npm ci` in Build | ESLint is a dependency, so it does not exist until `npm ci` runs | Moved `npm ci` into Lint; Build reuses the modules. A lint failure still stops everything after it (#14). |
| 16 | Concurrency setting described inconsistently | Canvas says `disableConcurrentBuilds()` cancels the second build | By default it queues the second build. I wrote it as `disableConcurrentBuilds(abortPrevious: false)` to make that explicit. |
| 17 | Shell mistakes while collecting evidence | `getlog #6` saved nothing, because `#` starts a comment; a placeholder `<N>` caused a syntax error; running `restore` without a fault commit would have reverted my real Jenkinsfile commit | Used plain numbers, wrote small helper functions (`runbuild`, `fault`, `restore`, `saveflt`) that start a build and wait for its result, and turned polling off during fault injection so every build was one I started. Git refused the stray revert, and I restored the file with `git restore`. |

## Results

- All five stages faulted independently, each with the expected downstream behaviour, and each followed by a green build.
- Final run: 35 seconds, well under the 10-minute target.
- Nexus holds `1.0.0` (manual) and multiple pipeline versions in the `1.0.0-<sha>` format, one per green commit.
- The version for the failed publish commit (`ad1435f`) does not exist in Nexus, which confirms that the failed Publish stage published nothing.
- Credential audit: no matches in the Jenkinsfile, the tracked files, the git history, or any build log, in either plain or base64 form.
