# Autonomy policies

Module F introduces an explicit `autonomy_mode` declaration in subagent YAML so the lab can mirror Azure SRE Agent operating modes.

## Default policy

- **After-hours:** default to **Read** unless the remediation is routine, reversible, and already protected by hooks.
- **Business hours:** default to **Review** for any write-capable workflow so a human can approve in the portal.
- **Operator:** reserve for repetitive, low-blast-radius remediations with pre-validated runbooks and guardrails.
- **Access level:** keep **Low** for investigation-only agents; use **High** only when the subagent genuinely needs write scope.

## Recommended autonomy by subagent

| Subagent | Primary scope | Recommended autonomy | Access level | Notes |
|---|---|---:|---:|---|
| `read-only-investigator` | Triage, evidence collection, after-hours first look | Read | Low | Default first responder for ambiguous incidents. |
| `cluster-health-monitor` | Scheduled AKS health checks | Read | Low | Safe for daily reports and baseline drift checks. |
| `incident-handler-core` | Interactive AKS break/fix | Review | High | Human-in-the-loop for write actions. |
| `incident-handler-full` | AKS break/fix plus GitHub issue creation | Review | High | Same as core, plus external system writes. |
| `code-analyzer` | Root cause + code correlation | Review | High | Can open GitHub issues; keep a human in the loop. |
| `review-autonomy-handler` | Full incident handling with approval package | Review | High | Recommended business-hours default. |
| `operator-autonomy-handler` | Routine execution inside guardrails | Operator | High | Use only for known-safe actions such as daily-health-check follow-up or a guarded AKS pod restart. |

## When Operator mode is acceptable

Use **Operator** only when all of the following are true:

1. The remediation is **routine** and documented.
2. The action is **reversible** or has a clear rollback step.
3. The blast radius is **single-service or single-resource**.
4. Hooks are registered to block unsafe variants (for example, production deletes or unapproved restarts).
5. Telemetry exists to prove the action helped.

Examples that fit Operator mode in this lab:

- Restarting a single unhealthy AKS pod after a confirmed OOM or stuck state.
- Re-running a daily health workflow that only executes hook-guarded restart actions.
- Closing a known-good mitigation loop where the rollback is immediate.

## Anti-patterns

| Anti-pattern | Policy |
|---|---|
| Operator + production + destructive command + no hooks | **NO** |
| Read mode agent with write tools attached | **NO** |
| Review mode agent that skips blast-radius analysis | **NO** |
| High access for a read-only monitoring workflow | **NO** |
| Operator mode for first-time or unclear incidents | **NO** |

## Guardrail checklist

Before promoting any subagent to Operator mode, verify:

- Hook coverage exists (`stop-prod-deletes`, `approval-required-restarts`, or stronger).
- The runbook is deterministic enough to automate.
- The action can be audited afterward.
- The team is comfortable with the remediation happening without portal approval.
