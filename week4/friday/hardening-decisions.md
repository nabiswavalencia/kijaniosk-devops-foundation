# Hardening Decisions: KijaniKiosk Staging Environment

## What this document covers

This explains the security choices in the KijaniKiosk staging environment and why each matters. Every choice is written into code that rebuilds the environment automatically, so none depends on someone remembering a manual step.

## How the environment is built

Two tools work in sequence. The first creates three servers: one for the shop's main service, one for the payment service, and one for the log collector. The second configures them to a written standard: who can log in, what each program may touch, and which traffic is allowed. A single script runs both tools in order and stops if either one fails. We ran it twice. The second run found nothing to change, which shows the environment matches its specification and has not drifted.

## Controls

| Control | What it does | Risk mitigated |
|---|---|---|
| Key-only login, one key for both tools | Servers accept logins only with the key the build installs; the configuration tool uses the same key | Password guessing; servers drifting because someone configured them by hand |
| Administrative access limited by network | The firewall accepts logins only from the network the build machine sits on and from the monitoring subnet | Login attempts from anywhere else |
| Default-deny firewall on every server | Incoming traffic is refused unless a rule allows it; service ports answer only the server itself and the monitoring subnet | Direct access to internal services that should only be reached through the web front end |
| Central, locked record of the environment | The record of what exists is kept in central storage, and only one change can run at a time; a second attempt is refused | Two people changing the environment at once and corrupting the record |
| No storage credentials in the code | Credentials for the central record are supplied when the pipeline runs, never written into shared files | Credentials leaking through the code repository |
| A separate identity for each service, with no login | Each service runs under its own account, which cannot be used to sign in | One compromised service being used to log in or act as another |
| Three access levels on the shared log area | The main service can write logs, the payment service can only read them, and the log collector owns them | The payment service altering or erasing log evidence |
| Settings owned by the administrator | Services can read their settings but cannot change them | A compromised service rewriting its own configuration |
| Payment service sealed off from the system | It cannot gain privileges, sees the system as read-only, and cannot reach home folders, hardware, kernel settings or other programs | An attacker inside the payment service moving into the wider server |
| Payment service network limited to the server itself | It can only communicate over the server's internal connection | Payment data being sent directly to an outside address |
| Persistent, size-limited logs with daily rotation | Logs survive restarts, are capped in size, and keep their access rules when rotated | Losing the record after a reboot; logs filling the disk |

## The payment service score

The operating system's security assessment rates exposure from 0, most protected, to 10. The payment service scores 2.5. The main service and log collector score 3.0. The target was below 2.5, and this result sits on that boundary.

Two further restrictions would lower the number, but both stop the payment service from working. One blocks the technique the service's runtime relies on to run its code. The other stopped the service from starting, and we did not identify the exact cause. We chose a working service at 2.5 over a lower number on a service that cannot process payments. The build code now produces this score on every rebuild.

## Locking the environment record

The training brief expected the storage service we used to offer no locking. We tested it: with one change waiting for approval, a second attempt was refused. Locking works here because this particular storage build supports the check it relies on. That is a property of this build, not of every storage service. In production, cloud providers' locking services or a dedicated coordination service provide it reliably.

## Choices made to keep rebuilds predictable

Two behaviours from last week's script were left out on purpose: it wiped and rebuilt the firewall on every run, and it stamped the time on its health record. Both make every run look like a change, which hides real drift. Each server now runs one service instead of all three, which keeps the payment service separate from the others at the server level.

## What this does not protect against

All three services can read every settings file, including the payment provider key, because they share one group; separating that key so only the payment service can read it is the next fix. The payment key in the build code is a placeholder, and real secrets need an encrypted vault before production. Because firewall rules are no longer wiped on each run, a rule added by hand would remain in place unnoticed until someone reviews the firewall. The storage service holding the environment record uses its default administrator login, has no encryption, and runs on one laptop with no backup. Software versions are pinned and held, so security patches arrive only when someone updates the pinned versions. Nothing here watches for intrusions or alerts anyone when a service fails. These servers sit on a private laptop network, so none of this has faced real internet traffic.

## Appendix: evidence

From `pipeline-run2.log`:

```
kk-payments: Overall exposure level for kk-payments.service: 2.5 OK
kk-api:      Overall exposure level for kk-api.service: 3.0 OK
kk-logs:     Overall exposure level for kk-logs.service: 3.0 OK
```

Lock test: HTTP 412 `PreconditionFailed`, see `week4/notes/lock-test.png`.
