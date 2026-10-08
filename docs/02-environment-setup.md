# 02 — Environment Setup

> Module 2 of 11 · Prev: [01 — Foundations](01-foundations.md) · Next: [03 — Prometheus & Grafana](03-prometheus.md)

## Goal

A working local Kubernetes cluster plus a validated toolchain — the foundation
every later module builds on.

## Prerequisites

| Tool | Why | Install |
|---|---|---|
| Docker | runs kind nodes & builds the app image | https://docs.docker.com/get-docker/ |
| kubectl | talks to Kubernetes | https://kubernetes.io/docs/tasks/tools/ |
| kind | Kubernetes *in* Docker (local cluster) | `go install sigs.k8s.io/kind@latest` |
| Git Bash / WSL | runs this repo's shell scripts on Windows | https://git-scm.com/download/win |
| Go (optional) | only if you build/run the app locally | https://go.dev/dl/ |

Recommended machine size: **8 GB RAM free** (the logging stack in module 07
needs ~3 GB alone).

## Step 1 — check your machine

```bash
bash scripts/doctor.sh
```

Expected: every required tool prints `[OK]`. `[WARN] Docker daemon not
reachable` means Docker Desktop is not started yet. `[WARN] no cluster yet`
is normal at this point.

## Step 2 — create the cluster

```bash
bash scripts/cluster-up.sh
```

Expected (abridged):

```text
[1/2] creating kind cluster 'observability-lab' ...
[2/2] waiting for the node to be Ready ...
kubectl cluster-info
Kubernetes control plane is running at ...
[DONE] cluster is up.
```

What you got:

```text
kind cluster "observability-lab"      (1 control-plane node, inside Docker)
kubectl context: kind-observability-lab
```

## Step 3 — your kubectl survival kit

Run these now so they are muscle memory later:

```bash
kubectl get nodes                                  # cluster up? node Ready?
kubectl get ns                                     # namespaces (observability + demo arrive in step 4)
kubectl get pods -A                                # all pods
kubectl describe pod <pod> -n <ns>                 # WHY is it pending/crashing?
kubectl logs <pod> -n <ns> --tail 50 -f            # what is it printing?
kubectl get all -n observability                   # everything of ours, later
```

## Step 4 — create the namespaces

```bash
kubectl apply -f deploy/00-namespaces.yaml
kubectl get ns
```

Expected:

```text
NAME             STATUS   AGE
default          Active   ...
demo             Active   ...     <- application
observability    Active   ...     <- monitoring/logging/tracing tools
```

**Why namespaces?** They scope names and isolate blast radius. Everything you
observe lives in `observability`; everything observed lives in `demo` — two
names, short commands, clear separation of platform vs application.

## Verify — you are ready

```bash
kubectl get nodes               # NAME STATUS ... Ready
kubectl get ns demo observability
bash scripts/validate.sh        # repo integrity check (also runs in CI)
```

`validate.sh` ends with `== ALL CHECKS PASSED ==`.

## Troubleshoot

| Symptom | Cause & fix |
|---|---|
| `kind: command not found` | kind not installed — see prerequisites, then re-open the terminal |
| `Cannot connect to the Docker daemon` | start Docker Desktop |
| `kind create` hangs on pulling image | slow network; re-run the script — it resumes/creates once |
| `kubectl cluster-info` times out | cluster deleted or context wrong: `kubectl config use-context kind-observability-lab` |
| `bash: scripts/doctor.sh: No such file` | you are not in the repo root — `cd` into it first |
| Scripts fail in PowerShell | use **Git Bash** on Windows, not PowerShell |
| Port already in use (later modules) | something else owns 3000/9090 — stop it or edit the port in `scripts/port-forward.sh` |

## Cleanup

Keep the cluster — every later module needs it.

```bash
bash scripts/cluster-down.sh    # ONLY when you are fully done with the course
```

## Key takeaways

1. kind = disposable Kubernetes inside Docker; perfect for observability labs.
2. Namespaces: `observability` (tools) vs `demo` (app).
3. `describe` explains *why* something is broken; `logs` shows *what* it says.

## Interview questions

1. What does `kubectl describe pod` show that `kubectl logs` does not?
2. Why prefer kind/minikube over a managed cluster for learning?
3. What is a kubeconfig context, and what does `kubectl config use-context` change?

## Next

Deploy your first monitoring stack: [03 — Prometheus & Grafana](03-prometheus.md)
