# SRE Agent Prompts Guide — Movistar BSS

A curated collection of prompts to use with Azure SRE Agent when demoing the lab. Organized by scenario and intent.

## Getting Started (Healthy Cluster)

Start here when the cluster is healthy to show SRE Agent's baseline capabilities:

| Prompt | What It Shows |
|--------|---------------|
| "Show me the health status of my AKS cluster" | Cluster overview, node status, system pods |
| "Are there any issues in the movistar namespace?" | Baseline health check — confirms everything is green |
| "What workloads are running in my Movistar BSS platform?" | Inventory of deployments and replica counts |
| "Show me resource utilization across my BSS pods" | CPU/memory usage and headroom |
| "What changes were made to my cluster recently?" | Audit trail and event history |

---

## Per-Scenario Diagnosis Prompts

### OOMKilled (`break-oom`)

| Stage | Prompt |
|-------|--------|
| **Open-ended** | "New line activations are failing. Can you investigate?" |
| **Direct** | "Why is the activation-service pod restarting repeatedly?" |
| **Specific** | "I see OOMKilled events in the movistar namespace. What's going on?" |
| **Remediation** | "What memory limits should I set for activation-service?" |
| **Action** | "Can you increase the memory limit for activation-service to 256Mi?" |

### CrashLoopBackOff (`break-crash`)

| Stage | Prompt |
|-------|--------|
| **Open-ended** | "Customers can't browse plans in Mi Movistar. What broke?" |
| **Direct** | "Why is catalog-service in CrashLoopBackOff?" |
| **Specific** | "Show me the logs for the crashing catalog-service pods" |
| **Remediation** | "What's causing exit code 1 in catalog-service?" |
| **Action** | "Restart the catalog-service deployment" |

### ImagePullBackOff (`break-image`)

| Stage | Prompt |
|-------|--------|
| **Open-ended** | "Provisioning stopped after the last rollout. Help?" |
| **Direct** | "Why is provisioning-service stuck in ImagePullBackOff?" |
| **Specific** | "Is there an issue with the container image for provisioning-service?" |
| **Remediation** | "What image should provisioning-service be using?" |

### High CPU (`break-cpu`)

| Stage | Prompt |
|-------|--------|
| **Open-ended** | "Mi Movistar feels slow. What's going on?" |
| **Direct** | "Which workloads are consuming the most CPU?" |
| **Specific** | "Analyze CPU usage across all pods in movistar and identify contention" |
| **Remediation** | "What should I do about the cpu-stress-test workload?" |
| **Action** | "Delete the cpu-stress-test deployment" |

### Pending Pods (`break-pending`)

| Stage | Prompt |
|-------|--------|
| **Open-ended** | "I deployed more provisioning capacity, but it isn't starting" |
| **Direct** | "Why are my pods stuck in Pending?" |
| **Specific** | "Analyze cluster capacity versus what's being requested" |
| **Remediation** | "Should I scale the node pool or reduce resource requests?" |

### Probe Failure (`break-probe`)

| Stage | Prompt |
|-------|--------|
| **Open-ended** | "Provisioning keeps restarting even though the app looks healthy" |
| **Direct** | "Diagnose the health check failures in the movistar namespace" |
| **Specific** | "What's wrong with the liveness probe on unhealthy-service?" |
| **Remediation** | "How should I fix the probe configuration?" |

### Network Policy Block (`break-network`)

| Stage | Prompt |
|-------|--------|
| **Open-ended** | "Customers can browse plans, but new line activations fail immediately. What happened?" |
| **Direct** | "Why can't customer-portal reach activation-service?" |
| **Specific** | "Are there any network policies blocking traffic in the movistar namespace?" |
| **Remediation** | "How do I restore connectivity to activation-service?" |
| **Action** | "Delete the deny-activation-service network policy" |

### Missing ConfigMap (`break-config`)

| Stage | Prompt |
|-------|--------|
| **Open-ended** | "The CSR console won't start — it says something about missing config" |
| **Direct** | "What configuration is missing for misconfigured-service?" |
| **Specific** | "Check for ConfigMap or Secret reference errors in the movistar namespace" |

### MongoDB Down (`break-mongodb`)

| Stage | Prompt |
|-------|--------|
| **Open-ended** | "The portal is up, but plan changes and recharges aren't completing. What's wrong?" |
| **Direct** | "Why is provisioning-service failing health checks?" |
| **Follow-up** | "Is subscriber-db running? What depends on it?" |
| **Root cause** | "Trace the dependency chain — what broke first?" |
| **Action** | "Scale the subscriber-db deployment back to 1 replica" |

### Service Selector Mismatch (`break-service`)

| Stage | Prompt |
|-------|--------|
| **Open-ended** | "Mi Movistar loads, but activating a new line spins forever. Everything looks healthy though." |
| **Direct** | "Why does activation-service have no endpoints?" |
| **Specific** | "Compare the activation-service Service selector to the actual pod labels" |
| **Remediation** | "Fix the selector on activation-service so it matches the pods" |

---

## Proactive & Exploratory Prompts

Use these to demo SRE Agent's ability to investigate and report without a specific incident:

| Prompt | Demonstrates |
|--------|-------------|
| "Give me a health report for the movistar namespace" | Comprehensive status review |
| "Are there any pods that have restarted in the last hour?" | Proactive monitoring |
| "What's the resource utilization trend for my cluster?" | Capacity planning |
| "Check if any containers are running without resource limits" | Best-practice enforcement |
| "Are there any deprecated API versions in my workloads?" | Upgrade readiness |
| "Show me error trends from the last 24 hours" | Log analysis / App Insights |
| "What are the most common exceptions affecting activations or plan catalog traffic?" | Observability integration |

---

## Remediation Prompts

Show that SRE Agent can take action, not just report:

| Prompt | Action |
|--------|--------|
| "Restart the activation-service pods" | Rolling restart |
| "Scale catalog-service to 3 replicas" | Horizontal scaling |
| "Delete the cpu-stress-test deployment" | Resource cleanup |
| "Remove the deny-activation-service network policy" | Policy management |
| "Scale subscriber-db back to 1 replica" | Dependency restoration |

> **Note:** Remediation requires the SRE Agent to have write permissions (Contributor + AKS Cluster Admin). See [SRE-AGENT-SETUP.md](SRE-AGENT-SETUP.md) for RBAC configuration.

---

## Scheduled Tasks & Subagents

Demo proactive SRE automation:

| Prompt | What It Sets Up |
|--------|----------------|
| "Check the health of my AKS cluster every hour and alert if anything is unhealthy" | Recurring health check |
| "Monitor pod restarts in the movistar namespace and notify me if any pod restarts more than 3 times" | Threshold-based alerting |
| "Run a daily capacity analysis and report if any node is above 80% utilization" | Capacity monitoring |

To set these up in the portal:
1. Go to **Subagent builder** in your SRE Agent resource
2. Click **Create scheduled task**
3. Enter the prompt and set the schedule (for example, cron: `0 * * * *` for hourly)

### Pre-Configured Subagents

When you run `configure-sre-agent.ps1` (or let `deploy.ps1` call it automatically), these subagents are created:

| Subagent | Purpose | GitHub Required |
|----------|---------|----------------|
| **incident-handler** | Investigates alerts using knowledge base runbooks, collects evidence, identifies root cause | No (core) / Yes (full — creates GitHub issues) |
| **cluster-health-monitor** | Proactive health checks across pods, nodes, and resource utilization | No |
| **code-analyzer** | Correlates production errors with source code, creates detailed incident reports | Yes |

#### Using Subagents

After configuration, you can invoke subagents directly:

| Prompt | Subagent | What It Does |
|--------|----------|-------------|
| "Investigate the pod failures in the movistar namespace" | incident-handler | Runs the pod-failures runbook, queries logs, and reports findings |
| "Run a health check on my cluster" | cluster-health-monitor | Checks all pods, nodes, and services, then reports status |
| "Analyze the source code for the root cause of activation-service failures" | code-analyzer | Searches GitHub code, correlates with logs, and creates an issue |

#### Incident Response Plan

The configuration script also creates a response plan that auto-triggers the `incident-handler` subagent when pod failure alerts fire. This means:

1. A breakable scenario causes pod crashes
2. Azure Monitor fires an alert
3. The SRE Agent picks up the alert
4. The `incident-handler` subagent runs the relevant runbook automatically
5. Findings are summarized (and optionally written to a GitHub issue)

### Knowledge Base

The following runbooks are uploaded to the agent's knowledge base:

| Document | Content |
|----------|---------|
| `aks-pod-failures.md` | OOMKilled, CrashLoopBackOff, ImagePullBackOff, Pending, Probe, and Config errors |
| `network-connectivity.md` | Network policy blocks, service selector mismatches, and DNS issues |
| `dependency-failures.md` | `subscriber-db` / `provisioning-queue` outages and cascading failure analysis |
| `resource-exhaustion.md` | CPU contention, memory pressure, scheduling failures, and node health |
| `app-architecture.md` | Movistar BSS service map, dependencies, ports, storage, and common failure modes |
| `incident-report-template.md` | Structured template for GitHub incident reports |

> **Tip:** You can add custom runbooks to `sre-config/knowledge-base/` and re-run `configure-sre-agent.ps1` to upload them.

### GitHub MCP Integration (Optional)

When you provide a GitHub PAT, the configuration script enables:

- **GitHub MCP connector** — lets the agent search code, read files, and create issues
- **Full incident-handler** — upgraded to create GitHub issues with structured reports
- **code-analyzer subagent** — deep source code root cause analysis

To add GitHub integration after initial setup:
```powershell
.\scripts\configure-sre-agent.ps1 `
    -ResourceGroupName "rg-srelab-eastus2" `
    -GitHubPat $env:GITHUB_PAT `
    -GitHubRepo "owner/repo"
```

---

## "What Changed?" Correlation

After applying a break scenario, instead of asking "what's wrong," try asking about changes:

| Prompt | Why It's Interesting |
|--------|---------------------|
| "What changed in my cluster in the last 10 minutes?" | Shows audit and event correlation |
| "Were any deployments modified recently?" | Traces the break to a specific change |
| "Show me the diff between the current and previous deployment of activation-service" | Rollback context |

---

## Tips for Effective Prompts

1. **Start vague, get specific** — open with "something seems wrong" and let SRE Agent discover the issue, then drill down with follow-up questions
2. **Ask for root cause** — "Why?" is more powerful than "show me the status"
3. **Request action** — don't just diagnose; ask SRE Agent to fix it
4. **Use follow-ups** — SRE Agent maintains context within a conversation, so build on previous answers
5. **Try the naive-user approach** — prompts like "Mi Movistar is broken" or "líneas no activan" are great starting points
6. **Combine observability** — ask about logs, metrics, and events together: "Correlate the pod restarts with any CPU or memory spikes"
