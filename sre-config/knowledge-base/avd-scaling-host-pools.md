# Azure Virtual Desktop Host Pool Scaling Runbook

Use this runbook when Azure Virtual Desktop capacity is tight, session hosts are overloaded, or maintenance requires draining hosts safely.

---

## When to Scale

Scale the host pool when one or more of these are true:
- New connections fail during busy periods
- Session hosts frequently sit at the configured max session limit
- CPU, memory, or disk queue stays elevated on most hosts
- Users are delayed because the remaining healthy hosts are in drain mode
- Start-on-connect takes too long to satisfy demand spikes

---

## Key Signals

### AVD Insights
Review the built-in workbook for:
- Active sessions per host
- Connection success/failure rate
- Session host availability
- Host performance counters

### KQL
Use AVD diagnostics to spot saturation windows:

```kql
WVDConnections
| where TimeGenerated > ago(4h)
| where ConnectionType == "Connection"
| summarize Started=countif(State == "Started"), Completed=countif(State == "Completed") by bin(TimeGenerated, 15m), HostPoolName = column_ifexists("HostPoolName", "")
| order by TimeGenerated desc
```

Use agent health to count healthy hosts:

```kql
WVDAgentHealthStatus
| where TimeGenerated > ago(1h)
| summarize HealthyHosts = dcountif(SessionHostName, Status == "Available") by HostPoolName = column_ifexists("HostPoolName", "")
```

---

## Drain Mode Flow

Before maintenance or host replacement, stop new sessions on one host at a time:

```bash
az desktopvirtualization sessionhost update \
  --resource-group <rg> \
  --host-pool-name <host-pool> \
  --name <session-host-resource-name> \
  --allow-new-session false
```

Recommended flow:
1. Pick the host you want to patch or remove.
2. Set `allow-new-session` to `false`.
3. Wait for current users to log off, or coordinate a maintenance window.
4. Repair, restart, or replace the host.
5. Set `allow-new-session` back to `true` after validation.

---

## Start-on-Connect Guidance

If you rely on start-on-connect:
- Ensure at least one host can become available quickly enough for the first user wave.
- Pair start-on-connect with a scaling plan when possible.
- Watch for repeated `Started` without `Completed` connection patterns if cold starts are too slow.

---

## Remediation Options

| Situation | Recommended Action |
|----------|--------------------|
| All hosts are healthy but full | Add more session hosts or raise the session limit carefully |
| One host is overloaded | Drain and rebalance sessions, then investigate host health |
| Hosts are unavailable | Restore AVD agent health first, then reassess capacity |
| Start-on-connect is too slow | Keep a warm minimum host count or accelerate host readiness |
| Repeated after-hours spikes | Add autoscale rules or schedule more capacity before peak |

---

## Validation

After scaling or drain-mode changes:
1. Re-run the session host inventory command.
2. Confirm at least one healthy host allows new sessions.
3. Watch AVD Insights for 15-30 minutes.
4. Verify connection completions recover to normal.
