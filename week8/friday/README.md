# Week 8 Friday: KijaniKiosk Container Delivery Pipeline

kk-payments built as a production image, pushed to a private registry with an
immutable version tag, run on Kubernetes (minikube) with 2 replicas behind a
NodePort Service, and checked for self-healing.

## Files

| File | Purpose |
|---|---|
| `Dockerfile.production` | Two-stage build: `node:22.23.3-alpine` builder, `alpine:3.22` + Node.js runtime, non-root `kijani` user, wget HEALTHCHECK, exec-form CMD |
| `Dockerfile.single-stage` | Baseline image, built only to measure the size reduction |
| `.dockerignore` | Excludes node_modules, .git, tests, .env files, dist (copied to `payments/.dockerignore` at build time, since `payments/` is the build context) |
| `kk-payments-deployment.yaml` | 2 replicas, requests and limits, `imagePullSecrets: kijani-registry-credentials`, image tag from this run |
| `kk-payments-service.yaml` | NodePort 30001 -> Pod port 3001, selector `app: kk-payments` |
| `run-week8.sh` | Runs each step and writes the evidence files below |
| `cluster-reset.txt` | Namespace cleared and image cache removed before starting |
| `build-verification.txt` | `--no-cache` builds, `docker images`, sizes, the five image tests |
| `registry-push.txt` | Version computation, push, delete local copy, pull back |
| `deploy-output.txt` | Pods READY, Deployment AVAILABLE 2 |
| `service-output.txt` | Endpoints with two Pod IPs, NodePort health check, in-cluster DNS check |
| `self-healing-rerun.txt` | Pod deletion, T0, T1, recovery time, Service probe during recovery |
| `credential-audit.txt` | No token in files, history or manifests |
| `nia-comparison.md` | Week 7 vs Week 8 for Nia, with the measured numbers |
| `measurements.env` | The numbers the scripts measured (sizes, reduction, recovery time) |

## Version string (Requirement 2)

Computed at build time, never typed by hand:

```bash
PKG_VERSION=$(node -p "require('./package.json').version")
GIT_SHORT=$(git rev-parse --short=7 HEAD)
IMAGE_TAG="${PKG_VERSION}-${GIT_SHORT}"
```

The tag is passed into the image as `APP_VERSION`, and `/health` returns it, so
the version seen through the Service is the same string as the registry tag.

## Registry choice (Integration Challenge C)

Docker Hub private repository, as used in class. Minikube reaches it over the
internet, so no `minikube image load` or insecure-registry restart is needed.
Pushing uses `docker login` with an access token over stdin. Pulling uses the
`kijani-registry-credentials` Secret, created at deploy time and never committed.

## Design decisions

- **Runtime base is `alpine:3.22` with the distro Node.js 22, not `node:22-alpine`.**
  The official Node image also ships npm, yarn and corepack, which makes it hard to keep the final image under 100MB.
  The builder still uses the same pinned `node:22.23.3-alpine` as the Week 5 Jenkins agent.
- **The production stage copies `node_modules` from the builder after `npm prune --omit=dev`**,
  so npm is not needed (or present) in the final image.
- **HEALTHCHECK `--start-period=30s`, `--interval=10s`** (Integration Challenge B): generous
  enough for startup, while still reaching healthy well inside 60 seconds.
- **`/health` now includes `version`** (one-line change in `payments/src/app.js`), so a tag
  mismatch between the manifest and what is running is visible immediately.

## Running it

```bash
export DOCKERHUB_USER=<username>
echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin
bash week8/friday/run-week8.sh check
bash week8/friday/run-week8.sh reset
bash week8/friday/run-week8.sh build
bash week8/friday/run-week8.sh push
bash week8/friday/run-week8.sh secret
bash week8/friday/run-week8.sh deploy
bash week8/friday/run-week8.sh service
bash week8/friday/run-week8.sh heal
bash week8/friday/run-week8.sh audit
bash week8/friday/run-week8.sh report
```
