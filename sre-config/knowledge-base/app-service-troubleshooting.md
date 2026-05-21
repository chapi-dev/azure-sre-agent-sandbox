# App Service Troubleshooting Runbook

Diagnose and remediate **slot swap failures, broken app settings, 502/503 responses, and scaling issues** for the front-end App Service.

---

## Step 1: Classify the Web Tier Issue

| Symptom | Likely Cause | Jump To |
|---------|--------------|---------|
| Immediate 502/503 responses | Worker/runtime issue or bad configuration | Step 2 |
| Failures after a deployment or swap | Slot swap issue | Step 3 |
| App starts but downstream calls fail | Broken app settings | Step 4 |
| Latency rises under load with queueing | Scale or plan sizing issue | Step 5 |

---

## Step 2: Investigate 502/503 Patterns

**Symptoms:** requests fail at the front door, often before the function or backend tiers are even called.

**Diagnostic steps:**
1. Check HTTP status distribution:
   ```kql
   AppServiceHTTPLogs
   | where TimeGenerated > ago(30m)
   | summarize Requests = count(),
               Failures = countif(ScStatus >= 500),
               P95LatencyMs = percentile(TimeTaken, 95)
       by SiteName, ScStatus, bin(TimeGenerated, 5m)
   | order by TimeGenerated desc
   ```
2. Inspect console/runtime errors:
   ```kql
   AppServiceConsoleLogs
   | where TimeGenerated > ago(30m)
   | project TimeGenerated, SiteName, Level, ResultDescription
   | order by TimeGenerated desc
   ```
3. Correlate with Application Insights requests where `cloud_RoleName` starts with `app-`.

**Remediation:**
- Restart the web app if the worker is wedged.
- Roll back the last code/config change if 5xx began immediately after deployment.
- Restore the missing or malformed configuration value.

---

## Step 3: Diagnose Slot Swap Failures

**Symptoms:** swap does not complete, traffic shifts to a broken slot, or production degrades immediately after swap.

**Diagnostic steps:**
1. List slots and verify status:
   ```bash
   az webapp deployment slot list --resource-group <rg> --name <app-name>
   ```
2. Review deployment logs:
   ```bash
   az webapp log deployment show --resource-group <rg> --name <app-name>
   ```
3. Validate slot-specific settings and connection strings before retrying the swap.

**Remediation:**
- Mark environment-specific settings as slot settings.
- Warm the target slot before swapping.
- Swap back immediately if the new production slot is unhealthy.

---

## Step 4: Validate App Settings and Broken Downstream Configuration

**Symptoms:** App Service is up, but downstream calls fail because a setting such as `Cosmos__Endpoint` is invalid.

**Diagnostic steps:**
1. List the critical settings:
   ```bash
   az webapp config appsettings list --resource-group <rg> --name <app-name> --query "[?name=='Cosmos__Endpoint' || name=='Sql__ConnectionString' || name=='APPLICATIONINSIGHTS_CONNECTION_STRING']"
   ```
2. Compare `Cosmos__Endpoint` to the actual account endpoint.
3. Look for connection or DNS errors in `AppServiceConsoleLogs`.
4. Confirm whether failed App Insights requests have downstream dependency spans. If not, the app may be failing before it calls the next tier.

**Remediation:**
- Restore the expected setting value.
- Restart the app after configuration changes.
- If a bad slot swap introduced the setting, swap back or resync slot settings.

---

## Step 5: Check Scale and App Service Plan Pressure

**Symptoms:** 5xx and latency worsen as request volume rises, but configuration looks correct.

**Diagnostic steps:**
1. Query App Service / App Service Plan metrics:
   ```kql
   AzureMetrics
   | where TimeGenerated > ago(30m)
   | where ResourceProvider == 'MICROSOFT.WEB'
   | where MetricName in ('CpuPercentage', 'MemoryPercentage', 'HttpQueueLength', 'Requests', 'Http5xx')
   | summarize AvgValue = avg(Total), MaxValue = max(Maximum) by Resource, MetricName, bin(TimeGenerated, 5m)
   | order by MaxValue desc
   ```
2. Compare request volume to latency and 5xx spikes from `AppServiceHTTPLogs`.
3. Verify the Basic B1 plan is not undersized for the current demo load.

**Remediation:**
- Scale up or out if the issue is legitimate capacity pressure.
- Reduce synchronous fan-out from the web tier.
- Fix the downstream bottleneck first if App Service is only waiting on Cosmos, SQL, or Functions.

---

## General Recovery

For the demo baseline, restore `Cosmos__Endpoint` to the real Cosmos endpoint, confirm front-end 5xx drops, and verify downstream spans appear again in Application Insights.
