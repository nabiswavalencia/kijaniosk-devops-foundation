#!/bin/bash
# kijanikiosk-provision.sh
# Idempotent provisioning for KijaniKiosk application servers (Ubuntu 22.04).
# Usage: sudo bash kijanikiosk-provision.sh
#
# Dirty conditions found in pre-provisioning-audit.txt, and where each one is handled.

# - kk-api, kk-payments, kk-logs already exist (UIDs 998/997/996) ... Phase 2 detects via id check
# - group kijanikiosk exists but was missing kk-logs as a member .... Phase 2 re-adds all three unconditionally
# - shared/logs and config ACLs already match the Tuesday model ..... Phase 3 re-applies them idempotently
# - ufw has a stray "deny 3001" rule from Thursday's remediation .... Phase 5 resets to a known baseline
# - nginx and nodejs already installed and held at pinned versions .. Phase 1 detects and skips reinstall
# - /etc/logrotate.d/kijanikiosk exists from Thursday but was never
#   committed to this script ......................................... Phase 7 now writes it directly
# - kk-api.service exists and is enabled; kk-payments.service and
#   kk-logs.service do not exist yet ................................. Phase 4 converges kk-api, creates the other two
# - /opt/kijanikiosk/app exists from Monday's lab setup, not part
#   of the access model .............................................. removed explicitly in Phase 3

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
  die "Set NGINX_VERSION and NODE_VERSION first (runbook step 3)"
fi

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
check() {   # check "<description>" <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then success "PASS: $desc"; else fail "$desc"; fi
}

check_ufw() {   # check_ufw "<description>" "<extended regex matched against 'ufw status'>"
  local desc="$1" pattern="$2"
  if ufw status | grep -E "$pattern" >/dev/null; then success "PASS: firewall: $desc"; else fail "firewall: $desc"; fi
}

gate() { if (( FAILED > 0 )); then die "${FAILED} check(s) failed, see FAIL lines above"; fi; }

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

write_placeholder_app() {   # write_placeholder_app <path> <owner>
  local path="$1" owner="$2"
  if [[ -e "$path" ]] && grep -q 'listen(' "$path"; then
    log "App file already present: $path"; return 0
  fi
  if [[ -e "$path" ]]; then warn "Replacing lab stub with placeholder app: $path"; fi
  printf '%s\n' "require('http').createServer((q,s)=>s.end('ok')).listen(process.env.PORT,'127.0.0.1');" > "$path"
  chown "$owner:$owner" "$path"; chmod 640 "$path"
}

# ---------------------------------------------------------------------------
# Phase 1: packages
# ---------------------------------------------------------------------------
provision_packages() {
  log "=== Phase 1: Packages ==="
  local p
  for p in curl gnupg acl ufw ca-certificates logrotate; do
    if apt-mark showhold | grep -x "$p" >/dev/null; then
      warn "Prerequisite $p was on hold: releasing it (only nginx and nodejs are meant to be pinned)"
      apt-mark unhold "$p" >/dev/null
    fi
  done
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends curl gnupg acl ufw ca-certificates logrotate >/dev/null
  # --yes lets gpg overwrite the key file on every run, which keeps this step idempotent
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /usr/share/keyrings/nodesource.gpg
  echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
  apt-get update -qq
  ensure_pinned nginx "$NGINX_VERSION"
  ensure_pinned nodejs "$NODE_VERSION"
  success "Packages ready: nginx $(installed_version nginx), nodejs $(installed_version nodejs) (both held)"
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
      usermod --shell /usr/sbin/nologin "$u"       # converge accounts that were made by hand
    else
      log "Creating account: $u"
      useradd --system --user-group --no-create-home --home-dir /nonexistent \
        --shell /usr/sbin/nologin --comment "KijaniKiosk ${u#kk-}" "$u"
    fi
    usermod -aG "$APP_GROUP" "$u"
  done
  if id amina &>/dev/null; then
    usermod -aG "$APP_GROUP" amina
  else
    warn "amina not present, skipped"
  fi
  success "Service accounts converged"
}

# ---------------------------------------------------------------------------
# Phase 3: directories, modes, ACLs
# ---------------------------------------------------------------------------
provision_dirs() {
  log "=== Phase 3: Directories, modes, ACLs ==="
  if [[ -d /opt/kijanikiosk/app ]]; then
    log "Removing orphaned /opt/kijanikiosk/app (leftover from Monday's lab, not part of the access model)"
    rm -rf /opt/kijanikiosk/app
  fi
  
  local b="$APP_BASE" s f
  mkdir -p "$b"/{api,payments,logs,config,scripts,shared/logs,health}

  # 1) owners and modes first (chmod after setfacl would rewrite the ACL mask)
  chown root:root "$b" "$b/shared" "$b/scripts"
  chmod 755 "$b" "$b/shared"
  chmod 750 "$b/scripts"
  for s in api payments logs; do
    chown -R "kk-$s:kk-$s" "$b/$s"
    chmod 750 "$b/$s"
  done
  chown root:"$APP_GROUP" "$b/config" "$b/health"
  chmod 750 "$b/config" "$b/health"
  chown kk-logs:kk-logs "$b/shared/logs"
  chmod 2770 "$b/shared/logs"
  if [[ -e "$b/scripts/deploy.sh" ]]; then
    chown root:root "$b/scripts/deploy.sh"; chmod 750 "$b/scripts/deploy.sh"     # removes SUID and world-write
  fi

  # config files: create empty ones if missing, never overwrite existing secrets
  for f in db.env api.env payments-api.env logs.env; do
    if [[ ! -e "$b/config/$f" ]]; then : > "$b/config/$f"; fi
    chown root:"$APP_GROUP" "$b/config/$f"
    chmod 640 "$b/config/$f"
  done

  # 2) ACLs second, mask set explicitly
  local acl="u:kk-api:rwx,u:kk-payments:r-x,m::rwx"
  if id amina &>/dev/null; then acl="u:amina:r-x,${acl}"; fi
  setfacl    -m "$acl" "$b/shared/logs"
  setfacl -d -m "$acl" "$b/shared/logs"
  if id amina &>/dev/null; then
    setfacl -m u:amina:r-x "$b/config"                       # x on a directory is what allows entering it
    setfacl -m u:amina:r-- "$b/config/"*.env
    for s in api payments; do setfacl -R -m u:amina:r-X "$b/$s"; done
  fi
  success "Directories, modes and ACLs applied"
}

# ---------------------------------------------------------------------------
# Phase 4: systemd units
# ---------------------------------------------------------------------------
provision_services() {
  log "=== Phase 4: systemd units ==="
  write_placeholder_app "$APP_BASE/api/server.js" kk-api
  write_placeholder_app "$APP_BASE/payments/processor.js" kk-payments
  write_placeholder_app "$APP_BASE/logs/aggregator.js" kk-logs

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
RemoveIPC=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
UMask=0077
ReadWritePaths=/opt/kijanikiosk/shared/logs

[Install]
WantedBy=multi-user.target
UNIT

  cat > /etc/systemd/system/kk-payments.service << 'UNIT'
[Unit]
Description=KijaniKiosk Payments Service
After=network-online.target
After=kk-api.service
Wants=network-online.target
Wants=kk-api.service
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=kk-payments
Group=kk-payments
WorkingDirectory=/opt/kijanikiosk/payments
ExecStart=/usr/bin/node /opt/kijanikiosk/payments/processor.js
Restart=on-failure
RestartSec=5s
EnvironmentFile=/opt/kijanikiosk/config/db.env
EnvironmentFile=/opt/kijanikiosk/config/payments-api.env
Environment=NODE_ENV=production
Environment=PORT=3001
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-payments
# --- extra hardening (filled in from harden-payments.sh, runbook step 5) ---
# EXTRA-HARDENING-KK-PAYMENTS
IPAddressDeny=any
IPAddressAllow=localhost
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
RemoveIPC=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
ProtectProc=invisible
ProcSubset=pid
UMask=0077
PrivateUsers=true
IPAddressDeny=any
IPAddressAllow=localhost

[Install]
WantedBy=multi-user.target
UNIT

  # kk-logs has no ExecReload on purpose: a HUP would stop a Node process that does not handle it,
  # so logrotate's "try-reload-or-restart" falls back to a restart, which is safe here.
  cat > /etc/systemd/system/kk-logs.service << 'UNIT'
[Unit]
Description=KijaniKiosk Log Aggregator
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=kk-logs
Group=kk-logs
WorkingDirectory=/opt/kijanikiosk/logs
ExecStart=/usr/bin/node /opt/kijanikiosk/logs/aggregator.js
Restart=on-failure
RestartSec=5s
EnvironmentFile=/opt/kijanikiosk/config/logs.env
Environment=NODE_ENV=production
Environment=PORT=3002
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-logs
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
RemoveIPC=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
UMask=0077
ReadWritePaths=/opt/kijanikiosk/shared/logs

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  local u
  for u in "${SERVICES[@]}"; do
    systemctl enable "$u.service" >/dev/null 2>&1
    if ! systemctl restart "$u.service"; then fail "could not start $u"; fi
  done
  sleep 2
  success "Units written, enabled and started"
}

# ---------------------------------------------------------------------------
# Phase 5: firewall  (YOUR TURN)
# ---------------------------------------------------------------------------
provision_firewall() {
  log "=== Phase 5: Firewall ==="
  local admin_ip
  admin_ip="${OPERATOR_IP:-}"

  ufw --force reset >/dev/null
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null

  ufw allow from 10.0.1.0/24 to any port 22 proto tcp comment "SSH from monitoring/admin subnet" >/dev/null
  ufw allow from 10.0.1.0/24 to any port 80 proto tcp comment "HTTP from monitoring subnet" >/dev/null
  ufw allow from 10.0.1.0/24 to any port 3001 proto tcp comment "kk-payments health check from monitoring subnet" >/dev/null

  if [[ -n "$admin_ip" ]]; then
    ufw allow from "$admin_ip" to any port 22 proto tcp comment "SSH operator access, lab exception - see integration-notes.md" >/dev/null
  fi

  ufw allow in on lo to any port 3001 proto tcp comment "kk-payments loopback for nginx proxy" >/dev/null
  ufw deny 3001/tcp comment "kk-payments internal port, no external access" >/dev/null

  ufw --force enable >/dev/null
  log "Active firewall rules:"
  ufw status numbered
  success "Firewall configured to express intent, not history"
}

# ---------------------------------------------------------------------------
# Phase 6: verification of phases 1 to 5 (also re-run at the end of Phase 8)
# ---------------------------------------------------------------------------
verify_core() {
  local u d p sl="$APP_BASE/shared/logs"
  for p in nginx nodejs; do
    check "package held: $p" bash -c 'apt-mark showhold | grep -x "$1" >/dev/null' _ "$p"
  done
  check "nginx at pinned version" test "$(installed_version nginx)" = "$NGINX_VERSION"
  check "nodejs at pinned version" test "$(installed_version nodejs)" = "$NODE_VERSION"

  for u in "${SERVICES[@]}"; do
    check "account exists: $u" id "$u"
    check "nologin shell: $u" test "$(getent passwd "$u" | cut -d: -f7)" = "/usr/sbin/nologin"
    check "member of $APP_GROUP: $u" bash -c 'id -nG "$1" | tr " " "\n" | grep -x "$2" >/dev/null' _ "$u" "$APP_GROUP"
    check "unit enabled: $u" systemctl is-enabled --quiet "$u.service"
    check "unit active: $u" systemctl is-active --quiet "$u.service"
  done

  for d in api payments logs config scripts shared/logs health; do
    check "directory exists: $d" test -d "$APP_BASE/$d"
  done
  check "base directory mode 755" test "$(stat -c %a "$APP_BASE")" = "755"
  check "config directory mode 750" test "$(stat -c %a "$APP_BASE/config")" = "750"
  check "shared/logs mode 2770 (SGID)" test "$(stat -c %a "$sl")" = "2770"
  check "no SUID or SGID files in app tree" bash -c '[[ -z "$(find "$1" -type f -perm /6000)" ]]' _ "$APP_BASE"

  check "ACL: kk-api rwx on shared/logs" bash -c 'getfacl -p "$1" | grep "^user:kk-api:rwx" >/dev/null' _ "$sl"
  check "ACL: kk-payments r-x on shared/logs" bash -c 'getfacl -p "$1" | grep "^user:kk-payments:r-x" >/dev/null' _ "$sl"
  check "default ACL: kk-api" bash -c 'getfacl -p "$1" | grep "^default:user:kk-api:rwx" >/dev/null' _ "$sl"
  check "default ACL: kk-payments" bash -c 'getfacl -p "$1" | grep "^default:user:kk-payments:r-x" >/dev/null' _ "$sl"
  check "ACL mask is rwx" bash -c 'getfacl -p "$1" | grep "^mask::rwx" >/dev/null' _ "$sl"

  check "kk-api can write shared/logs" sudo -u kk-api test -w "$sl"
  check "kk-payments cannot write shared/logs" bash -c '! sudo -u kk-payments test -w "$1"' _ "$sl"
  check "kk-api can read config" sudo -u kk-api test -r "$APP_BASE/config/db.env"
  check "kk-api cannot read payments code" bash -c '! sudo -u kk-api test -r "$1"' _ "$APP_BASE/payments/processor.js"
  check "kk-payments cannot read api code" bash -c '! sudo -u kk-payments test -r "$1"' _ "$APP_BASE/api/server.js"

  # Your turn: one check_ufw line per firewall rule, for example
  check_ufw "SSH allowed from monitoring subnet" '^22/tcp.*ALLOW.*10\.0\.1\.0/24'
  check_ufw "HTTP allowed from monitoring subnet" '^80/tcp.*ALLOW.*10\.0\.1\.0/24'
  check_ufw "3001 allowed from monitoring subnet" '^3001/tcp.*ALLOW.*10\.0\.1\.0/24'
  check_ufw "3001 denied externally" '^3001/tcp *DENY'
  check "ufw is active" bash -c "ufw status | grep -q 'Status: active'"
  #   check_ufw "SSH allowed" '^22/tcp +ALLOW'
  # Add one for each rule you wrote in Phase 5.
}

# ---------------------------------------------------------------------------
# Phase 7: journal persistence and log rotation
# ---------------------------------------------------------------------------
provision_logging() {
  log "=== Phase 7: Journal persistence and log rotation ==="
  mkdir -p /var/log/journal /etc/systemd/journald.conf.d      # the drop-in directory may not exist
  systemd-tmpfiles --create --prefix /var/log/journal
  cat > /etc/systemd/journald.conf.d/kijanikiosk.conf << 'CONF'
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=500M
SystemMaxFileSize=50M
CONF
  systemctl restart systemd-journald                            # journald has no reload

  # su: logrotate refuses to rotate in a group-writable directory unless told which user to use.
  # create 660 kk-logs kk-logs: new files get mode 660 (mask rw-) and group kk-logs, so only the
  # ACL entries decide who else can write. Group "kijanikiosk" here would let kk-payments write.
  # postrotate: reload if the service supports it, restart if not, do nothing if it is stopped.
  cat > /etc/logrotate.d/kijanikiosk << 'CONF'
/opt/kijanikiosk/shared/logs/*.log {
    su kk-logs kk-logs
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    create 660 kk-logs kk-logs
    sharedscripts
    postrotate
        systemctl try-reload-or-restart kk-logs.service >/dev/null 2>&1 || true
    endscript
}
CONF
  if ! logrotate --debug /etc/logrotate.d/kijanikiosk >/dev/null 2>&1; then die "logrotate config is invalid"; fi
  success "Journal persistent (500M cap), logrotate configured (daily, 14 kept)"
}

verify_logging() {
  check "journal directory exists" test -d /var/log/journal
  check "journal size cap configured" grep '^SystemMaxUse=500M' /etc/systemd/journald.conf.d/kijanikiosk.conf
  check "logrotate config valid (--debug)" logrotate --debug /etc/logrotate.d/kijanikiosk
  check "logrotate rotates daily" grep -x '    daily' /etc/logrotate.d/kijanikiosk
}

# Simulates a rotation on a test file with the same rules, then checks the ACL model survived.
# A separate config and state file are used so the real logs are not rotated by every run.
verify_logrotate_acl() {
  local sl="$APP_BASE/shared/logs" lf="$APP_BASE/shared/logs/provision-test.log" conf=/tmp/kk-logrotate-test.conf
  echo "seed $(date +%s)" >> "$lf"                              # notifempty skips empty files
  chown kk-logs:kk-logs "$lf"; chmod 660 "$lf"
  sed "s|$sl/\*.log|$lf|" /etc/logrotate.d/kijanikiosk > "$conf"
  chmod 644 "$conf"
  if logrotate --force --state /tmp/kk-logrotate.state "$conf" >/dev/null 2>&1; then
    success "PASS: forced rotation of the test log ran"
  else
    fail "forced rotation of the test log failed"
  fi
  check "rotation created a new log file" test -e "$lf"
  check "kk-api can append to the new log" sudo -u kk-api sh -c "echo test >> '$lf'"
  check "kk-payments can read the new log" sudo -u kk-payments test -r "$lf"
  check "kk-payments cannot write the new log" bash -c '! sudo -u kk-payments test -w "$1"' _ "$lf"
  check "kk-api can create files in shared/logs" sudo -u kk-api sh -c "touch '$sl/test-write.tmp' && rm -f '$sl/test-write.tmp'"
}

# ---------------------------------------------------------------------------
# Phase 8: health checks and final verification
# ---------------------------------------------------------------------------
provision_health() {
  log "=== Phase 8: Health checks and final verification ==="
  local api pay
  sleep 2
  api=$(timeout 2 bash -c 'echo >/dev/tcp/localhost/3000' 2>/dev/null && echo '"ok"' || echo '"down"')
  pay=$(timeout 2 bash -c 'echo >/dev/tcp/localhost/3001' 2>/dev/null && echo '"ok"' || echo '"down"')
  mkdir -p "$APP_BASE/health"
  printf '{"timestamp":"%s","kk-api":%s,"kk-payments":%s}\n' "$(date -Is)" "$api" "$pay" \
    > "$APP_BASE/health/last-provision.json"
  chown root:"$APP_GROUP" "$APP_BASE/health/last-provision.json"
  chmod 640 "$APP_BASE/health/last-provision.json"
  log "Health file: $(cat "$APP_BASE/health/last-provision.json")"
  check "health file exists and is not empty" test -s "$APP_BASE/health/last-provision.json"
  check "health file readable by kk-api (group)" sudo -u kk-api test -r "$APP_BASE/health/last-provision.json"
  verify_core
  verify_logging
  verify_logrotate_acl
}

main() {
  log "Starting KijaniKiosk provisioning on $(hostname)"
  provision_packages
  provision_users
  provision_dirs
  provision_services
  provision_firewall
  log "=== Phase 6: Verification (phases 1-5) ==="
  verify_core
  gate
  provision_logging
  provision_health
  gate
  success "Provisioning complete. All checks passed."
}

main "$@"
