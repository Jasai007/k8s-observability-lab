#!/usr/bin/env bash
# =============================================================================
# doctor.sh — check that everything this project needs is installed
# -----------------------------------------------------------------------------
# Run this FIRST. It never changes anything, it only reports:
#   [OK]      tool present
#   [MISSING] tool required but not installed (with install hint)
#   [WARN]    tool installed but not usable right now
#
#   bash scripts/doctor.sh
#
# Windows: run scripts from Git Bash (or WSL), not PowerShell.
# =============================================================================
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== Observability lab doctor =="

# --- required command-line tools ---------------------------------------------
check_required() {
  local name="$1" hint="$2"
  if command -v "$name" >/dev/null 2>&1; then
    echo "[OK]      $name -> $(command -v "$name")"
  else
    echo "[MISSING] $name — $hint"
  fi
}

check_required git    "install: https://git-scm.com/downloads"
check_required docker "install Docker Desktop (docker.com) or the docker engine"
check_required kubectl "install: https://kubernetes.io/docs/tasks/tools/"
check_required kind   "install: go install sigs.k8s.io/kind@latest   (or download the kind binary)"
check_required curl   "preinstalled on macOS/Linux; on Windows use Git Bash"
check_required jq     "optional but recommended: brew install jq / choco install jq"

echo
echo "-- optional (only needed to build/run the demo app yourself) --"
if command -v go >/dev/null 2>&1; then
  echo "[OK]      go -> $(go version | cut -d' ' -f3)"
else
  echo "[MISSING] go — not required: scripts/deploy.sh builds the image via Docker"
fi

echo
echo "-- daemon / cluster status --"
if docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
  echo "[OK]      Docker daemon running (version $(docker version --format '{{.Server.Version}}'))"
else
  echo "[WARN]    Docker daemon not reachable — start Docker Desktop / dockerd"
fi

if command -v kind >/dev/null 2>&1; then
  if kind get clusters 2>/dev/null | grep -qx 'observability-lab'; then
    echo "[OK]      kind cluster 'observability-lab' exists"
    kubectl --context kind-observability-lab cluster-info 2>/dev/null \
      | sed 's/^/          /' || echo "[WARN]    cluster exists but kubectl cannot reach it"
  else
    echo "[WARN]    no cluster yet — create it with: bash scripts/cluster-up.sh"
  fi
fi

echo
echo "== Next: bash scripts/cluster-up.sh =="
