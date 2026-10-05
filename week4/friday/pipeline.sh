#!/usr/bin/env bash
# KijaniKiosk IaC pipeline: Terraform provisions, Ansible configures.
# Usage: ./pipeline.sh [multipass]
# Requires AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY exported for the MinIO backend.
set -euo pipefail

PATH_MODE="${1:-multipass}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
ANSIBLE_DIR="$SCRIPT_DIR/ansible"
INVENTORY="$ANSIBLE_DIR/inventory.ini"

log()  { printf '\n==> [%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
fail() { printf '\nPIPELINE FAILED: %s\n' "$*" >&2; exit 1; }

# Preflight
[ "$PATH_MODE" = "multipass" ] || fail "only the multipass path is implemented (got: $PATH_MODE)"
: "${AWS_ACCESS_KEY_ID:?export AWS_ACCESS_KEY_ID for the MinIO backend}"
: "${AWS_SECRET_ACCESS_KEY:?export AWS_SECRET_ACCESS_KEY for the MinIO backend}"
for tool in terraform ansible ansible-playbook multipass jq; do
  command -v "$tool" >/dev/null || fail "$tool is not installed"
done

# 1. Terraform
log "Terraform init (MinIO S3 backend)"
terraform -chdir="$TF_DIR" init -input=false -no-color >/dev/null || fail "terraform init"

log "Terraform plan"
terraform -chdir="$TF_DIR" plan -input=false -no-color -out=tfplan || fail "terraform plan"

log "Terraform apply"
terraform -chdir="$TF_DIR" apply -input=false -no-color tfplan || fail "terraform apply"
rm -f "$TF_DIR/tfplan"

# 2. Terraform outputs -> Ansible inventory (Challenge A)
log "Writing inventory from Terraform outputs"
terraform -chdir="$TF_DIR" output -raw ansible_inventory > "$INVENTORY" || fail "terraform output"
echo >> "$INVENTORY"
cat "$INVENTORY"

log "Cross-checking inventory IPs against Multipass"
while read -r host vars; do
  tf_ip="${vars#ansible_host=}"
  mp_ip="$(multipass info "$host" --format json | jq -r '.info[].ipv4[0]')"
  [ "$tf_ip" = "$mp_ip" ] || fail "IP mismatch for $host: terraform=$tf_ip multipass=$mp_ip"
  echo "$host $tf_ip matches Multipass"
done < <(grep 'ansible_host=' "$INVENTORY")

# 3. Ansible
cd "$ANSIBLE_DIR"
log "Waiting for SSH on all hosts (Challenge B)"
ansible kijanikiosk -m ansible.builtin.wait_for_connection -a "timeout=180" -o || fail "hosts unreachable over SSH"

log "Ansible playbook"
ansible-playbook kijanikiosk.yml || fail "ansible-playbook"

log "Pipeline complete"
