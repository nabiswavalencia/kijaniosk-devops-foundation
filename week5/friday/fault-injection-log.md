# Fault Injection Log: KijaniKiosk Payments Pipeline

Final Jenkinsfile: repo root. Agent: `node:22.23.3-alpine` (Docker). Stage order: Lint, Build, Verify (parallel: Test, Security Audit), Archive, Publish.

Method: one fault at a time. Each fault was committed (`fault: ...`), built, its console log saved, then undone with `git revert` and rebuilt green before the next fault. No faults were stacked. Full red logs are in `week5/thursday/faults/`.

| # | Stage faulted | Fault introduced | Red build | Expected behaviour | Observed behaviour | Match | Restored green | Design rationale |
|---|---|---|---|---|---|---|---|---|
| 1 | Lint | Appended `const broken = ;` to `payments/src/payments.js` | #14 | Lint fails; Build, Verify, Archive, Publish skip | ESLint `18:16 Parsing error: Unexpected token ;`. Log: Build, Verify, Test, Security Audit, Archive and Publish all "skipped due to earlier failure(s)". `changed` and `failure` post blocks ran | Y | #15 | Lint is the fastest check, so malformed code is rejected before any time is spent building or testing it. |
| 2 | Build | Changed `npm run build` to `npm run build-missing` in the Jenkinsfile | #16 | Lint passes; Build fails; Verify, Archive, Publish skip | Lint green. `npm error Missing script: "build-missing"`, exit code 1. Verify, Test, Security Audit, Archive, Publish skipped. Post blocks ran | Y | #17 | If the service cannot be packaged there is nothing valid to test or ship, so stopping here keeps tests from running against missing or stale output. |
| 3 | Test (in Verify) | Added test `expect(true).toBe(false)` to `payments/tests/payments.test.js` | #18 | Test fails; Security Audit runs to completion; Archive, Publish skip | Test red with exit code 1. Security Audit was not skipped: only Archive and Publish appear as skipped. Post blocks ran | Y | #19 | Leaving `failFast` off lets the developer see the audit result in the same run, while no artifact is ever produced from code with a failing test. |
| 4 | Archive | Pointed `archiveArtifacts` at `nonexistent-dir/**` | #20 | Archive fails; Publish skips | `ERROR: No artifacts found that match the file pattern "nonexistent-dir/**"`. Publish skipped. Post blocks ran | Y | #21 | Publish depends on a recorded, fingerprinted copy existing first, so nothing reaches Nexus without a matching record in Jenkins. |
| 5 | Publish | Changed `credentialsId` to `'wrong-id'` | #22 | Archive has run; Publish fails; artifact in Jenkins but not Nexus | `Archiving artifacts` completed, then `ERROR: Could not find credentials entry with ID 'wrong-id'`. No version for the fault commit appeared in Nexus. Post blocks ran | Y | #23 | The credential lookup fails before any upload starts, so a bad credential can never produce a half-published version, and the fix is in the Jenkins credentials store rather than in the code. |

## Notes

- Row 2 differs from the Canvas table, which faults `npm ci`. In my final pipeline `npm ci` runs in the Lint stage, because ESLint is installed as a dependency and must be present before linting. I faulted the Build stage's own command instead so that the fault isolates Build.
- Every red build printed `Build status changed to FAILURE` (the `changed` condition) and the `FAILURE NOTIFICATION` line (the `failure` condition). Every green restore printed the artifact URL from the `success` condition.
- Exit codes seen during the week: 127 on Monday (#2, command not found) and 1 for test and script failures. The difference tells me whether to look for a missing tool or a failing check.
