# 04 — PromQL (Querying Metrics)

> Module 4 of 11 · Prev: [03 — Prometheus & Grafana](03-prometheus.md) · Next: [05 — Application metrics](05-application-metrics.md)

## Goal

Turn operational questions into PromQL. This module is hands-on: every query
below is meant to be pasted into the Prometheus UI (**Graph** tab) or the
Grafana *Explore* view.

## Concepts in one page

```text
metric_name{label="value", ...}      selector: which series?

instant vector   a snapshot NOW      up
range vector     a window of past    rate(http_requests_total[5m])

rate(x[5m])        per-second average growth of a counter over 5m
increase(x[5m])    total growth over 5m (rate * 300)
histogram_quantile(q, buckets)   percentile from a histogram
sum by (labels) (...)   aggregate, keeping only "labels"
avg / max / min / count / topk / bottomk
```

**Mental model:**

```text
question  ->  which counter/gauge/histogram?  ->  window/rate?  ->  aggregate by what?
   │                                                                     │
 "how fast are             http_requests_total                 sum by (service)
  orders coming in?"       (a counter)                         rate(...[5m])
```

**Rules that save you from wrong answers:**

1. Counters only make sense with `rate()`/`increase()` — raw counters just
   climb forever.
2. The range (`[5m]`) should be ≥ 4× your scrape interval (15s → ≥1m; 5m is
   comfortable and smooths noise).
3. `rate()` of a reset (pod restart) is still correct — Prometheus handles
   counter resets.
4. Division by zero yields `NaN`, and comparisons with `NaN` are false —
   "no traffic" will not trigger your error-rate alert.

## Hands-on: 8 queries that matter

Port-forward first and open **http://localhost:9090/graph**:

```bash
bash scripts/port-forward.sh prometheus
```

### 1. Is every target being scraped?

```promql
up
```

Expect: one series per target, value `1`. A `0` means scrape failure.

### 2. How busy is the node's CPU?

```promql
100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))
```

Expect: a % 0–100 per node. Notice `mode="idle"` filtering and
`avg by (instance)` aggregation.

### 3. How much memory is free?

```promql
100 * node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
```

Expect: percent per node. (Instant queries — no `rate` needed: gauges are
already "current values".)

### 4. Are my deployments fully available?

```promql
kube_deployment_status_replicas_available{namespace=~"observability|demo"}
```

Expect: one series per deployment with its available replica count.

### 5. How many pods have crash-looped in the last 15 minutes?

```promql
increase(kube_pod_container_status_restarts_total[15m]) > 0
```

Expect: only pods that actually restarted. This is alert `PodCrashLooping`
material (see `deploy/prometheus/rules/learning.yml`).

### 6. Top 5 series by memory usage — the `topk` pattern

```promql
topk(5, node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes)
```

Expect: five largest memory consumers (on a single-node lab: just the node —
the pattern is what matters).

### 7. Prometheus' own scrape health

```promql
rate(prometheus_target_scrapes_exceeded_sample_limit_total[5m])
prometheus_tsdb_head_series
sum by (job) (prometheus_target_interval_length_seconds_count)
```

Expect: the middle query shows how many active series Prometheus stores —
your first cardinality number (module 11).

### 8. Range queries (Graph, not just numbers)

In the UI select **Range** with `step = 1m`:

```promql
rate(node_cpu_seconds_total{mode="user"}[5m])
```

Expect: a line chart per instance — this is what dashboards render.

## From query to alert (connection to module 06)

An alert is exactly these queries plus `for:` and labels:

```promql
# "error rate > 20%" only makes sense once demo-api exists (module 05)
sum by (service) (rate(http_requests_total{status=~"5.."}[5m]))
  /
sum by (service) (rate(http_requests_total[5m]))
  > 0.2
```

Compare with the live rules: **Alerts** tab in the Prometheus UI, or open
`deploy/prometheus/rules/learning.yml`.

## Bonus concept: recording rules

Recording rules pre-compute expensive expressions and store them under a new
name (prefixed with a convention like `job:`):

```yaml
# hypothetical — see deploy/prometheus/rules/learning.yml for the real rules
- record: job:http_requests_rate5m
  expr: sum by (job) (rate(http_requests_total[5m]))
```

Use them when a query is slow, used by many dashboards, or needed at a fine
alerting interval. The trade-off: extra storage.

## Verify — checklist

- [ ] All 8 queries above return sensible values (no `no data` except app ones)
- [ ] A Range graph renders node CPU movement
- [ ] You can explain every clause of query 2 out loud
- [ ] The **Alerts** tab lists the rules from `learning.yml` (state: inactive)

## Troubleshoot

| Symptom | Cause & fix |
|---|---|
| `no data` for kube_* metrics | exporters not deployed — module 03 |
| Instant `rate()` returns nothing | no data in that window / wrong labels — check `up` and metric existence first with a bare selector |
| `unexpected end of input` in query | unbalanced braces/parens — typical after editing; re-check `[5m]` placement |
| Weird spikes at pod restarts | you graphed a raw counter — wrap in `rate()` |
| Query works in UI, alert does not fire | alert needs `for:` to elapse — wait, or check the **Alerts** tab state (pending vs firing) |

## Cleanup

None — queries are read-only.

## Key takeaways

1. Question → metric type → window → aggregation. Always in that order.
2. Counters need `rate()`; gauges do not; histograms need
   `histogram_quantile()`.
3. `by (...)` decides your x-axis/legend — pick label sets that are bounded.
4. NaN comparisons are false: silence ≠ success for statistical queries you
   *want* to fire.

## Next

Instrument an application and watch these concepts come alive:
[05 — Application metrics](05-application-metrics.md)

