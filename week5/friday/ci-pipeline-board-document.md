# KijaniKiosk Payments: How New Code Becomes an Approved Version

Prepared for Nia (Platform Lead) for the board review. Author: Valencia Neema.

## Why this exists

Until this week, releasing a change to the payments service depended on a person remembering to test it and copying the right files by hand. For a service that handles customer money, that is too much to leave to memory. We now have an automatic quality check that runs every time a developer saves work to our shared codebase. It either stores the change as a numbered, approved version, or stops and tells the team what is wrong. Nobody can forget or skip it.

## The journey of a change

Within five minutes of a change being saved, the checker works through these steps in order. A step only starts if the one before it passed. The whole journey takes about a minute.

| Step | What it confirms | Why it matters to the business |
|---|---|---|
| 1. Style and syntax check | The code is written correctly and follows team rules | The cheapest mistakes are caught first, in seconds |
| 2. Assemble | The service can be packaged into a runnable form | Proves there is something real to test and ship |
| 3a. Behaviour tests | Payment rules work, such as rejecting a zero amount | Wrong payment logic never reaches customers |
| 3b. Security check (alongside 3a) | No outside building block the service uses has a known serious flaw | Protects us from weaknesses in other people's code |
| 4. Record | A copy of the package is kept with a unique fingerprint | We can later prove exactly which copy was produced |
| 5. Store as a version | The approved package enters our version library under a unique number | Releases use a known, approved version, never "whatever is newest" |

Every run uses a fresh, sealed workspace with fixed tool versions, so an upgrade on a laptop or server cannot quietly change the result.

## Why version numbers matter for a payments platform

Each stored version has a two-part number, for example 1.0.0-bfeddba. The first part is the release number people talk about. The second part is a short code pointing to the exact change it was built from. If a customer reports a payment problem, we can name the version that was running and trace it to the code behind it. If a release misbehaves, we return to the previous approved version instead of rebuilding old code and hoping it matches. The library already holds several versions, each tied to a different change.

## What Happens When Something Goes Wrong

I deliberately broke each step, one at a time, to prove the system stops in the right place:

- A typing error in the code was caught by step 1. Nothing else ran.
- A broken packaging instruction stopped the process at step 2, before any testing time was spent.
- A payment rule that gave the wrong answer failed step 3a. The security check still finished, so the developer received both results together. Nothing was stored.
- Pointing step 4 at a folder that did not exist stopped the process there, so nothing unrecorded could be stored.
- Pointing step 5 at a stored password that did not exist failed the final step. The recorded copy stayed available for inspection, but nothing entered the version library.

Each time, the process stopped at the failing step, nothing unapproved became a version, and a failure notice named the problem. Our rule is that whoever caused the stop fixes it before starting new work, because everyone else is waiting on a healthy shared codebase. After each test I undid the break and confirmed the process passed again.

## Keeping passwords out of sight

The password used to store versions lives in a locked store inside the checker, not in the code. I searched the code, its full history and every run record: it appears nowhere, as written or in disguised form.

## What this does not yet do

This work proves a change is tested and stored safely. It does not yet place that version on the live servers; that delivery step comes next. It runs on a single machine, so it demonstrates the process rather than being production equipment, and it can take up to five minutes to notice a change because that machine is not reachable from the internet. Failure notices go to the run record, not yet to the team's chat. The tests check payment rules, not complete customer journeys or heavy load, and the storage account uses an administrator login that should become a restricted one.
