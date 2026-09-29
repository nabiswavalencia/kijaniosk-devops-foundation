# Access Model (final): KijaniKiosk

This is Tuesday's access model, carried through Wednesday's provisioning script
and extended on Friday with the new `health/` directory and the rules that keep
the model intact when logs are rotated. Every row below is enforced by
`kijanikiosk-provision.sh` and reverified on every run, dirty or clean.

## Principle

Each service account can reach only its own code and the shared data it
actually needs. Secrets are readable through one group, and nothing except
root can change them.

## Directories

| Path | Owner:Group | Mode | Extra ACL | Why |
|---|---|---|---|---|
| `/opt/kijanikiosk` | root:root | 755 | none | Nobody can add or rename entries at the top. Services need `x` to walk down to their own folders. |
| `api/` | kk-api:kk-api | 750 | none | Only the API account can run or read its code. |
| `payments/` | kk-payments:kk-payments | 750 | none | Payment code is invisible to the API and log accounts. |
| `logs/` | kk-logs:kk-logs | 750 | none | The aggregator's own code. |
| `config/` | root:kijanikiosk | 750 (files 640) | none beyond the group | All three services read secrets through the group. Root owns the files, so a compromised service cannot rewrite its own configuration. |
| `shared/logs/` | kk-logs:kk-logs | 2770 (SGID) | kk-api rwx, kk-payments r-x, plus default ACLs and an explicit mask of rwx | Three identities need three different levels of access, which one owner and one group cannot express. |
| `scripts/` | root:root | 750 | none | `deploy.sh` is 750 with no SUID bit and no world-write. |
| `health/` | root:kijanikiosk | 750 (file 640) | none | New in Friday's script. See below. |

## Decisions worth explaining

**Why ACLs on `shared/logs/` and not a shared group.** A group would give
`kk-api`, `kk-payments` and any other member identical rights, which would let
`kk-payments` write logs it should only read. ACLs let each identity have
exactly its own level, and `getfacl` shows the whole picture in one command.
The cost is more moving parts: the mask, default ACLs, and a `+` in `ls -l`
that is easy to overlook if you don't know to look for it.

**Why the mask is set explicitly.** A `chmod` run on a path that already has
ACLs rewrites the ACL mask, and an entry can still display `rwx` while its
effective rights have silently dropped. The provisioning script applies file
modes first and ACLs second, and states the mask (`m::rwx`) in the same
command that sets the named entries, so this cannot happen by accident.

**The health directory (new this week).** The provisioning script runs as
root, and it is the only writer of `last-provision.json`. Readers are the
`kijanikiosk` group, which already contains all three service accounts and
the operator account. `root:kijanikiosk` with mode 750 on the directory and
640 on the file covers exactly that readership without needing an ACL: the
group membership already expresses who should read it, and adding an ACL on
top would only add complexity with no one left outside the group who needs
access. This reasoning, and the two alternatives considered, is written up in
full in `integration-notes.md` (Challenge B).

## Logrotate interaction

Rotating a log file creates a new, empty file, and that file's permissions
have to fit the model above or the access model quietly breaks the moment
rotation runs.

- `create 660 kk-logs kk-logs` in the logrotate config: mode 660 gives the new
  file's ACL mask `rw-`, which keeps `kk-api`'s write access. Mode 640 would
  set the mask to `r--` and silently remove it.
- The owning group is `kk-logs`, not `kijanikiosk`. Every service account is a
  member of `kijanikiosk`, so using that group with mode 660 would let
  `kk-payments` write to the rotated file. With `kk-logs` as the owning group,
  only the ACL entries decide who else can write, and `kk-payments` stays
  read-only (its ACL entry is `r-x`, capped by the mask to `r--`).
- `su kk-logs kk-logs` in the config: logrotate refuses to rotate inside a
  directory that a non-root group can write to unless it is told explicitly
  which user to act as.
- The directory's default ACLs, not the `create` directive, are what new
  files actually inherit; `create` only sets ownership and mode.

## Verified

The provisioning script's own verification phase checks every row in this
table on each run, and the full battery also runs a real forced rotation and
confirms `kk-api` can still write and `kk-payments` still cannot, after
rotation, not just before. See `post-remediation-verification.txt` for the
standalone version of that same test.

## Known trade-off

All three services share the `kijanikiosk` group, so each can read every file
in `config/`, including the payments API key. Splitting the secrets so that
only `kk-payments` can read `payments-api.env` (a per-file ACL, the same
pattern already used on `shared/logs/`) is the next improvement I would make;
it is noted as a gap in `hardening-decisions.md` as well.

## Evidence

`getfacl` output for `shared/logs`, `config`, `api` and `payments` is attached
as screenshots alongside this document.
