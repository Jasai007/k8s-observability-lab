# 06 — Alerting

> Module 6 of 11 · Prev: [05 — Application metrics](05-application-metrics.md) · Next: [07 — Logging (EFK)](07-logging.md)

## Goal

Deploy Alertmanager, understand the two-stage alerting pipeline, and watch a
real alert travel: condition met → pending → firing → grouped in the UI.

## Concepts

### Two-stage pipeline (the #1 interview answer)

```text
  Prometheus                          Alertmanager
  ----------                          ------------
  evaluates rules every 15s           receives firing alerts
  'for: 2m' prevents flapping   -->   groups duplicates (by alertname+ns)
  sends ONLY when condition true      routes by labels (severity, team...)
                                      inhibits children of bigger problems
                                      dedups + repeats notifications
                                      --> receiver (email/Slack/webhook/UI)
```

Prometheus **detects**; Alertmanager **notifies**. Neither does the other's job.

### Anatomy of an alert (from `deploy/prometheus/rules/learning.yml`)

```yaml
- alert: DemoHighErrorRate
  expr: |                          # PromQL that must be TRUE
    sum by (service) (rate(http_requests_total{status=~"5.."}[5m])) /
    sum by (service) (rate(http_requests_total[5m])) > 0.2
  for: 2m                          # must be true for 2m before FIRING
  labels:
    severity: critical             # drives routing & inhibition
  annotations:
    summary: "Service {{ $labels.service }} error rate > 20%"   # shown to humans
    description: "..."             # what to DO — include a next command!
```

States: `inactive` (condition false) → `pending` (true, `for` not elapsed) →
`firing` (true long enough).

### What makes an alert *good*?

```text
actionable    every firing alert implies an action ("do X")
symptom-based alert on user pain (errors, latency), not on causes (CPU)
not noisy     use for:, inhibition, grouping; silence the predictable
enriched      summary + description + runbook link in annotations
```

### Routes, grouping, inhibition (configured in `deploy/alertmanager/alertmanager.yml`)

```text
group_by: [alertname, namespace]   1 notification per alert+ns, not per pod
group_wait: 30s                    wait for siblings to join the first notify
repeat_interval: 4h                re-notify while still broken
inhibit critical> warning          one big problem hides its smaller echoes
receiver: lab-inbox                (no integration — watch the UI in a lab)
```

## Step 1 — deploy Alertmanager

```bash
kubectl apply -k deploy/alertmanager
kubectl -n observability rollout status deploy/alertmanager --timeout=120s
```

Prometheus already knows where to send alerts — `alerting.alertmanagers` is
part of `prometheus.yml` (applied in module 03).

## Step 2 — see the rules loaded

Open the Prometheus UI **Alerts** tab (port-forward `prometheus`):

```bash
bash scripts/port-forward.sh prometheus
```

Expected: groups `infrastructure` and `demo-app` with the rules from
`learning.yml`, all `inactive`.

## Step 3 — fire a real alert on purpose

Break the payment dependency (module 10 will do this systematically):

```bash
kubectl -n demo scale deploy/demo-payment --replicas=0
```

Send traffic so errors accumulate:

```bash
FAIL_PERCENT=100 bash scripts/generate-load.sh     # terminal A
```

Watch the alert transition:

1. Prometheus **Alerts** tab: `DemoPaymentDependencyFailing` → **pending**
   (condition already true).
2. After `for: 2m` → **firing** (red).
3. Alertmanager UI:

```bash
bash scripts/port-forward.sh alertmanager        # http://localhost:9093
```

Expected: the alert appears, grouped under `alertname=... namespace=demo`,
with `severity: critical`.

## Step 4 — exercise the basics of Alertmanager

Still in the UI:

- **Silence** the alert (Show → Silence): create a matcher on
  `alertname=DemoPaymentDependencyFailing`, duration 15m. The alert shows as
  silenced but keeps firing underneath — that is the point (suppression ≠ fix).
- Delete the silence → it returns to plain firing.
- Explore the **API**:

```bash
curl -s localhost:9093/api/v2/alerts | head -c 400
```

## Step 5 — heal the system

```bash
kubectl -n demo scale deploy/demo-payment --replicas=1
# Ctrl-C the load generator
```

Expected: alert goes to **resolved** in Alertmanager within a couple of
minutes (Prometheus stops sending once the condition is false).

## Verify — checklist

- [ ] Alerts tab shows rules from `learning.yml`
- [ ] You observed pending → firing → resolved for one alert
- [ ] A silence suppressed (but did not delete) the alert
- [ ] `curl localhost:9093/api/v2/alerts` returns JSON

## Troubleshoot

| Symptom | Cause & fix |
|---|---|
| Alert stays `pending` forever | condition not true for `for:` duration — or you stopped the traffic too early |
| Alert never fires though errors are up | check your PromQL in the Graph tab first; alerts evaluate *exactly* that expression |
| Nothing in Alertmanager UI | check Prometheus **Alerts** tab: if there, `kubectl -n observability logs deploy/prometheus \| grep -i alertmanager` (connection?), and `kubectl -n observability get svc alertmanager` |
| Alert fires for missing targets before you deploy things | with endpoints SD this should not happen; if you add *static* targets, remember DNS failures report `up=0` |
| Too many notifications in real life | tune `group_by`, `for:`, add inhibition — never fix noise by deleting alerts |
| Want real email/Slack | uncomment a receiver block in `deploy/alertmanager/alertmanager.yml` (module 11 covers Secrets for credentials) |

## Cleanup

If you created silences, expire them. Everything else stays for later modules.

## Key takeaways

1. Prometheus detects, Alertmanager routes/dedups/notifies — two components.
2. `for:` is your anti-flap shield; `severity` is your routing metadata.
3. Annotations must tell a human what to DO, not just what happened.
4. Silences are for maintenance windows, not for ignoring reality.

## Next

Metrics answer *that* it broke; logs answer *what* broke:
[07 — Logging (EFK)](07-logging.md)

