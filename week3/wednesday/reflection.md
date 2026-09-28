# Wednesday reflection

## 1. The idempotency boundary
My patterns (guard before create, overwrite instead of append, `mkdir -p`) work for things that either exist or do not. Three things they do not cover:
1. **Changing the configuration of a running service.** Writing a new file is idempotent, but the running process still holds the old settings in memory. The script has to know whether the file changed and then reload or restart, which depends on the service. I would compare a checksum before and after, and restart only on a change.
2. **Rotating a credential that is in use.** Setting a new password is easy to repeat, but the old one may be in use by live connections, so applying it twice at the wrong moment breaks a working system. This needs a rollover: accept both, switch clients, then retire the old one.
3. **Rolling back a package when a newer one is installed.** A downgrade can conflict with dependencies or with data already migrated by the newer version. Repeating it is not the same as the first time. I would fail and ask for a decision, which is what my script does on a version mismatch.

## 2. Version pinning vs security updates
My colleague is right that a pin blocks automatic patches, so it is a risk if nobody looks after it. But an unpinned server can change under us at any moment, and on a payments platform a surprise upgrade is also a risk. The correct process is to pin, subscribe to the vendor's security notices, test the patched version in staging, and then release the pin deliberately through change management. In a two-person startup that might mean a weekly check and one person testing. In a company with a security team, there is a defined response time per severity (for example critical within 48 hours), an owner, and a tested rollback. The pin is what makes those updates controlled.

## 3. systemd hardening trade-offs
`ProtectSystem=strict` mounts the entire filesystem read-only for that service's private mount namespace, except `/dev`, `/proc` and `/sys`. A write to `/var/run/kijanikiosk/` or `/var/cache/kijanikiosk/` fails with "read-only file system", which the developer sees as a failure with no obvious cause. The fix is to keep the hardening and grant exactly what is needed. The best way is `RuntimeDirectory=kijanikiosk` (systemd creates `/run/kijanikiosk`, which `/var/run` points to) and `CacheDirectory=kijanikiosk` (creates `/var/cache/kijanikiosk`), both owned by the service user. The alternative is `ReadWritePaths=` for those paths. My own unit uses `ReadWritePaths=/opt/kijanikiosk/shared/logs`, because the API writes there.

## 4. The gap between shell scripts and IaC tools
Three cases where my bash script would go wrong and Ansible or Terraform would not:
1. **Drift.** My script only fixes what it knows about. If someone changes a setting by hand, nothing tells me. Terraform compares real infrastructure to its recorded state and shows the difference in a plan.
2. **Many servers.** The script runs on one machine at a time and I have to copy and start it myself. Ansible runs the same tasks across an inventory, in order, and reports which hosts changed.
3. **Failing halfway.** If my script stops in Phase 4, the server is in an unknown state and I have to work out what ran. Terraform records what it created and can continue or destroy exactly that.
So shell scripts suit bootstrapping a single server or a small one-off task. Once a fleet, drift or shared state is involved, a declarative tool is the right choice.
