# kk-payments hardening log

The payments service handles financial transaction data, so it was hardened
further than the API and log services. Every directive below was tested on a
scratch copy of the service (`kk-payments-test.service`, port 3101) before
being applied to the real unit, so that a bad directive would break the test
copy, never the real payments service.

## Starting score

**9.2 UNSAFE**, with only the baseline directives that all three services share
(`Type=simple`, `User=`, `Group=`, `EnvironmentFile=`, restart policy). No
sandboxing directives applied yet.

## Automated round: 25 candidates tested one at a time

Run via `harden-payments.sh`, which applies one directive at a time to the
scratch copy, restarts it, checks whether it is still active and answering on
its port, and records the score either way.

| Step | Directive | Score | Kept? |
|---|---|---|---|
| 1 | `NoNewPrivileges=true` | 9.0 | kept |
| 2 | `PrivateTmp=true` | 8.7 | kept |
| 3 | `ProtectSystem=strict` | 8.5 | kept |
| 4 | `ProtectHome=true` | 8.3 | kept |
| 5 | `CapabilityBoundingSet=` | 5.8 | kept |
| 6 | `ProtectKernelTunables=true` | 5.6 | kept |
| 7 | `ProtectKernelModules=true` | 5.5 | kept |
| 8 | `ProtectKernelLogs=true` | 5.3 | kept |
| 9 | `ProtectControlGroups=true` | 5.1 | kept |
| 10 | `ProtectClock=true` | 4.9 | kept |
| 11 | `ProtectHostname=true` | 4.9 | kept |
| 12 | `PrivateDevices=true` | 4.7 | kept |
| 13 | `RestrictNamespaces=true` | 3.9 | kept |
| 14 | `RestrictRealtime=true` | 3.8 | kept |
| 15 | `RestrictSUIDSGID=true` | 3.7 | kept |
| 16 | `LockPersonality=true` | 3.7 | kept |
| 17 | `SystemCallArchitectures=native` | 3.5 | kept |
| 18 | `RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX` | 3.0 | kept |
| 19 | `SystemCallFilter=@system-service` | 1.7 (if applied) | **rejected** |
| 20 | `ProtectProc=invisible` | 2.9 | kept |
| 21 | `ProcSubset=pid` | 2.9 | kept |
| 22 | `UMask=0077` | 2.9 | kept |
| 23 | `MemoryDenyWriteExecute=true` | 2.8 (if applied) | **rejected** |
| 24 | `PrivateUsers=true` | 2.7 | kept |
| 25 | `IPAddressDeny=any` | 2.5 (if applied) | **rejected** |

**22 directives kept** from this round, bringing the scratch service to a
starting point of **2.7**.

## Manual follow-up round: resolving the three rejections

The automated tester's own log of *why* each rejection happened was not
informative (a timing issue in the test script meant it captured a shutdown
message rather than the real failure), so I re-tested each rejected directive
individually, by hand, on a fresh scratch copy, capturing the real
`journalctl` output this time.

**`MemoryDenyWriteExecute=true` — rejected, with a clear, reproducible cause.**
The service crashed on the very first request: `Main process exited,
code=dumped, status=5/TRAP`, and the journal shows the crash happening inside
Node's V8 engine while it is JIT-compiling JavaScript
(`v8::internal::baseline::BaselineBatchCompiler`, `Runtime_CompileLazy`).
`MemoryDenyWriteExecute` blocks a process from creating memory that is both
writable and executable at the same time; V8 needs exactly that to compile
and run JavaScript. This is not a configuration problem to work around, it is
a fundamental incompatibility between this directive and any Node.js service.

**`IPAddressDeny=any` alone — rejected, then resolved by pairing it with an
allow rule.** Applied alone, it blocks all IP traffic, including loopback,
which broke connectivity to the service entirely (the test could not even
confirm the port was open). Paired with `IPAddressAllow=localhost`, the same
protection intent (deny all IP traffic) now excludes loopback specifically,
and the service works normally. This pairing is what actually brought the
score down to 2.5, and it is included in the final unit.

**`SystemCallFilter=@system-service` — rejected by the automated tester; not
re-tested manually.** The real, valid test that `harden-payments.sh` performed
(restart the scratch service, then check whether it answers on its port)
failed with this directive applied — the service did not come back up. The
score of 1.7 shown in the table is what the tool reported *would* apply if the
directive were kept, not a score actually measured on a working service. I
attempted to re-test this directive in isolation afterward to capture the
exact blocked syscall, but hit unrelated scripting mistakes of my own (a
missing scratch-unit file on two attempts) that consumed the time I had for
this line of investigation, and chose not to keep retrying given the safety
margin already achieved. I am recording this honestly rather than claiming a
clean re-test that did not happen: the rejection itself is real and was
independently observed by the automated tester, but the specific syscall it
blocks was never identified.

**`RemoveIPC=true` — tested separately, accepted, no measurable score
change.** Verified working on the real `kk-payments.service` after all other
directives were applied. Kept anyway: it is a safe, genuine hardening step
(cleans up SysV IPC objects on stop) even though `systemd-analyze security`'s
two-decimal precision does not show a difference.

## Final score

**2.5 OK**, measured directly on the real `kk-payments.service`, running:
```
sudo systemd-analyze security kk-payments.service --no-pager
```
The service was confirmed active and listening throughout
(`systemctl status kk-payments.service` showed `Active: active (running)`).

This does not clear the "below 2.5" target strictly. I chose not to pursue
`SystemCallFilter=@system-service` further to try to reach it, because the one
real test available showed it breaks the service, and the project brief is
explicit that a lower score on a broken service is worse than a higher score
on a working one. I judged 2.5, backed by a running service and honestly
documented limits, to be the more defensible outcome than an unverified
attempt at a lower number.

## Final directive set applied to kk-payments.service

```
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
CapabilityBoundingSet=
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
PrivateDevices=true
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
SystemCallArchitectures=native
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
ProtectProc=invisible
ProcSubset=pid
UMask=0077
PrivateUsers=true
IPAddressDeny=any
IPAddressAllow=localhost
RemoveIPC=true
```

To capture the exact live unit for the deliverable, run on the VM:
```
sudo systemctl cat kk-payments.service
```
ubuntu@ip-172-31-9-45:~/friday$ sudo systemctl cat kk-payments.service
# /etc/systemd/system/kk-payments.service
[Unit]
Description=KijaniKiosk Payments Service
After=network-online.target
After=kk-api.service
Wants=network-online.target
Wants=kk-api.service
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=kk-payments
Group=kk-payments
WorkingDirectory=/opt/kijanikiosk/payments
ExecStart=/usr/bin/node /opt/kijanikiosk/payments/processor.js
Restart=on-failure
RestartSec=5s
EnvironmentFile=/opt/kijanikiosk/config/db.env
EnvironmentFile=/opt/kijanikiosk/config/payments-api.env
Environment=NODE_ENV=production
Environment=PORT=3001
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-payments
# --- extra hardening (filled in from harden-payments.sh, runbook step 5) ---
# EXTRA-HARDENING-KK-PAYMENTS
IPAddressDeny=any
IPAddressAllow=localhost
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
CapabilityBoundingSet=
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
PrivateDevices=true
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
SystemCallArchitectures=native
RemoveIPC=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
ProtectProc=invisible
ProcSubset=pid
UMask=0077
PrivateUsers=true
IPAddressDeny=any
IPAddressAllow=localhost

[Install]
WantedBy=multi-user.target


## Judgment note

I was most tempted to keep pushing for `SystemCallFilter=@system-service`,
since 1.7 would have given a comfortable margin under the target instead of
landing exactly on the boundary. I chose not to, because the only test I ran
against it showed the service failing to start, and shipping a payments unit
I could not verify actually runs would have been the wrong trade to make for
a better-looking number.
