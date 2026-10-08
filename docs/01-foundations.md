# 01 — Observability Foundations

> Module 1 of 11 · No deploy · Next: [02 — Environment setup](02-environment-setup.md)

## Goal

Understand what observability *is*, how it differs from monitoring, and what
the three signals (metrics, logs, traces) are each good for — before touching
any tool.

## Why this matters

When a service is slow, two very different questions come up:

```text
"Is the service healthy?"   -> monitoring: compare against known thresholds
"Why is it slow right now?" -> observability: explore data you did not plan
                               to need, to find an unknown cause
```

**Monitoring** checks known failure modes against known signals.
**Observability** is the ability to *ask new questions* of a system from the
outside, without shipping new code.

You get that ability by instrumenting the system to produce three kinds of
**telemetry** — and by keeping them **correlatable** (same trace id, same
service name, same time window).

## The three signals

```text
                what happened?          where did time go?
                     │                        │
   what is happening?│                        │
        │            │                        │
        ▼            ▼                        ▼
     METRICS        LOGS                    TRACES
   numbers over   one line per           one record per
      time          event                 request journey
        │            │                        │
   "traffic is     "payment failed:      "request spent 800ms
    up 40%"         connection refused"    in inventory, 50ms
                                          in payments"
```

| Signal | Best for | Shape | Cost | Tool in this repo |
|---|---|---|---|---|
| **Metrics** | *Is it broken? How much / how fast?* — alerting, dashboards, capacity | numbers with labels, aggregated, fixed cardinality | low | Prometheus → Grafana |
| **Logs** | *Why did THIS thing fail?* — forensics, audit | discrete JSON lines, unbounded detail | medium | Fluent Bit → Elasticsearch → Kibana |
| **Traces** | *Where did this one request spend time?* — latency of a call chain | span tree per request, sampled | high | OpenTelemetry → Jaeger |

Key intuition:

```text
Metrics tell you THAT something is wrong.
Logs   tell you WHAT went wrong.
Traces tell you WHERE in the request path it went wrong.
```

They are useless in isolation during an incident — the skill you build in
this course is **correlation**: jump from an alert → the metric graph → the
matching logs → the exact trace, using shared ids (`service`, `trace_id`).

## Instrumentation

**Instrumentation** = adding code that emits telemetry. In this repo the demo
service (`apps/demo-api/main.go`) shows all three in one file:

```text
metrics   -> promhttp.Handler()          (module 05)
logs      -> log/slog, JSON + trace_id   (module 07)
traces    -> OpenTelemetry SDK -> OTLP   (module 08)
```

Two instrumentation styles you will meet:

- **Automatic** — agents add metrics without code changes
  (node-exporter, kube-state-metrics).
- **Manual/library** — your code emits signals (the Go app, most APM agents).

## Metrics vocabulary (used from module 03 on)

```text
time series = metric name + labels    e.g. http_requests_total{service="order",status="500"}
counter     monotonically increasing  e.g. total requests since process start
gauge       value that goes up/down   e.g. in-flight requests, CPU %
histogram   distribution of values    e.g. latency buckets -> percentiles
label       a bounded dimension       NEVER unbounded (no user ids, no request ids)
scrape      one pull of /metrics from one target
```

**Cardinality rule** (the one that saves production systems): every label
value combination creates a separate time series. `route="/api/orders"` = a
handful of series; `request_id="a1b2..."` = millions of series = dead
Prometheus. Module 05 shows the guard in code; module 11 covers the fallout.

## SLIs, SLOs and error budgets

```text
SLI   (indicator)  the measurement:       "95% of requests answered in < 300ms"
SLO   (objective)  the target for an SLI: "95% of requests < 300ms over 30 days"
error budget       allowed unreliability: 100% - SLO = 5% of requests may be slow/failed
```

The error budget bridges reliability and product velocity:
budget left → ship features; budget spent → stop shipping, fix reliability.

## The four Golden Signals (preview of module 10)

```text
Latency     how long a request takes (separate success from failure!)
Traffic     how much demand (requests/s, jobs/s)
Errors      requests that failed (5xx, timeouts, wrong results)
Saturation  how "full" the busiest resource is (CPU, memory, queue depth)
```

A starting framework for *services*, not a replacement for your own SLIs.
Module 10 drives an actual incident with them.

## The architecture you are building

```text
             ┌─────────────── namespace: demo ─────────────────┐
             │  demo-api ────HTTP────> demo-payment            │
             └───────┼─────────────────────────────────────────┘
                     │ scrape /metrics │ tail logs │ OTLP traces
      ┌──────────────┼─────────────────┼───────────┼───────────────┐
      ▼              ▼                 ▼           ▼               │
 Prometheus     Fluent Bit ──> Elasticsearch    Jaeger  <──────────┘
      │                             │             │
      ▼                             ▼             ▼
   Grafana                      Kibana        trace UI
      │
      └── rules ──> Alertmanager (notifications)
        (all tools in namespace: observability)
```

## Cleanup

Nothing was deployed in this module.

## Key takeaways

1. Monitoring answers known questions; observability enables unknown ones.
2. Metrics, logs and traces complement each other — correlation is the skill.
3. Bounded labels only; cardinality is the classic production failure.
4. SLIs/SLOs make "reliable enough" a number instead of an opinion.

## Interview questions

1. Monitoring vs observability — give a question only observability can answer.
2. Which signal do you reach for first when p95 latency spikes, and why?
3. What is a counter vs a gauge? Why must a counter never be reset randomly?
4. Define SLI, SLO and error budget. What does an exhausted budget change in
   your team's behaviour?
5. What is cardinality, and what happens when a label is unbounded?

## Next

Set up your machine and cluster: [02 — Environment setup](02-environment-setup.md)

