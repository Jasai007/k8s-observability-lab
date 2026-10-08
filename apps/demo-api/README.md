# demo-api — the instrumented service used by every module

A deliberately tiny "order service" that emits **all three observability
signals**, so you can see where each signal comes from in one file:

| Signal   | Where it comes from                          | Where you look at it        |
|----------|----------------------------------------------|-----------------------------|
| Metrics  | `GET /metrics` (prometheus/client_golang)    | Prometheus / Grafana        |
| Logs     | stdout, structured JSON (`log/slog`)         | Kibana                      |
| Traces   | OTLP gRPC (OpenTelemetry), optional         | Jaeger                      |

> Read [`main.go`](main.go) top to bottom once — it is commented section by
> section (metrics → config → logging → tracing → middleware → handlers → main).

## Endpoints

| Endpoint        | Purpose                                                        |
|-----------------|----------------------------------------------------------------|
| `/health`       | Liveness probe (excluded from metrics)                          |
| `/metrics`      | Prometheus scrape target (also excluded from metrics)           |
| `/api/orders`   | Main flow; calls the payment service if `DEPENDENCY_URL` is set |
| `/api/payment`  | Downstream "service" — same binary deployed as `demo-payment`   |

**Fault injection** (used by the incident lab): append `?fail=1` (HTTP 500)
or `?slow=1` (~2s latency) to `/api/orders`.

## Configuration

| Variable / flag            | Default | Meaning                                             |
|----------------------------|---------|-----------------------------------------------------|
| `--service`                | `order` | Logical service name (metric label + log field)     |
| `--listen`                 | `:8080` | Listen address                                      |
| `DEPENDENCY_URL`           | (empty) | If set, `/api/orders` calls it (distributed trace)  |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | (empty) | If set (e.g. `otel-collector:4317`), traces are exported. If empty, tracing is a cheap no-op. |

That last row is why **one image works for every module**: modules 01–06 run
without tracing; module 07 turns it on with a single env var.

## Run locally

```bash
go run .                                  # basic: metrics + logs
go run . --service=payment --listen=:8081 # second instance = payment service

DEPENDENCY_URL=http://localhost:8081/api/payment go run .   # order -> payment
OTEL_EXPORTER_OTLP_ENDPOINT=localhost:4317 go run .         # + traces
```

## Build the container

```bash
docker build -t demo-api:0.1.0 .
docker run -p 8080:8080 demo-api:0.1.0
```

`scripts/deploy.sh` runs this build for you and loads the image into the
kind cluster automatically.
