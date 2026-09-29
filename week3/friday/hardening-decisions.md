# KijaniKiosk Payments Foundation: Security Posture Summary

## What this covers

Before moving the payments service to its own production server, I rebuilt how
that server is set up, using a single automated build process rather than manual
configuration. This explains, in plain terms, what protections are now in place,
why each matters for the business, and what still needs attention before this
becomes permanent.

## The core idea

The principle behind every decision below is least privilege: each part of the
system, whether a program or a connection from the internet, is only allowed to
do the specific job it exists to do. This matters because when something goes
wrong, through a mistake, a bug, or an attacker, the damage is contained to
exactly what that one thing was allowed to touch, rather than spreading across
the whole server. The program handling payments cannot read or change the files
belonging to the program serving the website, and neither can touch system
settings.

## How the server protects customer and payment data

Every program runs under its own restricted identity rather than as an
all-powerful administrator. Each identity can only read the files it owns, and
the folder holding database passwords and payment keys can only be read by the
handful of programs that legitimately need it. The payments program carries the
tightest restrictions of the three, reflecting that it handles financial data.

Network access follows the same logic. The firewall blocks all incoming
connections by default and only opens the specific doors actually needed:
administrative access from an approved source, and the normal web traffic the
site depends on. The internal port the payments program listens on is closed to
the outside world entirely, reachable only from within the server itself, the
way an internal extension cannot be dialed from outside the building.

## How it stays that way

All of this is captured in a single, repeatable build process rather than living
in one engineer's memory or steps someone might skip. Running it on a server,
however messy or previously misconfigured, brings that server to the same known,
secure state every time, and it checks its own work at the end, refusing to
report success unless every protection is actually in place. Software versions
are locked deliberately, so nothing changes silently in the background.

## What changed compared to before

Previously, all three server programs ran with full administrative rights, so a
flaw in any one was a flaw in the whole machine. Configuration files, including
database and payment credentials, were readable by anyone with access to the
server. A deployment script had a dangerous combination of settings that would
have let any user replace it with something else entirely, which a scheduled
task would then have run with full privileges. None of that is true anymore.

| Control | What it does | Risk mitigated |
|---|---|---|
| Dedicated, non-login service accounts | Each program runs under its own restricted identity that cannot sign in | A flaw in one program does not hand an attacker the whole server |
| Directory permissions and access lists | Each program can only read or write the files it owns | A compromised program cannot read another's data, including payment credentials |
| Firewall, default-deny | Blocks all incoming connections except those explicitly approved | Reduces what an attacker can even attempt to reach |
| Payments port blocked from outside | The payments program's internal port is unreachable from outside the server | Attackers cannot connect to it directly, only through the approved front door |
| Process sandboxing | Restricts what each program can see and do on the system, beyond file permissions | Contains the damage a single compromised program could cause |
| Extra restrictions on the payments process | Held to a stricter standard than the others, since it touches financial data | Limits what a compromised payments process could reach further still |
| Software version pinning | Locks installed software to specific, tested versions | Prevents an unplanned update from silently introducing a bug |
| Automated log rotation | Old logs are compressed and cleared on a schedule, with correct permissions kept | Stops disk space filling up unnoticed, which can take the server down |
| Persistent, capped system logging | Keeps an activity record that survives a restart, with a fixed size limit | Preserves evidence for investigating an incident without risking the disk |
| Automated, self-checking build | Rebuilds the server and verifies every protection before declaring success | Removes reliance on memory; catches mistakes before production |
| Post-build health record | Writes a record after each build showing whether each service is running | Gives an early signal if something failed to start, before a customer notices |

## What this does not protect against

This work protects the server and its configuration; it does not review the
payment application's own code for bugs, and a flaw in that code is unaddressed
here. All three programs currently share read access to the same configuration
folder, so a compromise of any one could still expose payment credentials, even
though it could not alter another's files; narrowing that further is a sensible
next step. This does not cover monitoring by a person, backups, or disaster
recovery. Finally, everything here was tested on a single server with
placeholder application code, not the real payments software under real
transaction load, so a final check once the real application is deployed is
strongly recommended before this goes live.
