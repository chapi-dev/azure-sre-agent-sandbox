# Enterprise Incident Flow

Use this runbook when the lab is configured with enterprise connectors and an incident must be mirrored across operational systems.

---

## End-to-end flow

```text
   [Azure Monitor Alert] ----\
                              \
   [ServiceNow Incident] ------> [SRE Agent: enterprise-incident-orchestrator]
                              /                  |
   [PagerDuty Incident] ------/                   v
                                      [Search KB + incident history]
                                                   |
                                                   v
                              [Investigation: Az CLI + Log Analytics + App Insights + Grafana MCP]
                                                   |
                                                   v
                         +-------------------------+---------------------------+--------------------+
                         |                         |                           |                    |
                         v                         v                           v                    v
               [ServiceNow Work Notes]   [Azure DevOps Bug + evidence]   [Teams update]   [Optional GitHub issue]
                         |
                         v
                [PagerDuty note / escalation]
```

### System-of-record guidance

- **Source = ServiceNow**: ServiceNow stays the writable incident record.
- **Source = PagerDuty**: PagerDuty remains the paging record, but create or update a ServiceNow incident if long-form work notes are needed.
- **Source = Azure Monitor**: Create or attach a ServiceNow incident early, then use Azure DevOps and Teams as supporting sinks.

---

## Routing rules by severity

| Severity | Primary route | Required sinks | Notes |
|---|---|---|---|
| Sev1 / High | ServiceNow + PagerDuty immediately | Azure DevOps Bug, Teams major incident channel | Treat as major incident. Use 5-minute updates until stabilized. |
| Sev2 / Medium-High | ServiceNow first | Azure DevOps Bug, Teams on-call channel | Page PagerDuty if outside business hours or if no acknowledgement within 10 minutes. |
| Sev3 / Medium | ServiceNow or Azure DevOps based on owning team | Teams service channel | PagerDuty only if user impact expands or repeats. |
| Sev4 / Low | Azure DevOps Bug or backlog item | Optional Teams summary | No immediate paging; document and track during business hours. |

## Routing rules by service

| Service pattern | Owner path | Investigation emphasis | Default sink behavior |
|---|---|---|---|
| `aks`, `kubernetes`, `platform` | Platform SRE | Node health, pod events, cluster metrics, Grafana cluster dashboards | Open Azure DevOps Bug in platform project and notify platform on-call channel |
| `appservice`, `functions`, `frontend`, `api` | App/service owner + SRE | App Insights traces, deployment history, downstream dependency failures | Create bug in application project and post summary to service channel |
| `database`, `sql`, `cosmos`, `storage` | Data/platform owner | Capacity, throttling, latency, lock contention, quota | Update ServiceNow with evidence and tag data owner in Teams |
| `shared`, `network`, `identity` | Core infrastructure team | Cross-service blast radius, RBAC, DNS, networking, certs | Escalate broadly if customer-facing tags are present |

## Routing rules by tag

| Tag | Action |
|---|---|
| `customer-facing` | Notify Teams incident room, create Azure DevOps Bug immediately, and prefer PagerDuty over email for any Sev2+ incident |
| `payment`, `checkout`, `revenue` | Treat as business-critical. Escalate one severity level higher for notification purposes |
| `security`, `compliance` | Involve a human immediately and avoid autonomous remediation that changes evidence |
| `after-hours` | Favor PagerDuty and concise Teams summaries; defer non-urgent work item triage until business hours |
| `known-issue` | Link to the existing Azure DevOps Bug or GitHub issue instead of opening duplicates |
| `maintenance-window` | Reduce escalation unless the impact exceeds the approved maintenance scope |

---

## When to escalate

Escalate through PagerDuty when any of the following is true:

- Severity is **Sev1** at any time of day.
- Severity is **Sev2** and it is outside business hours.
- A Sev2 incident remains unacknowledged for 10 minutes.
- A Sev3 incident starts to impact multiple services, a customer-facing path, or a regulated workflow.
- The tags include `security`, `compliance`, or `payment`.
- The investigation cannot identify an owner within 15 minutes.

Always involve a human incident commander for Sev1 and for any incident with unclear blast radius.

---

## Run order recommendations

1. Normalize the trigger context: severity, service, tags, owner, and impacted environment.
2. Search this runbook and `escalation-policies.md` before sending any notifications.
3. Gather technical evidence from Azure Monitor, Log Analytics, App Insights, and Grafana MCP.
4. Establish or confirm the writable incident record in ServiceNow or PagerDuty.
5. Post the first progress note with impact, scope, and next action.
6. Create or update the Azure DevOps Bug with evidence and links back to the incident.
7. Notify Teams with a concise summary and next checkpoint.
8. Escalate via PagerDuty if the severity, time of day, or blast radius rules require it.
9. Optionally create or update a GitHub issue if engineering workflow or code ownership requires it.
