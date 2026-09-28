# Tuesday: file permissions, users and access control

## What this day was about
The audit found that all three KijaniKiosk services ran as root, the configuration files (database password, payment keys) were readable by everyone, a deploy script had the SUID bit and was world-writable, and the on-call engineer had unrestricted sudo. The task was to rebuild the access model on the principle of least privilege.

## What I did
| Task | Result |
|---|---|
| 1. Service accounts | Created `kk-api`, `kk-payments` and `kk-logs` as system accounts with no login shell, no home directory and their own group. A shared group `kijanikiosk` holds the three accounts and `amina`. |
| 2. Ownership, modes and ACLs | Each service folder is owned by its own account (mode 750). `config/` is owned by root with group `kijanikiosk` (files 640). `shared/logs/` has mode 2770 (SGID) with ACLs: `kk-api` read and write, `kk-payments` and `amina` read only. |
| 3. SUID fix | `deploy.sh` went from `-rwsrwxrwx` (4777) to `-rwxr-x---` (750, root:root). A scan of `/opt/kijanikiosk` finds no SUID files. |
| 4. Sudoers | `amina` can only check status, restart and read logs for the three services, and edit the nginx config with `sudoedit`. Shells, editors and Python are denied. |
| 5. Audit | The audit report shows `kk-api` and `kk-payments` cannot read each other's code, and `kk-api` can read the config. |

## Files in this folder
| File | What it is |
|---|---|
| `audit-report.txt` | Output of the final audit. Shows the PASS lines at the end. |
| `sudoers-policy.txt` | The final sudoers file for `amina`. |
| `access-model.md` | The design table, with the reason for every mode, group and ACL. |
| `suid-analysis.md` | Why SUID plus world-write is dangerous even when the kernel ignores SUID on scripts. |
| `nologin-decision.md` | Why service accounts use `nologin`. |
| `reflection.md` | Answers to the four reflection questions. |

## Things to know
- Once `config/` became 750, my own login could no longer list it. Commands that touch it need `sudo`, and shell wildcards like `config/*` must be replaced by `sudo find`.
- The lab's last audit line would print the database password into a committed file, so I used `test -r` to check readability instead.
- Monday's setup left an extra empty directory, `/opt/kijanikiosk/app`. I set it to 750 root:root.

## Main commands used
`useradd`, `usermod`, `chown`, `chmod`, `setfacl`, `getfacl`, `find -perm /6000`, `visudo`, `sudo -l -U amina`
