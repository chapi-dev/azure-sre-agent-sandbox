# Module E — Enterprise Connectors

Module E extends the Azure SRE Agent demo lab with enterprise SaaS integrations for incident intake, enrichment, escalation, and collaboration.

## What gets configured

This module does **not** deploy additional Azure infrastructure. It only adds SRE Agent configuration assets:

- Connector templates in `sre-config\connectors\`
- An enterprise orchestration subagent in `sre-config\agents\`
- Routing and escalation runbooks in `sre-config\knowledge-base\`

All external systems must already exist and be reachable before you configure the agent:

- ServiceNow
- PagerDuty
- Grafana MCP endpoint
- Azure DevOps organization/project
- Microsoft Teams workflow webhook
- Datadog account

The follow-up wire-up change is expected to update `scripts\configure-sre-agent.ps1` so it can replace placeholders in these YAML files and submit them to the SRE Agent connectors endpoint.

---

## Per-connector setup guide

### 1. ServiceNow (`sre-config\connectors\servicenow.yaml`)

**What you need**
- ServiceNow instance URL, for example `https://YOUR_INSTANCE.service-now.com`
- OAuth Application Registry integration (recommended)
- Client ID and Client Secret
- Integration user for incident read/write access

**Where to store credentials**
- `servicenow-client-id`
- `servicenow-client-secret`
- `servicenow-username`
- `servicenow-password`

**Placeholders to replace**
- `YOUR_INSTANCE`
- `YOUR_SERVICE_NOW_CLIENT_ID`
- `YOUR_SERVICE_NOW_CLIENT_SECRET`
- `YOUR_SERVICE_NOW_INTEGRATION_USERNAME`
- `YOUR_SERVICE_NOW_INTEGRATION_PASSWORD`

**Notes**
- Prefer OAuth2.
- Basic auth is included only as a fallback pattern for lab environments.
- Required scopes should include `useraccount` or the equivalent scoped app permission for `x_microsoft_sre`.

### 2. PagerDuty (`sre-config\connectors\pagerduty.yaml`)

**What you need**
- REST API user token created from **My Profile → User Settings → Create API User Token**
- PagerDuty service ID
- PagerDuty team ID
- Optional escalation policy ID

**Where to store credentials**
- `pagerduty-token`

**Placeholders to replace**
- `YOUR_PAGERDUTY_API_TOKEN`
- `YOUR_PAGERDUTY_SERVICE_ID`
- `YOUR_PAGERDUTY_TEAM_ID`
- `YOUR_PAGERDUTY_ESCALATION_POLICY_ID`

### 3. Grafana MCP (`sre-config\connectors\grafana-mcp.yaml`)

**What you need**
- Hosted or self-hosted Grafana MCP endpoint
- Grafana service account token
- Optional org ID if you do not use the default org

**Where to store credentials**
- `grafana-mcp-url`
- `grafana-token`

**Placeholders to replace**
- `YOUR_GRAFANA_MCP_URL`
- `YOUR_GRAFANA_SERVICE_ACCOUNT_TOKEN`

**Supported patterns**
- Grafana hosted MCP
- Self-hosted `grafana/mcp-grafana`
- Azure Managed Grafana MCP endpoint when available

### 4. Azure DevOps (`sre-config\connectors\azure-devops.yaml`)

**What you need**
- Organization URL, for example `https://dev.azure.com/YOUR_ORG`
- Project name
- PAT with **Work Items: Read & Write**, **Code: Read**, and **Build: Read**
- Repo names to search for code and deployment context

**Where to store credentials**
- `azure-devops-pat`

**Placeholders to replace**
- `YOUR_ORG`
- `YOUR_PROJECT`
- `YOUR_AZURE_DEVOPS_PAT`
- `YOUR_APP_REPO`
- `YOUR_INFRA_REPO`

### 5. Teams webhook (`sre-config\connectors\teams-webhook.yaml`)

**What you need**
- A Teams Workflows webhook URL for the target channel
- An Adaptive Card payload shape for notifications

**Where to store credentials**
- `teams-webhook-url`

**Placeholders to replace**
- `YOUR_WORKFLOW_OR_TEAMS_WEBHOOK_URL`

**Notes**
- Classic Office 365 connectors are deprecated.
- Use Teams Workflows or another supported incoming HTTP workflow.

### 6. Datadog (`sre-config\connectors\datadog.yaml`)

**What you need**
- Datadog site, such as `datadoghq.com` or `datadoghq.eu`
- Datadog API key
- Datadog app key with at least **Monitors Read**, **Metrics Read**, and **Events Read**

**Where to store credentials**
- `datadog-api-key`
- `datadog-app-key`

**Placeholders to replace**
- `YOUR_DATADOG_API_KEY`
- `YOUR_DATADOG_APP_KEY`
- `site`
- `defaultEnv`
- `defaultService`

---

## Key Vault guidance

Store every secret in Azure Key Vault and inject it during the configuration step. Recommended pattern:

1. Create one secret per token or password.
2. Grant the deployment identity `Key Vault Secrets User` or equivalent read access.
3. Pass secret values into the configuration script through environment variables or runtime lookup.
4. Keep only placeholders in source control.

---

## Planned deployment flag

The intended Module E wire-up command is:

```powershell
.\scripts\configure-sre-agent.ps1 `
  -ResourceGroupName "rg-srelab-eastus2" `
  -DeployEnterprise `
  -ServiceNowUrl "https://YOUR_INSTANCE.service-now.com" `
  -ServiceNowClientId "YOUR_SERVICE_NOW_CLIENT_ID" `
  -ServiceNowClientSecret $env:SN_SECRET `
  -PagerDutyToken $env:PD_TOKEN `
  -GrafanaMcpUrl "https://YOUR_GRAFANA_MCP_URL/mcp" `
  -GrafanaToken $env:GRAFANA_TOKEN `
  -AzureDevOpsOrgUrl "https://dev.azure.com/YOUR_ORG" `
  -AzureDevOpsProject "YOUR_PROJECT" `
  -AzureDevOpsPat $env:ADO_PAT `
  -TeamsWebhookUrl $env:TEAMS_WEBHOOK `
  -DatadogApiKey $env:DD_API `
  -DatadogAppKey $env:DD_APP
```

> This command documents the expected interface for the later wire-up step. This task only adds the connector, agent, runbook, and documentation files.

---

## Demo flow

1. Apply the AKS memory scenario:
   ```powershell
   kubectl apply -f k8s\scenarios\oom-killed.yaml
   ```
2. Azure Monitor detects the failure condition and raises the incident.
3. `enterprise-incident-orchestrator` activates.
4. The agent investigates with Azure diagnostics plus Grafana MCP context.
5. The agent opens or updates a ServiceNow incident, alerts PagerDuty if needed, creates an Azure DevOps Bug, and posts a Teams summary.
6. The operator can see the same incident context mirrored across ServiceNow, PagerDuty, Azure DevOps, and Teams.
7. If Datadog is connected, the agent can also pull monitor and event context to enrich the timeline.

---

## Suggested prompts

- `A new Azure Monitor alert fired for AKS memory pressure. Run the enterprise incident flow.`
- `Investigate the latest Sev2 incident and sync progress to ServiceNow, Azure DevOps, and Teams.`
- `Correlate this PagerDuty incident with Azure logs and Grafana dashboards, then open a bug.`
- `Use the enterprise-incident-orchestrator to triage the current platform incident.`
- `Post an incident update to the on-call Teams channel and attach the Azure DevOps bug link.`
- `If this is after hours and severity is high, escalate it through PagerDuty.`
