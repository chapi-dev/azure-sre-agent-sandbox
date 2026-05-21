# Dependency Failure Investigation Runbook

Diagnose cascading failures caused by backend dependency outages in the Movistar BSS application on AKS. Covers subscriber-db and provisioning-queue failures and their downstream impact.

---

## Application Architecture

| Service | Role | Dependencies |
|---------|------|-------------|
| customer-portal | Consumer self-service UI | activation-service, catalog-service |
| csr-console | CSR workspace | activation-service, catalog-service, provisioning-service |
| activation-service | Accepts activations, plan changes, and recharges | catalog-service, subscriber-db, provisioning-queue |
| catalog-service | Serves plans and bundle catalog data | subscriber-db |
| provisioning-service | Applies provisioning and service changes | subscriber-db, provisioning-queue |
| traffic-simulator | Simulates subscriber activations | customer-portal |
| network-worker | Simulates operational completion | provisioning-service |
| subscriber-db | Subscriber state store | PersistentVolumeClaim (`mongodb-data-pvc`) |
| provisioning-queue | Provisioning queue | In-memory |

---

## Step 1: Identify the Root Dependency

When multiple services report errors simultaneously, the root cause is usually a shared dependency:

1. Check which pods are unhealthy:
   ```bash
   kubectl get pods -n movistar
   ```
2. Check logs across failing services:
   ```bash
   kubectl logs -l app=activation-service -n movistar --tail=20
   kubectl logs -l app=catalog-service -n movistar --tail=20
   kubectl logs -l app=provisioning-service -n movistar --tail=20
   ```
3. Check backing services:
   ```bash
   kubectl get pods -n movistar -l app=subscriber-db
   kubectl get pods -n movistar -l app=provisioning-queue
   ```

| Pattern | Root Cause |
|---------|-----------|
| activation-service, catalog-service, provisioning-service all failing | subscriber-db is down |
| activation-service failing, provisioning-service idle | provisioning-queue is down |
| Only one service failing | Isolated issue (see pod-failures runbook) |

---

## Step 2: MongoDB Down

**Symptoms:**
- `provisioning-service` cannot read subscriber data and fails health checks
- `activation-service` cannot validate or persist subscriber state, so activations and recharges fail
- `customer-portal` loads but line activations or top-ups do not complete
- `subscriber-db` has 0 replicas or is in CrashLoopBackOff

**Diagnostic steps:**
1. Check the `subscriber-db` pod status:
   ```bash
   kubectl get deployment subscriber-db -n movistar
   kubectl get pods -l app=subscriber-db -n movistar
   ```
2. Check the backing PVC:
   ```bash
   kubectl get pvc mongodb-data-pvc -n movistar
   ```
3. Check logs of dependent services for connection errors:
   ```bash
   kubectl logs -l app=provisioning-service -n movistar --tail=10 | grep -i "mongo\|subscriber\|connection\|error"
   kubectl logs -l app=activation-service -n movistar --tail=10 | grep -i "mongo\|subscriber\|connection\|error"
   ```
4. Query Log Analytics for the timeline:
   ```kql
   KubePodInventory
   | where Namespace == "movistar"
   | where Name contains "subscriber-db"
   | where TimeGenerated > ago(1h)
   | project TimeGenerated, Name, PodStatus, PodRestartCount
   | order by TimeGenerated desc
   ```

**Remediation:**
- Scale `subscriber-db` back up:
  ```bash
  kubectl scale deployment subscriber-db -n movistar --replicas=1
  ```
- Or apply the healthy baseline:
  ```bash
  kubectl apply -f k8s/base/application.yaml
  ```
- Dependent services should auto-recover once `subscriber-db` is available; `provisioning-service` usually stabilizes first, then `activation-service`

---

## Step 3: Provisioning Queue Down

**Symptoms:**
- `activation-service` cannot publish provisioning work to the queue
- `provisioning-service` has no work to process
- Activations may appear accepted in the portal but never complete provisioning

**Diagnostic steps:**
1. Check the `provisioning-queue` pod:
   ```bash
   kubectl get pods -l app=provisioning-queue -n movistar
   kubectl logs -l app=provisioning-queue -n movistar --tail=20
   ```
2. Check dependent service logs:
   ```bash
   kubectl logs -l app=activation-service -n movistar --tail=10 | grep -i "rabbit\|amqp\|queue"
   ```

**Remediation:**
- Restart `provisioning-queue`:
  ```bash
  kubectl rollout restart deployment provisioning-queue -n movistar
  ```
- Scale back if needed:
  ```bash
  kubectl scale deployment provisioning-queue -n movistar --replicas=1
  ```

---

## Step 4: Cascading Failure Analysis

To demonstrate root cause analysis, trace the failure chain:

1. **Identify symptoms:** Multiple services failing
2. **Find the common dependency:** Usually `subscriber-db` or `provisioning-queue`
3. **Verify the dependency is down:** Check pod status and replica count
4. **Trace the timeline:** When did the dependency go down? Query events:
   ```bash
   kubectl get events -n movistar --sort-by=.metadata.creationTimestamp | tail -20
   ```
5. **Correlate:** Show that `subscriber-db` failed first, `provisioning-service` lost subscriber context, and `activation-service` then failed as the cascade moved upstream

**Key investigation prompt for SRE Agent:**
> "Trace the dependency chain — what broke first and what was impacted downstream?"

This demonstrates SRE Agent's ability to perform root cause analysis across interconnected services rather than just reporting individual pod failures.
