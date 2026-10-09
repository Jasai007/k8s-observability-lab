# Observability & Monitoring — Zero to Hero

A hands-on, self-contained reference for learning observability on Kubernetes
**from fundamentals to incident response**. You deploy every tool yourself,
with commented manifests, guided labs, and a demo application that emits all
three telemetry signals.

> **The goal is not "I installed Prometheus."**
> The goal is: *an incident happened — I detected it from metrics, explained
> it from logs, located it with traces, fixed it, and proved the fix.*

Based on the 7-day course
[iam-veeramalla/observability-zero-to-hero](https://github.com/iam-veeramalla/observability-zero-to-hero),
restructured into 11 runnable modules with full implementation steps.

## What you build

```text
             ┌─────────────── namespace: demo ─────────────────┐
             │  demo-api ────HTTP────> demo-payment            │
             │  (Go, instrumented: metrics + JSON logs + OTLP) │
             └───────┼───────────┼───────────────┼─────────────┘
                     │           │               │
              scrape /metrics    │ tail logs     │ OTLP traces
                     │           │               │
             ┌───────▼───────────▼───────────────▼─────────────┐
             │        namespace: observability                 │
             │                                                │
             │  Prometheus ──rules──> Alertmanager             │
             │     │                                          │
             │     ├── node-exporter (host metrics)            │
             │     ├── kube-state-metrics (cluster objects)    │
             │     │                                          │
             │     ▼                                          │
             │  Grafana (provisioned dashboards)               │
             │                                                │
             │  Fluent Bit ──> Elasticsearch ──> Kibana        │
             │                                                │
             │  Jaeger <── OpenTelemetry Collector <── apps    │
             └────────────────────────────────────────────────┘
```

## Quick start

```bash
# 0. check your machine (Docker, kubectl, kind, Git Bash on Windows)
bash scripts/doctor.sh

# 1. create the local Kubernetes cluster (~2 min)
bash scripts/cluster-up.sh

# 2. follow the labs in order — starting here:
#    docs/01-foundations.md  (concepts, no deploy)
#    docs/03-prometheus.md   (first deploy: kubectl apply -k deploy/prometheus)
...
# or deploy the entire stack at once (capstone / impatient mode):
bash scripts/deploy.sh
```

Open the UIs any time: `bash scripts/port-forward.sh {prometheus|grafana|alertmanager|jaeger|kibana}`

> **Windows:** run all scripts from **Git Bash** (or WSL), not PowerShell.

## Learning path

| # | Module (in `docs/`) | Deploy | You learn |
|---|---|---|---|
| 01 | [Foundations](docs/01-foundations.md) | — | metrics vs logs vs traces, SLIs/SLOs, golden signals |
| 02 | [Environment setup](docs/02-environment-setup.md) | kind cluster | toolchain, namespaces, kubectl |
| 03 | [Prometheus & Grafana](docs/03-prometheus.md) | prometheus, exporters, grafana | scrape model, service discovery, dashboards |
| 04 | [PromQL](docs/04-promql.md) | — | rate, histograms, aggregation, recording rules |
| 05 | [Application metrics](docs/05-application-metrics.md) | demo-api, demo-payment | instrumentation, cardinality, fault injection |
| 06 | [Alerting](docs/06-alerting.md) | alertmanager | rules, pending→firing, grouping, silences |
| 07 | [Logging (EFK)](docs/07-logging.md) | elasticsearch, kibana, fluent-bit | structured logs, collection pipeline, search |
| 08 | [Distributed tracing](docs/08-tracing.md) | jaeger | spans, propagation, OTLP, reading a trace |
| 09 | [OTel Collector](docs/09-opentelemetry-collector.md) | otel-collector | receive → process → export, unified telemetry |
| 10 | [Golden signals & incident](docs/10-golden-signals-incident.md) | — | detect → investigate → fix → verify → document |
| 11 | [Hardening & capstone](docs/11-production-capstone.md) | — | production checklist, rebuild-from-zero, unscripted drill |

Every module uses the same shape: **Goal → Concepts → Architecture → Steps
(with expected output) → Verify → Troubleshoot → Cleanup → Takeaways →
Interview questions.** See [docs/README.md](docs/README.md) for the full
guide and design decisions.

## Prerequisites

| Tool | Minimum | Why |
|---|---|---|
| Docker | 24+ (daemon running) | runs kind nodes, builds demo image |
| kubectl | 1.28+ | applies manifests, debugging |
| kind | 0.22+ | local cluster |
| Git Bash / WSL (Windows) | — | all scripts are bash |
| Go 1.24+ (optional) | — | run app locally without Docker |
| 8 GB free RAM | — | Elasticsearch alone wants ~2–3 GB |

Check everything at once: `bash scripts/doctor.sh`

## Repository structure

```text
apps/demo-api/        Go service: metrics + JSON logs + OTLP traces (one file, commented)
deploy/
  00-namespaces.yaml  observability + demo namespaces (apply first)
  prometheus/         Prometheus + RBAC + Service + rules (configMapGenerator)
  exporters/          node-exporter + kube-state-metrics
  alertmanager/       Alertmanager + routing config
  grafana/            Grafana + provisioned datasource + dashboard
  app/                demo-api + demo-payment Deployments + Services
  logging/            Elasticsearch + Kibana + Fluent Bit (DaemonSet)
  tracing/            Jaeger all-in-one (OTLP on :4317)
  otel/               OpenTelemetry Collector (OTLP in, Jaeger + Prometheus out)
docs/                 11 guided modules — the actual course (start at 01)
scripts/              doctor, cluster-up/down, deploy, port-forward, generate-load, cleanup, validate
```

Design rule: **each `deploy/<component>` is self-contained** — `kubectl apply -k`
one folder and it works, because config files ride along via
`configMapGenerator`. No Helm, no hidden templating.

## Pinned versions

| Component | Image |
|---|---|
| Prometheus | `prom/prometheus:v3.13.3` |
| Alertmanager | `prom/alertmanager:v0.32.2` |
| Grafana | `grafana/grafana:12.4.12` |
| node-exporter | `prom/node-exporter:v1.12.1` |
| kube-state-metrics | `registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.20.0` |
| Elasticsearch / Kibana | `docker.elastic.co/...:9.5.5` (both must match) |
| Fluent Bit | `fluent/fluent-bit:5.1.3` |
| Jaeger | `jaegertracing/jaeger:2.22.0` |
| OTel Collector | `otel/opentelemetry-collector-contrib:0.162.0` |
| demo-api base | `golang:1.26-alpine` → `alpine:3.22` runtime |

Pinned on purpose: labs must work next month, not just today.

## Two ways to work through this repo

**Guided (recommended):** follow `docs/01` → `docs/11` in order. Each module
tells you exactly which `kubectl apply -k deploy/<x>` to run, what output to
expect, and how to verify — then how to break and fix it.

**Full-stack (impatient / capstone):**

```bash
bash scripts/cluster-up.sh
bash scripts/deploy.sh          # builds image + deploys all 8 components
bash scripts/port-forward.sh grafana
```

## Validate (same check as CI)

```bash
bash scripts/validate.sh
# == ALL CHECKS PASSED ==
```

Checks: required files exist → YAML/JSON parse → every `deploy/*`
renders via kustomize → `bash -n` on scripts → `gofmt` + `go vet` +
`go build` on the app → no placeholder artifacts.

## Cleanup

```bash
bash scripts/cleanup.sh       # remove everything deployed, keep the cluster
bash scripts/cluster-down.sh  # delete the cluster entirely
```

