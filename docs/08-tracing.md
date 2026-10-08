# 08 — Distributed Tracing

> Module 8 of 11 · Prev: [07 — Logging (EFK)](07-logging.md) · Next: [09 — OpenTelemetry Collector](09-opentelemetry-collector.md)

## Goal

Turn tracing on for the demo app, send traces straight to Jaeger, and learn
to *read* a distributed trace — including the cross-service hop from
`demo-api` to `demo-payment`.

## Concepts

### Trace, span, context

```text
trace  = the whole journey of ONE request through ALL services
span   = one unit of work inside that trace (a handler, a DB call, an HTTP hop)
       has: name, start, duration, status, parent, attributes/events

trace-id  4bf92f...   shared by every span of the request
span-id   00f067...   unique per span; parent-span-id links the tree

demo-api                                   demo-payment
┌──────────────────────────────┐   HTTP    ┌─────────────────────┐
│ [SERVER] HTTP GET /api/orders│──────────>│[SERVER] /api/payment│
│  └─ orders.validate          │  trace    │  └─ payment.charge  │
│     (child span)             │ propagation│    (child span)    │
└──────────────────────────────┘           └─────────────────────┘
         one trace-id stitches both services together
```

**Context propagation** is the magic: demo-api injects the trace context
into HTTP headers (`traceparent`), demo-payment extracts it and *continues*
the same trace instead of starting a new one. In code:
`otel.GetTextMapPropagator().Inject/Extract` in `main.go`.

### OTLP — the OpenTelemetry wire protocol

```text
app (OTel SDK) ──OTLP/gRPC :4317──> backend (Jaeger in this module)
                    OTLP/HTTP :4318 (alternative)
```

OTLP is vendor-neutral: the *same* app code can send traces to Jaeger today
and to an OTel Collector tomorrow (that is exactly module 09).

### Why the app can run "tracing off"

`OTEL_EXPORTER_OTLP_ENDPOINT` is empty by default → the SDK is a cheap no-op.
One env var turns tracing on — same image, same pods.

## Step 1 — deploy Jaeger

```bash
kubectl apply -k deploy/tracing
kubectl -n observability rollout status deploy/jaeger --timeout=120s
```

Jaeger v2 all-in-one: storage + UI (`:16686`) + OTLP intake (`:4317`).

## Step 2 — switch tracing on for both services

```bash
kubectl -n demo set env deploy/demo-api     OTEL_EXPORTER_OTLP_ENDPOINT=jaeger.observability.svc:4317
kubectl -n demo set env deploy/demo-payment OTEL_EXPORTER_OTLP_ENDPOINT=jaeger.observability.svc:4317
kubectl -n demo rollout status deploy/demo-api --timeout=120s
kubectl -n demo rollout status deploy/demo-payment --timeout=120s
```

Confirm the new process knows about it:

```bash
kubectl -n demo logs deploy/demo-api --tail 5 | grep tracing
```

Expected: `"msg":"tracing enabled","otlp_endpoint":"jaeger.observability.svc:4317"`.

## Step 3 — create traces

```bash
bash scripts/port-forward.sh demo-api &     # terminal A (if not forwarded yet)
bash scripts/generate-load.sh               # terminal B: steady traffic
```

Each `/api/orders` request now produces a trace spanning both pods.

## Step 4 — read a trace in Jaeger

```bash
bash scripts/port-forward.sh jaeger         # http://localhost:16686
```

1. *Service* = **order** (the `service.name` resource attribute), *Find Traces*.
2. Click any trace → you get the span waterfall:

```text
order: HTTP GET /api/orders            240ms  (SERVER span)
 ├─ orders.validate                     60ms
 └─ GET http://demo-payment:8080/...   170ms  (CLIENT span)
     payment: HTTP GET /api/payment    168ms  (SERVER span, other service)
      └─ payment.charge                 95ms
```

Things to notice:

- One **trace id** across two services = propagation worked.
- The CLIENT span in `order` and SERVER span in `payment` represent the same
  network hop — their durations bracket the network latency.
- Total ≈ sum of children on the critical path — the waterfall shows exactly
  **where the time went**.

## Step 5 — look at a failing trace

```bash
curl -s 'localhost:8080/api/orders?fail=1'       # injected app error
kubectl -n demo scale deploy/demo-payment --replicas=0   # broken dependency
bash scripts/generate-load.sh                    # -> HTTP 502s
```

In Jaeger: find recent **order** traces with error status (red). The last
span before the failure shows `payment ... connection refused` / status
error → root cause visible in one click. Scale back:

```bash
kubectl -n demo scale deploy/demo-payment --replicas=1
```

## Step 6 — correlate log ↔ trace (the payoff)

```bash
bash scripts/port-forward.sh kibana
```

In Kibana, open an ERROR document from the failing period, find `trace_id`,
copy it. In Jaeger: *Search by Trace ID*. The log line and the full span
tree are the same event, two views — this is **signal correlation**.

## Verify — checklist

- [ ] `logs` show `tracing enabled` for both deployments
- [ ] Jaeger lists service `order` AND `payment` (two services = real
      distributed tracing, not just spans in one process)
- [ ] A trace contains spans from both services under one trace-id
- [ ] An error trace points at the failing hop
- [ ] A Kibana `trace_id` opens the matching trace in Jaeger

## Troubleshoot

| Symptom | Cause & fix |
|---|---|
| No traces at all in Jaeger | env not applied or pods not restarted — check `kubectl -n demo get deploy demo-api -o jsonpath='{.spec.template.spec.containers[0].env}'` and re-run Step 2 |
| Traces missing after enabling | exporter batches every ~5s — wait, then refresh; also generate fresh traffic (old requests are gone) |
| Only `demo-api` spans, no `demo-payment` | `DEPENDENCY_URL` env missing (it is set in `deploy/app/deployment.yaml` — re-apply) or payment pod down |
| Traces vanished after a while | Jaeger storage is **in-memory** in this lab — restarts clear it (module 11 discusses durable storage) |
| Wrong service name in Jaeger | it comes from the `service.name` resource attribute / `--service` flag |
| Still nothing | port 4317 conflict: `kubectl -n observability get svc jaeger` must show `4317/TCP`; check app logs for OTLP connection errors |

## Cleanup

Tracing stays on for modules 09–11 (module 09 only changes the *endpoint*).

## Key takeaways

1. A trace is a tree of spans sharing one trace-id; context propagation
   (headers) is what makes it *distributed*.
2. OTLP is the neutral transport — backends are interchangeable.
3. CLIENT + SERVER spans around one call let you separate network time from
   work time.
4. `trace_id` in logs is the bridge between signals — always emit it.

## Interview questions

1. What travels in a `traceparent` header? What happens if it is stripped?
2. Sampled vs unsampled tracing — why is 100% sampling expensive?
3. What is the difference between a span and a trace?
4. How would you trace a message-queue consumer (no HTTP headers)?
5. Why does the client span usually start slightly before / end slightly
   after the server span?

## Next

Unify collection through one pipeline:
[09 — OpenTelemetry Collector](09-opentelemetry-collector.md)

