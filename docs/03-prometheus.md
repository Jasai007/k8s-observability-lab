# 03 — Prometheus & Grafana

> Module 3 of 11 · Prev: [02 — Environment setup](02-environment-setup.md) · Next: [04 — PromQL](04-promql.md)

## Goal

Deploy the metrics backbone (Prometheus), the two infrastructure exporters
(node-exporter, kube-state-metrics) and Grafana — then prove every target is
being scraped and every dashboard renders.

## Concepts

### Prometheus architecture

```text
                 (pull: HTTP GET /metrics every 15s)
  targets ─────────────────────────────┐
  ┌───────────────┐   ┌────────────┐   │
  │ node-exporter │   │    KSM     │   ▼
  └───────────────┘   └────────────┘ ┌──────────────────────────────┐
  ┌───────────────┐                  │  Prometheus                  │
  │  prometheus   │◄── scrapes ──────│  ├── scrape manager          │
  │  (itself :9090│                  │  ├── TSDB (time-series db)   │
  └───────────────┘                  │  ├── rule evaluator ──────► Alertmanager
                                     │  └── HTTP API :9090 /api/v1  │
                                     └──────────────┬───────────────┘
                                                    │ PromQL
                                                    ▼
                                              Grafana :3000
```

- **Pull model**: Prometheus *fetches* `/metrics` from each target. Simple,
  self-healing (a target that answers = a target that is alive), and it
  centralizes "where is data coming from".
- **Targets & jobs**: a *job* is a class of targets (e.g. `node-exporter`);
  each *target* is one endpoint. See `deploy/prometheus/prometheus.yml`.
- **Service discovery (SD)**: instead of hardcoding pod IPs (which change on
  every restart), Prometheus asks the Kubernetes API for Services/Endpoints.
  That is what the `kubernetes_sd_configs` blocks do — and why
  `deploy/prometheus/rbac.yaml` exists.
- **Time series & labels**: `up{job="node-exporter", instance="..."}` is one
  series; labels let you slice (`by (job)`), filter (`{job="..."}`) and join.

### The two exporters (easy to confuse)

```text
node-exporter      answers: "is the MACHINE healthy?"      reads /proc, /sys of the HOST
kube-state-metrics answers: "does the CLUSTER think my objects are healthy?"
                                       reads the Kubernetes API -> kube_* metrics
```

### Grafana

Provisioned **as code** (`deploy/grafana/`): datasource and dashboards are
files in git, mounted at startup — no UI clicks, nothing to lose.

## Architecture deployed in this module

```text
namespace: observability
├── prometheus        (Deployment + Service + RBAC, port 9090)
├── node-exporter     (DaemonSet, port 9100)
├── kube-state-metrics(Deployment, port 8080)
└── grafana           (Deployment, port 3000, admin/admin)
```

## Step 1 — deploy Prometheus

```bash
kubectl apply -k deploy/prometheus
kubectl -n observability rollout status deploy/prometheus --timeout=120s
```

Expected: `deployment "prometheus" successfully rolled out`.

What got created (read `deploy/prometheus/` afterwards):

1. `rbac.yaml` — ServiceAccount + ClusterRole: *permission to list
   Services/Endpoints/Pods for discovery, read-only*.
2. `kustomization.yaml` — generates the `prometheus-config` and
   `prometheus-rules` ConfigMaps from the files next to it.
3. `deployment.yaml` — flags, probes, resource limits, volume mounts.
4. `service.yaml` — stable DNS: `prometheus.observability.svc:9090`.

## Step 2 — deploy the exporters

```bash
kubectl apply -k deploy/exporters
kubectl -n observability get pods -o wide
```

Expected: `prometheus-... 1/1 Running`, `node-exporter-<node> ... 1/1 Running`
(one per node), `kube-state-metrics-... 1/1 Running`.

## Step 3 — verify the scrape pipeline

```bash
kubectl -n observability port-forward svc/prometheus 9090:9090 &
```

Open **http://localhost:9090/targets** — every target must be `UP`:

```text
prometheus            localhost:9090          UP
node-exporter         :9100                   UP
kube-state-metrics    :8080                   UP
```

Or from the terminal:

```bash
curl -s 'localhost:9090/api/v1/targets' | head -c 400
curl -s 'localhost:9090/api/v1/query?query=up' | head -c 400
```

Expected JSON contains `"state":"up"` for each target.

## Step 4 — see real metrics

In the Prometheus UI **Graph** tab (or via API), run:

```promql
up                                    # 1 = healthy target
node_cpu_seconds_total                # raw counter (huge, per CPU + mode)
100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))
                                      # % CPU busy, last 5 min
kube_deployment_status_replicas_available{namespace="demo"}
                                      # KSM: 0/0 series until module 05!
```

Expected: the CPU query returns a number 0–100; `up` returns 1 per target.

## Step 5 — deploy Grafana

```bash
kubectl apply -k deploy/grafana
kubectl -n observability rollout status deploy/grafana --timeout=120s
bash scripts/port-forward.sh grafana     # leave it running
```

Open **http://localhost:3000** → login `admin` / `admin`.

Verify **provisioning** (config-as-code worked):

1. *Connections → Data sources* → exactly one: **Prometheus**
   (url `http://prometheus.observability.svc:9090`).
2. *Dashboards → Observability* → **Demo API Overview**.
   Panels are empty/flat for now — there is no application traffic yet.
   That is expected and fixed in module 05.

## Verify — checklist

```bash
kubectl -n observability get deploy,pods                 # all 4 deployments Ready
kubectl -n observability get svc prometheus grafana      # ClusterIPs exist
curl -s localhost:9090/api/v1/query?query=count\(up\)    # (port-forward first)
```

- [ ] Prometheus **/targets** shows 3 UP targets
- [ ] `up == 1` query returns a value per target
- [ ] Grafana datasource health = **OK** (click "Save & test")
- [ ] Node CPU query returns live numbers

## Troubleshoot

| Symptom | Cause & fix |
|---|---|
| Pod `CreateContainerConfigError` | ConfigMap name mismatch — re-run `kubectl apply -k deploy/prometheus` |
| `FailedMount ... configmap "prometheus-config/rules" not found` | namespace mismatch: Pod in `observability` looks there, ConfigMap landed in `default` — happens when applying with plain `kubectl apply -f` (skips `configMapGenerator`) or an outdated checkout. Fix: `kubectl delete configmap prometheus-config prometheus-rules -n default; kubectl delete -k deploy/prometheus; kubectl apply -k deploy/prometheus` |
| Prometheus log: `server returned HTTP 403` on discovery | RBAC missing — `kubectl apply -k deploy/prometheus` applied the ClusterRole? check `kubectl get clusterrole prometheus` |
| Target shows `context deadline exceeded` | pod or resources overloaded — `kubectl -n observability top pods`, raise limits |
| Target `connection refused` after pod restart | SD has not refreshed yet — wait ~30s, refresh /targets |
| Grafana panels say "No data" | correct at this stage: no app deployed yet (module 05) |
| `deploy/prometheus` fails: `error loading ...` | always apply via `kubectl apply -k <dir>` — plain `kubectl apply -f` on a kustomization dir does not generate ConfigMaps |
| CrashLoopBackOff on prometheus | config syntax error — `kubectl -n observability logs deploy/prometheus | head -30` |

## Cleanup

Not needed — later modules build on this. (Full teardown:
`bash scripts/cleanup.sh`.)

## Key takeaways

1. Prometheus pulls `/metrics` on a schedule; targets are discovered through
   the Kubernetes API, never hardcoded.
2. RBAC exists because discovery is an API call — least privilege in action.
3. node-exporter = machine health; kube-state-metrics = object health.
4. Grafana config lives in git; the pod is disposable.

## Next

Learn to actually query the data: [04 — PromQL](04-promql.md)

