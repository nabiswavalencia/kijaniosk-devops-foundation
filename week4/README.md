# Week 4: Infrastructure as Code (KijaniKiosk)

Primary path: Multipass VMs, MinIO as the Terraform S3 backend, Ansible for configuration.
Host: Ubuntu 24.04 (native), Terraform 1.16.5.

- `notes/`: Week 3 phase-to-module map, MinIO image record, state lock test
- `terraform/`: `app_server` module called with `for_each` (api, payments, logs); IPs read from
  Multipass, remote state in MinIO with `use_lockfile` locking. Tuesday's single-VM config was
  refactored into this module on Wednesday.
- `ansible/`: Week 3 provisioning script as an idempotent playbook
- `friday/`: full pipeline, graded project
