# SUID analysis of deploy.sh

## Starting state
`deploy.sh` was `-rwsrwxrwx` (mode 4777, owner root): the SUID bit set, and writable by anyone. A root-owned cron job runs it. After the fix it is `-rwxr-x---` (750, root:root), and a scan for SUID or SGID files under `/opt/kijanikiosk` finds nothing.

## 1. Why does the kernel ignore SUID on scripts?
A script is not run directly. The kernel starts the interpreter named on the first line (`#!/bin/bash`) and passes it the script's path, and then the interpreter opens the script itself. Between the kernel's permission check and the interpreter opening the file, an attacker can swap the file (or a symlink to it) for something else, so the interpreter would run attacker-controlled code with the owner's privileges. Interpreters also read environment variables and options that an attacker can influence. Linux does not honour the SUID bit on files that start with `#!` because this cannot be made safe.

## 2. If SUID has no effect, why is SUID plus world-write still critical?
The SUID bit is not what makes this dangerous. The danger is that **anyone can change what the script does, and root runs it**. A root-owned cron job executes `deploy.sh` as root, so a local user or a compromised service account only needs to append one line to the file and wait for the next run. No SUID is required. The SUID bit is a second warning sign: it shows someone believed the file needed extra privilege, and it becomes effective the moment the script is replaced by a compiled program.

## 3. What would make it exploitable in practice?
- a root cron job, deployment pipeline or `sudo` rule that runs the file
- any account that can write to the file. With mode 777, every account on the server qualifies, including `kk-api` and `kk-payments`, so an attacker who breaks into one service gets root at the next scheduled run
- a directory that others can write to, which allows deleting or replacing the file
- the file being a real binary instead of a script, in which case SUID would give an immediate privilege jump

## The fix
`chown root:root`, `chmod 0750`, on a `scripts/` directory that is also 750 root:root. Only root can now change or run it, and no other account can even list the directory.
