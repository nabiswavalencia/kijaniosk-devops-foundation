# Friday reflection

## 1. When did I find two requirements in conflict?

The clearest one came while building the firewall. Requirement 4 asks for SSH
restricted to a specific monitoring subnet (`10.0.1.0/24`), and Requirement 1
requires the script to run successfully, unattended, on the real dirty VM. The
moment I actually enabled that firewall, I realised those two requirements
directly conflict on a single-instance lab setup with no bastion host: my own
connection does not originate from that subnet, so a literal reading of
Requirement 4 would have satisfied the letter of the brief while making
Requirement 1 impossible to demonstrate, because I would have locked myself
out before the script could even finish.

I resolved it by keeping the monitoring-subnet rule exactly as specified, and
adding one additional rule, explicitly commented in the firewall itself as a
lab exception, allowing SSH from my own current address. That is documented in
`integration-notes.md`. What I learned is that a security requirement written
for a target production topology (with a bastion host, a VPN, or a jump box)
does not always translate cleanly onto a single test instance, and the honest
move is to say so in the artifact itself rather than either breaking the rule
silently or locking myself out to satisfy it literally.

A second, smaller conflict came from the same area: my first attempt tried to
have the provisioning script detect "my IP" automatically from inside itself,
to build the operator-exception rule. Running server-side, that call can only
ever return the server's own public address, never the address of whoever is
about to connect to it. I had built something that looked correct and ran
without error, and only noticed the problem because I checked what it
actually returned before trusting it. The fix was to pass the operator's
address in explicitly, from outside the server, rather than have the script
guess at something it structurally cannot know.

## 2. Rewriting a sentence from the Nia document for Tendo

From `hardening-decisions.md`, written for Nia: *"Every program runs under its
own restricted identity rather than as an all-powerful administrator."*

For Tendo, I would write: *"Each of the three services runs as its own
non-login system account (`kk-api`, `kk-payments`, `kk-logs`), each in its own
primary group and all three in a shared `kijanikiosk` group for config read
access, rather than as root, with `NoNewPrivileges=true` and an emptied
`CapabilityBoundingSet=` on each systemd unit preventing any privilege
escalation even if application code were compromised."*

What is gained: the technical version is checkable. Tendo can look at that
sentence and go verify `id kk-api`, or read the unit file, and confirm it is
true. It also communicates the actual mechanism, not just the outcome, which
matters if something later needs debugging or extending. What is lost: the
Nia version is readable in one pass by someone with no Linux background, and
carries the business-relevant idea (blast radius is limited) without
requiring the reader to already know what a capability bounding set is. The
technical version would fail Nia's own requirement that the document contain
zero command names or identifiers outside a table; it is correct but
unusable for its actual audience.

## 3. The most fragile part of the script

The single most fragile part is `ensure_pinned()`, the function that decides
what to do when an installed package version does not match the pin. Right
now it has exactly two behaviours: match, or die with an error asking for
manual intervention. That is the right choice for safety, but it means the
script cannot run unattended on any server where a version has drifted, which
somewhat undercuts the goal of full automation. It also silently assumes the
package is available at the pinned version from whatever repository is
configured; if that exact version has since been superseded or removed
upstream (which happens routinely with `nodesource` package feeds), the
install step fails with a plain apt error that gives no hint that the pin
itself is now unobtainable, not just mismatched.

To make this robust in an environment that differs from my test VM, I would
need to know: how far in the future this script might run relative to when
the version was pinned (older pins go stale as upstream repositories rotate
out old builds), whether the target servers have any other automated process
that might independently run `apt upgrade` and interact badly with the hold,
and whether there is an actual change-management process this script should
plug into rather than just halting and printing a message that a human then
has to notice. On this project the versions never drifted, so this path was
never actually exercised end to end, which is itself part of why I consider
it the weakest-tested part of the whole script.
