# Module D — Skills, Hooks, and Plugins

Module D showcases the most differentiated Azure SRE Agent capabilities: custom skills, governance hooks, and HTTP plugins that enrich investigations beyond the built-in Azure tools.

## Concept map

| Concept | What it is | Example in this module |
|--------|-------------|------------------------|
| **Skill** | Custom Python tool the agent invokes like a first-party capability | Log anomaly detection, KQL generation, impact estimation, PDF reporting |
| **Hook** | Policy interception point around tool execution | Block deletes, validate CLI arguments, require approvals, emit audits |
| **Plugin** | REST API wrapper exposed as an agent tool | Mock CMDB lookups and Jira ticket updates |

## What gets deployed or registered

### Infrastructure

- **Mock CMDB Function App** (`infra\bicep\modules\mock-cmdb-function.bicep`)
  - Linux Consumption Function App
  - Node 20 runtime settings
  - Base URL used by the CMDB HTTP plugin
- **Audit Storage** (`infra\bicep\modules\audit-storage.bicep`)
  - Container: `agent-audit`
  - 90-day immutability policy
  - Blob write access granted to the SRE Agent managed identity

### Skills

- `analyze-log-patterns`
- `cost-impact-estimator`
- `kql-query-builder`
- `generate-incident-pdf`

### Hooks

- `stop-prod-deletes`
- `pre-tool-validation`
- `approval-required-restarts`
- `post-tool-audit`

### Plugins

- `cmdb-http-plugin`
- `jira-http-plugin`

### Upload helpers

- `scripts\upload-skills.ps1`
- `scripts\upload-hooks.ps1`
- `scripts\upload-plugins.ps1`

## Deployment flags

The integration layer for this module is expected to use these flags:

- `-DeploySkills`
  - Deploys the mock CMDB Function App
  - Uploads skill bundles
  - Registers HTTP plugins
- `-DeployHooks`
  - Deploys immutable audit storage
  - Registers governance hooks

After infrastructure deployment, the module assets can be pushed manually with:

```powershell
.\scripts\upload-skills.ps1 -ResourceGroupName "rg-srelab-eastus2"
.\scripts\upload-hooks.ps1 -ResourceGroupName "rg-srelab-eastus2"
.\scripts\upload-plugins.ps1 `
    -ResourceGroupName "rg-srelab-eastus2" `
    -MockCmdbUrl "https://func-cmdb-srelab.azurewebsites.net/api" `
    -MockCmdbKey "<function-key>"
```

## Demo flow 1 — Skill demo

### Goal
Have the agent investigate an incident, estimate cost, and generate a PDF report that can be attached to an email.

### Prompt to use

```text
Investigate the activation-service OOM incident in the movistar namespace. Estimate the business impact for 45 minutes of downtime affecting 320 subscribers, generate a PDF incident report with supporting metrics, and prepare it for email.
```

### Expected behavior

1. The agent analyzes logs with `analyze-log-patterns`
2. It calculates impact with `cost-impact-estimator`
3. It generates a charted PDF with `generate-incident-pdf`
4. It can attach the returned PDF payload to an email workflow

## Demo flow 2 — Hook demo

### Goal
Show governance controls blocking unsafe operations and capturing an audit trail when the action is allowed.

### Prompt to test outside business hours

```text
Run az group delete --name rg-srelab-eastus2 --subscription <sub-id>
```

**Expected result:** `stop-prod-deletes` blocks the request.

### Prompt to test during business hours (for a safe test resource)

```text
Run az group delete --name rg-srelab-scratch --subscription <sub-id>
```

**Expected result:**

1. At **10:00 UTC on a weekday**, the delete can proceed if no other hook blocks it
2. `post-tool-audit` writes a blob under:
   - `https://staudit<suffix>.blob.core.windows.net/agent-audit/{date}/{toolName}-{timestamp}.json`

### Additional validation prompt

```text
Run az aks delete --name aks-srelab --resource-group rg-srelab-eastus2 --subscription <sub-id>
```

**Expected result:** `pre-tool-validation` blocks the command before execution.

## Demo flow 3 — Plugin demo

### Goal
Use service metadata to enrich incident severity and recommended response.

### Prompt to use

```text
Investigate repeated OOMKilled restarts for activation-service in the movistar namespace. Use CMDB data to identify the owner, service criticality, dependencies, and linked runbook before you summarize severity.
```

### Expected behavior

1. The agent calls `cmdb-http-plugin.get_service_criticality`
2. The mock CMDB returns `high` for `activation-service`
3. The agent escalates severity in the incident summary
4. It can also use owner, dependencies, and runbook data for routing and next steps

## Cost estimate

This module adds only lightweight incremental cost compared to the base lab:

- Mock CMDB Function App: approximately **$1–3/day** depending on executions
- Audit Storage with immutable blobs: approximately **$1–2/day** depending on retention and write volume

**Estimated total:** **~$2–5/day**

## Notes

- Keep the audit hook enabled when demonstrating plugins or remediation actions
- Use test resource groups when validating destructive command hooks
- Store plugin secrets in Key Vault or the SRE Agent secret store instead of editing YAML in source control
