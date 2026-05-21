# Movistar SRE Agent BSS Demo Lab 

**Telefónica Movistar self-service + provisioning platform simulator on AKS**

A fully automated Azure environment for demonstrating **Azure SRE Agent** against a multi-service **Movistar BSS** application. Deploy a breakable AKS-based self-service and OSS provisioning platform, then optionally add **six extension modules** for multi-stack Azure, AVD, Citrix MCP, skills/hooks/plugins, enterprise connectors, and governance — all while keeping the original AKS lab mechanics intact.

## 🎯 What This Lab Provides

- **Azure Kubernetes Service (AKS)** with a multi-service **Movistar BSS** application simulating self-service plan management, top-ups, plan changes, and line activations
- **10 breakable scenarios** for demonstrating SRE Agent diagnosis and remediation
- **Azure SRE Agent** deployed automatically via Bicep for AI-powered diagnostics
- **SRE Agent configuration layer**: knowledge base runbooks, custom agents, connectors, and scheduled tasks
- **Full observability stack**: Log Analytics, Application Insights, Managed Grafana
- **Ready-to-use scripts** for deployment, teardown, and scenario handling
- **Dev container** for a consistent demo experience

## 🧭 Brand note — UI text vs. lab narrative

> **Important:** The underlying container images are Microsoft's `aks-store-demo` reference images, so the storefront UI text says **"AKS Store"**. For the purposes of this lab, treat that UI as **Movistar's self-service portal** — the rebranding lives in the Kubernetes resource names, knowledge base, runbooks, prompts, and tooling.

## 🚀 Extended Modules

Optional modules can be layered onto the base Movistar BSS lab independently.

| Module | What it adds | Flag | Doc |
|--------|--------------|------|-----|
| Module A — Multi-stack Azure | App Service, Function App, Cosmos DB, Azure SQL, Storage, cross-stack investigator | `-DeployMultiStack` | [MODULE-A-MULTI-STACK.md](docs/MODULE-A-MULTI-STACK.md) |
| Module B — AVD | Host pool, session hosts, AVD diagnostics, AVD subagent | `-DeployAvd` | [MODULE-B-AVD.md](docs/MODULE-B-AVD.md) |
| Module C — Citrix MCP | Custom Citrix MCP server, connector, Citrix subagent | `-DeployCitrixMcp` | [MODULE-C-CITRIX.md](docs/MODULE-C-CITRIX.md) |
| Module D — Skills / Hooks / Plugins | Python skills, governance hooks, HTTP plugins, mock CMDB, immutable audit | `-DeploySkills`, `-DeployHooks` | [MODULE-D-SKILLS-HOOKS-PLUGINS.md](docs/MODULE-D-SKILLS-HOOKS-PLUGINS.md) |
| Module E — Enterprise connectors | ServiceNow, PagerDuty, Grafana MCP, Azure DevOps, Teams, Datadog | `-DeployEnterprise` | [MODULE-E-ENTERPRISE-CONNECTORS.md](docs/MODULE-E-ENTERPRISE-CONNECTORS.md) |
| Module F — Governance / multi-model | autonomy tiers, model comparison, cost workbook and alerts | `-DeployGovernance` | [MODULE-F-GOVERNANCE.md](docs/MODULE-F-GOVERNANCE.md) |

See [EXTENDED-DEMO-MAP.md](docs/EXTENDED-DEMO-MAP.md) for the full roadmap and recommended combinations.

## 🚀 Quick Start

### Prerequisites

- Azure subscription with Owner/Contributor access
- Azure region supporting SRE Agent: `East US 2`, `Sweden Central`, or `Australia East`
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) installed
- [VS Code](https://code.visualstudio.com/) with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (optional but recommended)

![Menu](media/menu.png)

### Deploy

```powershell
# 1. Login to Azure
az login --use-device-code

# 2. Deploy the base lab (~15-25 minutes)
.\scripts\deploy.ps1 -Location eastus2 -Yes

# 3. Optional: deploy all six extension modules for the full demo
.\scripts\deploy.ps1 -Location eastus2 -DeployAll -Yes
```

> 💡 **Tip:** No extension flags = base lab only. Type `menu` in the terminal to see available break scenarios, fix commands, and kubectl shortcuts.

## 💥 Breaking Things (The Fun Part)

Once deployed, you can break the Movistar BSS platform using shortcut commands:

```bash
# Activations failing with OOMKilled
break-oom

# Catalog service CrashLoopBackOff
break-crash

# Provisioning image pull failure
break-image

# See all scenarios
menu
```

To restore:

```bash
fix-all
```

## 🤖 Using SRE Agent

After deployment, `deploy.ps1` automatically configures the SRE Agent with:

- **Knowledge base** — runbooks for pod failures, networking, dependencies, resource exhaustion, and Movistar BSS architecture
- **Custom agents** — `incident-handler` (alert investigation), `cluster-health-monitor` (proactive checks), and optionally `code-analyzer` (GitHub source code RCA)
- **Connectors** — Azure Monitor (incident source) and optionally GitHub MCP (source code search)
- **Scheduled tasks** — `daily-health-check` runs cluster-health-monitor every day at 08:00 UTC

With the extension modules enabled, the agent can also use **custom skills**, **governance hooks**, **HTTP plugins**, and additional connectors for Citrix, ServiceNow, PagerDuty, Grafana, Azure DevOps, Teams, and more. Start with [Module D](docs/MODULE-D-SKILLS-HOOKS-PLUGINS.md) and use [DEMO-RUNBOOK.md](docs/DEMO-RUNBOOK.md) for the full end-to-end demo flow.

### Getting Started

1. **Open the SRE Agent Portal** — the URL is displayed in deployment output, or visit [sre.azure.com](https://sre.azure.com)
2. **Verify configuration** — check Builder > Agent Canvas and Knowledge Files
3. **Break something** — `break-oom`, `break-crash`, etc.
4. **Ask the agent to investigate** — or create an incident response plan in the portal
5. **Try prompts like:**
   - "Why are new line activations failing in the movistar namespace?"
   - "Run a health check on my AKS cluster and summarize any BSS risk."
   - "Trace the dependency chain — why can't subscribers change plans or recharge?"

### Adding GitHub Integration

To enable source code analysis and automated issue creation:

```powershell
.\scripts\configure-sre-agent.ps1 `
    -ResourceGroupName "rg-srelab-eastus2" `
    -GitHubPat $env:GITHUB_PAT `
    -GitHubRepo "owner/repo"
```

See [docs/SRE-AGENT-SETUP.md](docs/SRE-AGENT-SETUP.md) for detailed instructions, or [docs/PROMPTS-GUIDE.md](docs/PROMPTS-GUIDE.md) for a full catalog of prompts to try.

## 💰 Cost Estimate

| Configuration | Daily Cost | Monthly Cost |
|--------------|------------|--------------|
| Base deployment | ~$22-28 | ~$650-850 |
| + SRE Agent (recommended base lab) | ~$32-38 total | ~$950-1,150 total |
| + Module A — Multi-stack Azure | +$3-5 | +$90-150 |
| + Module B — AVD | +$5-8 | +$150-240 |
| + Module C — Citrix MCP | +$15-30 | +$450-900 |
| + Module D — Skills / Hooks / Plugins | +$2-5 | +$60-150 |
| + Module E — Enterprise connectors | +$0 Azure + external SaaS cost | External |
| + Module F — Governance / multi-model | +$0-1 Azure + variable AAU/query cost | Variable |

See [docs/COSTS.md](docs/COSTS.md), [docs/EXTENDED-DEMO-MAP.md](docs/EXTENDED-DEMO-MAP.md), and the per-module docs for detailed assumptions and optimization tips.

## 🔧 Available Scenarios

| Scenario | Description | SRE Agent Diagnoses |
|----------|-------------|---------------------|
| OOMKilled | `activation-service` gets OOMKilled during peak provisioning load | Memory exhaustion, limit recommendations |
| CrashLoop | `catalog-service` crashes on startup, plans disappear from the portal | Exit codes, log analysis |
| ImagePullBackOff | Bad image tag halts `provisioning-service` rollout | Registry/image troubleshooting |
| HighCPU | Rogue workload saturates BSS node CPU | Performance analysis |
| PendingPods | Cluster capacity is exhausted for new provisioning workloads | Scheduling analysis |
| ProbeFailure | Health checks churn on the provisioning path | Probe configuration |
| NetworkBlock | `customer-portal` cannot reach `activation-service` | Connectivity analysis |
| MissingConfig | Back-office configuration error breaks the CSR console path | Configuration troubleshooting |
| MongoDBDown | `subscriber-db` is offline, cascading across activations and recharges | Dependency tracing, root cause |
| ServiceMismatch | `activation-service` selector mismatch creates silent failures | Endpoint/selector analysis |

## 🛠️ Commands Reference

### Deployment Scripts (PowerShell)

> **Note:** These PowerShell scripts deploy to Azure and can be run from the dev container, locally on Windows, or on any system with PowerShell Core installed.

| Command | Description |
|---------|-------------|
| `.\scripts\deploy.ps1 -Location eastus2` | Deploy all infrastructure to Azure |
| `.\scripts\deploy.ps1 -WhatIf` | Preview what would be deployed |
| `.\scripts\configure-sre-agent.ps1 -ResourceGroupName <rg>` | Configure SRE Agent (KB, agents, connectors) |
| `.\scriptsalidate-deployment.ps1 -ResourceGroupName <rg>` | Verify resources and the Movistar BSS app are healthy |
| `.\scripts\destroy.ps1 -ResourceGroupName <rg>` | Tear down all infrastructure |

**Deploy script parameters:**
- `-Location`: Azure region (`eastus2`, `swedencentral`, `australiaeast`) — Default: `eastus2`
- `-WorkloadName`: Resource prefix — Default: `srelab`
- `-SkipRbac`: Skip RBAC assignments if subscription policies block them
- `-WhatIf`: Preview deployment without making changes
- `-Yes`: Skip confirmation prompts (non-interactive mode)

### Kubernetes Commands (kubectl)

| Command | Description |
|---------|-------------|
| `kubectl apply -f k8s/base/application.yaml` | Deploy healthy Movistar BSS application |
| `kubectl apply -f k8s/scenarios/<scenario>.yaml` | Apply a break scenario |
| `kubectl get pods -n movistar` | Check pod status |
| `kubectl get events -n movistar --sort-by='.lastTimestamp'` | View recent events |

## ⚙️ SRE Agent Configuration Layer

The `sre-config/` directory contains the SRE Agent configuration layer:

```text
sre-config/
├── knowledge-base/                # Runbooks uploaded to agent memory
│   ├── aks-pod-failures.md        # OOM, CrashLoop, ImagePull, Pending, Probe, Config
│   ├── network-connectivity.md    # Network policies, selector mismatches, DNS
│   ├── dependency-failures.md     # subscriber-db / provisioning-queue outages, cascading analysis
│   ├── resource-exhaustion.md     # CPU, memory, scheduling, node health
│   ├── app-architecture.md        # Movistar BSS service map, dependencies, monitoring queries
│   └── incident-report-template.md # Structured GitHub issue template
├── agents/                        # Custom agent YAML specifications
│   ├── incident-handler-core.yaml   # Log/metric investigation (no GitHub)
│   ├── incident-handler-full.yaml   # Full investigation + GitHub issues
│   ├── cluster-health-monitor.yaml  # Proactive health checks
│   └── code-analyzer.yaml           # Source code RCA (requires GitHub)
└── connectors/
    ├── azure-monitor.yaml          # Azure Monitor incident connector
    └── github-mcp.yaml            # GitHub MCP connector template
```

## 📚 Documentation

- [Extended Demo Map](docs/EXTENDED-DEMO-MAP.md) — roadmap, module matrix, deployment combinations, and prerequisites
- [Demo Runbook](docs/DEMO-RUNBOOK.md) — 90-minute end-to-end presentation script
- [Lab Guide](docs/LAB-GUIDE.md) — 60–90 minute hands-on Movistar BSS walkthrough
- [Module A — Multi-stack Azure](docs/MODULE-A-MULTI-STACK.md)
- [Module B — AVD](docs/MODULE-B-AVD.md)
- [Module C — Citrix MCP](docs/MODULE-C-CITRIX.md)
- [Module D — Skills, Hooks, and Plugins](docs/MODULE-D-SKILLS-HOOKS-PLUGINS.md)
- [Module E — Enterprise Connectors](docs/MODULE-E-ENTERPRISE-CONNECTORS.md)
- [Module F — Governance](docs/MODULE-F-GOVERNANCE.md)
- [SRE Agent Setup Guide](docs/SRE-AGENT-SETUP.md) — deployment, RBAC, and configuration
- [Prompts Guide](docs/PROMPTS-GUIDE.md) — prompts, agents, knowledge base, GitHub integration
- [Breakable Scenarios Guide](docs/BREAKABLE-SCENARIOS.md)
- [Cost Estimation](docs/COSTS.md)

## 🤝 Contributing

Contributions welcome! Feel free to open issues or submit PRs.

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

**⚠️ Important Notes:**

- SRE Agent is currently in **Preview**
- Only available in **East US 2**, **Sweden Central**, and **Australia East**
- AKS cluster must **NOT** be a private cluster for SRE Agent to access
- Firewall must allow `*.azuresre.ai`
