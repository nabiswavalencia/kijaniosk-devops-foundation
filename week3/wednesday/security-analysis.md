# Security analysis of kk-api.service

## Scores
| Stage | Overall exposure | Evidence |
|---|---|---|
| Five course directives only | **5.8 MEDIUM** | `security-analysis-before.txt` |
| After adding 14 more | **3.0 OK** | `security-analysis.txt` |

The lab's target is below 4.0, so the unit meets it. The advanced target of below 3.0 was not reached.

## What the first five do
| Directive | Effect |
|---|---|
| `NoNewPrivileges=true` | The service cannot gain privileges through SUID or SGID files |
| `PrivateTmp=true` | The service gets its own `/tmp`, invisible to others |
| `ProtectSystem=strict` | The whole filesystem is read-only for the service, except paths listed in `ReadWritePaths=` |
| `ProtectHome=true` | `/home`, `/root` and `/run/user` are not accessible |
| `CapabilityBoundingSet=` (empty) | Drops all Linux capabilities |

## The 14 I added, chosen from the unmet (✗) lines of the tool's own output
`ProtectKernelTunables`, `ProtectKernelModules`, `ProtectKernelLogs`, `ProtectControlGroups`, `ProtectClock`, `ProtectHostname`, `PrivateDevices`, `RestrictNamespaces`, `RestrictRealtime`, `RestrictSUIDSGID`, `LockPersonality`, `SystemCallArchitectures=native`, `RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`, `UMask=0077`.

Two I want to explain properly:
- **`RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`.** An API only needs IPv4, IPv6 and local sockets. Raw sockets and other exotic network families are a way to attack the kernel's network code or to sniff traffic, and this closes them. I chose it over blocking `AF_UNIX` as well because the service still needs local sockets.
- **`UMask=0077`.** Files the service creates are readable by its owner only, so a log or cache file cannot accidentally become world-readable. The shared log directory's default ACLs still let the right accounts read what they should.

## What I left out, and why
- **`MemoryDenyWriteExecute=true`.** This blocks memory that is both writable and executable. Node's JavaScript engine compiles code on the fly and normally needs exactly that, so I expect it to crash the service. I did not test it here because no application runs on this unit yet.
- **`SystemCallFilter=@system-service`.** It narrows the calls the service may make, but I would want to test it with the real application before enabling it.
- **`ProcSubset=pid`** (still listed as unmet at 0.1). Hides non-process files under `/proc`. Low risk, small gain, left for a later pass.

## Other observations
- The unit is enabled but not started, because no application code is deployed. After a reboot systemd did start it and it exited with status 0, because the placeholder `server.js` from Tuesday just prints one line.
- Each of the last remaining items in the tool's output is worth only 0.1, so the next drop below 3.0 would need several more directives plus real-app testing.
