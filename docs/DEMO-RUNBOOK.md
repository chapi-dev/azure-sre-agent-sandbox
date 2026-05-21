# Demo Runbook — Movistar BSS Demo Lab

This runbook ties the base AKS lab and all six extension modules into a single **90-minute presentation**. Use it as the live script for a customer demo, internal workshop, or recorded walkthrough of **Telefónica's Movistar BSS** operating model.

> Reference set: [EXTENDED-DEMO-MAP.md](EXTENDED-DEMO-MAP.md), [LAB-GUIDE.md](LAB-GUIDE.md), [MODULE-A-MULTI-STACK.md](MODULE-A-MULTI-STACK.md), [MODULE-B-AVD.md](MODULE-B-AVD.md), [MODULE-C-CITRIX.md](MODULE-C-CITRIX.md), [MODULE-D-SKILLS-HOOKS-PLUGINS.md](MODULE-D-SKILLS-HOOKS-PLUGINS.md), [MODULE-E-ENTERPRISE-CONNECTORS.md](MODULE-E-ENTERPRISE-CONNECTORS.md), [MODULE-F-GOVERNANCE.md](MODULE-F-GOVERNANCE.md).

## Recommended pre-stage (30–60 minutes before the audience joins)

Deploy the full environment once and keep the following tabs open: **customer portal**, Azure portal, SRE Agent portal, AVD web client, and the cost workbook.

```powershell
.\scripts\deploy.ps1 -Location eastus2 -DeployAll -Yes
```

Quick sanity checks:

```bash
kgp
site
```

> If the browser tab still says **AKS Store**, call it out once: it is the upstream image text. For the rest of the demo, treat it as **Mi Movistar**.

If you are not using `-DeployAll`, run the per-module enablement commands listed in each section before you go live.

## 90-minute timeline

| Segment | Time | Primary reference |
|---|---:|---|
| Opening | 5 min | [EXTENDED-DEMO-MAP.md](EXTENDED-DEMO-MAP.md) |
| Part 1 — Baseline AKS demo | 10 min | [LAB-GUIDE.md](LAB-GUIDE.md) |
| Part 2 — Multi-stack incident | 15 min | [MODULE-A-MULTI-STACK.md](MODULE-A-MULTI-STACK.md) |
| Part 3 — AVD on-call | 10 min | [MODULE-B-AVD.md](MODULE-B-AVD.md) |
| Part 4 — Citrix end-user | 10 min | [MODULE-C-CITRIX.md](MODULE-C-CITRIX.md) |
| Part 5 — Skills + Hooks | 15 min | [MODULE-D-SKILLS-HOOKS-PLUGINS.md](MODULE-D-SKILLS-HOOKS-PLUGINS.md) |
| Part 6 — Enterprise routing | 10 min | [MODULE-E-ENTERPRISE-CONNECTORS.md](MODULE-E-ENTERPRISE-CONNECTORS.md) |
| Part 7 — Governance + multi-model | 10 min | [MODULE-F-GOVERNANCE.md](MODULE-F-GOVERNANCE.md) |
| Wrap-up + Q&A | 5 min | [COSTS.md](COSTS.md) |

## Opening — 5 min

**Presenter goal**
- Re-establish the base story: Azure SRE Agent investigates, correlates, and remediates incidents.
- Frame the target system as a **Movistar self-service + provisioning platform** running on AKS.
- Explain that the six modules are optional overlays, not a replacement.

**Prerequisites**
- Full lab deployed and healthy
- `EXTENDED-DEMO-MAP.md` open in a browser or editor
- Customer portal and SRE Agent portal already loaded

**Command to run before**

```bash
site
```

**Prompts to use during**
- `Show me the health status of my AKS cluster.`
- `What capabilities are enabled in this SRE Agent environment?`

**Fix / reset after**
- None

**Success criteria**
- Audience sees a healthy baseline
- Audience understands: Movistar BSS on AKS + six optional modules + independent flags

**Talk track**
- “We start with a breakable Movistar BSS workload on AKS: customer portal, CSR console, activation API, provisioning queue, and subscriber data.”
- “Then we add six optional modules: multi-stack Azure, AVD, Citrix MCP, custom skills/hooks/plugins, enterprise connectors, and governance.”
- “The point is not one giant monolith. Each module is independently deployable and demoable.”

## Part 1: Baseline AKS demo — 10 min

Deep dive: [LAB-GUIDE.md](LAB-GUIDE.md) and [BREAKABLE-SCENARIOS.md](BREAKABLE-SCENARIOS.md)

**Prerequisites**
- Base AKS lab deployed
- `kubectl` context points at the demo cluster
- Healthy baseline verified with `kgp`

**Command to run before**

```bash
kgp
```

**Live script**

| Mini-demo | Break command | Prompt | Fix command | Success criteria |
|---|---|---|---|---|
| OOMKilled | `kubectl apply -f k8s/scenarios/oom-killed.yaml` | `Why are new line activations failing in the movistar namespace?` | `kubectl apply -f k8s/base/application.yaml` | Agent identifies `OOMKilled` on `activation-service`, shows memory-limit mismatch, and recommends remediation |
| subscriber-db dependency failure | `kubectl apply -f k8s/scenarios/mongodb-down.yaml` | `Trace the dependency chain — why are plan changes and recharges failing?` | `kubectl apply -f k8s/base/application.yaml` | Agent finds `subscriber-db` scaled to 0 and explains cascading impact on `provisioning-service` |
| Service mismatch | `kubectl apply -f k8s/scenarios/service-mismatch.yaml` | `Why does activation-service have no endpoints?` | `kubectl apply -f k8s/base/application.yaml` | Agent checks Service selector vs. pod labels while `customer-portal` still appears healthy |

**Presenter notes**
- If time is tight, run OOM live and narrate the other two from screenshots.
- Always return to the healthy baseline before moving on.
- Use this section to prove the base Movistar BSS lab works before extension modules enter the story.

## Part 2: Multi-stack incident — 15 min

Deep dive: [MODULE-A-MULTI-STACK.md](MODULE-A-MULTI-STACK.md)

**Prerequisites**
- Module A deployed with `-DeployMultiStack`
- App Service, Function App, Cosmos DB, and SQL resources visible in the resource group
- `cross-stack-investigator` available in the SRE Agent portal

**Command to run before**

```powershell
.\scripts\scenarios-multistack\break-cosmos-throttle.ps1 -ResourceGroupName rg-srelab-eastus2 -CosmosAccountName <cosmos-account> -LoadRequests 25
```

**Prompts to use during**
- `Los usuarios reportan que Mi Movistar va lento. Investiga end-to-end.`
- `Trace the request path from the self-service portal through the activation API to the catalog and subscriber stores. Which tier is the bottleneck?`
- `Correlate Application Insights requests and dependencies by operation_Id and cloud_RoleName.`

**Fix command after**

```powershell
.\scripts\scenarios-multistack\fix-multistack.ps1 -ResourceGroupName rg-srelab-eastus2
```

**Success criteria**
- Agent correlates App Service latency with Function dependencies and Cosmos `429 RequestRateTooLarge`
- Audience sees the SRE Agent move past “the portal is slow” into a cross-service root cause
- Fix restores RU/s and clears the symptom

**Talk track**
- “This is where the demo stops being AKS-only.”
- “The user symptom starts in the customer portal, but the root cause is downstream Cosmos throttling in the catalog path.”
- “The agent is correlating across service boundaries, not just reading one log stream.”

## Part 3: AVD on-call — 10 min

Deep dive: [MODULE-B-AVD.md](MODULE-B-AVD.md)

**Prerequisites**
- Module B deployed with `-DeployAvd`
- A test user assigned to the AVD desktop application group
- AVD web client or desktop client ready

**Command to run before**

```powershell
.\scripts\scenarios-avd\break-avd-agent-stopped.ps1 -ResourceGroupName rg-srelab-eastus2
```

**Prompts to use during**
- `Los usuarios no se pueden conectar al host pool. Investiga.`
- `Check WVDConnections and WVDErrors for the host pool and identify the failing session host.`
- `Tell me whether the problem is the AVD agent, FSLogix, NSG, or host capacity.`

**Fix command after**

```powershell
.\scripts\scenarios-avd\fix-avd.ps1 -ResourceGroupName rg-srelab-eastus2
```

**Success criteria**
- Agent identifies a host with `RDAgentBootLoader` stopped
- Audience sees an end-user VDI problem handled in the same SRE workflow
- Re-test in the AVD client succeeds after the fix

**Talk track**
- “We have moved from AKS into end-user computing without changing the operating model.”
- “The user symptom is ‘I can’t connect’; the agent translates that into host pool, session host, and agent-health evidence.”
- “This is still the same SRE Agent, just with a different runbook and subagent.”

## Part 4: Citrix end-user — 10 min

Deep dive: [MODULE-C-CITRIX.md](MODULE-C-CITRIX.md)

**Prerequisites**
- Module C deployed with `-DeployCitrixMcp`
- Citrix Cloud tenant and API client already configured
- `citrix-session-doctor` and the Citrix MCP connector are healthy
- A known user session or unhealthy VDA is ready in Citrix Cloud

**Command to run before**

```powershell
.\scripts\deploy.ps1 -Location eastus2 -DeployCitrixMcp -CitrixCustomerId <customer-id> -CitrixClientId <client-id> -CitrixClientSecret $env:CITRIX_CLIENT_SECRET -Yes
```

**Prompts to use during**
- `A Citrix user reports a frozen session. Use citrix-session-doctor to investigate.`
- `Find the affected Citrix session, identify the backing machine, and correlate it with Azure VM health.`
- `If a single VDA is unhealthy, drain it and recommend the safest recovery action.`

**Fix / reset after**
- No repo-side reset script is included for Citrix.
- Use the remediation prompt to let the agent call the Citrix tools needed for recovery:
  - `Drain the affected machine, restart it if capacity allows, and summarize what changed.`

**Success criteria**
- Audience sees the agent call a **custom MCP toolchain**, not just Azure-native tools
- Agent identifies the Citrix session, backing machine, and next action
- Demo clearly shows extensibility beyond built-in connectors

**Talk track**
- “GitHub MCP is not the only MCP story. Here we bring our own MCP server.”
- “The agent can traverse Citrix session data, then pivot back into Azure VM telemetry.”
- “This is the extension point many enterprise teams ask for.”

## Part 5: Skills + Hooks — 15 min

Deep dive: [MODULE-D-SKILLS-HOOKS-PLUGINS.md](MODULE-D-SKILLS-HOOKS-PLUGINS.md)

**Prerequisites**
- Module D deployed with `-DeploySkills` and `-DeployHooks`
- Skills, hooks, and plugins uploaded successfully
- A scratch resource group such as `rg-srelab-scratch` is available and tagged to trigger the Stop hook, or you are running outside the allowed delete window

**Command to run before**

```powershell
.\scripts\upload-skills.ps1 -ResourceGroupName rg-srelab-eastus2
.\scripts\upload-hooks.ps1 -ResourceGroupName rg-srelab-eastus2
.\scripts\upload-plugins.ps1 -ResourceGroupName rg-srelab-eastus2 -MockCmdbUrl "https://<mock-cmdb-function>.azurewebsites.net/api" -MockCmdbKey "<function-key>"
```

**Prompts to use during**
- `Investigate the activation-service OOM incident in the movistar namespace. Estimate the business impact for 45 minutes of downtime affecting 320 subscribers, generate a PDF incident report, and prepare it for email.`
- `Investigate repeated OOMKilled restarts for activation-service in the movistar namespace. Use CMDB data to identify the owner, service criticality, dependencies, and linked runbook before you summarize severity.`
- `Run az group delete --name rg-srelab-scratch --subscription <sub-id>`

**Fix / reset after**

```bash
kubectl apply -f k8s/base/application.yaml
```

Additional cleanup if you used a scratch RG:

```powershell
az group delete --name rg-srelab-scratch --yes --no-wait
```

**Success criteria**
- Agent invokes `cost_impact_estimator` and `generate_incident_pdf`
- CMDB plugin enriches severity and ownership
- Stop hook blocks the dangerous delete request and PostToolUse audit is written when safe actions are allowed

**Talk track**
- “This is the most differentiated part of the story: the agent can gain deterministic skills, safety rails, and lightweight plugins.”
- “The skill is not just a pretty wrapper; it returns structured output the agent can use.”
- “The governance hooks prove that autonomy does not mean bypassing controls.”

## Part 6: Enterprise routing — 10 min

Deep dive: [MODULE-E-ENTERPRISE-CONNECTORS.md](MODULE-E-ENTERPRISE-CONNECTORS.md)

**Prerequisites**
- Module E configured with valid ServiceNow, PagerDuty, Azure DevOps, Teams, and optional Grafana or Datadog credentials
- `enterprise-incident-orchestrator` present in the SRE Agent portal
- A target ServiceNow queue, PagerDuty service, ADO project, and Teams channel ready

**Command to run before**

```powershell
.\scripts\configure-sre-agent.ps1 -ResourceGroupName "rg-srelab-eastus2" -DeployEnterprise -ServiceNowUrl "https://<instance>.service-now.com" -PagerDutyToken $env:PD_TOKEN -AzureDevOpsPat $env:ADO_PAT -TeamsWebhookUrl $env:TEAMS_WEBHOOK
```

**Prompts to use during**
- `A new Azure Monitor alert fired for AKS memory pressure on the Movistar BSS cluster. Run the enterprise incident flow.`
- `Investigate the latest Sev2 incident and sync progress to ServiceNow, Azure DevOps, and Teams.`
- `If this is after hours and severity is high, escalate it through PagerDuty.`

**Fix / reset after**
- Close or resolve the generated ticket objects in your external systems.
- Recommended operator prompt:
  - `Mark the incident resolved and post a final update to Teams with links to the ServiceNow and Azure DevOps records.`

**Success criteria**
- A single investigation produces synchronized artifacts in ServiceNow, PagerDuty, Azure DevOps, and Teams
- Audience sees incident routing, not just diagnosis
- The agent keeps the timeline consistent across systems

**Talk track**
- “This is how the lab leaves the sandbox and plugs into real operating workflows.”
- “The agent is not replacing ITSM or on-call tooling; it is orchestrating them.”
- “The value is consistent evidence and faster handoff across systems that already exist.”

## Part 7: Governance + multi-model — 10 min

Deep dive: [MODULE-F-GOVERNANCE.md](MODULE-F-GOVERNANCE.md)

**Prerequisites**
- Module F deployed with `-DeployGovernance`
- `read-only-investigator`, `review-autonomy`, and `operator-autonomy` available
- Azure OpenAI and Claude-backed comparison agents already configured if you want the provider comparison live
- Cost workbook deployed and open in a browser tab

**Command to run before**

```powershell
.\scripts\compare-models.ps1 -ResourceGroupName rg-srelab-eastus2 -Prompt "Investigate why the Movistar BSS platform is timing out after break-mongodb."
```

**Prompts to use during**
- `The movistar namespace is unstable after an OOM event. Investigate why activation-service is failing and restore service.`
- `Run the same incident in Read, Review, and Operator autonomy modes and compare the outcome.`
- `Compare Azure OpenAI and Claude responses for the same incident and summarize latency, depth, and AAU differences.`

**Fix / reset after**

```bash
kubectl apply -f k8s/base/application.yaml
```

**Success criteria**
- Audience sees clear differences between Read, Review, and Operator modes
- Provider comparison shows that model choice affects latency, answer style, and cost
- Workbook view ties autonomy and provider selection back to observable consumption

**Talk track**
- “The enterprise question is never only ‘can the agent do it?’ It is also ‘under what guardrails, with which model, and at what cost?’”
- “Review mode is usually the default sweet spot; Operator is for repeatable, controlled workflows.”
- “Multi-model is both a technical and governance choice.”

## Wrap-up — 5 min

**Prerequisites**
- Cost workbook tab open
- `EXTENDED-DEMO-MAP.md` open for the closing summary

**Command to run before**

```powershell
Get-Date
```

**Close with**
- A screenshot or live view of the cost workbook
- The module map to show how each demo segment relates to the underlying assets
- Next steps: deploy only the modules you need, then extend the agent with your own skills, hooks, connectors, or MCP servers

**Suggested closing lines**
- “The Movistar BSS lab is still the entry point, but the extended modules turn it into a broader Azure operations demo.”
- “You can enable only the slices you need: AVD, multi-stack, Citrix, enterprise routing, or governance.”
- “The next step is to replace the demo integrations with your own runbooks, tenants, and approval policies.”

**Post-demo cleanup**

```powershell
.\scripts\destroy.ps1 -ResourceGroupName "rg-srelab-eastus2"
```

**Success criteria**
- Audience leaves with a clear roadmap, a repeatable runbook, and a realistic understanding of cost and prerequisites
- Demo environment is either ready for the next session or explicitly torn down
