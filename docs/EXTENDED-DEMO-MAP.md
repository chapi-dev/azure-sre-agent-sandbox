# Extended Demo Map

The extended Azure SRE Agent demo lab keeps the current AKS-based deployment intact, then layers **six optional modules** on top of it: multi-stack Azure, Azure Virtual Desktop, Citrix via custom MCP, custom skills/hooks/plugins, enterprise connectors, and governance/multi-model controls. Each module is independently deployable through its own flag, so you can stay with the low-cost **Movistar BSS Demo Lab** baseline or assemble a larger 90-minute showcase without changing the existing AKS scenario mechanics.

> Assume the base lab is already deployed. All commands below describe the intended Phase 2 wire-up contract from `scripts\deploy.ps1` and `scripts\configure-sre-agent.ps1`.

## Overview

- **Base lab**: Movistar BSS on AKS + observability + Azure SRE Agent + break/fix scenarios
- **Module A**: cross-stack Azure incidents across App Service, Functions, Cosmos DB, SQL, and Storage
- **Module B**: Azure Virtual Desktop user/session troubleshooting
- **Module C**: Citrix DaaS integration through a custom MCP server
- **Module D**: custom skills, governance hooks, and HTTP plugins
- **Module E**: enterprise incident routing to ServiceNow, PagerDuty, Grafana, Azure DevOps, Teams, and Datadog
- **Module F**: autonomy tiers, multi-model comparison, and cost governance

## Architecture diagram

```text
                               ┌───────────────────────────────────────────────┐
                               │               Outer service ring              │
                               │ Movistar BSS | Multi-stack Azure |   AVD     │
                               │   on AKS     |   (Module A)       | (Module B)│
                               │             Citrix DaaS via MCP (Module C)   │
                               └───────────────────────────────────────────────┘
                                               ▲
                                               │
┌───────────────────────────────────────────────────────────────────────────────────────────────┐
│                             Connector and integration ring                                   │
│ Azure Monitor | Outlook | GitHub MCP | Citrix MCP | ServiceNow | PagerDuty | Grafana MCP    │
│ Azure DevOps  | Teams webhook | Datadog | HTTP plugins (CMDB / Jira)                        │
│                                   Modules C / D / E                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                          Capability and control ring                                   │  │
│  │ Subagents | Skills | Hooks | Scheduled tasks | Autonomy tiers | Multi-model routing    │  │
│  │                               Modules A / B / C / D / E / F                            │  │
│  │   ┌─────────────────────────────────────────────────────────────────────────────────┐   │  │
│  │   │                         SRE Agent (sre-srelab)                                 │   │  │
│  │   │ Knowledge base + incident context + remediation workflow orchestration         │   │  │
│  │   └─────────────────────────────────────────────────────────────────────────────────┘   │  │
│  └─────────────────────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Module matrix

| Module | Adds | Deployment flag | Cost delta | Demo time | Module doc |
|---|---|---|---:|---:|---|
| Module A — Multi-stack Azure | App Service, Function App, Cosmos DB, Azure SQL, extra Storage, cross-stack runbooks, `cross-stack-investigator` | `-DeployMultiStack` | `+$3-5/day` | 15 min | [MODULE-A-MULTI-STACK.md](MODULE-A-MULTI-STACK.md) |
| Module B — AVD | Host pool, workspace, app group, session hosts, AVD diagnostics, `avd-session-investigator` | `-DeployAvd` | `+$5-8/day` | 10 min | [MODULE-B-AVD.md](MODULE-B-AVD.md) |
| Module C — Citrix MCP | `citrix-mcp\` server, Container App, Key Vault, Citrix connector, `citrix-session-doctor` | `-DeployCitrixMcp` | `+$15-30/day` | 10 min | [MODULE-C-CITRIX.md](MODULE-C-CITRIX.md) |
| Module D — Skills / Hooks / Plugins | Python skills, governance hooks, HTTP plugins, mock CMDB, immutable audit storage | `-DeploySkills`, `-DeployHooks` | `+$2-5/day` | 15 min | [MODULE-D-SKILLS-HOOKS-PLUGINS.md](MODULE-D-SKILLS-HOOKS-PLUGINS.md) |
| Module E — Enterprise connectors | ServiceNow, PagerDuty, Grafana MCP, Azure DevOps, Teams, Datadog, `enterprise-incident-orchestrator` | `-DeployEnterprise` | `+$0/day Azure` + external SaaS cost | 10 min | [MODULE-E-ENTERPRISE-CONNECTORS.md](MODULE-E-ENTERPRISE-CONNECTORS.md) |
| Module F — Governance / multi-model | autonomy-tiered agents, governance docs, workbook, cost alerts, model comparison tooling | `-DeployGovernance` | `+$0-1/day Azure` + variable AAU / query cost | 10 min | [MODULE-F-GOVERNANCE.md](MODULE-F-GOVERNANCE.md) |

## Capability matrix

| SRE Agent capability | Base lab | Module A | Module B | Module C | Module D | Module E | Module F | Primary demo path |
|---|---|---|---|---|---|---|---|---|
| Knowledge base | ✅ | ✅ | ✅ | ✅ | — | ✅ | — | Base runbooks plus service-specific runbooks |
| Subagents | ✅ | ✅ | ✅ | ✅ | — | ✅ | ✅ | `incident-handler`, `cross-stack-investigator`, `avd-session-investigator`, `citrix-session-doctor`, `enterprise-incident-orchestrator`, autonomy agents |
| Skills | — | — | — | — | ✅ | — | — | `cost_impact_estimator`, `generate_incident_pdf`, `kql_query_builder` |
| Hooks | — | — | — | — | ✅ | — | ✅ | Stop / PreToolUse / PostToolUse governance guardrails |
| Plugins | — | — | — | — | ✅ | — | — | CMDB and Jira HTTP plugins |
| Connectors | ✅ | — | — | ✅ | ✅ | ✅ | — | Azure Monitor, Outlook, GitHub MCP, Citrix MCP, ServiceNow, PagerDuty, Grafana MCP, Azure DevOps, Teams, Datadog |
| Scheduled tasks | ✅ | — | — | — | — | — | — | `daily-health-check` remains the baseline recurring demo |
| Autonomy modes | — | — | — | — | — | — | ✅ | Read vs Review vs Operator comparison |
| MCP | ✅ | — | — | ✅ | — | ✅ | — | GitHub MCP in base, custom Citrix MCP in C, Grafana MCP in E |
| Multi-model | — | — | — | — | — | — | ✅ | Azure OpenAI vs Claude comparison |

## Deployment combinations

### 1. Lab base only

```powershell
.\scripts\deploy.ps1 -Location eastus2 -Yes
```

Default Movistar BSS on AKS + observability + SRE Agent. No extension flags.

### 2. AKS + AVD demo

```powershell
.\scripts\deploy.ps1 -Location eastus2 -DeployAvd -Yes
```

Use when you want the core Movistar BSS scenarios plus an on-call VDI troubleshooting story.

### 3. Cross-stack demo

```powershell
.\scripts\deploy.ps1 -Location eastus2 -DeployMultiStack -Yes
```

Use when you want self-service portal → activation API → catalog → subscribers correlation on top of the base lab.

### 4. Enterprise integrations only

```powershell
.\scripts\deploy.ps1 -Location eastus2 -DeployEnterprise -ServiceNowUrl "https://<instance>.service-now.com" -PagerDutyToken $env:PD_TOKEN -AzureDevOpsPat $env:ADO_PAT -TeamsWebhookUrl $env:TEAMS_WEBHOOK -Yes
```

Use when you want the base demo plus incident routing into external systems without deploying AVD, Citrix, or multi-stack Azure resources.

### 5. Everything

```powershell
.\scripts\deploy.ps1 -Location eastus2 -DeployAll -Yes
```

Recommended for the full 90-minute extended demo. Requires all external credentials for Modules C and E and model access for Module F.

## Cost summary

| Layer | Daily delta | Running total vs. base lab | Notes |
|---|---:|---:|---|
| Base lab + SRE Agent | `$32-38/day` | `$32-38/day` | Current recommended baseline |
| + Module A | `+$3-5/day` | `$35-43/day` | App Service + Cosmos + SQL + extra telemetry |
| + Module B | `+$5-8/day` | `$40-51/day` | Two AVD session hosts and storage |
| + Module C | `+$15-30/day` | `$55-81/day` | Container Apps environment + Key Vault + MCP service |
| + Module D | `+$2-5/day` | `$57-86/day` | Mock CMDB + immutable audit storage |
| + Module E | `+$0/day Azure` | `$57-86/day` + external SaaS | ServiceNow, PagerDuty, Teams, Grafana, ADO, Datadog are external |
| + Module F | `+$0-1/day Azure` | `$57-87/day` + external SaaS + variable AAU | Workbook/alerts are small; token and query cost vary |

> Use these as demo-lab estimates, not production forecasts. Module E adds third-party licensing, and Module F grows with AAU usage and Log Analytics queries.

## Prerequisites by module

All modules assume the base lab prerequisites from `README.md`: supported SRE Agent region, Azure subscription access, Azure CLI, and the base AKS/SRE Agent deployment.

| Module | External prerequisites | Notes |
|---|---|---|
| Module A — Multi-stack Azure | None beyond the base lab | Uses only Azure services already covered by the base deployment model |
| Module B — AVD | Test user account assignable to the AVD application group | Recommended to pre-stage one user and validate the web client at `https://client.wvd.microsoft.com` |
| Module C — Citrix MCP | Citrix Cloud tenant, DaaS enabled, Citrix API client (`CitrixCustomerId`, `CitrixClientId`, `CitrixClientSecret`) | Also requires the `citrix-mcp\` image to be built and pushed before the Container App is deployed |
| Module D — Skills / Hooks / Plugins | None for the core demo; optional Jira tenant if you want the Jira plugin live | Skills depend on `sre-config\skills\requirements.txt`; plugins should read secrets from Key Vault |
| Module E — Enterprise connectors | ServiceNow tenant, PagerDuty account/token, Grafana MCP endpoint, Azure DevOps org/project/PAT, Teams workflow webhook, optional Datadog account | These are configuration-only connectors; no extra Azure infra is required |
| Module F — Governance / multi-model | Azure OpenAI access and/or Claude access for side-by-side comparison | Workbook viewers also need access to the target resource group and Log Analytics workspace |

## Where to go next

- Use [DEMO-RUNBOOK.md](DEMO-RUNBOOK.md) for the full 90-minute presentation script.
- Use [LAB-GUIDE.md](LAB-GUIDE.md) for the Movistar BSS baseline labs.
- Use the per-module docs above for detailed prompts, break/fix flow, and external setup.
