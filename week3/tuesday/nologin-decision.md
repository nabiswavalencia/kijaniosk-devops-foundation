# nologin, false or locked?

## Decision
All three service accounts (`kk-api`, `kk-payments`, `kk-logs`) use **`/usr/sbin/nologin`** as their shell.

## How the mechanism works
The shell is the last field of an account's line in `/etc/passwd`. When someone logs in over SSH, at the console, or with `su`, the system starts whatever program is named there. That is the only thing the shell field controls.

| Option | What happens at an interactive login |
|---|---|
| `/usr/sbin/nologin` | Prints "This account is currently not available." and exits with an error |
| `/bin/false` | Exits with an error and says nothing |
| Locked password (`passwd -l`, a `!` in `/etc/shadow`) | Blocks **password** login only. It does nothing to the shell, and key-based SSH could still work if the account had a key |

None of these stops `sudo -u kk-api some-command`, because that runs the command directly with no shell. systemd's `User=kk-api` works the same way. That is why a nologin account can still run a service.

## Why nologin
- It behaves the same as `/bin/false` for security, but the message tells an engineer why a login failed. I saw it myself: `sudo -u kk-api -i` printed "This account is currently not available." A silent failure would look like a broken server.
- It is the standard convention for system accounts on Ubuntu, so other engineers recognise it.
- The accounts were created with `--system --no-create-home`, so they have no home directory, no SSH keys and no password. The shell is one layer of several, not the only one.

## Why not lock as well
A lock blocks only password login, which these accounts do not have. Adding `passwd -l` would change nothing today, but it is a cheap extra layer for accounts that might one day get a password by mistake.

## Where I would use each
- `nologin`: service accounts that must never log in, with a clear message for humans.
- `/bin/false`: the same, when I do not want any message shown (for example a mail-only account).
- Locked account: a person who has left, where I want to disable the account without deleting it or its files.
