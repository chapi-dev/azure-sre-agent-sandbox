# Enterprise Connectors

These files extend the base demo with enterprise incident-management, collaboration, and observability integrations. Treat every YAML file in `sre-config\connectors\` as a template: the wire-up step should substitute placeholders with real values from Azure Key Vault before posting the connector definition to the SRE Agent connectors endpoint.

## Connector catalog

| File | Connector type | Supports | Primary use | Required setup |
|---|---|---|---|---|
| `azure-monitor.yaml` | `AzureMonitor` | Source | Native Azure alert and incident ingestion | Connected Azure resources plus agent RBAC |
| `github-mcp.yaml` | `StreamableHttp` | Context | Code search, repo context, optional issue workflows | GitHub PAT and repo scope |
| `outlook.yaml` | `Outlook` | Sink | Email summaries and human notifications | OAuth consent in SRE Agent portal |
| `servicenow.yaml` | `ServiceNow` | Both | Ingest incidents, add work notes, create/update records | ServiceNow instance URL, OAuth app or integration user, incident table |
| `pagerduty.yaml` | `PagerDuty` | Both | Escalation, notes, and incident synchronization | PagerDuty API token plus service/team scope |
| `grafana-mcp.yaml` | `StreamableHttp` | Context | Query dashboards and metrics through a Grafana MCP endpoint | Grafana MCP URL and service account token |
| `azure-devops.yaml` | `AzureDevOps` | Both | Create work items and search repos/builds for deployment context | Organization URL, project, PAT or OAuth app, repo list |
| `teams-webhook.yaml` | `Webhook` | Sink | Post Adaptive Card summaries to a Teams channel | Teams Workflows webhook URL |
| `datadog.yaml` | `Datadog` | Source/Context | Pull monitor, metric, and event context during investigations | Datadog site, API key, and app key |

> `Context` means the connector is primarily used as a tool surface during an investigation instead of acting as the source of record for an incident.

## Setup principles

1. **Use Key Vault for every secret**: PATs, bearer tokens, webhook URLs, client secrets, and app keys should come from Azure Key Vault at deployment time.
2. **Never commit live credentials**: keep only placeholders in this repo.
3. **Prefer service accounts over personal accounts**: create dedicated non-human identities in ServiceNow, PagerDuty, Grafana, Azure DevOps, and Datadog.
4. **Use least privilege scopes**: grant only the read/write actions required for the demo path.
5. **Prefer Workload Identity where possible**: use Azure-managed identities to retrieve secrets and configuration from Azure services instead of storing connection strings.
6. **Separate demo and production tenants**: point the lab at sandbox or non-production SaaS accounts whenever possible.
7. **Rotate and audit**: define token rotation owners, expiry dates, and logging for every connector.

## Recommended secret mapping

| Connector | Suggested Key Vault secrets |
|---|---|
| ServiceNow | `servicenow-client-id`, `servicenow-client-secret`, `servicenow-username`, `servicenow-password` |
| PagerDuty | `pagerduty-token` |
| Grafana MCP | `grafana-mcp-url`, `grafana-token` |
| Azure DevOps | `azure-devops-pat` |
| Teams webhook | `teams-webhook-url` |
| Datadog | `datadog-api-key`, `datadog-app-key` |
| GitHub MCP | `github-pat` |

## Operational notes

- Native connectors such as Azure Monitor, Outlook, ServiceNow, PagerDuty, Azure DevOps, and Datadog should be treated as first-class sources or sinks.
- MCP-based connectors (`github-mcp.yaml`, `grafana-mcp.yaml`) are ideal for read-heavy investigation context.
- The Teams webhook connector is outbound only and should be used for concise incident updates, not as a system of record.
- The enterprise orchestrator agent in `sre-config\agents\enterprise-incident-orchestrator.yaml` assumes these connectors exist and are reachable.
