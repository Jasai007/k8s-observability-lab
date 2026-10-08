#!/usr/bin/env bash
# =============================================================================
# cluster-up.sh — create the local Kubernetes cluster (kind)
# -----------------------------------------------------------------------------
# kind runs a Kubernetes cluster inside Docker containers — no cloud account,
# no hypervisor, throwaway by design.
#
#   bash scripts/cluster-up.sh
#
# Takes ~1-2 minutes (pulls the node image on first run).
# =============================================================================
set -euo pipefail

CLUSTER_NAME="observability-lab"

if ! command -v kind >/dev/null 2>&1; then
  echo "[ERROR] kind is not installed."
  echo "        go install sigs.k8s.io/kind@latest"
  echo "        (or see https://kind.sigs.k8s.io/docs/user/quick-start/)"
  exit 1
fi

if ! docker version >/dev/null 2>&1; then
  echo "[ERROR] Docker daemon is not running — start Docker Desktop first."
  exit 1
fi

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "[SKIP] cluster '$CLUSTER_NAME' already exists"
else
  echo "[1/2] creating kind cluster '$CLUSTER_NAME' ..."
  kind create cluster --name "$CLUSTER_NAME" --wait 120s
fi

echo "[2/2] waiting for the node to be Ready ..."
kubectl --context "kind-$CLUSTER_NAME" wait --for=condition=Ready node --all --timeout=120s

kubectl --context "kind-$CLUSTER_NAME" cluster-info
echo
echo "[DONE] cluster is up. Next: follow docs/02-environment-setup.md"
