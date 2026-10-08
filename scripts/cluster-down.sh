#!/usr/bin/env bash
# =============================================================================
# cluster-down.sh — delete the kind cluster and EVERYTHING in it
# -----------------------------------------------------------------------------
#   bash scripts/cluster-down.sh
#
# Use scripts/cleanup.sh first if you only want to remove the deployed
# components but keep the cluster.
# =============================================================================
set -euo pipefail

CLUSTER_NAME="observability-lab"

if ! command -v kind >/dev/null 2>&1; then
  echo "[ERROR] kind is not installed"
  exit 1
fi

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  kind delete cluster --name "$CLUSTER_NAME"
  echo "[DONE] cluster '$CLUSTER_NAME' deleted"
else
  echo "[SKIP] cluster '$CLUSTER_NAME' does not exist"
fi
