# 10 — Golden Signals & Incident Response

> Module 10 of 11 · Prev: [09 — OpenTelemetry Collector](09-opentelemetry-collector.md) · Next: [11 — Hardening & capstone](11-production-capstone.md)

## Goal

Run a full incident drill with everything you have built:
**detect** with metrics → **investigate** with logs → **locate** with traces
→ **fix** → **verify** → **document**. No new tools — this module is about
method.

## Concepts

### The four Golden Signals, mapped to this repo

| Signal | Dashboard panel / query | Alert in `learning.yml` |
|---|---|---|
| **Latency** | p95 `histogram_quantile(0.95, ...)` | `DemoHighLatencyP95` |
| **Traffic** | `sum(rate(http_requests_total[5m]))` | — (watch, don't alert) |
| **Errors** | error rate %, `status=~"5.."` | `DemoHighErrorRate`, `DemoPaymentDependencyFailing` |
| **Saturation** | node CPU/memory; in-flight requests | `NodeHighCPU`, `NodeLowMemory` |

### The investigation loop

```text
   ALERT / DASHBOARD
         │  what changed, when, for which service?
         ▼
   METRICS ── narrow it: errors? latency? which status? since when?
         │
         ▼
   LOGS   ── what do the error lines say? (Kibana: level=ERROR, same window)
         │
         ▼
   TRACES ── which hop failed / was slow? (Jaeger: error or slow traces)
         │
         ▼
   ROOT CAUSE  ->  FIX  ->  VERIFY (metrics return to baseline, alert resolves)
```

Always write the **timeline**: *T0 first symptom, T1 detected, T2 root cause,
T3 fixed, T4 verified*. That document is the deliverable of this module.

## The scenario

A dependency (`demo-payment`) dies. Symptoms: orders start failing with
HTTP 502, error-rate metric spikes, alert fires, business metric drops.

**You will not be told what broke** — you start at the alert, like real life.

## Step 1 — prepare observability

```bash
# three windows (or tabs):
bash scripts/port-forward.sh grafana       # window 1: dashboards
bash scripts/port-forward.sh prometheus    # window 2: rules/alerts (optional)
bash scripts/generate-load.sh              # window 3: steady traffic
```

Confirm green baseline in **Demo API Overview**: error rate ≈ 0%, latency
flat, traffic steady.

## Step 2 — break it (simulator = a colleague's bad deploy)

```bash
kubectl -n demo scale deploy/demo-payment --replicas=0
```

Optionally amplify: `FAIL_PERCENT=50 bash scripts/generate-load.sh`
(restart the generator with this).

## Step 3 — DETECT (metrics, ≤ 2 minutes)

Answer, out loud, in order:

1. *What changed?* → error-rate panel jumps to 100% (or 50%+), traffic line
   may stay flat (requests still arrive — they fail).
2. *Which service?* → `service="order"` (the caller), NOT `payment` —
   note this: metrics often show the *scream*, not the *cause*.
3. *When?* → hover the panel; note T0.
4. *Is an alert firing?* → Prometheus **Alerts** tab:
   `DemoPaymentDependencyFailing` firing; Alertmanager received it.

## Step 4 — INVESTIGATE with logs (Kibana, ≤ 3 minutes)

```bash
bash scripts/port-forward.sh kibana
```

Discover → filter window around T0:

```text
level : "ERROR" and service : "order"
```

Read the message: `payment dependency failed ... dial tcp ... connection
refused`. **Hypothesis: the payment service is unreachable** (not slow —
*refused*, which means "not listening / not there", not "overloaded").

Confirm scope: `kubernetes.namespace : "demo"` — any errors from `payment`
itself? (None: it is not crashing loudly, it is *gone*.)

## Step 5 — LOCATE with traces (Jaeger, ≤ 3 minutes)

```bash
bash scripts/port-forward.sh jaeger
```

Find recent **error traces** of service `order`. The waterfall ends in:

```text
[SERVER] HTTP GET /api/orders       502 (red)
 └─ GET http://demo-payment...      error: connection refused   <- THE HOP
     (no child spans — the call never completed)
```

The failing hop is the client span to `demo-payment` — root cause located:
**dependency down**, evidenced by all three signals.

## Step 6 — FIX

```bash
kubectl -n demo scale deploy/demo-payment --replicas=1
kubectl -n demo get pods -l app=demo-payment -w     # wait for 1/1 Running
```

Diagnosis→action check: was the *fix* derived from evidence? (Scale-up is
correct for "connection refused to a scaled-to-zero deployment"; a memory
OOM would have needed a different fix.)

## Step 7 — VERIFY (do not skip this)

1. Traffic generator: errors stop climbing (`requests=... errors=...` flat).
2. Grafana: error-rate panel returns to ~0%, latency flattens.
3. Prometheus **Alerts**: alert → **resolved**.
4. Kibana: no new `level:ERROR` for `service:order`.
5. Jaeger: latest traces are green, span to payment succeeds.

## Step 8 — DOCUMENT (the actual artifact)

Fill this in — it is what "handling an incident" produces:

```markdown
# Incident: order service 502s — <date>

- Impact:   X% of orders failed for ~N minutes (error-rate panel)
- T0:       14:03 first errors on Grafana (Errors signal)
- T1:       14:04 DemoPaymentDependencyFailing fired (alert)
- T2:       14:06 Kibana: "connection refused" -> hypothesis: payment gone
- T3:       14:08 Jaeger: client span to demo-payment fails -> confirmed
- Cause:    demo-payment scaled to 0 (bad deploy / manual scale)
- Fix:      scale deployment back to 1 (14:09)
- Verify:   14:11 error rate 0%, alert resolved, traces green
- Prevention: alert on replicas_available == 0 (exists: DeploymentUnavailable),
              require min-replicas / PDB for demo-payment, block manual scale
```

## Variant drills (try them for extra practice)

| Break this | Detect with | Investigate with |
|---|---|---|
| `SLOW_PERCENT=100 generate-load.sh` (latency) | p95 panel / `DemoHighLatencyP95` | traces: which span grew? (orders.validate) |
| `kubectl -n demo delete pod -l app=demo-api` (crash) | KSM `DeploymentUnavailable` / pod restarts | `kubectl logs` + Kibana for the dead pod's last lines |
| `kubectl -n observability scale deploy/prometheus --replicas=0` | your dashboards go dark | who watches the watchmen? (module 11: monitoring the monitor) |
| Memory pressure: raise load + lower limits | `NodeLowMemory` | node-exporter gauges, pod evicted events |

## Verify — checklist

- [ ] You started from the alert/dashboard, NOT from the break
- [ ] All four Golden Signals were checked at least once
- [ ] Log line → trace_id → trace worked at least once
- [ ] Incident timeline written (Step 8)
- [ ] System verified healthy after the fix (all four signals)

## Troubleshoot

| Symptom | Cause & fix |
|---|---|
| Alert did not fire | load too low or `for:` not elapsed — check PromQL manually, keep traffic running ≥3m |
| Jaeger shows no error traces | traces still point... generate fresh failing traffic after the break; confirm collector/app logs |
| Kibana shows nothing for the window | widen the time picker; verify Fluent Bit is running (`kubectl -n observability ds fluent-bit`) |
| You "fixed" it by deleting the alert | anti-pattern — silencing ≠ resolving; the drill requires a real fix |

## Cleanup

```bash
kubectl -n demo scale deploy/demo-payment --replicas=1
# Ctrl-C all port-forwards and the load generator
```

## Key takeaways

1. Detect with metrics (fast, cheap), explain with logs (context), prove
   with traces (the hop) — in that order.
2. The service that *screams* is often not the service that *broke*.
3. Evidence before action; verification after action; timeline always.
4. Golden Signals are a checklist for "what should I even look at?".

## Next

Harden it all and prove you own the stack:
[11 — Production hardening & capstone](11-production-capstone.md)

