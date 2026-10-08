#!/usr/bin/env bash
# =============================================================================
# deploy.sh — build the app image (if needed) and apply manifests
# -----------------------------------------------------------------------------
#   bash scripts/deploy.sh                 # deploy EVERYTHING
#   bash scripts/deploy.sh prometheus      # deploy one component
#   bash scripts/deploy.sh grafana otel    # deploy two components
#
# What it does:
#   1. builds demo-api:0.1.0 (skipped when Docker is unavailable)
#   2. loads the image into the kind cluster (kind load)
#   3. applies namespaces, then the requested components (kubectl apply -k)
#   4. waits for the core pods to become Ready
#
# Components (folder names under deploy/):
#   prometheus exporters alertmanager grafana app logging tracing otel
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CLUSTER_NAME="observability-lab"
IMAGE="demo-api:0.1.0"

# Default = full stack (the capstone / quick-start path).
if [ -z "${1:-}" ]; then
  COMPONENTS=(prometheus exporters alertmanager grafana app logging tracing otel)
else
  COMPONENTS=("$@")
fi

# --- 1. build the demo image --------------------------------------------------
if docker version >/dev/null 2>&1; then
  echo "[1/3] building $IMAGE ..."
  docker build -t "$IMAGE" apps/demo-api
else
  echo "[1/3] SKIP: Docker daemon not reachable — cannot build $IMAGE"
fi

# --- 2. make the image visible to the cluster ---------------------------------
if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "[2/3] loading $IMAGE into kind cluster '$CLUSTER_NAME' ..."
  kind load docker-image "$IMAGE" --name "$CLUSTER_NAME"
else
  echo "[2/3] SKIP: no kind cluster (minikube users: minikube image load $IMAGE)"
fi

# --- 3. apply manifests --------------------------------------------------------
echo "[3/3] applying manifests ..."
kubectl apply -f deploy/00-namespaces.yaml

for component in "${COMPONENTS[@]}"; do
  if [ ! -d "deploy/$component" ]; then
    echo "[ERROR] unknown component '$component' (expected a folder under deploy/)"
    exit 1
  fi
  echo "  -> deploy/$component"
  kubectl apply -k "deploy/$component"
done

# --- 4. wait for the important pods (best effort, capped time) -----------------
echo
echo "Waiting for rollouts (Ctrl-C does NOT undo the deployment) ..."
wait_rollout() { kubectl -n "$1" rollout status "deploy/$2" --timeout=180s 2>/dev/null || echo "  [WARN] $1/$2 not ready yet"; }
wait_rollout observability prometheus
wait_rollout observability grafana
wait_rollout demo demo-api
wait_rollout demo demo-payment

echo
echo "[DONE] deployed: ${COMPONENTS[*]}"
echo "       check:    kubectl get pods -A"
echo "       UIs:      bash scripts/port-forward.sh {prometheus|grafana|...}"
