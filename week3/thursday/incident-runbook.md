# Incident runbook: intermittent 502s on the staging server

**Status of this document.** I took the shortened route on Thursday and did not run the full timed fault-injection drill. This runbook records the method, the commands, and the state I left on the server. It does not describe a measured incident.

## Incident summary
Staging returned intermittent HTTP 502 errors from the payments endpoint under load, while the server "felt healthy". The team had 47 minutes before an SLA breach. The course scenario has three independent faults, one in each layer, so a fix in one layer alone does not resolve it.

## The method: performance, then logs, then network

### Phase 1: performance
| Command | What it tells you |
|---|---|
| `top` | Load average against CPU count, `%wa` (I/O wait), any process in state `D` |
| `vmstat 2 5` | Column `b` (blocked processes), `si`/`so` (swap), `wa` |
| `iostat -xh 2 5` | `%util` and `await` per disk. Near 100 percent and above 50 ms means the disk is saturated |
| `df -h`, `sudo du -sh /opt/kijanikiosk/shared/logs` | Disk space and what is taking it |

**Baseline I recorded on my server:** uptime 32 minutes, load average 0.00, 0.00, 0.00. A healthy machine, so any later change stands out.

### Phase 2: logs
```
journalctl -u kk-payments -p err --since "60 minutes ago" -r -n 50
sudo tail -50 /var/log/nginx/error.log
sudo journalctl -k | grep -iE "ata|scsi|i/o error"
cat /etc/logrotate.d/kijanikiosk
sudo du -sh /opt/kijanikiosk/shared/logs/*
```
What to look for: the first error and its time, whether the disk logs errors, and whether log rotation runs daily or weekly.

### Phase 3: network
```
sudo ss -tlnp | grep 3001
ps -p <PID> -o pid,ppid,user,lstart,cmd
curl -sv --max-time 3 http://localhost:3001/
sudo ufw status numbered
```
ufw checks rules from the top and the first match wins, so a deny placed above an allow blocks the traffic.

## State I left on the server (the lite route)
| Item | What I set up |
|---|---|
| Monitoring | `sysstat`, `htop`, `iotop` installed, `sysstat` collecting |
| Firewall | `deny 3001/tcp` (rules 3 and 6 in `ufw status numbered`), commented "left over from Thursday" |
| Log rotation | `/etc/logrotate.d/kijanikiosk` with `daily` and `rotate 7` |
| Logs | 301 MB in `shared/logs/`: three 100 MB payment logs plus `api.log` |

## Root causes (from the course scenario)
1. **Disk saturation from unrotated logs.** Weeks of payment logs and a retry storm saturate the disk, so writes block and requests time out.
2. **A leftover process on port 3001.** A test server competes with the real payments service, and nginx sometimes proxies to the wrong one, which returns errors that nginx reports as 502.
3. **A stray firewall deny rule on 3001.** It blocks the monitoring health probe, so the load balancer marks the node unhealthy and the remaining nodes take extra load.

## Remediation, in this order
```
kill <PID of the stray process>                          # SIGTERM first; kill -9 only if it does not exit
sudo ufw status numbered                                 # find the deny 3001 rule numbers
sudo ufw delete <number>                                 # repeat for the IPv6 rule
sudo logrotate --force /etc/logrotate.d/kijanikiosk      # emergency rotation
```
**Why this order.** The stray process is the quickest fix and restores correct routing at once. The firewall rule comes second, because the health probe reaching the real service lets the load balancer send traffic again. Log rotation comes last, because compressing large files is I/O heavy and would add disk pressure while the other two faults are still active. If I removed the firewall rule first, monitoring would see the stray process answering with errors and keep the node marked unhealthy. If I rotated first, the I/O spike would land on a system that is already struggling.

## Verification
```
vmstat 2 5                 # wa below 10, b = 0
df -h /
sudo ss -tlnp | grep 3001  # exactly one listener
sudo ufw status numbered   # no deny rule for 3001
journalctl -u kk-payments -p err --since "5 minutes ago"
```

## Prevention
- Put the logrotate configuration and a `daily` schedule into the provisioning script, and verify it with `logrotate --debug` on every run.
- Have the script reset the firewall to a known baseline and never add a blanket deny on a service port.
- Alert on disk I/O wait and on more than one listener on a service port.
- Keep a written record of temporary test processes so they are not left running.
