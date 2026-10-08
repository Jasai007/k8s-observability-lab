#!/usr/bin/env bash
# =============================================================================
# cleanup.sh — remove everything deployed by deploy.sh, KEEP the cluster
# -----------------------------------------------------------------------------
#   bash scripts/cleanup.sh
#
# Deletes in reverse order (apps first, then tooling), including the
# cluster-scoped RBAC objects, then the namespaces themselves.
# After this the cluster is empty but still running — redeploy anytime with
# scripts/deploy.sh.
#
# To delete the cluster too: bash scripts/cluster-down.sh
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== Removing deployed components =="
for component in app otel tracing logging grafana alertmanager exporters prometheus; do
  if [ -d "deploy/$component" ]; then
    echo "  -> deploy/$component"
    kubectl delete -k "deploy/$component" --ignore-not-found 2>/dev/null \
      || echo "     (nothing to delete for $component)"
  fi
done

echo "== Removing namespaces (this deletes all pods inside them) =="
kubectl delete -f deploy/00-namespaces.yaml --ignore-not-found

echo "[DONE] cluster kept. Redeploy with: bash scripts/deploy.sh"
