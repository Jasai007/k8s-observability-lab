# 11 — Production Hardening & Capstone

> Module 11 of 11 · Prev: [10 — Golden signals & incident](10-golden-signals-incident.md) · Course complete!

## Goal

Two endings: (1) know exactly which lab shortcuts must never reach
production, (2) prove you own the whole system by rebuilding it from zero
and running one unscripted incident.

## Part A — Production hardening checklist

Every entry marks a deliberate lab shortcut in this repo. For each: know the
*lab setting*, the *production rule*, and the *failure it prevents*.

### 1. Resource management & backpressure

| Lab shortcut | Production rule | Failure prevented |
|---|---|---|
| modest limits on tools | requests+limits on EVERYTHING; CPU limits where noisy-neighbor matters | node OOM, evictions, noisy neighbors |
| ES `emptyDir` | persistent volumes + backups | data loss on restart |
| collector `memory_limiter` kept | keep it, tune `limit_percentage` for the pod limit | OOMKilled telemetry black hole |
| default batching | size `batch` from backend capacity; bound queues | memory blow-up, export storms |

**Saturation watchlist:** collector queue length, ES heap/disk, Prometheus
head series, node memory — the things that die *before* your app does.

### 2. Cardinality & retention

```bash
# current series count (do this BEFORE adding labels in real life):
# Grafana/Prometheus query:
prometheus_tsdb_head_series
sum by (__name__) (group by (__name__) (up))   # series per metric name
```

Rules:

- Label values must be a bounded set — never ids, URLs with ids, timestamps.
- Set retention deliberately: this lab uses `--storage.tsdb.retention.time=7d`;
  production balances **query window needs × disk budget**.
- Size disk for `series × samples × bytes` — measure with
  `prometheus_tsdb_storage_blocks_bytes`, do not guess.
- For logs: index lifecycle (ILM) — hot/warm/delete; do not index what you
  never query.

### 3. High availability & durability

```text
lab: 1 Prometheus, 1 ES, 1 Jaeger, in-memory/emptyDir
prod:
  metrics   2x Prometheus (replicas, distinct data) behind Thanos/Mimir/VictoriaMetrics,
            or remote_write to a central store
  logs      ES data nodes ≥3 (or managed), replicas>1
  traces    persistent storage + sampling (head 5-10%, always keep errors)
  alerts    Alertmanager cluster (3) — a single AM is a single point of silence
```

### 4. Security (all off in this lab, on in production)

```text
[x] xpack.security.enabled=false      -> TLS + authn/authz + sealed secrets
[x] Grafana admin/admin in YAML       -> Secret + SSO, change default passwords
[ ] plaintext OTLP (insecure: true)   -> mTLS / at least network policies
[ ] cluster-wide read RBAC            -> namespace-scoped where possible
[ ] no audit of who viewed what       -> audit logs (which you now collect!)
Never commit credentials; use Kubernetes Secrets / external secret managers.
```

### 5. The observability stack itself

- Alert on the monitor: `up == 0` (exists), `DeploymentUnavailable` (exists),
  collector `otelcol_exporter_send_failed_*`, ES cluster health, disk space.
- Test notifications quarterly — an alert route nobody verified is not a route.
- Budget cost per signal; traces and logs grow fastest — sample both.

### 6. Safe change management for telemetry

- Dashboards & alerts as code (you already do this — keep it).
- `validate.sh` in CI (exists) — config drift and broken YAML fail the build.
- Canary config changes to the Collector first; it fails fast by design.

## Part B — Capstone: own it end to end

### Act 1 — rebuild from zero (30 min, no peeking)

```bash
bash scripts/cleanup.sh        # remove everything, keep cluster
# NOW rebuild the platform using the docs as your only guide:
#   03 -> 05 -> 06 -> 07 -> 08 -> 09   (apply steps only)
bash scripts/validate.sh       # repo still healthy
```

Definition of done:

- [ ] Prometheus targets: prometheus, node-exporter, KSM, demo-apps, AM,
      otel-collector — all UP
- [ ] Grafana shows live Demo API Overview panels
- [ ] Kibana finds `service:order` documents
- [ ] Jaeger shows traces with two services (collector path!)
- [ ] An alert fires and resolves on demand

### Act 2 — unscripted incident (your instructor / a friend breaks it)

Someone breaks one of these **while you are not watching**:

```text
a) scale demo-payment to 0                     (dependency outage)
b) inject SLOW via a modified replica / load   (latency)
c) delete demo-api pod + forbid scheduling     (capacity)
d) break the collector env var                 (telemetry pipeline)
e) fill the disk / crush memory                (saturation)
```

You must deliver the incident timeline from module 10, using metrics → logs →
traces, within 15 minutes. Grade yourself:

| Score | Meaning |
|---|---|
| 5/5 | detected by ALERT, root-caused with all three signals, verified, timeline complete |
| 3-4 | found it, but jumped to `kubectl get pods` before reading signals |
| <3 | guessing — redo modules 06–10 |

### Act 3 — extend something (pick one)

1. Add a new alert + a Grafana panel for a metric you invented
   (e.g. `payment` dependency latency from the client span → use
   `spanmetrics` connector idea).
2. Add a second replica to `demo-api`, and show load balancing in traces
   (pod label in spans needs resource attributes — do it properly).
3. Write an SLO: "99% of orders < 1s monthly" — error budget alert included.
4. Move one lab shortcut to production grade (ES persistence + auth is the
   classic).

## The final architecture (what you can now explain unaided)

```text
demo-api ─┬─ /metrics ── Prometheus ── PromQL ── Grafana ── rules ──> Alertmanager
          │                    │  (service discovery via Kubernetes API + RBAC)
          │                    └── node-exporter, kube-state-metrics
          ├─ stdout JSON ── Fluent Bit ── Elasticsearch ── Kibana
          └─ OTLP ── OpenTelemetry Collector ─┬── Jaeger (traces)
                                              └── :8889 metrics (scraped back!)
        correlation keys: service name + trace_id + time window
```

## Cleanup / keep going

```bash
bash scripts/cleanup.sh      # remove components, keep cluster
bash scripts/cluster-down.sh # full teardown when you are done
```

Ideas beyond this repo: Prometheus Operator / kube-prometheus-stack (Helm),
Thanos or Mimir (long-term metrics), Loki (logs), Tempo (traces), Sentry or
OpenSearch Dashboards, eBPF-based auto-instrumentation, and the OpenTelemetry
Operator for Kubernetes.

## Key takeaways

1. Every lab shortcut here has a production counterpart — know both.
2. Cardinality, retention and saturation are the three ways observability
   stacks fail in the real world.
3. Rebuilding from zero is the real test of learning — tools you can only
   assemble with a tutorial, you do not yet own.
4. The goal was never "I installed Prometheus": it is
   *"an incident happened — I detected it, explained it, fixed it, proved it."*

## Done

Return to the [README](../README.md) — or revisit any module; the docs are
the reference.

