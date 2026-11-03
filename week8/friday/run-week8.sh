#!/usr/bin/env bash
# week8/friday/run-week8.sh
# Runs the Week 8 container delivery pipeline step by step and writes the
# evidence files next to this script.
#
# Usage (from anywhere inside the repo):
#   export DOCKERHUB_USER=<your Docker Hub username>
#   bash week8/friday/run-week8.sh <phase>
#
# Phases, in order:
#   check    tools, minikube, Docker Hub login
#   reset    clear kk-payments from the cluster and local image cache -> cluster-reset.txt
#   build    baseline + production images (--no-cache), 5 tests     -> build-verification.txt
#   push     tag, push, delete local, pull back                     -> registry-push.txt
#   secret   create kijani-registry-credentials if missing (asks for the token, never stores it)
#   deploy   write tag into manifest, apply, wait for 2/2           -> deploy-output.txt
#   service  apply Service, endpoints, NodePort + in-cluster checks -> service-output.txt
#   heal     delete a Pod, time the replacement                     -> self-healing-rerun.txt
#   audit    credential audit (asks for the token to search for)    -> credential-audit.txt
#   report   fill measured numbers into nia-comparison.md
#   all      check reset build push secret deploy service heal audit report

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository"; exit 1; }
OUT="${REPO_ROOT}/week8/friday"
APP_DIR="${REPO_ROOT}/payments"
STATE="${OUT}/measurements.env"
LOCAL_REPO="kijanikiosk/kk-payments"
BASELINE_TAG="${LOCAL_REPO}:baseline-single-stage"
NODE_PORT=30001

ts()   { date +%H:%M:%S; }
say()  { echo; echo "=== [$(ts)] $* ==="; }
fail() { echo "STOP: $*" >&2; exit 1; }
run()  { echo "\$ $*"; "$@"; local rc=$?; echo "(exit ${rc})"; return ${rc}; }

if command -v kubectl >/dev/null 2>&1; then KUBECTL=(kubectl); else KUBECTL=(minikube kubectl --); fi
k() { "${KUBECTL[@]}" "$@"; }

save() { # save KEY VALUE into measurements.env
  touch "${STATE}"
  grep -v "^$1=" "${STATE}" > "${STATE}.tmp" || true
  echo "$1=$2" >> "${STATE}.tmp"
  mv "${STATE}.tmp" "${STATE}"
}
# shellcheck disable=SC1090
load() { [ -f "${STATE}" ] && . "${STATE}"; return 0; }

need_user() { [ -n "${DOCKERHUB_USER:-}" ] || fail "export DOCKERHUB_USER=<your Docker Hub username> first"; }

compute_tag() {
  cd "${APP_DIR}" || exit 1
  # The two-line version computation from Wednesday (documented in README.md)
  PKG_VERSION=$(node -p "require('./package.json').version" 2>/dev/null \
    || python3 -c "import json; print(json.load(open('package.json'))['version'])")
  GIT_SHORT=$(git rev-parse --short=7 HEAD)
  IMAGE_TAG="${PKG_VERSION}-${GIT_SHORT}"
  cd - >/dev/null || exit 1
}

mb() { awk -v b="$1" 'BEGIN { printf "%.1f", b/1000/1000 }'; }

# ─────────────────────────────────────────────────────────────────────────────
phase_check() {
  say "Tool check"
  for t in docker git minikube; do command -v "$t" >/dev/null || fail "$t is not installed"; done
  docker --version
  minikube version | head -1
  k version --client 2>/dev/null | head -1
  docker info >/dev/null 2>&1 || fail "Docker daemon not reachable (is your user in the docker group?)"
  minikube status >/dev/null 2>&1 || fail "minikube is not running: minikube start --driver=docker --memory=2048 --cpus=2"
  k get nodes
  need_user
  if grep -q 'index.docker.io' ~/.docker/config.json 2>/dev/null || grep -q '"credsStore"' ~/.docker/config.json 2>/dev/null; then
    echo "Docker Hub login: present"
  else
    fail "Not logged in to Docker Hub. Run: docker login -u ${DOCKERHUB_USER}   (paste an access token, not your password)"
  fi
  if [ -n "$(git -C "${REPO_ROOT}" status --porcelain -- payments)" ]; then
    echo "WARNING: payments/ has uncommitted changes. Commit them first so the image tag's SHA matches the code."
  fi
  echo "All checks passed."
}

# ─────────────────────────────────────────────────────────────────────────────
phase_reset() {
  need_user
  {
    say "Clearing exploratory kk-payments resources"
    run k delete deployment kk-payments --ignore-not-found
    run k delete service kk-payments-service --ignore-not-found
    sleep 3
    say "Namespace check (expected: No resources found)"
    k get all -l app=kk-payments 2>&1
    say "ImagePullSecret check (expected: present; create it with the 'secret' phase if not)"
    k get secret kijani-registry-credentials 2>&1
    say "Removing locally cached kk-payments images (cold build and pull)"
    docker images | grep kk-payments || echo "(no kk-payments images cached)"
    ids=$(docker images --filter=reference='*/kk-payments' --filter=reference='*/*/kk-payments' -q | sort -u)
    [ -n "${ids}" ] && docker rmi -f ${ids} || true
    docker images | grep kk-payments || echo "(no kk-payments images remain)"
  } 2>&1 | tee "${OUT}/cluster-reset.txt"
}

# ─────────────────────────────────────────────────────────────────────────────
phase_build() {
  compute_tag
  cp "${OUT}/.dockerignore" "${APP_DIR}/.dockerignore"
  {
    echo "# kk-payments build verification"
    echo "# Date: $(date -u +'%F %T') UTC   Host: $(hostname)"
    echo "# Version computation:"
    echo "#   PKG_VERSION=\$(node -p \"require('./package.json').version\")  -> ${PKG_VERSION}"
    echo "#   GIT_SHORT=\$(git rev-parse --short=7 HEAD)                    -> ${GIT_SHORT}"
    echo "#   IMAGE_TAG=\${PKG_VERSION}-\${GIT_SHORT}                         -> ${IMAGE_TAG}"

    say "Baseline: single-stage image (--no-cache), for the size comparison"
    run docker build --no-cache --progress=plain -f "${OUT}/Dockerfile.single-stage" \
      -t "${BASELINE_TAG}" "${APP_DIR}" || fail "baseline build failed"

    say "Production: two-stage image (--no-cache)"
    run docker build --no-cache --progress=plain -f "${OUT}/Dockerfile.production" \
      --build-arg APP_VERSION="${IMAGE_TAG}" \
      -t "${LOCAL_REPO}:${IMAGE_TAG}" "${APP_DIR}" || fail "production build failed"

    say "docker images"
    docker images | head -1
    docker images | grep kk-payments

    BASE_B=$(docker image inspect -f '{{.Size}}' "${BASELINE_TAG}")
    PROD_B=$(docker image inspect -f '{{.Size}}' "${LOCAL_REPO}:${IMAGE_TAG}")
    PCT=$(awk -v a="${BASE_B}" -v b="${PROD_B}" 'BEGIN { printf "%.0f", (a-b)*100/a }')
    echo
    echo "Baseline single-stage: $(mb "${BASE_B}") MB (${BASE_B} bytes)"
    echo "Production two-stage:  $(mb "${PROD_B}") MB (${PROD_B} bytes)"
    echo "Reduction:             ${PCT}%"

    IMG="${LOCAL_REPO}:${IMAGE_TAG}"
    say "TEST 1: image under 100MB"
    if [ "${PROD_B}" -lt 100000000 ]; then echo "PASS: $(mb "${PROD_B}") MB"; else echo "FAIL: $(mb "${PROD_B}") MB"; fi

    say "TEST 2: runs as non-root"
    echo "\$ docker run --rm ${IMG} whoami"
    WHO=$(docker run --rm "${IMG}" whoami); echo "${WHO}"
    [ "${WHO}" = "kijani" ] && echo "PASS" || echo "FAIL"
    echo "\$ docker run --rm ${IMG} id"; docker run --rm "${IMG}" id

    say "TEST 3: no TypeScript compiler"
    echo "\$ docker run --rm ${IMG} which tsc"
    TSC=$(docker run --rm "${IMG}" which tsc 2>/dev/null); echo "${TSC}"
    [ -z "${TSC}" ] && echo "(empty) PASS" || echo "FAIL"

    say "TEST 4: no devDependencies, no npm"
    docker run --rm "${IMG}" sh -c 'for d in jest eslint typescript; do [ -d node_modules/$d ] && echo "FAIL: $d present" || echo "PASS: $d absent"; done; command -v npm >/dev/null && echo "FAIL: npm present" || echo "PASS: npm absent"; echo "node $(node --version)"'

    say "TEST 5: HEALTHCHECK reaches healthy within 60s"
    docker rm -f kk-prod-test >/dev/null 2>&1
    docker run -d --name kk-prod-test "${IMG}" >/dev/null
    START=$(date +%s); HEALTHY=""
    for _ in $(seq 1 30); do
      S=$(docker inspect -f '{{.State.Health.Status}}' kk-prod-test)
      echo "[$(ts)] +$(( $(date +%s) - START ))s ${S}"
      [ "${S}" = "healthy" ] && { HEALTHY=$(( $(date +%s) - START )); break; }
      sleep 2
    done
    [ -n "${HEALTHY}" ] && [ "${HEALTHY}" -le 60 ] && echo "PASS: healthy after ${HEALTHY}s" || echo "FAIL: not healthy within 60s"
    echo "\$ docker exec kk-prod-test wget -qO- http://127.0.0.1:3001/health"
    docker exec kk-prod-test wget -qO- http://127.0.0.1:3001/health; echo
    docker rm -f kk-prod-test >/dev/null

    save IMAGE_TAG "${IMAGE_TAG}"
    save BASELINE_MB "$(mb "${BASE_B}")"
    save PROD_MB "$(mb "${PROD_B}")"
    save REDUCTION_PCT "${PCT}"
  } 2>&1 | tee "${OUT}/build-verification.txt"
}

# ─────────────────────────────────────────────────────────────────────────────
phase_push() {
  need_user; load
  [ -n "${IMAGE_TAG:-}" ] || fail "run the build phase first"
  REMOTE="docker.io/${DOCKERHUB_USER}/kk-payments:${IMAGE_TAG}"
  {
    echo "# kk-payments registry push and pull verification"
    echo "# Date: $(date -u +'%F %T') UTC"
    echo "# Registry: Docker Hub, private repository ${DOCKERHUB_USER}/kk-payments"
    echo "# Login was done beforehand with 'docker login' using an access token via stdin; no credentials appear here."
    say "Version string"
    cd "${APP_DIR}" || exit 1
    echo "\$ PKG_VERSION=\$(node -p \"require('./package.json').version\")"; echo "${IMAGE_TAG%%-*}"
    echo "\$ GIT_SHORT=\$(git rev-parse --short=7 HEAD)"; git rev-parse --short=7 HEAD
    echo "\$ IMAGE_TAG=\"\${PKG_VERSION}-\${GIT_SHORT}\""; echo "${IMAGE_TAG}"
    cd - >/dev/null || exit 1
    say "Tag and push"
    run docker tag "${LOCAL_REPO}:${IMAGE_TAG}" "${REMOTE}"
    run docker push "${REMOTE}" || fail "push failed (is the repository private and are you logged in?)"
    LOCAL_ID=$(docker image inspect -f '{{.Id}}' "${REMOTE}")
    echo "Local image ID: ${LOCAL_ID}"
    say "Delete every local copy, then pull from the registry"
    run docker rmi "${REMOTE}" "${LOCAL_REPO}:${IMAGE_TAG}"
    docker images | grep "kk-payments" | grep "${IMAGE_TAG}" || echo "(no local copy of ${IMAGE_TAG} remains)"
    run docker pull "${REMOTE}" || fail "pull failed"
    PULLED_ID=$(docker image inspect -f '{{.Id}}' "${REMOTE}")
    echo "Pulled image ID: ${PULLED_ID}"
    [ "${LOCAL_ID}" = "${PULLED_ID}" ] && echo "PASS: pulled image is identical to the one built" || echo "NOTE: IDs differ"
    docker image inspect -f 'RepoDigests: {{.RepoDigests}}' "${REMOTE}"
    say "Full image reference for the Deployment"
    echo "${REMOTE}"
  } 2>&1 | tee "${OUT}/registry-push.txt"
  save IMAGE_REF "${REMOTE}"
}

# ─────────────────────────────────────────────────────────────────────────────
phase_secret() {
  need_user
  if k get secret kijani-registry-credentials >/dev/null 2>&1; then
    echo "kijani-registry-credentials already exists:"; k get secret kijani-registry-credentials; return 0
  fi
  read -rsp "Docker Hub access token for ${DOCKERHUB_USER} (input hidden): " TOKEN; echo
  [ -n "${TOKEN}" ] || fail "no token entered"
  k create secret docker-registry kijani-registry-credentials \
    --docker-server=https://index.docker.io/v1/ \
    --docker-username="${DOCKERHUB_USER}" \
    --docker-password="${TOKEN}" >/dev/null && echo "secret/kijani-registry-credentials created"
  unset TOKEN
  k get secret kijani-registry-credentials
}

# ─────────────────────────────────────────────────────────────────────────────
phase_deploy() {
  need_user; load
  [ -n "${IMAGE_TAG:-}" ] || fail "run build and push first"
  MANIFEST="${OUT}/kk-payments-deployment.yaml"
  REF="docker.io/${DOCKERHUB_USER}/kk-payments:${IMAGE_TAG}"
  sed -i -E "s#^( *image: ).*kk-payments:.*#\1${REF}#" "${MANIFEST}"
  {
    echo "# kk-payments Deployment"
    echo "# Date: $(date -u +'%F %T') UTC"
    say "Image in manifest (must match registry-push.txt)"
    grep 'image:' "${MANIFEST}"
    say "Secret present"
    k get secret kijani-registry-credentials
    say "Dry run"
    run k apply --dry-run=client -f "${MANIFEST}"
    say "Apply"
    START=$(date +%s)
    run k apply -f "${MANIFEST}"
    run k rollout status deployment/kk-payments --timeout=180s \
      || { k describe pods -l app=kk-payments | tail -25; fail "Pods not Running within 3 minutes"; }
    echo "Both Pods Running after $(( $(date +%s) - START ))s"
    say "Pods"
    k get pods -l app=kk-payments -o wide
    say "Deployment"
    k get deployment kk-payments
    say "ReplicaSet"
    k get replicaset -l app=kk-payments
    say "Running as non-root inside the cluster"
    POD=$(k get pod -l app=kk-payments -o name | head -1)
    run k exec "${POD}" -- whoami
  } 2>&1 | tee "${OUT}/deploy-output.txt"
}

# ─────────────────────────────────────────────────────────────────────────────
phase_service() {
  load
  {
    echo "# kk-payments Service verification"
    echo "# Date: $(date -u +'%F %T') UTC"
    say "Apply"
    run k apply -f "${OUT}/kk-payments-service.yaml"
    sleep 3
    say "Service"
    k get service kk-payments-service
    say "Endpoints (expected: two Pod IPs)"
    k get endpoints kk-payments-service
    k get pods -l app=kk-payments -o wide
    NODE_IP=$(minikube ip)
    say "External access through the NodePort"
    echo "\$ curl http://${NODE_IP}:${NODE_PORT}/health"
    RESP=$(curl -s --max-time 5 "http://${NODE_IP}:${NODE_PORT}/health"); echo "${RESP}"
    echo "${RESP}" | grep -q "\"version\":\"${IMAGE_TAG}\"" \
      && echo "PASS: version ${IMAGE_TAG} matches the deployed tag" || echo "FAIL: version does not match ${IMAGE_TAG}"
    say "In-cluster DNS (from inside a running Pod)"
    POD=$(k get pod -l app=kk-payments -o name | head -1)
    echo "\$ kubectl exec ${POD} -- wget -qO- http://kk-payments-service.default.svc.cluster.local:3001/health"
    k exec "${POD}" -- wget -qO- http://kk-payments-service.default.svc.cluster.local:3001/health; echo
  } 2>&1 | tee "${OUT}/service-output.txt"
}

# ─────────────────────────────────────────────────────────────────────────────
phase_heal() {
  NODE_IP=$(minikube ip)
  WATCH_LOG=$(mktemp); CURL_LOG=$(mktemp)
  {
    echo "# kk-payments self-healing measurement (fresh deployment)"
    echo "# Date: $(date -u +'%F %T') UTC"
    say "Pods before"
    k get pods -l app=kk-payments
    BEFORE=$(k get pods -l app=kk-payments -o jsonpath='{.items[*].metadata.name}')

    # Watch Pods and probe the Service in the background while the Pod is deleted
    ( k get pods -l app=kk-payments -w 2>&1 | while IFS= read -r l; do echo "[$(ts)] ${l}"; done ) > "${WATCH_LOG}" &
    WPID=$!
    ( while :; do c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://${NODE_IP}:${NODE_PORT}/health"); echo "[$(ts)] ${c}"; sleep 1; done ) > "${CURL_LOG}" &
    CPID=$!
    sleep 3

    VICTIM=$(k get pod -l app=kk-payments -o name | head -1)
    T0=$(date +%s); T0H=$(ts)
    echo "T0 (Pod deleted): ${T0H}   ${VICTIM}"
    k delete "${VICTIM}" --wait=false

    T1=""
    for _ in $(seq 1 120); do
      NOW=$(k get pods -l app=kk-payments --no-headers 2>/dev/null)
      READY=$(echo "${NOW}" | awk '$2=="1/1" && $3=="Running"' | wc -l)
      NEWPOD=$(echo "${NOW}" | awk '$2=="1/1" && $3=="Running" {print $1}' | grep -vxF -f <(echo "${BEFORE}" | tr ' ' '\n') | head -1)
      if [ "${READY}" -ge 2 ] && [ -n "${NEWPOD}" ]; then T1=$(date +%s); T1H=$(ts); break; fi
      sleep 1
    done
    sleep 3
    kill "${WPID}" "${CPID}" 2>/dev/null
    pkill -f "get pods -l app=kk-payments -w" 2>/dev/null
    wait 2>/dev/null

    [ -n "${T1}" ] || fail "replacement Pod did not become ready within 120s"
    echo "T1 (replacement Running and Ready): ${T1H}   pod/${NEWPOD}"
    HEAL=$(( T1 - T0 ))
    echo "Recovery time: ${HEAL} seconds"
    say "kubectl get pods -w (timestamped)"
    cat "${WATCH_LOG}"
    say "Pods after"
    k get pods -l app=kk-payments
    k get deployment kk-payments
    say "Service probe during the deletion (one request per second through the NodePort)"
    TOTAL=$(wc -l < "${CURL_LOG}"); OK=$(grep -c ' 200$' "${CURL_LOG}")
    echo "${OK}/${TOTAL} requests returned 200 while the Pod was replaced"
    grep -v ' 200$' "${CURL_LOG}" || echo "(no failed requests)"
    save SELF_HEAL_SECONDS "${HEAL}"
    save HEAL_REQUESTS_OK "${OK}/${TOTAL}"
  } 2>&1 | tee "${OUT}/self-healing-rerun.txt"
  rm -f "${WATCH_LOG}" "${CURL_LOG}"
}

# ─────────────────────────────────────────────────────────────────────────────
phase_audit() {
  read -rsp "Paste the Docker Hub token to search for it (input hidden, not saved): " TOKEN; echo
  {
    echo "# Credential audit for week8/friday"
    echo "# Date: $(date -u +'%F %T') UTC"
    cd "${REPO_ROOT}" || exit 1
    say "Check 1: token value in any file under week8/friday"
    if [ -n "${TOKEN}" ]; then grep -rlF -- "${TOKEN}" week8/ payments/ && echo "FAIL" || echo "PASS: no matches"; else echo "SKIPPED (no token entered)"; fi
    say "Check 2: token value anywhere in git history"
    if [ -n "${TOKEN}" ]; then [ -n "$(git log --all -S"${TOKEN}" --oneline)" ] && echo "FAIL" || echo "PASS: no commits contain it"; else echo "SKIPPED"; fi
    say "Check 3: Docker Hub token pattern (dckr_pat_) in tracked files"
    git grep -n 'dckr_pat_' && echo "FAIL" || echo "PASS: no matches"
    say "Check 4: no literal password/token values in the manifests"
    grep -niE 'password|token|secret' week8/friday/*.yaml | grep -v 'kijani-registry-credentials' && echo "FAIL" || echo "PASS: only the Secret name is referenced"
    say "Check 5: no Docker config, .env or .npmrc committed"
    git ls-files | grep -E '(^|/)(config\.json|\.env|\.npmrc)$' && echo "FAIL" || echo "PASS: none tracked"
  } 2>&1 | tee "${OUT}/credential-audit.txt"
  unset TOKEN
}

# ─────────────────────────────────────────────────────────────────────────────
phase_report() {
  load
  for v in SELF_HEAL_SECONDS BASELINE_MB PROD_MB REDUCTION_PCT; do
    [ -n "${!v:-}" ] || fail "${v} not measured yet (run build and heal)"
  done
  sed -i -e "s/{{SELF_HEAL_SECONDS}}/${SELF_HEAL_SECONDS}/g" -e "s/{{BASELINE_MB}}/${BASELINE_MB}/g" \
         -e "s/{{PROD_MB}}/${PROD_MB}/g" -e "s/{{REDUCTION_PCT}}/${REDUCTION_PCT}/g" "${OUT}/nia-comparison.md"
  grep -n '{{' "${OUT}/nia-comparison.md" && echo "Placeholders remain" || echo "nia-comparison.md filled"
  echo "Word count: $(wc -w < "${OUT}/nia-comparison.md")"
}

case "${1:-}" in
  check|reset|build|push|secret|deploy|service|heal|audit|report) "phase_$1" ;;
  all) for p in check reset build push secret deploy service heal audit report; do "phase_$p" || exit 1; done ;;
  *) sed -n '2,22p' "$0"; exit 1 ;;
esac
