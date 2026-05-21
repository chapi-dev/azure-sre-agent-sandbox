# Module F — Governance + multi-model + cost tracking

Module F adds the governance layer for the Azure SRE Agent **Movistar BSS** demo lab.

## What gets deployed

- Three tiered subagents in `sre-config\agents\`:
  - `read-only-investigator`
  - `review-autonomy-handler`
  - `operator-autonomy-handler`
- Governance guidance in `sre-config\governance\` covering autonomy, model-provider choice, and data boundaries
- A workbook module: `infra\bicep\modules\cost-workbook.bicep`
- A scheduled query alert module: `infra\bicep\modules\cost-alerts.bicep`
- Two helper scripts:
  - `scripts\compare-models.ps1`
  - `scripts\cost-report.ps1`

## Deployment flag

Planned orchestrator flag:

```powershell
.\scripts\deploy.ps1 -Location eastus2 -DeployGovernance -Yes
```

> This change set intentionally does **not** modify `deploy.ps1`, `main.bicep`, or parameter files. Use the new Bicep modules manually today, or wire the flag later using the comments included at the bottom of each Module F Bicep file.

## Demo flows

### 1) Autonomy demo

1. Trigger `break-oom`.
2. Send the same prompt to all three subagents:
   - `read-only-investigator`
   - `review-autonomy-handler`
   - `operator-autonomy-handler`
3. Use a prompt such as:
   - `The movistar namespace is unstable after an OOM event. Investigate why activation-service is failing and restore the activation flow.`
4. Show the outcome differences:
   - **Read** reports findings only.
   - **Review** proposes remediation and waits for approval in the SRE Agent portal.
   - **Operator** executes directly inside hook guardrails.
5. Compare **time to remediation** and explain the blast-radius trade-off.

### 2) Multi-model demo

1. Deploy the same review agent twice with different names and providers:
   - `review-autonomy-handler-aoai`
   - `review-autonomy-handler-claude`
2. Run:

```powershell
.\scripts\compare-models.ps1 -ResourceGroupName <rg> -Prompt "Investigate why the Movistar BSS platform is timing out after break-mongodb."
```

3. Compare:
   - response style
   - diagnostic depth
   - AAU consumption
   - latency
4. Save the raw outputs and show that the same workflow can be benchmarked provider-to-provider.

### 3) Cost tracking demo

1. Deploy `cost-workbook.bicep` and `cost-alerts.bicep`.
2. Run several scenarios (`break-oom`, `break-mongodb`, multi-model comparison).
3. Open the workbook **SRE Agent — Token & AAU Consumption**.
4. Refresh and show:
   - total AAU in the last 7 days
   - AAU by subagent
   - AAU by model provider
   - top incidents by token cost
   - token cost vs. remediation success
5. Lower the alert threshold temporarily to demonstrate the alert firing.

### 4) Memoria longitudinal demo

1. On Monday, run `break-mongodb` with an empty or freshly reset memory state.
2. Let the agent complete the investigation.
3. On Wednesday, run the same scenario again.
4. Ask the agent to investigate and explicitly mention `SearchMemory` in the narration.
5. Show that the second run is faster or more precise because the agent can reference prior incidents, learned remediation steps, and prior evidence.

## Minimal cost estimate

- Workbook: effectively free.
- Scheduled query alert: roughly **~$0.10/day per rule** plus query execution volume.
- Incremental cost drivers remain:
  - Log Analytics ingestion/query volume
  - SRE Agent AAU consumption
  - provider-specific token rates

## Recommended talking points

- Read mode reduces risk but not necessarily MTTR.
- Review mode is the default enterprise sweet spot.
- Operator mode is about **guardrailed repeatability**, not unrestricted autonomy.
- Provider choice is both a **cost** and **compliance** decision.
