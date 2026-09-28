# Monday: production server triage

## What this day was about
The KijaniKiosk API server was slow: response times had risen from about 120 ms to about 480 ms. The task was to find out what was going on inside the server using only the Linux command line, and to write it up so anyone on the team can follow it.

## What I did
1. Ran the lab setup script on an AWS EC2 instance (Ubuntu 22.04). It creates a simulated incident: a memory-hungry process, a large unrotated log file and an application log full of database errors.
2. Recorded a healthy baseline (`uptime`, `free -h`) before looking at anything else.
3. Investigated four areas, one at a time:
   - processes and memory
   - filesystem and disk
   - logs
   - network and services
4. Wrote everything up in `triage-report.md`.

## What I found (short version)
| Area | Finding |
|---|---|
| Processes and memory | One process held about 510 MB (26.6 percent of RAM). CPU was idle, no zombie processes, no swap. |
| Disk | Only 26 percent used, but a 270 MB log file has no rotation policy. |
| Logs | The connection pool went from 85 percent (03:45) to 94 percent (04:01) and was exhausted at 04:07:55. Queries then timed out, and at 06:22 the database refused connections. |
| Network | Only nginx (port 80) and SSH (port 22) are listening. The database host name in the log does not resolve. |

## Most likely cause
The database connection pool ran out. The memory use and the slow responses look like symptoms of requests piling up behind the database, not separate problems.

## Files in this folder
| File | What it is |
|---|---|
| `triage-report.md` | The full report. Start with the Summary at the top. |
| `reflection.md` | My answers to the five reflection questions. |

## Things to know
- This is a lab simulation. The application log is a fixed file dated 2024, while the server clock says 2026, so I used the log's own timestamps.
- The memory process from the setup script expires after one hour, so I restarted it by hand to investigate it live.
- The server has no `/var/log/syslog` or `auth.log`, so I used `journalctl` instead.

## Main commands used
`ps aux --sort=-%mem`, `free -h`, `df -h`, `du -sh`, `find`, `grep`, `awk`, `journalctl`, `ss -tlnp`, `curl`
