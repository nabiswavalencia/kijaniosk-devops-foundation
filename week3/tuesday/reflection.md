# Tuesday reflection

## 1. The SUID paradox
To my colleague: you are right that the SUID bit does nothing on a shell script, but the file is still a critical finding for a different reason. Linux does not honour SUID on scripts because the interpreter reopens the script after the kernel's check, which leaves a window where the file can be swapped for something else. That decision is why the bit is harmless here. What is not harmless is that `deploy.sh` was writable by everyone and is run by a root cron job. Any user, including a compromised `kk-api` account, could add a line to it and root would run that line at the next run. No SUID is needed for that. The bit adds a second problem: if the script is ever replaced by a compiled binary, the privilege is instantly real. Fixing only the "weird" bit would have left the actual hole open.

## 2. Sudoers policy completeness
The rules `systemctl restart *` and `systemctl status *` mean "restart any unit" and "status of any unit, with any extra arguments", because `*` matches anything, including spaces. That gives amina much more than the three services. Two abuses my restricted policy prevents: (1) `systemctl restart ssh` or restarting the logging or firewall units, which can lock everyone out or blind the audit trail; (2) `systemctl status` on a terminal opens a pager (`less`), and typing `!sh` inside it starts a root shell. My policy lists each command with its exact arguments and adds `--no-pager`. In my test, `sudo systemctl status ssh` was refused, and so were `bash`, `vim` and `python3`.

## 3. nologin vs locked account
**Part A.** `nologin` controls what happens when someone tries to start an interactive session: the shell field points to a program that refuses. A locked account (`passwd -l`) blocks password authentication only. An account with a `nologin` shell that is *not* locked can still be used by root or a service manager to run commands; a locked account with a normal shell can still accept an SSH key. They differ for an account that has a usable shell and a key. I would use `nologin` for service accounts, and a lock to disable a person's account without deleting it.

**Part B.** I did not reproduce an outage from `passwd -l` on my VM. Reasoning from how sudo works: `sudo -u kk-api command` does not authenticate as `kk-api`, it authenticates the caller, so locking the password should not stop a command run that way. A failure would appear if the pipeline logged in as the account (`su`, `sudo -i` or SSH), and then the error would be "This account is currently not available", which a junior engineer might blame on a missing shell, a wrong PATH or a missing sudo rule instead of the lock. To check on the VM: `sudo passwd -l kk-api; sudo -u kk-api id; sudo passwd -u kk-api`. Result: (add after running it).

## 4. ACLs vs group redesign
| Dimension | ACLs (what I did) | One shared group |
|---|---|---|
| Security isolation | Each identity has its own level: `kk-api` writes, `kk-payments` and `amina` only read | Everyone in the group has the same rights, so `kk-payments` could write logs |
| Auditability | `getfacl` shows exactly who has what on that path | You need group membership plus the mode, and membership changes are easy to miss |
| Operational complexity | Higher: the mask, default ACLs, a `+` that is easy to overlook, and some tools drop ACLs when copying | Lower: standard tools, one concept |

I would use ACLs when different identities need different levels on the same folder, as here. I would use a group when all members need identical access, because it is simpler and survives backup and copy tools better.
