# Access model

## Principle
Each service account can reach only its own code and the shared data it needs. Secrets are readable through one group, and only root can change them. Nothing is readable or writable by "everyone".

## The design

| Path | Owner:Group | Mode | Extra ACL | Why |
|---|---|---|---|---|
| `/opt/kijanikiosk` | root:root | 755 | none | Nobody can add or rename entries at the top level. Services need execute here to walk down to their own folders. It was 777 after the lab setup. |
| `/opt/kijanikiosk/shared` | root:root | 755 | none | Only holds `logs/`. Same reasoning as above. |
| `api/` | kk-api:kk-api | 750 | amina r-x | Only the API account can run or change its code. Amina can read it for operations. |
| `payments/` | kk-payments:kk-payments | 750 | amina r-x | Payment code is invisible to the API and log accounts. |
| `logs/` | kk-logs:kk-logs | 750 | none | The log aggregator's own code. |
| `config/` | root:kijanikiosk | 750 (files 640) | amina r-x on the directory, r-- on files | Services read secrets through the group. Root owns the files, so a compromised service cannot rewrite its own settings. |
| `shared/logs/` | kk-logs:kk-logs | 2770 (SGID) | kk-api rwx, kk-payments r-x, amina r-x, plus default ACLs, mask rwx | Three identities need three different levels, which one owner and one group cannot express. |
| `scripts/` | root:root | 750 | none | `deploy.sh` is 750 with no SUID bit and no world-write. |
| `app/` | root:root | 750 | none | Extra folder from Monday's setup. It was world-writable and empty, so I tightened it. |

## Decisions worth explaining

**Why amina needs execute on directories.** On a directory, execute means "may enter it". Read-only on `config/` would let her list names but not open any file inside, so she gets `r-x` on the directory and `r--` on the files.

**Why ACLs on `shared/logs/` and not a shared group.** A group gives every member the same rights, so `kk-payments` would be able to write logs. ACLs let each identity have its own level, and `getfacl` shows the whole picture in one place. The cost is more moving parts: the mask, default ACLs, and a `+` in `ls` that is easy to overlook.

**Why the SGID bit.** With mode 2770, new files inherit the directory's group. My test confirmed it: `api.log`, created by `kk-api`, came out as group `kk-logs`.

**The mask.** The ACL mask caps the effective rights of every named entry. The new `api.log` shows it: `kk-api` has `rwx` but an effective `rw-`, and `kk-payments` and `amina` have `r-x` but an effective `r--`, because the file was created with mode 666. A `chmod` on a path with ACLs also rewrites the mask, so I set modes first, ACLs second, and stated `m::rwx` explicitly.

## What I tested
- `kk-api` can read `config/db.env` (through the group). PASS.
- `kk-api` cannot read `payments/processor.py`, and `kk-payments` cannot read `api/server.js`. Both denied.
- `kk-payments` cannot create a file in `shared/logs/`. Denied.
- A SUID scan of `/opt/kijanikiosk` finds nothing.

## Known trade-off
All three services share the `kijanikiosk` group, so each can read every file in `config/`, including the payments key. The next improvement is a per-file ACL so that only `kk-payments` can read `payments-api.env`.

## A mistake worth recording
Once `config/` was 750 root, my own login could no longer list it. Shell wildcards like `config/*` stayed literal, so my `chmod` and `setfacl` on those files failed silently the first time. `sudo find ... -exec` fixed it, because root does the searching.
