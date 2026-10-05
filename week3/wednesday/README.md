# Wednesday: package management, systemd and provisioning

## What this day was about
A staging server had to be built the same way every time. The task was to write a provisioning script that puts a server into a known, secure state, and can be run again safely (it is idempotent).

## What the script does
`kijanikiosk-provision.sh` runs six phases:
| Phase | What it does |
|---|---|
| 1. Packages | Installs nginx and Node.js at pinned versions and holds them so they cannot change by accident. |
| 2. Accounts | Creates the three service accounts and the `kijanikiosk` group if they do not exist. |
| 3. Directories | Applies Tuesday's owners, modes and ACLs. |
| 4. systemd | Writes a hardened `kk-api.service` and enables it (it is not started, because there is no app code yet). |
| 5. Firewall | Resets ufw, denies incoming traffic and allows only SSH (22) and HTTP (80). SSH is allowed before ufw is switched on. |
| 6. Verification | Checks everything above. Any failed check stops the script with an error. |

## How to run it
```bash
sudo bash kijanikiosk-provision.sh
```
Before the first run, the two version lines near the top must hold real versions from `apt-cache policy` (the script refuses to run while they say `FILL_ME`).

## Results
| Test | Result |
|---|---|
| Run 1 | Exit 0, every check passed (`provision-run1.log`) |
| Run 2 (immediately after) | Exit 0, "Already at pinned version" for both packages (`provision-run2.log`) |
| Reboot test | The unit stayed enabled, the package holds stayed, ufw was still active (`reboot-verification.txt`) |
| Hardening score | 5.8 with the five basic directives (`security-analysis-before.txt`), 3.0 after adding 14 more (`security-analysis.txt`) |

## Files in this folder
| File | What it is |
|---|---|
| `kijanikiosk-provision.sh` | The final script |
| `provision-run1.log`, `provision-run2.log` | The two required runs |
| `provision-run3.log` | A third run, made after adding the extra hardening directives |
| `reboot-verification.txt` | State after a reboot |
| `security-analysis-before.txt`, `security-analysis.txt` | `systemd-analyze security` output before and after |
| `security-analysis.md` | Which directives I added and why |
| `reflection.md` | Answers to the four reflection questions |

## Things to know
- I ran the script on the same server used for Monday and Tuesday, not on a fresh one. That made it a better test, because the accounts and nginx already existed.
- After a reboot the `kk-api` unit shows as "inactive (dead)" with exit status 0. That is expected: Tuesday's placeholder script prints one line and exits.
- The nginx version in the course notes does not exist on Ubuntu 22.04, so the script uses the version that is really installed.
