# Escalation Policies

Use this matrix to decide who must be notified, which channel to use, and when the SRE Agent should stop acting autonomously and involve a human.

## Working assumptions

- **Business hours:** 08:00-18:00 local time, Monday-Friday
- **Off hours:** nights, weekends, and holidays
- **Primary on-call:** first responder for the owning service or platform
- **Secondary on-call:** backup responder when primary does not acknowledge or needs relief
- **Incident commander:** human coordinator for major incidents and unclear blast radius events

## Escalation matrix

| Severity | Time of day | Who to notify | Channel | SRE Agent action | When to involve a human |
|---|---|---|---|---|---|
| Sev1 | Business hours | Primary on-call, secondary on-call, incident commander, service owner, engineering manager | PagerDuty high-urgency page, ServiceNow major incident, Teams major incident bridge | Create/update ServiceNow immediately, page PagerDuty primary and secondary, open Azure DevOps Bug, post 5-minute Teams updates | Immediately; incident commander should engage within 5 minutes |
| Sev1 | Off hours | Primary on-call, secondary on-call, incident commander, duty manager | PagerDuty high-urgency page plus phone/SMS, ServiceNow major incident, Teams bridge | Same as business hours, with no wait for acknowledgement before paging secondary | Immediately; human response is mandatory |
| Sev2 | Business hours | Primary on-call, service owner, product/support lead if customer-facing | ServiceNow incident, Teams on-call channel, optional low-urgency PagerDuty | Create or update incident record, open Azure DevOps Bug, post Teams summary, monitor acknowledgement | If no acknowledgement within 10 minutes or impact exceeds one service |
| Sev2 | Off hours | Primary on-call first, secondary on-call after 10 minutes, incident commander if customer-facing | PagerDuty page, ServiceNow incident, Teams on-call channel | Page primary, create/update ServiceNow, open Azure DevOps Bug, send concise Teams update | If not acknowledged within 10 minutes or if blast radius grows |
| Sev3 | Business hours | Service owner or feature team, platform SRE if shared dependency | Teams service channel, ServiceNow incident or Azure DevOps Bug | Collect evidence, document impact, create/update work item, post Teams summary | If triage has not started within 1 hour or if recurring pattern suggests broader risk |
| Sev3 | Off hours | No immediate page by default; notify next-business-day owner unless customer-facing | ServiceNow incident or Azure DevOps Bug, optional Teams summary | Record the incident, capture evidence, queue follow-up for business hours | If tags include `customer-facing`, `payment`, `security`, or the impact worsens |
| Sev4 | Business hours | Backlog owner or service owner | Azure DevOps Bug or backlog item, optional Teams post | Document the issue, capture evidence, create backlog item, avoid noisy paging | If the issue blocks another critical fix or becomes a repeat offender |
| Sev4 | Off hours | No page; next-business-day owner only | Azure DevOps Bug/backlog item | Log the issue and defer human action until business hours | If severity is reclassified or another signal indicates customer impact |

## Escalation timers

| Condition | Timer | Action |
|---|---|---|
| Sev1 not acknowledged | 5 minutes | Page secondary on-call and incident commander |
| Sev2 not acknowledged | 10 minutes | Escalate from primary to secondary on-call |
| Sev3 recurring more than 3 times in 24h | Immediate review | Promote to Sev2 notification pattern |
| Any incident without a clear owner | 15 minutes | Involve incident commander or duty manager |

## Human handoff triggers

The SRE Agent should stop acting alone and request human ownership when:

- The incident affects regulated, security-sensitive, or compliance-tagged systems.
- Remediation would require destructive changes, risky rollbacks, or production deletes.
- More than one customer-facing service is degraded and the blast radius is still unclear.
- PagerDuty escalation has started and no human has acknowledged the incident.
- An executive, support, or incident commander asks for a formal communications cadence.
