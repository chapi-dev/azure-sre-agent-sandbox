# Movistar BSS Demo Lab — Hands-On Guide 📡

A step-by-step walkthrough for deploying the demo environment, exploring the healthy **Movistar BSS** application, breaking things, and watching Azure SRE Agent diagnose and fix them.

**Time estimate:** 60–90 minutes for all three labs (or pick just one)

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Part 1: Deploy and Explore](#part-1-deploy-and-explore)
- [Part 2: Verify the Healthy Application](#part-2-verify-the-healthy-application)
- [Part 3: Explore SRE Agent (Baseline)](#part-3-explore-sre-agent-baseline)
- [Lab 1: OOMKilled — Activation surge overload](#lab-1-oomkilled--activation-surge-overload)
- [Lab 2: subscriber-db Down — Cascading BSS failure](#lab-2-subscriber-db-down--cascading-bss-failure)
- [Lab 3: Service Mismatch — Silent activation failure](#lab-3-service-mismatch--silent-activation-failure)
- [Bonus: Automated Incident Response with Outlook](#bonus-automated-incident-response-with-outlook)
- [Explore More Scenarios](#explore-more-scenarios)
- [Cleanup](#cleanup)

---

## Prerequisites

Before starting, make sure you have:

- [ ] Azure subscription with Owner or Contributor access
- [ ] Access to a supported SRE Agent region: **East US 2**, **Sweden Central**, or **Australia East**
- [ ] VS Code with the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension (recommended), or Azure CLI + kubectl installed locally
- [ ] Firewall allows access to `*.azuresre.ai`

### Open the Dev Container

1. Clone the repository and open it in VS Code
2. When prompted, click **Reopen in Container** (or use the command palette: `Dev Containers: Reopen in Container`)
3. Wait for the container to build — it installs Azure CLI, kubectl, Helm, PowerShell, and helpful aliases
4. Type `menu` in the terminal to see all available commands

---

## Part 1: Deploy and Explore

### 1.1 — Log in to Azure

```powershell
az login --use-device-code
```

Follow the device code prompt to authenticate. Verify you're on the right subscription:

```powershell
az account show --query '{Name:name, Id:id}' -o table
```

### 1.2 — Deploy the Infrastructure

This creates AKS, Container Registry, Key Vault, Log Analytics, Application Insights, Managed Grafana, and the SRE Agent — all via Bicep.

```powershell
.\scripts\deploy.ps1 -Location eastus2 -Yes
```

Deployment takes approximately 15–25 minutes. While it runs, the script will:

1. Deploy all Azure infrastructure via Bicep
2. Get AKS credentials and deploy the **Movistar BSS simulator**
3. Configure the SRE Agent with knowledge base, custom agents, connectors, and scheduled tasks

> **Cost note:** The full environment costs ~$32–38/day with SRE Agent enabled. See [COSTS.md](COSTS.md) for a breakdown.

### 1.3 — Confirm Everything Is Running

Once the deployment completes, verify the pods:

```bash
kgp
```

You should see all pods in `Running` status with `1/1` ready:

```text
NAME                                   READY   STATUS    RESTARTS   AGE
subscriber-db-7f5f5c5d4-xxxxx          1/1     Running   0          5m
activation-service-6d8f7b9c5-xxxxx     1/1     Running   0          5m
provisioning-service-5f4d6e8b7-xxxxx   1/1     Running   0          5m
catalog-service-4c3d5f7a6-xxxxx        1/1     Running   0          5m
provisioning-queue-3b2c4d6e5-xxxxx     1/1     Running   0          5m
csr-console-2a1b3c5d4-xxxxx            1/1     Running   0          5m
customer-portal-1z0a2b4c3-xxxxx        1/1     Running   0          5m
traffic-simulator-9x8w7v6u-xxxxx       1/1     Running   0          5m
network-worker-8w7v6u5t-xxxxx          1/1     Running   0          5m
```

> **Tip:** If any pods aren't ready yet, wait a minute and run `kgp` again. The first pull of container images can take a moment.

---

## Part 2: Verify the Healthy Application

Before breaking anything, confirm the application is working end-to-end.

### 2.1 — Open the Customer Portal

Get the external URL:

```bash
site
```

This prints the **customer portal** URL (for example, `http://20.x.x.x`). Open it in your browser — the page text still says **AKS Store** because of the upstream image, but for the demo you should treat it as **Mi Movistar**.

### 2.2 — Walk Through the Architecture

The application is a multi-service **Movistar self-service and provisioning platform**:

| Service | Language | Role |
|---------|----------|------|
| **customer-portal** | Vue.js | Consumer-facing self-service portal (“Mi Movistar”) |
| **csr-console** | Vue.js | Customer Service Rep console |
| **activation-service** | Node.js | Handles activations, plan changes, and top-ups via the provisioning queue |
| **catalog-service** | Rust | Tariff, bundle, and plan catalog API |
| **provisioning-service** | Go | Simulates OSS / HLR-HSS provisioning and writes to subscriber-db |
| **ai-service** | Python | AI recommendations and helper services |
| **traffic-simulator** | Simulated | Generates customer portal traffic |
| **network-worker** | Simulated | Completes queued provisioning tasks |
| **provisioning-queue** | — | Message queue between activation and provisioning |
| **subscriber-db** | — | Persistent subscriber and order state |

### 2.3 — Check Services and Endpoints

```bash
kgs
```

Verify all services have endpoints and the `customer-portal` has an external IP.

---

## Part 3: Explore SRE Agent (Baseline)

Open the SRE Agent portal:

```bash
sre-agent
```

Or navigate directly to [sre.azure.com](https://sre.azure.com).

> **First-time onboarding screen:** On first launch you'll see a setup wizard asking you to add context sources (Code, Logs, Azure resources, Incidents). The deployment has already pre-configured Azure resources and logs, so click **"Done and go to agent"** to skip this screen.

### 3.1 — Healthy Baseline Prompts

Before introducing failures, ask the agent to confirm the cluster is healthy. Try these prompts:

| Prompt | What It Demonstrates |
|--------|----------------------|
| "Show me the health status of my AKS cluster" | Cluster overview, node health |
| "Are there any issues in the movistar namespace?" | Baseline — everything should be green |
| "What workloads are running in Movistar BSS?" | Inventory of deployments |
| "Show me resource utilization across my BSS pods" | CPU/memory usage |

Take note of the healthy state — you'll compare this to the broken state in each lab.

### 3.2 — Verify Agent Configuration

In the SRE Agent portal, check:

- **Builder > Agent Canvas** — you should see `incident-handler` and `cluster-health-monitor` custom agents
- **Knowledge Files** — runbooks for pod failures, networking, dependencies, and Movistar BSS architecture
- **Connectors** — Azure Monitor (and optionally Outlook, GitHub)

---

## Lab 1: OOMKilled — Activation surge overload

**Difficulty:** Beginner  
**What you'll learn:** How SRE Agent diagnoses memory exhaustion and recommends safe resource limits  
**Services affected:** `activation-service`

### Step 1 — Break It

```bash
break-oom
```

This redeploys `activation-service` with an absurdly low memory limit (16Mi). The container starts, begins processing activation requests, then exceeds its limit and gets killed by the OOM killer. Kubernetes restarts it, and the cycle repeats.

### Step 2 — Observe the Failure

Watch the pods cycle through crashes:

```bash
kgp
```

Within 30–60 seconds you should see:

```text
activation-service-xxxxx   0/1   OOMKilled   3   2m
```

For more detail:

```bash
kubectl describe pod -l app=activation-service -n movistar | grep -A 5 "Last State"
```

You'll see `Reason: OOMKilled` and `Exit Code: 137`.

### Step 3 — Ask SRE Agent to Diagnose

Go to the SRE Agent portal and try these prompts, progressing from open-ended to specific:

1. **Open-ended:** _"New line activations are failing. Can you investigate?"_
2. **Direct:** _"Why is the activation-service pod restarting repeatedly?"_
3. **Specific:** _"I see OOMKilled events in the movistar namespace. What's going on?"_

**What to look for in the response:**
- SRE Agent identifies the `OOMKilled` status
- It reads the current memory limit (16Mi) and explains why it's too low for provisioning bursts
- It recommends increasing the memory limit (typically to 128–256Mi)
- It may offer to apply the fix directly

### Step 4 — Ask SRE Agent to Remediate

Try:

- _"What memory limits should I set for activation-service?"_
- _"Can you increase the memory limit for activation-service to 256Mi?"_

SRE Agent has write access (Contributor + AKS Cluster Admin) and can patch the deployment directly.

### Step 5 — Fix It (Manual)

If you prefer to fix it yourself or want to restore the full healthy state:

```bash
fix-all
```

### Step 6 — Verify Recovery

```bash
kgp
```

All pods should return to `Running` 1/1. Open the customer portal again and confirm new activations or plan changes succeed.

---

## Lab 2: subscriber-db Down — Cascading BSS failure

**Difficulty:** Intermediate  
**What you'll learn:** How SRE Agent traces dependency chains and identifies the root cause of cascading failures  
**Services affected:** `subscriber-db` → `provisioning-service` → activations, recharges, and plan changes

This is the most realistic scenario. It tests whether SRE Agent can look past the immediate symptom (`provisioning-service` failing) to find the actual root cause (`subscriber-db` is offline).

### Step 1 — Break It

```bash
break-mongodb
```

This scales `subscriber-db` to 0 replicas. The database disappears, but the rest of the stack keeps running — at first.

### Step 2 — Observe the Cascade

Watch the effects unfold over 1–2 minutes:

```bash
kgp
```

You'll notice:
- **subscriber-db** — 0/0 pods (scaled to zero)
- **provisioning-service** — starts failing health checks and restarting
- **Everything else** — still `Running` (`customer-portal` loads, `catalog-service` returns plans)

The subtle part: *the portal looks fine*. Subscribers can browse plans. But try to activate a line, change a tariff, or run a top-up — requests queue up in `provisioning-queue` and never complete.

Check provisioning-service health:

```bash
kubectl logs -l app=provisioning-service -n movistar --tail=20
```

You'll see connection errors to `subscriber-db`.

### Step 3 — Ask SRE Agent to Diagnose

Start broad and let the agent investigate:

1. **Open-ended:** _"Mi Movistar is up, but line activations and recharges are stuck. What's wrong?"_
2. **Follow-up:** _"Is subscriber-db running? What depends on it?"_
3. **Root cause:** _"Trace the dependency chain — what broke first?"_

**What to look for in the response:**
- SRE Agent discovers `provisioning-service` is failing health checks
- It traces the dependency to `subscriber-db`
- It identifies that `subscriber-db` has 0 replicas
- It recommends scaling `subscriber-db` back to 1 replica
- It explains the cascading impact: `subscriber-db` → `provisioning-service` → activation and recharge flow

### Step 4 — Ask SRE Agent to Fix It

- _"Scale the subscriber-db deployment back to 1 replica"_

SRE Agent should execute the scale operation directly.

### Step 5 — Verify Recovery

```bash
kgp
```

Watch `subscriber-db` start, then `provisioning-service` stabilize. Requests queued in `provisioning-queue` during the outage should start completing.

### Step 6 — Fix All (If Needed)

```bash
fix-all
```

---

## Lab 3: Service Mismatch — Silent activation failure

**Difficulty:** Advanced  
**What you'll learn:** How SRE Agent detects subtle networking issues that don't show up in pod status  
**Services affected:** `activation-service` (reachable in theory, silently disconnected in practice)

This is the trickiest scenario. Everything *looks* healthy — all pods are Running, no restarts, no obvious errors. But the `activation-service` Service has the wrong selector, so it routes traffic to nothing.

### Step 1 — Break It

```bash
break-service
```

This replaces the `activation-service` Service with one whose selector points to `app: activation-service-v2` — a label that no pod has.

### Step 2 — Observe the Subtlety

Check pod status:

```bash
kgp
```

Everything is `Running` 1/1. No crashes. No restarts. Looks perfectly healthy.

Now check the Service endpoints:

```bash
kubectl get endpoints activation-service -n movistar
```

You'll see:

```text
NAME                 ENDPOINTS   AGE
activation-service   <none>      30s
```

**No endpoints.** The Service exists but routes to nothing. `customer-portal` still loads because it's mostly static UI, but any attempt to activate a line or submit a plan change fails because the portal cannot reach `activation-service`.

### Step 3 — Ask SRE Agent to Diagnose

This is where SRE Agent's depth of investigation shines. Start vague:

1. **Open-ended:** _"Mi Movistar loads, but activating a new line spins forever. Everything looks healthy though."_
2. **Direct:** _"Why does activation-service have no endpoints?"_
3. **Specific:** _"Compare the activation-service Service selector to the actual pod labels"_

**What to look for in the response:**
- SRE Agent goes beyond pod status (all Running) to check Service endpoints
- It discovers the selector mismatch: Service expects `app: activation-service-v2`, pods have `app: activation-service`
- It recommends correcting the selector to `app: activation-service`

### Step 4 — Ask SRE Agent to Fix It

- _"Fix the selector on the activation-service Service to match the pods"_

### Step 5 — Verify Recovery

```bash
kubectl get endpoints activation-service -n movistar
```

This should now show the `activation-service` pod IPs. Test by retrying an activation in the customer portal.

### Step 6 — Fix All

```bash
fix-all
```

---

## Bonus: Automated Incident Response with Outlook

If you've configured the Outlook connector (see [SRE-AGENT-SETUP.md](SRE-AGENT-SETUP.md#post-configuration-authorize-outlook)), your custom agents can email incident summaries automatically.

### How It Works

1. An alert fires (for example, activation-service crashes after `break-oom`)
2. The `incident-handler` agent investigates using the knowledge base runbooks
3. It collects evidence: pod status, logs, events, and metrics
4. It emails a structured incident report with findings and recommended remediation

### Try It

1. **Authorize Outlook** in the SRE Agent portal (Builder > Connectors > Outlook > Authorize)
2. **Create an incident response plan** in the portal that triggers the `incident-handler` agent
3. **Break something:** `break-oom`
4. **Watch the agent work** — it should investigate and send an email with findings

### Email Report Format

The agents are configured to send reports with a subject line like:

```text
[SRE Agent] Sev2: OOMKilled in movistar namespace — activation-service line activations degraded
```

The body includes root cause analysis, affected resources, evidence collected, and recommended remediation steps.

> **Note:** The incident response plan must be created manually in the [SRE Agent portal](https://sre.azure.com). See [SRE-AGENT-SETUP.md](SRE-AGENT-SETUP.md#post-configuration-create-incident-response-plan) for instructions.

---

## Explore More Scenarios

Once you're comfortable with the three labs above, try the other breakable scenarios:

| Command | Scenario | Difficulty | What Makes It Interesting |
|---------|----------|------------|---------------------------|
| `break-crash` | Catalog CrashLoopBackOff | Beginner | Exit code analysis, log inspection |
| `break-image` | Provisioning ImagePullBackOff | Beginner | Registry/image troubleshooting |
| `break-cpu` | High CPU | Intermediate | Resource contention, noisy neighbor |
| `break-pending` | Pending Pods | Intermediate | Scheduling constraints, capacity exhaustion |
| `break-probe` | Probe Failure | Intermediate | Health check misconfiguration |
| `break-network` | Network policy block | Advanced | Customer portal to activation API connectivity |
| `break-config` | Missing ConfigMap | Beginner | Back-office configuration dependency |

See [BREAKABLE-SCENARIOS.md](BREAKABLE-SCENARIOS.md) for detailed descriptions, observation commands, and suggested SRE Agent prompts for each scenario. The [PROMPTS-GUIDE.md](PROMPTS-GUIDE.md) has per-scenario prompt progressions from open-ended triage to remediation.

---

## Cleanup

When you're done, tear down the entire environment:

```powershell
.\scripts\destroy.ps1 -ResourceGroupName "rg-srelab-eastus2"
```

Or use the shortcut:

```bash
destroy
```

This deletes the resource group and everything in it (AKS, ACR, Key Vault, SRE Agent, and all optional modules).

> **Reminder:** The environment costs ~$32–38/day. Don't forget to tear it down when you're done.

---

## Tips and Troubleshooting

- **Type `menu`** to see all available commands at any time
- **Use `fix-all`** between scenarios to restore the healthy baseline
- **Wait 30–60 seconds** after applying a break scenario before asking SRE Agent — give the failure time to manifest
- **Start with open-ended prompts** — SRE Agent is more impressive when it discovers the issue rather than being told exactly what to inspect
- **Check pod events** if you want to verify what's happening before asking SRE Agent: `kubectl describe pod <pod-name> -n movistar`
- **Deployment stuck?** Make sure you're in a supported region (`eastus2`, `swedencentral`, `australiaeast`)
- **SRE Agent not responding?** Verify the firewall allows `*.azuresre.ai` and that you have the SRE Agent Standard User or Admin role

---

## Further Reading

- [SRE-AGENT-SETUP.md](SRE-AGENT-SETUP.md) — detailed agent setup and RBAC configuration
- [BREAKABLE-SCENARIOS.md](BREAKABLE-SCENARIOS.md) — all 10 scenarios with observation commands
- [PROMPTS-GUIDE.md](PROMPTS-GUIDE.md) — per-scenario prompt progressions
- [SRE-AGENT-PROMPTS.md](SRE-AGENT-PROMPTS.md) — comprehensive prompt library organized by SRE discipline
- [COSTS.md](COSTS.md) — detailed cost breakdown
