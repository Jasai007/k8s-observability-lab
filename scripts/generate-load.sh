#!/usr/bin/env bash
# =============================================================================
# generate-load.sh — send continuous traffic to the demo app
# -----------------------------------------------------------------------------
# Everything observable needs traffic. This script is the traffic generator
# used by several modules:
#
#   bash scripts/generate-load.sh                      # healthy traffic
#   FAIL_PERCENT=30 bash scripts/generate-load.sh      # 30% of requests -> ?fail=1 (HTTP 500)
#   SLOW_PERCENT=20 bash scripts/generate-load.sh      # 20% of requests -> ?slow=1 (2s latency)
#
# Prerequisites:
#   kubectl -n demo port-forward svc/demo-api 8080:8080   (or scripts/port-forward.sh demo-api)
# Ctrl-C to stop.
#
# Tunables (environment variables):
#   BASE_URL       target, default http://localhost:8080
#   INTERVAL       seconds between requests, default 0.2  (5 req/s)
#   FAIL_PERCENT   0-100, chance a request carries ?fail=1
#   SLOW_PERCENT   0-100, chance a request carries ?slow=1
# =============================================================================
set -u

BASE_URL="${BASE_URL:-http://localhost:8080}"
INTERVAL="${INTERVAL:-0.2}"
FAIL_PERCENT="${FAIL_PERCENT:-0}"
SLOW_PERCENT="${SLOW_PERCENT:-0}"

echo "Sending traffic to $BASE_URL every ${INTERVAL}s"
echo "  FAIL_PERCENT=$FAIL_PERCENT  SLOW_PERCENT=$SLOW_PERCENT"
echo "  (Ctrl-C to stop)"

count=0
errors=0
while true; do
  query=""
  # $RANDOM is 0..32767 — scale it to a percentage.
  if [ "$FAIL_PERCENT" -gt 0 ] && [ $(( RANDOM % 100 )) -lt "$FAIL_PERCENT" ]; then
    query="?fail=1"
  elif [ "$SLOW_PERCENT" -gt 0 ] && [ $(( RANDOM % 100 )) -lt "$SLOW_PERCENT" ]; then
    query="?slow=1"
  fi

  # -s silent, -o discard body, -w write status code only
  status=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/api/orders${query}" || echo "000")
  count=$((count + 1))
  if [ "$status" -ge 500 ] || [ "$status" = "000" ]; then
    errors=$((errors + 1))
  fi
  printf '\r  requests=%s errors=%s last_status=%s' "$count" "$errors" "$status"

  sleep "$INTERVAL"
done
