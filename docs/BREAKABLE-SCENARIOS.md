# Breakable Scenarios Guide — Movistar BSS Edition

This guide explains each failure scenario available in the demo lab and how to use them for demonstrating Azure SRE Agent capabilities against the **Movistar BSS** platform.

> The scenario filenames and shortcut commands stay the same (for example `mongodb-down.yaml` and `break-mongodb`), but the workload narrative is re-themed around **Mi Movistar**, subscriber operations, and provisioning.

## Quick Reference

| Scenario | File | Telco narrative | SRE Agent diagnosis |
|----------|------|-----------------|---------------------|
| OOMKilled | `oom-killed.yaml` | Activations failing — `activation-service` gets OOMKilled during peak provisioning load | Identifies OOM events, recommends memory limits |
| CrashLoop | `crash-loop.yaml` | Catalog unavailable — `catalog-service` crashes on startup, customers can't browse plans | Exit codes and log analysis |
| ImagePullBackOff | `image-pull-backoff.yaml` | Provisioning halted — a bad image tag breaks `provisioning-service` rollout | Registry/image troubleshooting |
| High CPU | `high-cpu.yaml` | Service degradation — a rogue workload saturates CPU on BSS nodes | Performance analysis |
| Pending Pods | `pending-pods.yaml` | Capacity exhausted — new provisioning workloads cannot be scheduled | Scheduling analysis |
| Probe Failure | `probe-failure.yaml` | Health checks fail on the provisioning path, causing restart churn | Probe configuration analysis |
| Network Block | `network-block.yaml` | `customer-portal` cannot reach `activation-service`, so new activations fail | Network policy analysis |
| Missing Config | `missing-config.yaml` | Misconfigured CSR path — back-office workload references a missing ConfigMap | Configuration troubleshooting |
| MongoDB Down | `mongodb-down.yaml` | `subscriber-db` is down — no plan changes, no recharges, CSR console goes blind | Dependency tracing and root cause |
| Service Mismatch | `service-mismatch.yaml` | `activation-service` selector mismatch — portal looks healthy but activations silently fail | Endpoint/selector analysis |

## Scenario Details

---

### 1. OOMKilled — Activation surge overload

**File:** `k8s/scenarios/oom-killed.yaml`

**What happens:**
- Redeploys `activation-service` with an extremely low memory limit (16Mi)
- The pod starts, handles a little traffic, then gets killed by the OOM killer
- Kubernetes restarts it, and line activations keep failing during the restart loop

**How to break:**
```bash
kubectl apply -f k8s/scenarios/oom-killed.yaml
```

**What to observe:**
```bash
# Watch the activation pods restart
kubectl get pods -n movistar -w

# See the OOMKilled state
kubectl describe pod -l app=activation-service -n movistar | grep -A 5 "Last State"
```

**SRE Agent prompts:**
- "Why is activation-service restarting repeatedly?"
- "New line activations are failing. What memory should I allocate?"
- "Diagnose OOMKilled events in the movistar namespace"

**How to fix:**
```bash
kubectl apply -f k8s/base/application.yaml
```

---

### 2. CrashLoopBackOff — Catalog unavailable

**File:** `k8s/scenarios/crash-loop.yaml`

**What happens:**
- Redeploys `catalog-service` with a command that exits immediately
- The container starts, fails, and exits with code 1
- Customers can open Mi Movistar, but the plan catalog fails to load

**How to break:**
```bash
kubectl apply -f k8s/scenarios/crash-loop.yaml
```

**What to observe:**
```bash
# See CrashLoopBackOff on the catalog tier
kubectl get pods -n movistar | grep catalog-service

# Inspect the crashing container logs
kubectl logs -l app=catalog-service -n movistar --previous
```

**SRE Agent prompts:**
- "Why is catalog-service in CrashLoopBackOff?"
- "Customers can't browse plans in Mi Movistar. Show me the crashing logs."
- "What's causing exit code 1 in the catalog tier?"

**How to fix:**
```bash
kubectl apply -f k8s/base/application.yaml
```

---

### 3. ImagePullBackOff — Provisioning rollout blocked

**File:** `k8s/scenarios/image-pull-backoff.yaml`

**What happens:**
- Redeploys `provisioning-service` with a non-existent image tag
- Kubelet cannot pull the image from the registry
- The provisioning tier never starts, so downstream OSS updates stop

**How to break:**
```bash
kubectl apply -f k8s/scenarios/image-pull-backoff.yaml
```

**What to observe:**
```bash
# See ImagePullBackOff on the provisioning tier
kubectl get pods -n movistar | grep provisioning-service

# Check pod events
kubectl describe pod -l app=provisioning-service -n movistar | grep -A 10 Events
```

**SRE Agent prompts:**
- "Provisioning stopped after the last deployment. Why won't the pods start?"
- "Is there an issue with the container image for provisioning-service?"
- "What's wrong with the provisioning rollout?"

**How to fix:**
```bash
kubectl apply -f k8s/base/application.yaml
```

---

### 4. High CPU Utilization — Rogue workload on BSS nodes

**File:** `k8s/scenarios/high-cpu.yaml`

**What happens:**
- Deploys stress-test pods that consume excessive CPU
- Customer portal and back-office operations may slow down due to node contention
- Alerts may trigger as the cluster approaches CPU saturation

**How to break:**
```bash
kubectl apply -f k8s/scenarios/high-cpu.yaml
```

**What to observe:**
```bash
# Watch CPU usage across the BSS namespace
kubectl top pods -n movistar

# Check node pressure
kubectl top nodes
```

**SRE Agent prompts:**
- "Mi Movistar feels slow. What's consuming all the CPU?"
- "Analyze CPU usage across the movistar namespace"
- "Which workloads are causing resource contention on my BSS nodes?"

**How to fix:**
```bash
kubectl delete deployment cpu-stress-test -n movistar
```

---

### 5. Pending Pods — Capacity exhausted

**File:** `k8s/scenarios/pending-pods.yaml`

**What happens:**
- Deploys oversized pods requesting 32Gi of memory and 8 CPUs each
- No node can satisfy those requests
- New provisioning workers stay in `Pending`, simulating a capacity crunch during demand spikes

**How to break:**
```bash
kubectl apply -f k8s/scenarios/pending-pods.yaml
```

**What to observe:**
```bash
# See pending pods
kubectl get pods -n movistar | grep resource-hog

# Check scheduling events
kubectl describe pod -l app=resource-hog -n movistar | grep -A 10 Events
```

**SRE Agent prompts:**
- "Why are new provisioning workloads stuck in Pending?"
- "I can't schedule more capacity in movistar. What's wrong?"
- "Analyze cluster capacity versus requested resources"

**How to fix:**
```bash
kubectl delete deployment resource-hog -n movistar
```

---

### 6. Probe Failure — Health checks churn on the provisioning path

**File:** `k8s/scenarios/probe-failure.yaml`

**What happens:**
- Deploys `unhealthy-service` as a stand-in for a broken provisioning endpoint
- The liveness probe points to a non-existent path, so Kubernetes keeps restarting the container
- The symptom mimics a provisioning path that flaps between healthy and unhealthy

**How to break:**
```bash
kubectl apply -f k8s/scenarios/probe-failure.yaml
```

**What to observe:**
```bash
# Watch restart churn increase
kubectl get pods -n movistar -l app=unhealthy-service -w

# See liveness probe failures
kubectl describe pod -l app=unhealthy-service -n movistar | grep -A 5 "Liveness"
```

**SRE Agent prompts:**
- "Provisioning keeps restarting even though the nodes look healthy. Why?"
- "Diagnose the health check failures in the movistar namespace"
- "What's wrong with the liveness probe on the provisioning stand-in workload?"

**How to fix:**
```bash
kubectl delete deployment unhealthy-service -n movistar
```

---

### 7. Network Policy Blocking — Customer portal cannot activate

**File:** `k8s/scenarios/network-block.yaml`

**What happens:**
- Applies a NetworkPolicy that blocks traffic to `activation-service`
- `customer-portal` becomes unable to reach the activation API
- Browsing still works, but line activations and plan changes fail

**How to break:**
```bash
kubectl apply -f k8s/scenarios/network-block.yaml
```

**What to observe:**
```bash
# Test connectivity from the customer portal tier
kubectl exec -n movistar deploy/customer-portal -- curl -s activation-service:3000/health
# Should timeout or fail
```

**SRE Agent prompts:**
- "Why can't customer-portal reach activation-service?"
- "Diagnose network connectivity issues in the movistar namespace"
- "What network policies are blocking the activation flow?"

**How to fix:**
```bash
kubectl delete networkpolicy deny-activation-service -n movistar
```

---

### 8. Missing ConfigMap — CSR console misconfiguration

**File:** `k8s/scenarios/missing-config.yaml`

**What happens:**
- Deploys `misconfigured-service` as a stand-in for a broken CSR console dependency
- The pod references a ConfigMap that does not exist
- The back-office path never starts, leaving CSRs without subscriber context

**How to break:**
```bash
kubectl apply -f k8s/scenarios/missing-config.yaml
```

**What to observe:**
```bash
# See the startup error
kubectl get pods -n movistar | grep misconfigured

# Check the events
kubectl describe pod -l app=misconfigured-service -n movistar | grep -A 10 Events
```

**SRE Agent prompts:**
- "The CSR console won't start. It says something about missing config."
- "What configuration is missing for this back-office workload?"
- "Troubleshoot the ConfigMap reference error in movistar"

**How to fix:**
```bash
kubectl delete deployment misconfigured-service -n movistar
```

---

### 9. MongoDB Down — Cascading BSS failure

**File:** `k8s/scenarios/mongodb-down.yaml`

**What happens:**
- Scales `subscriber-db` to 0 replicas so the database tier goes offline
- `provisioning-service` cannot connect and starts failing health checks
- The portal stays up, but activations, recharges, and plan changes never complete
- This is the most realistic scenario because it requires tracing the dependency chain

**How to break:**
```bash
kubectl apply -f k8s/scenarios/mongodb-down.yaml
```

**What to observe:**
```bash
# subscriber-db has 0 replicas
kubectl get deployment subscriber-db -n movistar

# provisioning-service becomes unhealthy
kubectl get pods -n movistar -l app=provisioning-service

# Work backs up in the provisioning queue
kubectl exec -n movistar deploy/provisioning-queue -- rabbitmqctl list_queues
```

**SRE Agent prompts:**
- "Mi Movistar is up, but recharges and plan changes are stuck. What's wrong?"
- "Why is provisioning-service failing health checks?"
- "Trace the dependency chain — what broke first?"
- "Scale the subscriber-db deployment back to 1 replica"

**How to fix:**
```bash
kubectl apply -f k8s/base/application.yaml
```

---

### 10. Service Selector Mismatch — Silent activation failure

**File:** `k8s/scenarios/service-mismatch.yaml`

**What happens:**
- Replaces the `activation-service` Service with a wrong selector (`app: activation-service-v2`)
- The `activation-service` pods remain healthy and ready
- The Service has zero endpoints, so traffic reaches nothing
- `customer-portal` looks healthy, but any activation attempt fails silently

**Why this is interesting:**
- All pods stay green — no crashes, no restarts, no OOM
- `kubectl get pods` looks healthy
- SRE Agent must inspect Service endpoints and selectors, not just pod status
- This mirrors a real-world rollout typo that is easy to miss in dashboards

**How to break:**
```bash
kubectl apply -f k8s/scenarios/service-mismatch.yaml
```

**What to observe:**
```bash
# Pods are healthy
kubectl get pods -n movistar -l app=activation-service

# But the Service has no endpoints
kubectl get endpoints activation-service -n movistar

# Compare selector vs pod labels
kubectl get svc activation-service -n movistar -o jsonpath='{.spec.selector}'
kubectl get pods -n movistar -l app=activation-service --show-labels
```

**SRE Agent prompts:**
- "Mi Movistar loads, but new line activations spin forever. Everything looks healthy though."
- "Why does activation-service have no endpoints?"
- "Compare the activation-service Service selector to the actual pod labels"
- "Fix the selector on activation-service so it matches the pods"

**How to fix:**
```bash
kubectl apply -f k8s/base/application.yaml
```

---

## Demo Flow Suggestions

### Quick Demo (5 minutes)

1. Apply the OOMKilled scenario
2. Show activations failing in kubectl
3. Ask SRE Agent to diagnose the issue
4. Apply the fix and show recovery

### Comprehensive Demo (20 minutes)

1. **Introduction** — show the healthy Movistar BSS application
2. **Break #1** — OOMKilled (activation surge)
3. **Break #2** — Network policy block (portal → activation API)
4. **Break #3** — CrashLoopBackOff (catalog unavailable)
5. **Advanced** — show a scheduled monitoring task
6. **Cleanup** — restore the healthy baseline

### “Baking” for Advisor Recommendations

Some scenarios benefit from running longer to gather metrics:

1. Deploy the CPU stress scenario
2. Wait 30–60 minutes
3. Check Azure Advisor for right-sizing recommendations
4. Use SRE Agent to analyze historical patterns

## Best Practices

- ✅ Always test scenarios in a dev/demo environment first
- ✅ Capture healthy baseline metrics before breaking things
- ✅ Narrate the business symptom and the technical root cause together
- ✅ Keep fix commands ready
- ❌ Don't apply multiple break scenarios simultaneously
- ❌ Don't leave scenarios running unattended
