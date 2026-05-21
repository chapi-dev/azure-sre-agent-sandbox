# Movistar BSS Demo Lab - Copilot Instructions

## Project Overview

This repository contains a fully automated Azure SRE Agent demo lab environment. It deploys:

- **Azure Kubernetes Service (AKS)** with a multi-pod **Movistar BSS** simulator for self-service, plan management, top-ups, and provisioning flows
- **Azure Container Registry** for container images
- **Azure Key Vault** for secrets management
- **Observability stack**: Log Analytics, Application Insights, Managed Grafana
- **Breakable scenarios** for demonstrating SRE Agent diagnosis capabilities across a telco-flavored platform
- **SRE Agent configuration layer**: knowledge base runbooks, custom agents, connectors, and scheduled tasks
- **Six optional extension modules** for multi-stack Azure, AVD, Citrix MCP, skills/hooks/plugins, enterprise connectors, and governance/multi-model controls

The base application uses in-cluster **subscriber-db** (Mongo image) and **provisioning-queue** (RabbitMQ image) with Azure Managed Disk storage, and the extension modules layer on top without replacing the original AKS demo path.

> The UI still renders the upstream **AKS Store** text because the underlying images are Microsoft's `aks-store-demo` reference images. In this repo, treat that storefront as **Movistar's self-service portal**.

## Technology Stack

- **Infrastructure as Code**: Bicep (modular templates in `infra/bicep/`)
- **Container Orchestration**: Kubernetes (manifests in `k8s/`)
- **SRE Agent Config**: YAML specs and Markdown runbooks in `sre-config/`
- **Scripting**: PowerShell (deployment scripts in `scripts/`)
- **Dev Environment**: Dev Containers with Azure CLI, kubectl, azd

## Key Directories

```text
├── infra/bicep/                # Bicep IaC templates
│   ├── main.bicep              # Main deployment orchestration
│   ├── main.bicepparam         # Parameters file
│   └── modules/                # Modular Bicep templates
├── k8s/
│   ├── base/                   # Healthy Movistar BSS manifests
│   └── scenarios/              # Breakable failure scenarios
├── citrix-mcp/                 # Custom Citrix MCP server (Module C)
├── sre-config/                 # SRE Agent configuration layer
│   ├── knowledge-base/         # Runbooks uploaded to agent memory
│   ├── agents/                 # Custom agent YAML specifications
│   ├── connectors/             # MCP connector templates
│   ├── skills/                 # Custom Python skills (Module D)
│   ├── hooks/                  # Governance hooks (Module D)
│   ├── plugins/                # HTTP plugin definitions (Module D)
│   └── governance/             # Autonomy and model governance docs (Module F)
├── scripts/                    # Deployment and management scripts
│   ├── scenarios-avd/          # AVD break/fix scripts (Module B)
│   └── scenarios-multistack/   # Cross-stack break/fix scripts (Module A)
├── docs/                       # Documentation for the Movistar BSS demo lab
└── .devcontainer/              # Dev container configuration
```

## Extension Modules

- **Module A — Multi-stack Azure**: Movistar self-service portal, activation API, Cosmos catalog, SQL subscribers, and cross-stack investigation runbooks
- **Module B — AVD**: Azure Virtual Desktop host pool, session hosts, diagnostics, and AVD troubleshooting subagent
- **Module C — Citrix MCP**: custom Citrix DaaS MCP server, connector, and Citrix-focused session subagent
- **Module D — Skills / Hooks / Plugins**: custom Python skills, governance hooks, HTTP plugins, mock CMDB, and immutable audit pattern
- **Module E — Enterprise connectors**: ServiceNow, PagerDuty, Grafana MCP, Azure DevOps, Teams, Datadog, and incident routing orchestration
- **Module F — Governance / multi-model**: autonomy tiers, model-provider comparison, cost workbook, and alerting

## Azure SRE Agent Context

Azure SRE Agent is a Preview feature that provides AI-powered site reliability engineering automation:

- **Supported Regions**: East US 2, Sweden Central, Australia East
- **Firewall Requirement**: Allow `*.azuresre.ai`
- **RBAC Roles**: SRE Agent Admin, Standard User, Reader
- **Key Feature**: Natural language diagnosis and remediation

### SRE Agent Starter Prompts

For AKS issues:
- "Why are new line activations failing in the movistar namespace?"
- "Show me the health status of my AKS cluster"
- "What's causing high CPU usage on the Movistar BSS nodes?"

For general diagnosis:
- "What issues are affecting Mi Movistar right now?"
- "Analyze performance metrics and identify bottlenecks across the BSS stack"

## Breakable Scenarios

Located in `k8s/scenarios/`:

| File | Issue | SRE Agent Can Diagnose |
|------|-------|----------------------|
| `oom-killed.yaml` | `activation-service` memory exhaustion | OOMKilled events, memory limits |
| `crash-loop.yaml` | `catalog-service` startup failure | CrashLoopBackOff, exit codes |
| `image-pull-backoff.yaml` | Bad `provisioning-service` image | Registry/image issues |
| `high-cpu.yaml` | Resource exhaustion | CPU contention |
| `pending-pods.yaml` | Insufficient resources | Scheduling issues |
| `probe-failure.yaml` | Health check failure | Probe configuration |
| `network-block.yaml` | Connectivity issues | Network policies |
| `missing-config.yaml` | ConfigMap reference | Configuration issues |
| `mongodb-down.yaml` | `subscriber-db` cascading dependency failure | Dependency tracing, root cause |
| `service-mismatch.yaml` | Silent activation networking failure | Endpoint/selector analysis |

## Common Operations

### Dev Container Commands
Type `menu` in the terminal to see all available commands. Key shortcuts:
- `deploy` - Deploy infrastructure
- `destroy` - Tear down infrastructure
- `site` - Show customer portal URL
- `kgp` - Get pods in the `movistar` namespace
- `break-oom`, `break-crash`, `break-image` - Apply scenarios
- `break-mongodb` - Subscriber database failure
- `break-service` - Activation service selector mismatch
- `fix-all` - Restore healthy state

### Deploy Infrastructure
```powershell
# Base lab
.\scripts\deploy.ps1 -Location eastus2 -Yes

# Full extended demo
.\scripts\deploy.ps1 -Location eastus2 -DeployAll -Yes
```

Common extension flags:
- `-DeployMultiStack`
- `-DeployAvd`
- `-DeployCitrixMcp`
- `-DeploySkills`
- `-DeployHooks`
- `-DeployEnterprise`
- `-DeployGovernance`
- `-DeployAll`

> Modules C and E require external credentials and tenant-specific values.

### SRE Agent Deployment
SRE Agent is deployed automatically via Bicep (`Microsoft.App/agents@2025-05-01-preview`).
Set `deploySreAgent = true` in parameters (default). To manage the agent after deployment:
- Portal: https://aka.ms/sreagent/portal
- The deploying user is automatically assigned SRE Agent Administrator role

### Configure SRE Agent (Post-Deployment)

After infrastructure deployment, configure the agent with knowledge base, custom agents, connectors, and scheduled tasks via the dataplane v2 API:

```powershell
# Basic configuration (auto-called by deploy.ps1)
.\scripts\configure-sre-agent.ps1 -ResourceGroupName "rg-srelab-eastus2"

# With GitHub integration
.\scripts\configure-sre-agent.ps1 -ResourceGroupName "rg-srelab-eastus2" -GitHubPat $env:GITHUB_PAT -GitHubRepo "owner/repo"
```

### Apply Breakable Scenario
```bash
kubectl apply -f k8s/scenarios/oom-killed.yaml
```

### Restore Healthy State
```bash
kubectl apply -f k8s/base/application.yaml
```

### Destroy Infrastructure
```powershell
.\scripts\destroy.ps1 -ResourceGroupName "rg-srelab-eastus2"
```

## Important Constraints

1. **SRE Agent Regions**: Only deploy to eastus2, swedencentral, or australiaeast
2. **AKS Networking**: Must NOT be a private cluster for SRE Agent access
3. **Authentication**: Use device code auth in dev containers (`az login --use-device-code`)
4. **RBAC**: Some role assignments may fail due to subscription policies — use scripts
5. **No SAS Tokens**: Use Workload Identity instead of connection strings where possible

## Cost Considerations

- **Full deployment**: ~$22-28/day (~$650-850/month)
- **With SRE Agent**: ~$32-38/day (~$950-1,150/month)
- **See**: `docs/COSTS.md` for detailed breakdown

## When Helping with This Project

1. **For Bicep changes**: Follow best practices in `infra/bicep/` patterns
2. **For K8s manifests**: Use namespace `movistar`, label with `sre-demo: breakable`
3. **For scripts**: Use PowerShell, include error handling, support `-WhatIf`
4. **For docs**: Keep formatting consistent and use Movistar BSS / telco terminology where appropriate
5. **For new scenarios**: Add to `k8s/scenarios/` and update `docs/BREAKABLE-SCENARIOS.md`
6. **For runbooks**: Add `.md` files to `sre-config/knowledge-base/` — auto-discovered by `configure-sre-agent.ps1`
7. **For custom agents**: Add YAML specs to `sre-config/agents/` following existing patterns
8. **For new module skills**: Follow `sre-config/skills/README.md` schema
9. **For upstream image references**: keep literal `aks-store-demo` image names when they appear in manifests, scripts, or documentation notes
