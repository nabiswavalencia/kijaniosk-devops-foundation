# Thursday: monitoring, logs and network validation

## What this day was about
A staging server was returning intermittent 502 errors, and the team had 47 minutes. The method is to work through three layers in order: performance, then logs, then network.

## What I did
I took the shortened route and did **not** run the full timed fault-injection drill. Instead I set up the monitoring tools and left the same traces the drill would leave, which the Friday project starts from:
| Item | State |
|---|---|
| Monitoring tools | `sysstat`, `htop` and `iotop` installed, `sysstat` collecting data |
| Firewall | A leftover `deny 3001/tcp` rule (a rule that blocks a health-check port) |
| Log rotation | `/etc/logrotate.d/kijanikiosk` set to rotate daily and keep 7 |
| Logs | About 300 MB of unrotated payment logs in `shared/logs/` |

## The method in three steps
1. **Performance:** `top`, `vmstat`, `iostat` show whether the machine is short of CPU, memory or disk.
2. **Logs:** `journalctl -u <service> -p err --since ...` shows what the service itself reports.
3. **Network:** `ss -tlnp` and `ufw status numbered` show which ports are open and which rules block traffic. ufw checks rules in order, so a deny above an allow wins.

## Files in this folder
| File | What it is |
|---|---|
| `incident-runbook.md` | The runbook for the three-layer diagnosis, written for whoever handles the next incident. |

## Things to know
- Because the timed drill was skipped, nothing here is a measured incident. It records the method and the state left for Friday.
- Shell wildcards do not work on `shared/logs/` for my normal user, because it is not readable by others. Use `sudo find ... -exec` instead.
