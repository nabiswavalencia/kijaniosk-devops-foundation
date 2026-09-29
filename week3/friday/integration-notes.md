# Integration Notes

Four places where two requirements from this project pulled against each other,
plus two additional conflicts I discovered while running the script live, which
I'm including because they were genuine integration problems, not anticipated
by the brief, and the reasoning behind resolving them is the same kind of work.

---

## Challenge A: ProtectSystem=strict and the EnvironmentFile

**Conflict.** `ProtectSystem=strict` makes the filesystem read-only for a service
except for explicitly listed paths. All three units read their secrets via
`EnvironmentFile=/opt/kijanikiosk/config/*.env`. If that path fell under a
directory the sandbox locks down, the services would fail to start with a
confusing, non-obvious error about environment loading, not a clear permissions
message.

**Options considered.**
1. Move configuration files to a path outside the sandboxed area (for example,
   somewhere under `/etc/kijanikiosk/`).
2. Keep configuration exactly where the Tuesday access model already put it, and
   confirm reads still work under `ProtectSystem=strict`.

**Chosen.** Option 2. Configuration stays at `/opt/kijanikiosk/config/`.

**Why.** `ProtectSystem=strict` restricts *writes*, not reads, across the whole
filesystem. Reading `db.env` or `payments-api.env` was never actually blocked;
the risk was theoretical, not real, for this specific directive. Moving the
config would have changed the access model Tuesday and Friday both depend on
for no actual benefit. I verified this directly: `sudo -u kk-api cat
/opt/kijanikiosk/config/db.env` succeeds with the hardened unit running. The
only path that does need write access is `/opt/kijanikiosk/shared/logs`, which
each hardened unit explicitly allows with `ReadWritePaths=`.

---

## Challenge B: The monitoring user and ACL defaults

**Conflict.** Phase 8 writes a health-check JSON file to
`/opt/kijanikiosk/health/`. The script runs as root, so the file would be
root-owned by default. But both the monitoring system and my own regular user
need to read it without elevated privileges, and this directory did not exist
in Tuesday's access model at all.

**Options considered.**
1. Owner `root`, group `kijanikiosk`, standard permissions, no ACL.
2. Owner one of the service accounts (for example `kk-logs`), matching the
   pattern used for `shared/logs/`.
3. Root-owned with a per-reader ACL entry.

**Chosen.** Option 1: directory mode 750, file mode 640, owner `root`, group
`kijanikiosk`.

**Why.** The `kijanikiosk` group already contains exactly the identities that
should read this file: all three service accounts and the operator account. No
one outside that group needs access, and no one inside it needs more than read.
A service-account owner (option 2) would be a poor fit, since no single service
is semantically responsible for provisioning health data; it is a property of
the whole build, which is why root, the entity that runs the build, owns it.
An ACL (option 3) would add a moving part with no benefit here, since the
group already expresses exactly the intended readership. This mirrors the
reasoning already used for `config/` in the Tuesday access model.

---

## Challenge C: logrotate postrotate and PrivateTmp

**Conflict.** After rotating a log file, something needs to tell `kk-logs` to
reopen its file handles. The common pattern is a reload signal, but `kk-logs`
has `PrivateTmp=true`, and more importantly, its unit defines no `ExecReload=`
directive at all, so a plain reload command has nothing to execute.

**Options considered.**
1. `systemctl reload kk-logs.service` directly in the postrotate script.
2. `copytruncate`, which needs no signal but truncates the live file in place,
   risking a lost line if something is mid-write during the truncation.
3. `systemctl kill -s HUP` sent manually, which only helps if the application
   itself is written to handle SIGHUP.
4. `systemctl try-reload-or-restart`.

**Chosen.** Option 4, and I deliberately left `ExecReload=` out of the
`kk-logs` unit.

**Why.** `try-reload-or-restart` checks whether the unit defines a reload
action; since `kk-logs` does not, it falls back to a full restart, which is
safe for a small Node service with no long-running state that a restart would
lose. Option 1 alone would simply fail outright with no fallback. Option 2 was
rejected because losing a log line during rotation is a worse outcome than a
brief restart on a service that already has `Restart=on-failure` and a short
startup time. Option 3 would work but requires the application to implement
SIGHUP handling, which the placeholder code does not, and building that in
just to avoid a restart was not worth the complexity for this service.

---

## Challenge D: The dirty VM and package holds

**Conflict.** On a server used for four days of labs, nginx and Node.js might
already be installed at a version that differs from the pin in this script.
Running the plain install command either does nothing useful if the version
already matches, or silently attempts a downgrade if it does not, and a
pre-existing `apt-mark hold` might or might not stop that depending on when it
was set.

**Options considered.**
1. Check the installed version against the pin before touching the package at
   all; if they differ, downgrade automatically and log that it happened.
2. Same check, but if they differ, refuse to proceed and require a human
   decision instead.

**Chosen.** Option 2, implemented as `ensure_pinned()` in the script.

**Why.** An automatic downgrade on a production-bound payments server is not a
decision a script should make silently. A version mismatch might mean someone
deliberately patched a security issue, and reverting that without a person
looking at it first is worse than simply stopping and asking. In this project
specifically, the versions never actually drifted, so the script's normal path
was `Already at pinned version`, but the guard exists for the day they do.

---

## Two additional conflicts found while testing the firewall live

Not named in the brief, but genuinely discovered through testing, and worth
recording for the same reason as the four above.

**The monitoring-subnet requirement conflicts with operating a single lab
instance.** The brief asks for SSH restricted to a specific monitoring subnet.
Applying that literally, with no exception, would have locked me out of the
only way to reach the server, since my own connection does not originate from
that subnet and there is no bastion host in this lab setup. I resolved it by
keeping the monitoring-subnet rule as specified, and adding one additional,
explicitly commented rule allowing SSH from my own current address, labelled
in the firewall itself as a lab exception. In a real deployment with a bastion
host or VPN, that extra rule would not be needed.

**A script cannot detect the operator's IP address from inside the server it
is configuring.** My first attempt had the script call an external service to
detect "the current IP" and allow SSH from it, intending that to be the
operator's address. Run from inside the provisioning script, that call
naturally returns the server's own public IP, not the address of whoever is
connecting to it; a script cannot know who is about to use it from the outside.
I resolved this by passing the operator's address in explicitly as an
environment variable at invocation time (`OPERATOR_IP=<address>`), set from the
operator's own machine, rather than trying to infer it automatically.
