# Documentation — learning path

Eleven modules that take you from "what is a metric?" to running a full
observability platform and handling a real incident. Every module follows the
**same structure** so you always know where you are:

```text
Goal -> Concepts -> Architecture -> Step by step -> Verify -> Troubleshoot
     -> Cleanup -> Key takeaways -> Interview questions
```

## The path

| # | Module | You deploy | You learn |
|---|--------|-----------|-----------|
| 01 | [Foundations](01-foundations.md) | — | metrics vs logs vs traces, SLIs/SLOs, golden signals |
| 02 | [Environment setup](02-environment-setup.md) | kind cluster | toolchain, namespaces, kubectl survival kit |
| 03 | [Prometheus & Grafana](03-prometheus.md) | Prometheus, node-exporter, kube-state-metrics, Grafana | scrape model, targets, service discovery, dashboards |
| 04 | [PromQL](04-promql.md) | — | querying: rate, histograms, aggregation |
| 05 | [Application metrics](05-application-metrics.md) | demo-api, demo-payment | instrumentation, counters/gauges/histograms, cardinality |
| 06 | [Alerting](06-alerting.md) | Alertmanager + rules | alert anatomy, firing, grouping, silencing |
| 07 | [Logging (EFK)](07-logging.md) | Elasticsearch, Kibana, Fluent Bit | structured logs, collection pipeline, log search |
| 08 | [Distributed tracing](08-tracing.md) | Jaeger | spans, propagation, OTLP, reading a trace |
| 09 | [OpenTelemetry Collector](09-opentelemetry-collector.md) | OTel Collector | receive → process → export, unified telemetry |
| 10 | [Golden signals & incident](10-golden-signals-incident.md) | — | detect → investigate → fix → verify (RCA) |
| 11 | [Hardening & capstone](11-production-capstone.md) | — | production checklist, rebuild-from-zero capstone |

**Do them in order.** Each module assumes the previous ones are deployed —
and the skills build the same way: you cannot read a trace before you
understand what a service is, and you cannot correlate signals you have
never seen individually.

## How this repo maps to the 7-day reference course

This project follows the excellent
[iam-veeramalla/observability-zero-to-hero](https://github.com/iam-veeramalla/observability-zero-to-hero)
course, but reorganized into a self-contained, runnable reference:

| Reference course day | This repo |
|---|---|
| Day 1 — Observability concepts | Module 01 |
| Day 2 — Prometheus + Grafana setup | Modules 02–03 |
| Day 3 — PromQL | Module 04 |
| Day 4 — Instrumentation & alerting | Modules 05–06 |
| Day 5 — Logging with EFK | Module 07 |
| Day 6 — Distributed tracing (Jaeger) | Module 08 |
| Day 7 — OpenTelemetry / unified observability | Module 09 |
| (extensions) | Modules 10–11: incident response, hardening, capstone |

## Design decisions (why the repo looks the way it does)

1. **Components first, integration later.** Prometheus, logs and traces are
   learned individually before they are correlated — debugging three tools at
   once teaches nothing.
2. **Plain YAML + kustomize, no Helm charts.** Every manifest is short enough
   to read end-to-end. Config files are embedded via `configMapGenerator`,
   so each component folder is one self-contained unit.
3. **One namespace for tooling, one for the app.** `observability` vs `demo`
   keeps `kubectl` commands short while still showing app/platform separation.
4. **Pull-based metrics with Prometheus** — scraping, service discovery and
   PromQL remain core skills even in an OpenTelemetry world.
5. **EFK for logging** (course Day 5 parity): Fluent Bit → Elasticsearch →
   Kibana. OpenTelemetry *Logs* is discussed in module 09, not required.
6. **OTLP everywhere for traces**, gRPC on 4317 — the official OpenTelemetry
   default. Apps first talk to Jaeger directly (module 08), then through the
   Collector (module 09) so you can feel the difference.
7. **Port names are a contract:** every scrapable Service port is named
   `metrics` (app ports are named `http`), which is what the relabel rules in
   `prometheus.yml` match on.
8. **Versions are pinned and documented** (see root README) — labs that work
   tomorrow need fixed images, not `latest`.

## Conventions used in every module

- **Commands** are copy-pasteable from the repository root.
- **Expected output** is shown right under each command.
- **Troubleshoot** sections list the failures we actually hit while writing
  this repo — start there before opening a search engine.
- UIs are reached with `scripts/port-forward.sh <name>` and Ctrl-C closes
  the tunnel.
