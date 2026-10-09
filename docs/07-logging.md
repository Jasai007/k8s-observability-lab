# 07 — Logging with the EFK Stack

> Module 7 of 11 · Prev: [06 — Alerting](06-alerting.md) · Next: [08 — Distributed tracing](08-tracing.md)

## Goal

Ship every container's log line to Elasticsearch, search them in Kibana, and
learn the collection pipeline: **Fluent Bit → Elasticsearch → Kibana**.

## Concepts

### Why logs need a pipeline

`kubectl logs` reads ONE pod's stdout. During an incident you need *all*
pods, *before* they crashed, filterable by field ("show me level=ERROR for
service=order in the last 15 minutes"). That requires centralization:

```text
 every node                 per log line                   store + index      UI
┌────────────────┐   ┌──────────────────────┐   ┌─────────────────┐   ┌─────────┐
│ /var/log/      │   │ Fluent Bit (DaemonSet)│   │ Elasticsearch   │   │  Kibana │
│  containers/   ├──>│  tail + parse + k8s   ├──>│  index:         ├──>│  search │
│  *.log         │   │  metadata -> ship     │   │  observability- │   │  dashbd │
└────────────────┘   └──────────────────────┘   │  YYYY.MM.DD     │   └─────────┘
                                                └─────────────────┘
```

- **Fluent Bit** — lightweight collector: one pod per node, tails
  `/var/log/containers/*.log` (containerd "CRI" format), attaches
  pod/namespace/container metadata, parses the app's JSON line into fields,
  forwards to ES. Config: `deploy/logging/fluent-bit.conf`.
- **Elasticsearch** — indexes documents for full-text + field search.
- **Kibana** — the search UI.

### Structured logging is half the battle

The demo app writes **JSON lines** (`log/slog` in Go):

```json
{"time":"...","level":"ERROR","msg":"http request","service":"order","route":"/api/orders","status":500,"trace_id":"4bf9..."}
```

Because it is structured, Fluent Bit's `Merge_Log On` turns `level`,
`trace_id`, `service` into **queryable ES fields** — and `trace_id` is your
bridge to Jaeger (module 08). Unstructured `printf` logs would just be one
big `message` blob.

### Resource warning (read before deploying)

Elasticsearch is memory-hungry: this lab asks for **≥ 6 GB free RAM**
(the Deployment requests 1 GiB and starts a small JVM). On Docker Desktop:
Settings → Resources → Memory ≥ 8 GB.

## Step 1 — deploy the stack

```bash
kubectl apply -k deploy/logging
kubectl -n observability get pods -w
```

Expected after ~60–90s (ES is slow to bootstrap — be patient):

```text
elasticsearch-...   1/1 Running
kibana-...          1/1 Running
fluent-bit-<node>   1/1 Running     (one per node)
```

## Step 2 — verify Elasticsearch

```bash
kubectl -n observability port-forward svc/elasticsearch 9200:9200 &
curl -s localhost:9200/_cluster/health | head -c 300
curl -s 'localhost:9200/observability-*/_count'
```

Expected: `"status":"green"` (single node) and a growing document count.

## Step 3 — produce logs, then find them

```bash
bash scripts/generate-load.sh &          # terminal A: healthy traffic
curl -s 'localhost:8080/api/orders?fail=1'   # terminal B (through port-forward of demo-api)
```

Wait ~10s, then check the count again (Step 2) — it must have grown.

Now Kibana:

```bash
bash scripts/port-forward.sh kibana       # http://localhost:5601
```

1. *Analytics → Discover* (first run: create a **data view**)
   - name: `observability`, index pattern: `observability-*`, time field:
     `@timestamp` → *Create*.
2. Set the time picker to **Last 15 minutes**.
3. You should see one document per container log line with fields:
   `kubernetes.pod_name`, `level`, `msg`, `service`, `trace_id`, ...

Search queries to try (KQL bar):

```text
level : "ERROR"
service : "order" and level : "ERROR"
kubernetes.namespace : "demo"
msg : "payment dependency failed"
```

Expected: the `?fail=1` request produced `level=ERROR` documents.

## Step 4 — connect logs to what you already know

```text
1. Grafana / Prometheus: note a spike time of 500s (e.g. 14:03)
2. Kibana: time-range to that minute, filter level:ERROR
3. Compare: same pod? same route? does the ERROR message explain the metric?
```

That three-way jump (metric → log → evidence) is the core investigative move
of module 10. The `trace_id` field in each line takes it one step further —
into Jaeger, next module.

## Verify — checklist

- [ ] Three components `1/1 Running` (es, kibana, fluent-bit per node)
- [ ] `/_cluster/health` = green; `/_count` > 0 and growing
- [ ] Kibana Discover shows demo-api JSON fields as columns
- [ ] `level : "ERROR"` isolates your injected failures
- [ ] Log lines carry `trace_id` (set once tracing is on, module 08)

## Troubleshoot

| Symptom | Cause & fix |
|---|---|
| ES pod `OOMKilled` / CrashLoop | not enough RAM — raise Docker Desktop memory, `kubectl -n observability delete pod -l app=elasticsearch` |
| Fluent Bit CrashLoop: `Sections 'parser' ... not valid in the main configuration file` | `[PARSER]` was placed inside `fluent-bit.conf` — v4/v5 forbids it. Parser must live in `parsers.conf` (separate `fluent-bit-parsers` ConfigMap, `Parsers_File` in main conf) — fixed in this repo, re-apply: `kubectl apply -k deploy/logging` |
| Fluent Bit CrashLoop: `could not open parser configuration file` | `Parsers_File` points at a path no ConfigMap provides — check `kubectl -n observability get cm fluent-bit-parsers` exists and `fluent-bit.yaml` mounts it at that exact path. ALSO: Windows CRLF line endings in `*.conf` break Fluent Bit's parser — this repo enforces LF via `.gitattributes`, and `validate.sh` fails on CRLF |
| Kibana CrashLoop, exit 134, `JavaScript heap out of memory` | Node heap exceeded container limit during plugin setup — this repo caps it via `NODE_OPTIONS=--max-old-space-size=700` with `limits.memory=1Gi`. If still OOMing, host RAM is the ceiling: give Docker ≥8GB or scale the stack to zero when idle (see Cleanup below) |
| ES log: `max virtual memory areas vm.max_map_count [65530] is too low` | host kernel setting — on Linux: `sudo sysctl -w vm.max_map_count=262144` (Docker Desktop VMs are usually fine) |
| ES `yellow` forever | normal for single-node with replicas>1 — for a lab, green-vs-yellow can be ignored; health endpoint still `green` here since single-node disables replica allocation |
| Kibana `Unable to connect` | ES still starting — wait and check `kubectl -n observability logs deploy/elasticsearch --tail 20` |
| No documents in ES | Fluent Bit problem: `kubectl -n observability logs ds/fluent-bit --tail 30`; check its DB/permission errors; confirm `kubectl -n demo logs deploy/demo-api` prints lines at all |
| Data view finds nothing | wrong index pattern — must be `observability-*` (Logstash prefix from `fluent-bit.conf`), and time picker widened |
| Duplicate documents | caused by re-shipping after DB loss; the config sets `Generate_ID On` to make retries idempotent |

## Cleanup

Keep it — module 10 searches these logs during the incident. To reclaim RAM
when you are not using logs:

```bash
kubectl -n observability scale deploy/elasticsearch deploy/kibana --replicas=0
kubectl -n observability scale deploy/elasticsearch deploy/kibana --replicas=1
```

(Elasticsearch data is in `emptyDir` — restarting the pod starts empty.)

## Key takeaways

1. Centralized logging = collect everywhere → index → search. `kubectl logs`
   does not scale past one pod.
2. One Fluent Bit per node (DaemonSet) is the standard collection pattern.
3. Structured JSON logs turn into filterable fields — this is what makes
   Kibana (and later correlation) useful.
4. Lab shortcuts (security off, emptyDir storage) are exactly what module 11
   tells you to fix in production.

## Next

Metrics say *that*, logs say *what* — traces say *where*:
[08 — Distributed tracing](08-tracing.md)

