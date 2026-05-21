# Cosmos DB Troubleshooting Runbook

Diagnose and remediate **RU throttling, hot partitions, and expensive query patterns** for the SQL API account used by the multi-stack Azure demo. Primary containers in this Movistar BSS lab are `plans-catalog` for plan metadata and `activations` for workflow state.

---

## Step 1: Identify the Pressure Pattern

| Signal | Likely Cause | Jump To |
|--------|--------------|---------|
| `429 RequestRateTooLarge` spikes | RU/s throttling | Step 2 |
| One partition range dominates traffic | Hot partition key | Step 3 |
| Queries are slow and RU-expensive | Poor query shape or missing filter selectivity | Step 4 |
| Throughput looks normal but latency is still high | Client retries or downstream contention | Step 5 |

---

## Step 2: Confirm RU/s Throttling

**Symptoms:** intermittent 429s, latency spikes, retried requests, the app eventually succeeds but feels slow.

**Diagnostic steps:**
1. Check current manual throughput:
   ```bash
   az cosmosdb sql container throughput show --resource-group <rg> --account-name <cosmos-account> --database-name movistar-bss-db --name plans-catalog
   ```
2. Query diagnostics logs for throttled requests:
   ```kql
   AzureDiagnostics
   | where TimeGenerated > ago(30m)
   | where ResourceProvider == 'MICROSOFT.DOCUMENTDB'
   | where Category == 'DataPlaneRequests'
   | extend Collection = column_ifexists('collectionName_s', column_ifexists('requestResourceId_s', 'unknown'))
   | extend StatusCode = toint(column_ifexists('statusCode_s', '0'))
   | extend RequestCharge = todouble(column_ifexists('requestCharge_s', '0'))
   | extend DurationMs = todouble(column_ifexists('durationMs_s', '0'))
   | summarize Requests = count(),
               Throttles = countif(StatusCode == 429),
               AvgRU = avg(RequestCharge),
               P95DurationMs = percentile(DurationMs, 95)
       by Collection, Operation = column_ifexists('operationName_s', 'unknown'), bin(TimeGenerated, 5m)
   | order by TimeGenerated desc
   ```
3. Correlate Cosmos failures back to the calling tier in App Insights:
   ```kql
   dependencies
   | where timestamp > ago(30m)
   | where target contains '.documents.azure.com'
   | summarize Calls = count(), Failures = countif(success == false), P95 = percentile(duration, 95) by cloud_RoleName, resultCode
   | order by Failures desc, P95 desc
   ```

**Remediation:**
- Raise throughput above 100/400 RU/s for the active demo phase.
- Spread writes across more partition key values.
- Add client retry/backoff for 429s instead of tight retry loops.

---

## Step 3: Detect a Hot Partition Key

**Symptoms:** overall RU looks reasonable, but one partition range is saturated and throttled.

**Diagnostic steps:**
1. Check partition range skew:
   ```kql
   AzureDiagnostics
   | where TimeGenerated > ago(30m)
   | where ResourceProvider == 'MICROSOFT.DOCUMENTDB'
   | where Category == 'DataPlaneRequests'
   | extend PartitionKeyRange = column_ifexists('partitionKeyRangeId_s', 'unknown')
   | extend RequestCharge = todouble(column_ifexists('requestCharge_s', '0'))
   | extend StatusCode = toint(column_ifexists('statusCode_s', '0'))
   | summarize Requests = count(),
               TotalRU = sum(RequestCharge),
               Throttles = countif(StatusCode == 429)
       by PartitionKeyRange, bin(TimeGenerated, 5m)
   | order by TotalRU desc, Throttles desc
   ```
2. Look for a single logical key value dominating application traffic (for this demo, `/planCategory` is the partition key).
3. Check whether the same workload repeatedly targets one plan family or recharge bundle.

**Remediation:**
- Choose a higher-cardinality partition key.
- Add a synthetic suffix if traffic naturally concentrates on one logical key.
- Batch writes across multiple keys instead of hammering one partition.

---

## Step 4: Identify Expensive Query Patterns

**Symptoms:** RU charge is high even without many 429s, query latency increases under modest concurrency.

**Diagnostic steps:**
1. Find the most expensive request types:
   ```kql
   AzureDiagnostics
   | where TimeGenerated > ago(30m)
   | where ResourceProvider == 'MICROSOFT.DOCUMENTDB'
   | where Category == 'DataPlaneRequests'
   | extend RequestCharge = todouble(column_ifexists('requestCharge_s', '0'))
   | where column_ifexists('operationName_s', '') has 'Query'
   | summarize Requests = count(), AvgRU = avg(RequestCharge), MaxRU = max(RequestCharge)
       by Collection = column_ifexists('collectionName_s', 'unknown'), Operation = column_ifexists('operationName_s', 'unknown')
   | order by MaxRU desc, AvgRU desc
   ```
2. Review common anti-patterns:
   - Cross-partition queries without a partition key filter
   - `SELECT *` for large documents
   - Sorting without selective predicates
   - Fan-out reads driven by chatty activation or catalog API design
3. Compare request charge before and after tuning the query or indexing policy.

**Remediation:**
- Prefer point reads over queries where possible.
- Always include the partition key in high-volume queries.
- Project only needed fields.
- Revisit indexing if writes are expensive and queries do not need every field indexed.

---

## Step 5: Separate Cosmos Pressure from Client-side Retry Storms

**Symptoms:** telemetry shows high end-to-end latency even after RU/s is restored.

**Diagnostic steps:**
1. Compare raw 429 counts to total dependency duration. If retries dominate, App Insights latency stays high even when many calls eventually succeed.
2. Inspect the caller:
   ```kql
   dependencies
   | where timestamp > ago(30m)
   | where target contains '.documents.azure.com'
   | summarize Calls = count(), Failures = countif(success == false), P95 = percentile(duration, 95), MaxDuration = max(duration) by cloud_RoleName
   | order by P95 desc
   ```
3. Check whether the caller removed retry jitter or is retrying too aggressively.

**Remediation:**
- Keep exponential backoff with jitter.
- Reduce client concurrency while RU/s is low.
- Scale the container throughput only after confirming the calling pattern is reasonable.

---

## General Recovery

For the demo baseline, restore the `plans-catalog` container to **400 RU/s** and verify 429s drop:

```bash
az cosmosdb sql container throughput update --resource-group <rg> --account-name <cosmos-account> --database-name movistar-bss-db --name plans-catalog --throughput 400
```
