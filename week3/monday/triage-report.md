# KijaniKiosk API Server - Triage Report

**Date:** 2026-09-28
**Investigated by:** Valencia Neema
**Server:** ip-172-31-9-45 (AWS EC2 t3.small, eu-north-1, Ubuntu 22.04.5 LTS, 1.9 GiB RAM, no swap, 7.6 GB disk)
**Incident start (approximate):** 2024-01-15 04:07:55, the first ERROR in `app.log`. The first warning sign is a WARN at 03:45:10.

## Summary
The application log points to the **database connection** as the most likely root cause: the connection pool climbed to 85 percent, then 94 percent, was exhausted at 04:07:55, queries began timing out after 30 seconds, and at 06:22 the database refused connections outright. On the server itself, the only abnormal item is one process holding about 510 MB of memory. Disk, kernel and network checks are clean, so I treat the memory and the slow responses as symptoms of requests piling up behind the database, not as separate causes.

**Scope and limits.** This is a lab simulation. The application log is a fixed file dated 2024 while the VM clock reads 2026, the instance runs no Node application and no database, and the memory-holding process is a stand-in started by the lab's setup script. I could therefore not measure P95 latency directly, and the conclusions below rest on the log and on what the live checks rule out.

## Process and Resource State

**Healthy baseline (13:03, before the memory process was running):** uptime 6 h 01 min, load average 0.06, 0.01, 0.00, 160 Mi used, 720 Mi free, 1.5 Gi available, swap 0 B.

**Top processes by memory** (`ps aux --sort=-%mem`, with the memory process running):

| Rank | PID | User | Process | RSS | % of RAM |
|---|---|---|---|---|---|
| 1 | 3279 | ubuntu | `python3` (the memory holder) | 521,856 KB (about 510 MB) | 26.6 |
| 2 | 351 | root | `snapd` | 39,176 KB | 2.0 |
| 3 | 381 | root | `unattended-upgrade-shutdown` | 21,792 KB | 1.1 |

**Top processes by CPU:** the memory holder at 1.0 percent, then nothing above 0.0 percent. The 1.0 percent is `ps` averaging its short start-up allocation over its lifetime. Once the memory is allocated it is idle (a second capture at 13:27 of a fresh copy, PID 4772, showed 12.3 percent for the same reason, when it was only seconds old). This is a memory problem, not a CPU problem.

**System memory with the process running:**

| Measure | Before | With process | After I stopped it |
|---|---|---|---|
| Used | 160 Mi | 679 Mi | 162 Mi |
| Available | 1.5 Gi | 1.0 Gi (`MemAvailable` 1,091,304 kB of 1,956,360 kB, about 56 percent) | 1.5 Gi |
| Swap | 0 B | 0 B | 0 B |

One process accounts for the whole difference, roughly 520 MB. Memory is under some pressure but not exhausted. With no swap, running out would trigger the kernel's out-of-memory killer with nothing behind it.

**Bad states:** no zombie (`Z`) processes and no processes in uninterruptible sleep (`D`).

**Open file descriptors.** With `sudo`, the highest counts are `systemd` (PID 1) with 73, `systemd-journal` with 30, and a user `systemd` with 28. The memory holder is not in the top 10. Run without `sudo`, the course's command can only read my own processes, so it reported `systemd --user` (PID 3074, 28 descriptors) as the top entry. The two results differ because of permissions, not because anything changed.

**About the memory process.** The setup script started the original (PID 3028, run as root) at about 07:29. It sleeps for one hour and had already expired when I began at 13:03, so I restarted the same code by hand at 13:06 (as user `ubuntu`) to investigate it live. I stopped it at about 13:26, and again after a second capture.

## Filesystem and Disk

| Item | Finding |
|---|---|
| Root filesystem | 7.6 GB, 1.9 GB used, 5.7 GB free, 26 percent. No partition is near the 80 percent line. |
| Largest log directory | `/var/log/kijanikiosk` at 271 MB. The next largest is `/var/log/journal` at 17 MB, then `dpkg.log` and `cloud-init.log` at 128 KB each. |
| Large file (over 50 MB) | `/var/log/kijanikiosk/access.log.1`, 283,299,483 bytes (about 270 MB), owner root, last modified 07:29, which is the minute the setup ran. Nothing is writing to it. |
| Contents | The first bytes are random base64 text, not request lines such as `GET /api/...`, so it does not contain real access data. |
| Rotation | Only `access.log.1` exists, with no current `access.log`, and `/etc/logrotate.d` has no entry for `kijanikiosk` (it lists alternatives, apport, apt, chrony, cloud-init, dpkg, nginx, ubuntu-pro-client, unattended-upgrades). |
| Recent files | Nothing modified in `/tmp` in the last 60 minutes. The newest entries in `/var/log` (13:02) are `lastlog`, `wtmp`, `apt` and `dpkg.log`, from my own login and installs. |

Disk space is not a factor in the slowness. The finding is a log hygiene gap: a 270 MB file that no policy rotates or removes.

## Log Analysis
This image has no `/var/log/syslog` or `/var/log/auth.log`, so I used `journalctl` for the kernel and SSH checks.

**Application log timeline** (timestamps as written in `app.log`, 2024-01-15):

| Time | Level | Event |
|---|---|---|
| 03:45:10 | WARN | Database connection pool at 85 percent |
| 04:01:33 | WARN | Database connection pool at 94 percent |
| 04:07:55 | ERROR | Connection pool exhausted, queuing requests |
| 04:08:01 | ERROR | Query timeout after 30,000 ms (`orders`) |
| 04:08:01 | ERROR | Query timeout after 30,000 ms (`products`) |
| 04:09:12 | WARN | Memory usage at 87 percent, consider restarting workers |
| 06:22:18 | ERROR | `ECONNREFUSED database:5432`, retrying in 5 s |
| 06:22:23 | ERROR | `ECONNREFUSED database:5432`, retrying in 5 s |
| 06:22:28 | ERROR | Retry limit reached, database connection failed |

- **Frequency:** 6 ERROR and 3 WARN. All six errors concern the database.
- **Pattern:** two bursts, 04:07:55 to 04:08:01 and 06:22:18 to 06:22:28, about 2 hours 14 minutes apart. The pool crossed 85 percent 22 minutes before it was exhausted, and 94 percent about 6 minutes before, so there was time to act.
- **Kernel journal:** no out-of-memory kills and no disk I/O errors in the last 6 hours.
- **SSH:** one accepted public-key login at 13:02:12 for user `ubuntu` from 196.96.78.118, which is my own connection. No failed or invalid attempts, so no unexpected logins.
- **Time caveat:** the log is dated 2024-01-15 and the VM clock reads 2026-09-28, so a "last 6 hours" query does not overlap the log. I used the log's own timestamps.

## Network and Service State

| Item | Finding |
|---|---|
| Listening ports | `nginx` on 80 (IPv4 and IPv6), `sshd` on 22 (IPv4 and IPv6), `systemd-resolve` on 127.0.0.53:53. Nothing on 3000, 443, 5432 or 8080. |
| Connections | `ss -s`: 6 TCP sockets. By state: 5 LISTEN and 1 ESTAB (my SSH session), 0 timewait, 0 orphaned. |
| Backlog | Every `Recv-Q` is 0, so no connections are queuing or being dropped. |
| HTTP | `/` returns 200 in 0.00051 s. `/api/health` returns 404 in 0.00042 s. |
| Database name | `getent hosts database` exits with status 2: the host name in the log does not resolve on this machine. |

Nginx answers instantly and the network shows no pressure, but nothing sits behind it to serve `/api/health`, and the database is not on this host.

## Assessment

**Hypothesis.** The latency increase began with **database connection pool exhaustion**. The pool climbed from 85 to 94 percent over 16 minutes and was exhausted at 04:07:55. New requests queued, queries timed out after 30 seconds, which would appear to users as much higher response times, and memory rose as queued requests accumulated (87 percent at 04:09:12). At 06:22 the database itself refused connections and the retry limit was reached. The memory-holding process is a symptom of this pile-up, not its origin.

**Correlation across the areas.**
- The log's only resource symptom (memory at 87 percent) appears after the pool was already exhausted, which supports memory being a consequence and not the trigger.
- The log's `ECONNREFUSED database:5432` matches the live findings: the `database` name does not resolve and nothing listens on 5432 here.
- Disk, kernel and network checks are clean and match the log: no I/O errors, no OOM kills, no queued connections.
- The log's 87 percent figure cannot be compared with the live 56 percent available, since the live host never ran the application.

**Signal and noise.**
- *Signal:* the pool percentages climbing, the 30-second timeouts, `ECONNREFUSED`, the missing rotation policy, and the 270 MB unrotated file.
- *Noise:* memory and descriptor use by system services (`snapd`, `unattended-upgrades`, `amazon-ssm-agent`, `systemd`), the DNS resolver on 127.0.0.53, the single SSH session (mine), and the random base64 in `access.log.1`, which is not real log data.

**Confidence and what would change it.** Medium. The evidence fits and nothing contradicts it, but it is inferred from one log file. It would be **confirmed** if the database server's own logs show connection limits reached or a restart between 03:45 and 06:22, and if the pool was full of long-running or idle-in-transaction sessions. It would be **refuted** if the database was healthy and the pool setting is simply too small for normal traffic (then the cause is capacity, not a fault), or if the app's own logs show requests stalling before they reached the database.

## Recommended Next Steps
1. **Confirm why the pool filled and why the database refused connections at 06:22.** From the app server, check reachability with `getent hosts database` and `timeout 3 bash -c 'echo >/dev/tcp/database/5432'`. Read the database's logs for 03:45 to 06:22, and if it is PostgreSQL, inspect active sessions (`pg_stat_activity`) for long-running queries. Then review the pool size and query timeout settings.
2. **Add log rotation for the application logs and identify the old file.** Create `/etc/logrotate.d/kijanikiosk` for `/var/log/kijanikiosk/*.log` (daily, keep 14, compressed), and put it in the provisioning script. Confirm what `access.log.1` is (`file`, owner, who wrote it) before deleting it.
3. **Alert on the early warning.** The pool sat above 80 percent for about 22 minutes before requests failed. An alert at 80 percent pool use, and one on available memory below 20 percent, would give the team time to act before users are affected.

## Appendix: commands run and evidence

| Area | Commands | Evidence |
|---|---|---|
| Baseline | `uptime`, `free -h`, `ps aux \| grep '[p]ython3'`, `ls -lh /var/log/kijanikiosk/` | Screenshot at 13:03 |
| 1. Process and resources | `ps aux --sort=-%mem \| head`, `ps aux --sort=-%cpu \| head`, `free -h`, `/proc/meminfo`, zombie and D-state `awk` checks, file descriptor counts, `find /proc ... -name fd` (Osei's benchmark) | Screenshots at 13:06 and 13:27 |
| 2. Filesystem and disk | `df -h`, `du -sh /var/log/*`, `find /var/log -type f -size +50M`, `find /tmp -mmin -60`, `ls -lhtr /var/log`, `head -c 200`, `ls /etc/logrotate.d` | Screenshot |
| 3. Logs | `grep` and `awk` on `app.log`, `journalctl -k`, `journalctl -u ssh` | Screenshot |
| 4. Network and services | `ss -tlnp`, `ss -s`, `ss -tan`, `curl` timing, `getent hosts database` | Screenshots |
