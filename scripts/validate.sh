#!/usr/bin/env bash
# =============================================================================
# validate.sh — verify the REPOSITORY is healthy (no cluster needed)
# -----------------------------------------------------------------------------
# Runs in CI on every push. Checks, in order:
#   1. required files exist
#   2. every YAML file parses
#   3. every JSON file parses
#   4. every deploy/ component renders through kustomize
#   5. shell scripts are syntactically valid (bash -n)
#   6. Go app: gofmt clean, go vet passes, go build passes
#   7. no leftover placeholder text / AI citation artifacts
#
#   bash scripts/validate.sh
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FAILURES=0
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }
ok()   { echo "  [OK]   $1"; }

# Find a WORKING python interpreter (on Windows the `python` on PATH is often
# just a Microsoft-Store stub that exits with an error — probe for that).
find_python() {
  local cand
  for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import sys' >/dev/null 2>&1; then
      echo "$cand"
      return 0
    fi
  done
  if command -v py >/dev/null 2>&1 && py -3 -c 'import sys' >/dev/null 2>&1; then
    echo "py -3"
    return 0
  fi
  return 1
}
PY="$(find_python || true)"

echo "== 1/7 required files =="
required=(
  README.md
  docs/README.md
  docs/01-foundations.md
  docs/02-environment-setup.md
  docs/11-production-capstone.md
  scripts/doctor.sh
  scripts/validate.sh
  deploy/00-namespaces.yaml
  deploy/prometheus/kustomization.yaml
  deploy/prometheus/prometheus.yml
  deploy/prometheus/rules/learning.yml
  deploy/alertmanager/alertmanager.yml
  deploy/otel/collector.yaml
  deploy/logging/fluent-bit.conf
  apps/demo-api/main.go
  apps/demo-api/Dockerfile
)
for f in "${required[@]}"; do
  if [ -f "$f" ]; then ok "$f"; else fail "$f missing"; fi
done

echo "== 2/7 YAML parses =="
# $PY may be "py -3" (two words) — deliberately unquoted when invoked.
if [ -n "$PY" ] && $PY -c "import yaml" 2>/dev/null; then
  yaml_files=$(find deploy .github -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
  # NOTE: $yaml_files is deliberately unquoted so paths split into separate
  # arguments (no path in this repo contains spaces).
  if $PY - $yaml_files <<'PYEOF'
import sys, yaml
bad = 0
for path in sys.argv[1:]:
    try:
        list(yaml.safe_load_all(open(path, encoding="utf-8")))
    except Exception as exc:
        print(f"    {path}: {exc}")
        bad += 1
sys.exit(1 if bad else 0)
PYEOF
  then ok "all YAML files parse"; else fail "YAML syntax errors (above)"; fi
else
  echo "  [SKIP] PyYAML not installed (pip install pyyaml)"
fi

echo "== 3/7 JSON parses =="
if [ -n "$PY" ]; then
  json_files=$(find deploy -type f -name '*.json' 2>/dev/null)
  if [ -n "$json_files" ] && $PY -c "
import json, sys
[json.load(open(p, encoding='utf-8')) for p in sys.argv[1:]]
" $json_files; then
    ok "all JSON files parse"
  else
    fail "JSON syntax errors"
  fi
else
  echo "  [SKIP] no working python interpreter found"
fi

echo "== 4/7 kustomize renders every component =="
if command -v kubectl >/dev/null 2>&1; then
  for dir in deploy/*/; do
    [ -f "$dir/kustomization.yaml" ] || continue
    if kubectl kustomize "$dir" >/dev/null 2>&1; then
      ok "$dir"
    else
      fail "$dir does not render (kubectl kustomize $dir)"
    fi
  done
else
  echo "  [SKIP] kubectl not found"
fi

echo "== 5/7 shell script syntax =="
for s in scripts/*.sh; do
  if bash -n "$s" 2>/dev/null; then ok "$s"; else fail "$s has syntax errors"; fi
done

echo "== 6/7 Go app =="
if command -v go >/dev/null 2>&1; then
  pushd apps/demo-api >/dev/null || exit 1
  if [ -n "$(gofmt -l .)" ]; then fail "gofmt needed: $(gofmt -l .)"; else ok "gofmt clean"; fi
  if go vet ./... >/dev/null 2>&1; then ok "go vet"; else fail "go vet failed"; fi
  if go build -o /dev/null . 2>/dev/null; then ok "go build"; else fail "go build failed"; fi
  popd >/dev/null || exit 1
else
  echo "  [SKIP] go not found"
fi

echo "== 7/7 no placeholder / artifact text =="
# These came from earlier drafts; they must never resurface.
if grep -rn --include='*.md' --include='*.yml' --include='*.yaml' \
     -e 'turn0search' -e 'YOUR_GITHUB_USERNAME' -e 'will be added' README.md docs deploy 2>/dev/null; then
  fail "placeholder or citation artifacts found (see lines above)"
else
  ok "no artifacts"
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "== ALL CHECKS PASSED =="
  exit 0
else
  echo "== $FAILURES CHECK(S) FAILED =="
  exit 1
fi
