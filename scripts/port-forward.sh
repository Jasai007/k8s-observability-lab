#!/usr/bin/env bash
# =============================================================================
# port-forward.sh — open a browser tunnel to one of the lab UIs
# -----------------------------------------------------------------------------
#   bash scripts/port-forward.sh prometheus     # http://localhost:9090
#   bash scripts/port-forward.sh grafana        # http://localhost:3000  admin/admin
#   bash scripts/port-forward.sh alertmanager   # http://localhost:9093
#   bash scripts/port-forward.sh jaeger         # http://localhost:16686
#   bash scripts/port-forward.sh kibana         # http://localhost:5601
#   bash scripts/port-forward.sh demo-api       # http://localhost:8080
#
# Ctrl-C stops the tunnel (the pod keeps running).
# =============================================================================
set -euo pipefail

case "${1:-}" in
  prometheus)    kubectl -n observability port-forward svc/prometheus     9090:9090 ;;
  grafana)       kubectl -n observability port-forward svc/grafana        3000:3000 ;;
  alertmanager)  kubectl -n observability port-forward svc/alertmanager   9093:9093 ;;
  jaeger)        kubectl -n observability port-forward svc/jaeger         16686:16686 ;;
  kibana)        kubectl -n observability port-forward svc/kibana         5601:5601 ;;
  elasticsearch) kubectl -n observability port-forward svc/elasticsearch  9200:9200 ;;
  demo-api)      kubectl -n demo port-forward svc/demo-api                8080:8080 ;;
  *)
    echo "Usage: $0 {prometheus|grafana|alertmanager|jaeger|kibana|elasticsearch|demo-api}"
    exit 1
    ;;
esac
