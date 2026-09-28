#!/bin/bash
# wednesday-provision.sh
# Wednesday's six-phase provisioning script (Hardened Service Deployment lab).
# Usage: sudo bash wednesday-provision.sh
#
# This is deliberately smaller than Friday's script. Friday adds journal persistence, log rotation,
# hardened units for all three services, a health check and a stricter firewall. Running this one
# first leaves the VM in the state Friday's project expects to inherit.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

readonly NGINX_VERSION="1.18.0-6ubuntu14.21"
readonly NODE_VERSION="20.20.2-1nodesource1"
readonly NODE_MAJOR="20"
readonly APP_GROUP="kijanikiosk"
readonly APP_BASE="/opt/kijanikiosk"
readonly SERVICES=(kk-api kk-payments kk-logs)
FAILED=0

log()     { echo "[$(date +%FT%T)] INFO  $*"; }
success() { echo "[$(date +%FT%T)] OK    $*"; }
warn()    { echo "[$(date +%FT%T)] WARN  $*"; }
fail()    { echo "[$(date +%FT%T)] FAIL  $*"; FAILED=$((FAILED + 1)); }
die()     { echo "[$(date +%FT%T)] ERROR $*" >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then die "Run with sudo"; fi
if ! grep -qi ubuntu /etc/os-release; then die "Ubuntu only"; fi
if [[ "$NGINX_VERSION" == "FILL_ME" || "$NODE_VERSION" == "FILL_ME" ]]; then
  die "Set NGINX_VERSION and NODE_VERSION first (command sheet, Wednesday W1)"
fi

check() {   # check "<description>" <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then success "PASS: $desc"; else fail "$desc"; fi
}

installed_version() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true; }

ensure_pinned() {   # ensure_pinned <package> <version>
  local pkg="$1" want="$2" have
  have="$(installed_version "$pkg")"
  if [[ "$have" == "$want" ]]; then
    log "Already at pinned version: $pkg $have"
  elif [[ -z "$have" ]]; then
    log "Installing $pkg=$want"
    apt-get install -y -qq --no-install-recommends "$pkg=$want" >/dev/null
  else
    die "$pkg is $have but pinned to $want. Decide by hand: apt-mark unhold $pkg && apt-get install --allow-downgrades $pkg=$want"
  fi
  apt-mark hold "$pkg" >/dev/null
}

# ---------------------------------------------------------------------------
# Phase 1: packages
# ---------------------------------------------------------------------------
provision_packages() {
  log "=== Phase 1: Packages ==="
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends curl gnupg acl ufw ca-certificates >/dev/null
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /usr/share/keyrings/nodesource.gpg
  echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
  apt-get update -qq
  ensure_pinned nginx "$NGINX_VERSION"
  ensure_pinned nodejs "$NODE_VERSION"
  success "nginx $(installed_version nginx) and nodejs $(installed_version nodejs) installed and held"
}

# ---------------------------------------------------------------------------
# Phase 2: service accounts
# ---------------------------------------------------------------------------
provision_users() {
  log "=== Phase 2: Service accounts ==="
  getent group "$APP_GROUP" >/dev/null || groupadd --system "$APP_GROUP"
  local u
  for u in "${SERVICES[@]}"; do
    if id "$u" &>/dev/null; then
      log "Already exists: $u"
    else
      log "Creating account: $u"
      useradd --system --user-group --no-create-home --home-dir /nonexistent \
        --shell /usr/sbin/nologin --comment "KijaniKiosk ${u#kk-}" "$u"
    fi
    usermod -aG "$APP_GROUP" "$u"
  done
  if id amina &>/dev/null; then usermod -aG "$APP_GROUP" amina; else warn "amina not present, skipped"; fi
  success "Service accounts ready"
}

# ---------------------------------------------------------------------------
# Phase 3: directories, modes, ACLs (Tuesday's access model)
# ---------------------------------------------------------------------------
provision_dirs() {
  log "=== Phase 3: Directories, modes, ACLs ==="
  local b="$APP_BASE" s f
  mkdir -p "$b"/{api,payments,logs,config,scripts,shared/logs}
  chown root:root "$b" "$b/shared" "$b/scripts"
  chmod 755 "$b" "$b/shared"
  chmod 750 "$b/scripts"
  for s in api payments logs; do
    chown -R "kk-$s:kk-$s" "$b/$s"
    chmod 750 "$b/$s"
  done
  chown root:"$APP_GROUP" "$b/config"
  chmod 750 "$b/config"
  chown kk-logs:kk-logs "$b/shared/logs"
  chmod 2770 "$b/shared/logs"
  if [[ -e "$b/scripts/deploy.sh" ]]; then chown root:root "$b/scripts/deploy.sh"; chmod 750 "$b/scripts/deploy.sh"; fi
  for f in db.env api.env payments-api.env; do
    if [[ ! -e "$b/config/$f" ]]; then : > "$b/config/$f"; fi
    chown root:"$APP_GROUP" "$b/config/$f"
    chmod 640 "$b/config/$f"
  done
  # ACLs after modes, with the mask stated explicitly
  local acl="u:kk-api:rwx,u:kk-payments:r-x,m::rwx"
  if id amina &>/dev/null; then acl="u:amina:r-x,${acl}"; fi
  setfacl    -m "$acl" "$b/shared/logs"
  setfacl -d -m "$acl" "$b/shared/logs"
  success "Directories, modes and ACLs applied"
}

# ---------------------------------------------------------------------------
# Phase 4: systemd unit for kk-api (enabled, not started: no application code yet)
# ---------------------------------------------------------------------------
provision_services() {
  log "=== Phase 4: systemd unit ==="
  cat > /etc/systemd/system/kk-api.service << 'UNIT'
[Unit]
Description=KijaniKiosk API Service
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=kk-api
Group=kk-api
WorkingDirectory=/opt/kijanikiosk/api
ExecStart=/usr/bin/node /opt/kijanikiosk/api/server.js
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s
EnvironmentFile=/opt/kijanikiosk/config/db.env
EnvironmentFile=/opt/kijanikiosk/config/api.env
Environment=NODE_ENV=production
Environment=PORT=3000
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-api
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
CapabilityBoundingSet=
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
PrivateDevices=true
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
SystemCallArchitectures=native
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
UMask=0077
ReadWritePaths=/opt/kijanikiosk/shared/logs

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable kk-api.service >/dev/null 2>&1
  success "kk-api.service written and enabled (not started)"
}

# ---------------------------------------------------------------------------
# Phase 5: firewall  (YOUR TURN: use `man ufw`)
# ---------------------------------------------------------------------------
provision_firewall() {
  log "=== Phase 5: Firewall ==="
  # ufw was installed in Phase 1. Reset first so the result does not depend on old rules.
  ufw --force reset >/dev/null
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  # SSH is allowed BEFORE ufw is enabled, otherwise the current session would be cut off.
  ufw allow 22/tcp comment 'SSH' >/dev/null
  ufw allow 80/tcp comment 'HTTP' >/dev/null
  ufw --force enable >/dev/null
  log "Active firewall rules:"
  ufw status numbered
  success "Firewall configured: deny incoming, allow 22 and 80"
}

# ---------------------------------------------------------------------------
# Phase 6: verification
# ---------------------------------------------------------------------------
verify_state() {
  log "=== Phase 6: Verification ==="
  local u d
  for u in "${SERVICES[@]}"; do
    check "account exists: $u" id "$u"
  done
  for d in api payments logs config scripts shared/logs; do
    check "directory exists: $d" test -d "$APP_BASE/$d"
  done
  check "no SUID files in app tree" bash -c '[[ -z "$(find "$1" -type f -perm /4000)" ]]' _ "$APP_BASE"
  check "nginx held" bash -c 'apt-mark showhold | grep -x nginx >/dev/null'
  check "nodejs held" bash -c 'apt-mark showhold | grep -x nodejs >/dev/null'
  check "kk-api.service enabled" systemctl is-enabled --quiet kk-api.service
  check "ufw is active" bash -c 'ufw status | grep "Status: active" >/dev/null'
  check "ufw default deny incoming" bash -c 'ufw status verbose | grep "deny (incoming)" >/dev/null'
  check "ufw allows SSH (22)" bash -c 'ufw status | grep -E "^22/tcp +ALLOW" >/dev/null'
  check "ufw allows HTTP (80)" bash -c 'ufw status | grep -E "^80/tcp +ALLOW" >/dev/null'
  if (( FAILED > 0 )); then die "${FAILED} check(s) failed"; fi
  success "All checks passed"
}

main() {
  log "Starting KijaniKiosk provisioning on $(hostname)"
  provision_packages
  provision_users
  provision_dirs
  provision_services
  provision_firewall
  verify_state
  success "Provisioning complete. Server is in a known state."
}

main "$@"
