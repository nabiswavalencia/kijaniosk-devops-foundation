# Reflection: Week 4 IaC Pipeline

## 1. Where two requirements conflicted

The conflict I met first was Challenge D. `ProtectSystem=strict` on kk-payments (Requirement 5) makes the whole filesystem read-only to the service, while Requirement 2 has Ansible template the service's environment file and restart the service when it changes. I had resolved the Week 3 version of this by keeping config under `/opt/kijanikiosk/config/`, owned `root:kijanikiosk`, mode 640, and the Ansible template reproduces exactly that. What I understand better now is why it works: `EnvironmentFile=` is read by systemd itself before the sandbox is applied, and the service only ever needs read access, which `ProtectSystem=strict` never removes. The real risk is ownership and mode, not the sandbox, so the playbook proves it on every run by reading each env file as the service account (Phase 8), rather than trusting the path.

The conflict I discovered this week was between idempotency (`changed=0` on run 2) and the Week 3 script's own behaviour. The script ran `ufw --force reset` and wrote a timestamp into `last-provision.json` on every run. Translated literally, both report a change every time, so run 2 could never be clean. I dropped the reset in favour of declarative rules and removed the timestamp. The cost is real: a rule added by hand is no longer wiped, and I listed that as a gap. The lesson was that a script that converges by rebuilding and a tool that converges by comparing need different designs, even when the end state is the same.

## 2. One sentence, rewritten for Tendo

For Nia: "The payment service can only communicate over the server's internal connection."

For Tendo: "kk-payments runs with `IPAddressDeny=any` and `IPAddressAllow=localhost`, so systemd's cgroup BPF filter drops any IP traffic to or from a non-loopback address, and the service itself binds only to 127.0.0.1."

What is lost going to Nia's version: the mechanism, which means she cannot verify it or see its limits. It filters IP only, so it says nothing about Unix sockets, and it is enforced per cgroup, so it only protects processes inside the unit. What is gained: the outcome and the risk it addresses, stated so she can repeat it to a board. Tendo's version is checkable; Nia's version is usable. Each audience needs the other half less than it needs its own.

## 3. The most fragile handoff

The handoff from Terraform's output to Ansible's first SSH connection. It works here because of three assumptions that only hold on this laptop:

- Multipass reports the VM's first IPv4 address, and that address is reachable from the machine running Ansible.
- The machine running Ansible sits on the same bridge subnet as the VMs.
- The firewall rule that keeps SSH open (`admin_cidr`) is computed from the VM's own default-route subnet, on the assumption that this is where Ansible connects from.

In an environment that differs slightly, such as servers behind a bastion host, a VPN, NAT, or a second network interface, the third assumption fails first and worst. The SSH allow rule would name the wrong network, and enabling the firewall could cut Ansible off partway through a run.

To make the handoff robust I would need to know: the network path from the controller to the servers (direct, bastion, or VPN); the source address the servers actually see for Ansible's connections; which interface carries the default route on each server; and whether server addresses are stable or should be resolved through DNS names. With that, the SSH rule would be an explicit variable fed from the same place Terraform gets its network settings, instead of being inferred from facts on the target.

A second, unplanned example of fragility came up on day one: `minio/minio` was removed from Docker Hub, so the brief's own setup command no longer works. Any pipeline step that pulls an unpinned image from a registry we do not control can break without a single change on our side. I pinned the replacement image by tag and recorded its digest in `environment-setup.md`.
