# 09 — OpenTelemetry Collector (Unified Telemetry)

> Module 9 of 11 · Prev: [08 — Distributed tracing](08-tracing.md) · Next: [10 — Golden signals & incident](10-golden-signals-incident.md)

## Goal

Insert the OpenTelemetry Collector between the apps and the backends —
apps now export to *one* address, the Collector fans out to *all* backends.
You will also see the three telemetry signals flowing through one pipeline.

## Concepts

### Why a Collector?

Without it (module 08), every app hardcodes its backend:

```text
  apps ──────────────────────────────> Jaeger          # coupling
  apps  (would need config per tool) > every backend    # N x config, N x creds
```

With it (this module):

```text
                    ┌── metrics ──> Prometheus-style endpoint (:8889)
  apps ── OTLP ──>  │-- traces  ──> Jaeger
  (one address)     └── logs    ──> Collector's own log (debug exporter)
                     Collector = receive -> process -> export
```

Benefits: **vendor-neutral apps**, central batching/retries, enrichment,
sampling and filtering in one place, backends can change without touching a
single application.

### Component model (current OpenTelemetry terms)

```text
RECEIVERS    how data gets in      otlp (gRPC 4317 / HTTP 4318), prometheus, filelog...
PROCESSORS   shape the data        memory_limiter*, batch*, attributes, filter, sampling...
EXPORTERS    where data goes       otlp, prometheus, debug (formerly "logging")...
CONNECTORS   bridge pipelines      e.g. spanmetrics (trace -> metrics)
EXTENSIONS   non-pipeline helpers  health_check, pprof, zpages...
```

Config lives in `deploy/otel/collector.yaml` — read it; it is ~60 lines and
fully commented. (`memory_limiter` first + `batch` last is the standard
shape of every pipeline.)

## Step 1 — deploy the Collector

```bash
kubectl apply -k deploy/otel
kubectl -n observability rollout status deploy/otel-collector --timeout=120s
kubectl -n observability logs deploy/otel-collector --tail 20
```

Expected log excerpt: the collector starts and reports its pipelines
(receivers/processors/exporters for traces, metrics, logs).

## Step 2 — repoint the apps at the Collector

One env var change — this is the payoff of using OTLP:

```bash
kubectl -n demo set env deploy/demo-api     OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector.observability.svc:4317
kubectl -n demo set env deploy/demo-payment OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector.observability.svc:4317
kubectl -n demo rollout status deploy/demo-api --timeout=120s
kubectl -n demo rollout status deploy/demo-payment --timeout=120s
```

## Step 3 — watch telemetry flow through the pipeline

```bash
bash scripts/generate-load.sh                                   # terminal A
kubectl -n observability logs deploy/otel-collector -f          # terminal B
```

Expected: periodic `Traces` telemetry log lines (exporter batch summaries)
while traffic runs. Stop with Ctrl-C on both.

## Step 4 — prove the backend still works

```bash
bash scripts/port-forward.sh jaeger
```

Jaeger still receives traces — but now the path is
`app → collector → jaeger`. Same data, new hop. Compare:

```text
module 08:  app ──────────────────────────> jaeger
module 09:  app ──> otel-collector ───────> jaeger
                                └──────────> metrics exporter :8889
```

## Step 5 — the Collector's own metrics

The collector exposes Prometheus metrics about itself (spans received/
exported, queue sizes) on port `8889` — and the `observability` scrape job in
`prometheus.yml` discovers it automatically (Service port is named
`metrics`).

```bash
bash scripts/port-forward.sh prometheus
```

**/targets** → job `observability` should now include
`otel-collector ... UP`. Query:

```promql
otelcol_receiver_accepted_spans
otelcol_exporter_sent_spans
```

Expect: counters growing while traffic runs. These "telemetry about the
telemetry pipeline" catch problems the app cannot see (queue full, export
failures) — observability of the observability stack (module 11).

## Step 6 — (exercise) modify the pipeline

Add a processor and watch it take effect — the skill, not the exact feature:

1. Edit `deploy/otel/collector.yaml`, add `resource` processor with a custom
   attribute, include it in the traces pipeline between `memory_limiter` and
   `batch`.
2. `kubectl apply -k deploy/otel`
3. Restart traffic → inspect the next trace in Jaeger for the new resource
   attribute.

(An invalid key fails fast at startup — read the pod logs: that
fail-fast-then-fix loop is daily life with collector configs.)

## Verify — checklist

- [ ] `otel-collector` pod Running, logs show pipelines loaded
- [ ] App logs show the new endpoint (`tracing enabled ... otel-collector...`)
- [ ] Jaeger still receives traces (via collector now)
- [ ] Prometheus target `observability / otel-collector` is UP
- [ ] `otelcol_receiver_accepted_spans` grows during traffic
- [ ] Collector logs show batch exports (traces pipeline active)

## Troubleshoot

| Symptom | Cause & fix |
|---|---|
| Collector exits immediately | config error — `kubectl -n observability logs deploy/otel-collector` prints the exact YAML problem |
| Apps cannot connect | env typo / rollout not finished — check `kubectl -n demo get pods` restart counts and app logs |
| No spans in `otelcol_receiver_accepted_spans` | apps still point at Jaeger directly — re-run Step 2 |
| Jaeger empty but collector receives spans | exporter target wrong: `otlp/jaeger` endpoint must be `jaeger.observability.svc:4317` (see `collector.yaml`) |
| Port 4317 conflict confusion | both jaeger and otel-collector expose 4317 — they are *different Services*; apps must address the right one |
| Collector CPU high | batching too small / too much debug logging — tune `batch` and `debug` verbosity |

## Cleanup

None — this is the final architecture (module 11 hardens it).

## Key takeaways

1. Collector = receive → process → export; apps only ever know one address.
2. OTLP (4317 gRPC / 4318 HTTP) is the standard ingress for modern telemetry.
3. `memory_limiter` first, `batch` last: the canonical pipeline shape.
4. Backends become swappable; sampling, filtering and enrichment get
   centralized — this is what "unified observability" means concretely.
5. Observability stacks need their own observability (`otelcol_*` metrics).

## Interview questions

1. DaemonSet vs sidecar vs gateway deployment modes for a Collector — pick
   one for this lab and justify it.
2. What is the difference between the `debug` exporter and the old `logging`
   exporter? (Renaming — component names evolve; check current docs.)
3. When would you use a `filter` processor? When is it the wrong place?
4. What is a connector (e.g. spanmetrics) and why is it not "just a
   processor"?
5. How do you troubleshoot "spans accepted but not exported"?

## Next

Use every signal together during a real failure:
[10 — Golden signals & incident response](10-golden-signals-incident.md)

