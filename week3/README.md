# Week 3: Linux administration for KijaniKiosk

One server, one story. Each day fixes a different layer of the same machine, and each day builds on the one before.

| Day | Question | Folder |
|---|---|---|
| Monday | What is going on inside this server? | [`monday/`](monday/) |
| Tuesday | Who is allowed to do what on it? | [`tuesday/`](tuesday/) |
| Wednesday | How do we build a correct server every time? | [`wednesday/`](wednesday/) |
| Thursday | How do we find faults across layers under pressure? | [`thursday/`](thursday/) |
| Friday | Can the whole thing be built repeatably on a messy server? | [`friday/`](friday/) |

## How the days connect
- **Monday's** commands (`ps`, `find`, `journalctl`, `ss`) are used again on Thursday and Friday.
- **Tuesday's** access model (accounts, groups, modes, ACLs) becomes code in Wednesday's script.
- **Wednesday's** script is extended on Friday with hardened units for all three services, journal and log rotation setup, and a health check.
- **Thursday** leaves the server in a realistic hand-edited state, which Friday's script has to handle.

## The server
An AWS EC2 `t3.small` running Ubuntu 22.04 LTS, used for all five days.

## Reading order
Start with a day's `README.md`, then the main file it points to.
