# 05 — Application Metrics

> Module 5 of 11 · Prev: [04 — PromQL](04-promql.md) · Next: [06 — Alerting](06-alerting.md)

## Goal

Deploy the instrumented demo application, understand *where* its metrics come
from in code, and see application traffic appear in Prometheus and Grafana.

## Concepts

### What "instrumenting an app" means

The app itself counts things and exposes them over HTTP. In
[`apps/demo-api/main.go`](../apps/demo-api/main.go) (read it — every section
is commented):

```text
section 1  metric definitions        CounterVec / HistogramVec / Gauge
section 5  middleware                 records duration+status for EVERY request
section 6  handlers                   business counter orders_total{status=...}
section 7  main                       wires metrics endpoint + graceful shutdown
```

### The four metric types — as implemented here

| Type | Metric in the app | Question it answers |
|---|---|---|
| counter | `http_requests_total` | how many requests, by service/method/route/status? |
| histogram | `http_request_duration_seconds` | how slow, as percentiles? |
| gauge | `http_requests_in_flight` | how many right now? |
| counter (business) | `orders_total{status}` | is the *business* succeeding? |

### Labels used (and why they are safe)

```text
service  = "order" | "payment"      bounded by design (flag --service)
method   = GET | POST               bounded
route    = /api/orders | ... | other   TEMPLATE, never the raw URL (see normalizeRoute())
status   = 200 | 500 | ...          bounded set
```

`normalizeRoute()` in the code is the cardinality guard: unknown paths
collapse to `other` instead of creating a series per URL.

### The demo system

```text
                       DEPENDENCY_URL
  client ──> demo-api ──────────────────> demo-payment
             (order)  ── HTTP 502 when payment is down
             exposes /metrics on :8080
```

Fault injection for later labs: `/api/orders?fail=1` → HTTP 500,
`?slow=1` → ~2s latency.

## Step 1 — build the image

```bash
bash scripts/deploy.sh app
```

This runs `docker build -t demo-api:0.1.0 apps/demo-api` and
`kind load docker-image demo-api:0.1.0` (getting the image *into* the kind
node), then applies `deploy/app/`.

> No Docker daemon? Build elsewhere and `kind load` manually — the image name
> must be `demo-api:0.1.0`.

Expected:

```text
[1/3] building demo-api:0.1.0 ...
[2/3] loading demo-api:0.1.0 into kind cluster ...
[3/3] applying manifests ...
  -> deploy/app
deployment.apps/demo-api configured
deployment.apps/demo-payment configured
```

## Step 2 — verify the pods

```bash
kubectl -n demo get pods -o wide
```

Expected: `demo-api-... 1/1 Running` and `demo-payment-... 1/1 Running`.

If `ImagePullBackOff`: the image never reached the node — re-run
`kind load docker-image demo-api:0.1.0 --name observability-lab`.

## Step 3 — look at raw metrics from the app

```bash
kubectl -n demo port-forward svc/demo-api 8080:8080 &
curl -s localhost:8080/health
curl -s localhost:8080/api/orders
curl -s localhost:8080/api/orders          # again
curl -s localhost:8080/metrics | grep -E '^(http_requests_total|orders_total)'
```

Expected (shape):

```text
http_requests_total{method="GET",route="/api/orders",service="order",status="200"} 2
orders_total{service="order",status="success"} 2
```

## Step 4 — generate traffic and find it in Prometheus

Terminal A:

```bash
bash scripts/generate-load.sh        # ~5 req/s
```

Terminal B (port-forward Prometheus, open **/targets**):

```bash
bash scripts/port-forward.sh prometheus
```

Expected: a `demo-apps` job with two targets (`demo-api`, `demo-payment`)
state **UP**. Run in the Graph tab:

```promql
sum by (service) (rate(http_requests_total[5m]))
sum by (status) (rate(orders_total[5m]))
histogram_quantile(0.95, sum by (le, service) (rate(http_request_duration_seconds_bucket[5m])))
```

Expect: live non-zero values for `service="order"` (and `"payment"` once the
dependency call is exercised).

## Step 5 — watch it break (fault injection)

```bash
curl -s 'localhost:8080/api/orders?fail=1'     # one failing request
FAIL_PERCENT=40 bash scripts/generate-load.sh  # 40% errors for a while
```

Then in Prometheus:

```promql
sum by (service, status) (rate(http_requests_total[5m]))
```

Expected: `status="500"` series rises; the error-rate ratio turns red in
Grafana (**Demo API Overview** dashboard now has moving lines — that is the
module 03 "empty dashboard" finally coming alive).

## Verify — checklist

- [ ] Both demo pods `1/1 Running`
- [ ] `curl localhost:8080/metrics` shows `http_requests_total` growing
- [ ] Prometheus **/targets**: `demo-apps` has 2 UP targets
- [ ] Grafana **Demo API Overview**: traffic, error-rate and p95 panels move
- [ ] `FAIL_PERCENT=40` visibly raises the error-rate panel, and 0% lowers it

Stop the load generator (Ctrl-C) when done.

## Troubleshoot

| Symptom | Cause & fix |
|---|---|
| `demo-apps` job shows no targets | Service missing (`kubectl -n demo get svc`) or port not named `http` — re-apply `deploy/app` |
| `ImagePullBackOff` | image not loaded into kind — see Step 1 |
| Panels flat at 0 | no traffic — start `generate-load.sh`, or your port-forward points at the wrong port |
| Series missing for `service="payment"` | payment metrics appear only when demo-api calls it — that happens continuously in-cluster; check `kubectl -n demo logs deploy/demo-api` |
| Cardinality explosion in real life | you added a label like `order_id` — never do this; see `normalizeRoute()` |

## Cleanup

Keep the app running — modules 06–10 use it. Traffic generators: Ctrl-C.

## Key takeaways

1. Instrumentation belongs at the edge of the app: one middleware records
   every request once.
2. Metric names are nouns, labels are bounded dimensions, `route` is a
   template — not a raw URL.
3. Business metrics (`orders_total`) complement HTTP metrics: the process can
   be healthy while the business is failing (and vice versa).
4. `docker build` ≠ cluster access — kind needs `kind load`.

## Next

Make the system wake you up when it breaks: [06 — Alerting](06-alerting.md)

