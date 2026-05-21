# Multi-stack Azure Investigation Runbook

Investigate incidents that traverse **customer-portal (App Service) → activation-service (AKS) → Cosmos DB → Azure SQL → Storage**. Use this runbook when the Movistar self-service channel is slow, intermittent, or returning partial failures and the root cause is unclear.

---

## Service Map

```text
Internet / Browser
        |
        v
[App Service: customer-portal]
        |  cloud_RoleName = customer-portal
        |  operation_Id starts here
        v
[AKS: activation-service] (namespace = movistar)
        |---------> [Cosmos DB: plans-catalog]
        |---------> [Azure SQL DB: subscribers / activations]
        \---------> [Blob Storage: provisioning artifacts]
```

**Telemetry rule:** start at the front door, keep the same `operation_Id`, and use `cloud_RoleName` plus AKS telemetry from the `movistar` namespace to see which tier emitted each signal.

---

## Step 1: Classify the Cross-stack Symptom

| Symptom | Likely Bottleneck | Primary Signal | Jump To |
|---------|-------------------|----------------|---------|
| Customer portal is slow or intermittent | AKS latency, Cosmos DB throttling, or SQL saturation | Dependency latency spikes behind otherwise healthy requests | Step 2 |
| Customer portal returns 502/503 quickly | App Service config/runtime issue | Failed requests at `customer-portal` with few downstream spans | Step 3A |
| Activations fail after leaving the portal | AKS mid-tier issue | `activation-service` errors or restarts in `movistar` | Step 3B |
| Catalog operations fail with 429s | Cosmos DB | `RequestRateTooLarge`, high RU, hot partition | Step 3C |
| Subscriber updates or recharge writes time out | Azure SQL | DTU near 100%, blocking, or deadlocks | Step 3D |
| Provisioning artifact paths fail intermittently | Storage | Blob dependency failures or 503/409 patterns | Step 3E |

---

## Step 2: Trace the Request End-to-End in Application Insights

Start with the slowest or failed portal requests and join them to dependencies using `operation_Id`.

```kql
let window = 30m;
requests
| where timestamp > ago(window)
| project operation_Id,
          requestId = id,
          requestTime = timestamp,
          operation_Name,
          requestName = name,
          requestRole = cloud_RoleName,
          requestResult = tostring(resultCode),
          requestSuccess = success,
          requestDuration = duration
| join kind=leftouter (
    dependencies
    | where timestamp > ago(window)
    | project operation_Id,
              dependencyId = id,
              dependencyTime = timestamp,
              dependencyName = name,
              dependencyType = type,
              dependencyTarget = target,
              dependencyRole = cloud_RoleName,
              dependencyResult = tostring(resultCode),
              dependencySuccess = success,
              dependencyDuration = duration
) on operation_Id
| order by requestTime desc, dependencyTime asc
```

**What to look for:**
- `requestRole == customer-portal` or `requestRole` values that start with `app-` usually represent the front-end self-service tier.
- `PodNamespace == "movistar"` and `PodName` values containing `activation-service` mark the AKS mid-tier.
- `dependencyTarget` values ending in `.documents.azure.com`, `.database.windows.net`, or `.blob.core.windows.net` identify Cosmos DB, SQL, and Storage.
- The first tier where latency or failure sharply increases is usually the bottleneck.

### Correlate the AKS mid-tier

```kql
KubePodInventory
| where TimeGenerated > ago(30m)
| where Namespace == "movistar"
| where Name contains "activation-service"
| project TimeGenerated, Name, PodStatus, PodRestartCount
| order by TimeGenerated desc
```

### Correlate by `cloud_RoleName`

```kql
union isfuzzy=true requests, dependencies, exceptions
| where timestamp > ago(30m)
| summarize Events = count(),
            Failures = countif(success == false),
            P95 = percentile(duration, 95)
    by itemType, cloud_RoleName
| order by Failures desc, P95 desc
```

Use this to separate front-end symptoms from downstream failures. A slow `customer-portal` tier with a healthy AKS layer points to App Service. A healthy portal with `activation-service` restarts or dependency failures points to the AKS tier.

---

## Step 3A: App Service as the Bottleneck

**Typical signals:** 502/503 at the web tier, missing app settings, worker restarts, or deployment slot issues.

**Quick checks:**
1. Query failed front-end requests:
   ```kql
   requests
   | where timestamp > ago(30m)
   | where cloud_RoleName == 'customer-portal' or cloud_RoleName startswith 'app-'
   | summarize Requests = count(), Failures = countif(success == false), P95 = percentile(duration, 95) by resultCode, name
   | order by Failures desc, P95 desc
   ```
2. Check whether downstream spans are absent for failed requests. If there are no dependency calls, the failure is probably in the App Service tier or its configuration.
3. Validate critical app settings:
   ```bash
   az webapp config appsettings list --resource-group <rg> --name <app-name>
   ```

**Fast mitigation:** restore broken settings, restart the web app, or roll back the last deployment/slot swap.

---

## Step 3B: AKS activation-service as the Bottleneck

**Typical signals:** portal requests reach AKS but fail or time out there, `activation-service` restarts, or `activation-service` cannot reach its downstream stores.

**Quick checks:**
1. Check AKS pod health:
   ```bash
   kubectl get pods -n movistar
   kubectl describe deployment activation-service -n movistar
   ```
2. Query AKS container logs:
   ```kql
   ContainerLogV2
   | where TimeGenerated > ago(30m)
   | where PodNamespace == "movistar"
   | where PodName contains "activation-service"
   | where LogMessage contains "error" or LogMessage contains "timeout" or LogMessage contains "connection"
   | project TimeGenerated, PodName, LogMessage
   | order by TimeGenerated desc
   ```
3. Check recent Kubernetes events:
   ```bash
   kubectl get events -n movistar --sort-by=.metadata.creationTimestamp | tail -20
   ```

**Fast mitigation:** restart or roll back `activation-service`, fix broken AKS configuration, and restore connectivity to `subscriber-db` or `provisioning-queue`.

---

## Step 3C: Cosmos DB as the Bottleneck

**Typical signals:** `429 RequestRateTooLarge`, elevated dependency latency to `.documents.azure.com`, or a single partition absorbing most traffic.

**Quick checks:**
1. App Insights dependency failures to Cosmos:
   ```kql
   dependencies
   | where timestamp > ago(30m)
   | where target contains '.documents.azure.com'
   | summarize Calls = count(), Failures = countif(success == false), P95 = percentile(duration, 95) by cloud_RoleName, resultCode
   | order by Failures desc, P95 desc
   ```
2. Validate container throughput:
   ```bash
   az cosmosdb sql container throughput show --resource-group <rg> --account-name <cosmos-account> --database-name movistar-bss-db --name plans-catalog
   ```
3. Follow `cosmos-db-troubleshooting.md` for RU, hot partition, and query shape analysis.

**Fast mitigation:** raise RU/s, distribute partition keys more evenly, and reduce expensive cross-partition queries.

---

## Step 3D: Azure SQL as the Bottleneck

**Typical signals:** activation, subscriber update, or recharge write paths time out; SQL dependencies show errors; DTU or worker pressure trends toward 100%.

**Quick checks:**
1. App Insights SQL dependencies:
   ```kql
   dependencies
   | where timestamp > ago(30m)
   | where target contains '.database.windows.net'
   | summarize Calls = count(), Failures = countif(success == false), P95 = percentile(duration, 95) by cloud_RoleName, resultCode
   | order by Failures desc, P95 desc
   ```
2. Query Azure Monitor metrics:
   ```kql
   AzureMetrics
   | where TimeGenerated > ago(30m)
   | where ResourceProvider == 'MICROSOFT.SQL'
   | where MetricName in ('dtu_consumption_percent', 'cpu_percent', 'workers_percent', 'sessions_percent')
   | summarize AvgValue = avg(Total), MaxValue = max(Maximum) by Resource, MetricName, bin(TimeGenerated, 5m)
   | order by MaxValue desc
   ```
3. Follow `azure-sql-troubleshooting.md` for DTU, blocking, deadlocks, and Query Store analysis.

**Fast mitigation:** stop the load source, scale above S0, or tune the heaviest query.

---

## Step 3E: Storage as the Bottleneck

**Typical signals:** provisioning artifacts or exported files fail, uploads/downloads are slow, or dependency targets point at `.blob.core.windows.net` with elevated latency.

**Quick checks:**
1. App Insights blob dependencies:
   ```kql
   dependencies
   | where timestamp > ago(30m)
   | where target contains '.blob.core.windows.net'
   | summarize Calls = count(), Failures = countif(success == false), P95 = percentile(duration, 95) by cloud_RoleName, resultCode
   | order by Failures desc, P95 desc
   ```
2. Storage metrics for throttling or server busy patterns:
   ```kql
   AzureMetrics
   | where TimeGenerated > ago(30m)
   | where ResourceProvider == 'MICROSOFT.STORAGE'
   | where MetricName in ('Transactions', 'SuccessE2ELatency', 'Availability')
   | summarize AvgValue = avg(Total), MaxValue = max(Maximum) by Resource, MetricName, bin(TimeGenerated, 5m)
   | order by MaxValue desc
   ```

**Fast mitigation:** reduce concurrency, add retry/backoff, or move heavy blob operations out of the synchronous request path.

---

## Step 4: Summarize the Incident Like a Service Map

When presenting findings, use this structure:

| Tier | Health | Evidence | Bottleneck? |
|------|--------|----------|-------------|
| App Service (`customer-portal`) | Healthy / Degraded / Failed | Request rate, 5xx, config evidence | Yes / No |
| AKS (`activation-service`) | Healthy / Degraded / Failed | Pod restarts, logs, namespace events | Yes / No |
| Cosmos DB (`plans-catalog`) | Healthy / Degraded / Failed | 429s, RU/s, partition hot spots | Yes / No |
| Azure SQL (`subscribers` / `activations`) | Healthy / Degraded / Failed | DTU, blocking, deadlocks | Yes / No |
| Storage | Healthy / Degraded / Failed | Blob latency, 503s, availability | Yes / No |

Highlight the first failing tier in the chain. Upstream tiers often look unhealthy because they are waiting on that dependency.

---

## Step 5: Common Cross-stack Remediations

- **Restore broken configuration** at the App Service layer before investigating downstream metrics.
- **Fix AKS deployment or connectivity issues** on `activation-service` before assuming the bottleneck is in Azure data services.
- **Scale Cosmos DB throughput** or fix partition skew when 429s dominate.
- **Kill synthetic SQL load** and scale/tune the database when DTU is saturated.
- **Add retries with exponential backoff** for Cosmos DB and Storage transient failures.

If the root cause is still unclear after Step 2, run the service-specific runbooks and keep the same `operation_Id` as your correlation key.
