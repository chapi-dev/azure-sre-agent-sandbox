# Module A — Multi-stack Azure

This module extends the AKS-focused lab with an Azure-native, cross-service incident path that the SRE Agent can trace end-to-end for **Movistar BSS**.

The demo story becomes:

```text
Movistar self-service portal (App Service)
    -> activation API (Function App)
    -> catalog (Cosmos DB)
    -> subscribers (Azure SQL)
```

> **Note:** This documentation assumes the `deployMultiStack` / `-DeployMultiStack` wiring is added by the follow-up integration work in `main.bicep`, `main.bicepparam`, and the deployment script.

---

## What Gets Deployed

When `deployMultiStack` is enabled, Module A adds:

- **App Service (Linux, B1)** for the Movistar self-service portal tier
- **Function App (Linux Consumption, Node 20)** for the activation API tier
- **Cosmos DB SQL API** for the catalog tier at **400 RU/s**
- **Azure SQL Database S0** for intentionally low DTU headroom on subscriber data
- **Extra Storage Account** with blob container `demo-throttle`
- **Knowledge base runbooks** for cross-stack, Cosmos DB, Azure SQL, and App Service troubleshooting
- **Custom subagent**: `cross-stack-investigator`
- **Break/fix scenario scripts** under `scripts\scenarios-multistack\`

---

## Deployment Flag

Expected deployment entry points after integration:

```powershell
.\scripts\deploy.ps1 -Location eastus2 -DeployMultiStack
```

Or set the Bicep parameter directly:

```bicep
param deployMultiStack bool = true
```

Use one of the supported SRE Agent regions:
- `eastus2`
- `swedencentral`
- `australiaeast`

---

## Demo Flow

### Primary cross-stack incident

1. Deploy the lab with **Module A** enabled.
2. Trigger Cosmos pressure:
   ```powershell
   .\scripts\scenarios-multistack\break-cosmos-throttle.ps1 -ResourceGroupName rg-srelab-eastus2 -CosmosAccountName <cosmos-account> -LoadRequests 25
   ```
3. Ask the agent to investigate end-to-end.
4. The agent should trace:
   - App Service request failures or latency in the self-service portal
   - Function dependencies for the same `operation_Id`
   - Cosmos DB dependency errors / 429s in the catalog tier
   - SQL pressure or subscriber lookup latency if the issue fans out further
   - `cloud_RoleName` to separate web and function tiers
5. The expected root cause is **Cosmos RU throttling** in the catalog path.
6. Recover with the fix script.

### Optional secondary breaks

- `break-appservice-config.ps1` — invalidates `Cosmos__Endpoint`
- `break-function-timeout.ps1` — deploys a 250s HTTP function
- `break-sql-dtu.ps1` — starts parallel `sqlcmd` query-bomb workers

---

## Suggested Prompts

Use prompts like these in the SRE Agent portal:

- "Los usuarios reportan que Mi Movistar va lento. Investiga end-to-end."
- "Trace the request path from the self-service portal through the activation API to the catalog and subscriber stores. Which tier is the bottleneck?"
- "Why is the portal intermittent? Build a service map and highlight the failing dependency."
- "Correlate Application Insights requests and dependencies by operation_Id and cloud_RoleName."
- "Is the problem in App Service, Functions, Cosmos DB, SQL, or Storage? Show evidence for each tier."

---

## Recovery Command

Restore the demo baseline with:

```powershell
.\scripts\scenarios-multistack\fix-multistack.ps1 -ResourceGroupName rg-srelab-eastus2
```

If auto-discovery is not enough, pass explicit names for the Cosmos account, App Service, Function App, or SQL server.

---

## Cost Estimate

Module A adds approximately **$3–5/day** on top of the base lab, driven mainly by:

- App Service B1
- Cosmos DB provisioned throughput
- Azure SQL Database S0
- Additional Storage transactions and telemetry

Treat this as demo-lab guidance, not a production estimate.
