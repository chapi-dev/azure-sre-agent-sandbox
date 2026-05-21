# Azure Virtual Desktop Troubleshooting Runbook

Diagnose and remediate common Azure Virtual Desktop (AVD) end-user issues in the demo lab. Use this runbook for logon failures, latency, disconnects, and desktop launch problems before taking corrective action.

---

## Step 1: Identify the Symptom

Start by classifying the user complaint:

| Symptom | Common Indicators | Jump To |
|---------|-------------------|---------|
| Logon failure | Session host unavailable, agent unhealthy, token or registration issues | Step 2A |
| Users connect but stall before full desktop | Started connection with no completion event | Step 2B |
| Slow sign-in or black screen | Long profile, GPO, or shell initialization | Step 2C |
| Users are intermittently rejected or land on busy hosts | Hosts in drain mode, low capacity, start-on-connect gaps | Step 2D |
| Desktop launches but profile is broken or unavailable | FSLogix profile attach errors | See `avd-fslogix-profiles.md` |

Initial commands:

```bash
az desktopvirtualization hostpool show --resource-group <rg> --name <host-pool>
az desktopvirtualization sessionhost list --resource-group <rg> --host-pool-name <host-pool>
```

---

## Step 2A: Session Host AVD Agent Stopped or Unhealthy

**Symptoms:**
- Users can't connect to one or more session hosts
- Session host shows **Unavailable** or **Needs assistance**
- Agent heartbeat is missing or stale

**KQL:**
```kql
WVDAgentHealthStatus
| where TimeGenerated > ago(1h)
| where Status != "Available"
| project TimeGenerated,
          HostPoolName = column_ifexists("HostPoolName", ""),
          SessionHostName = column_ifexists("SessionHostName", ""),
          Status,
          Message = column_ifexists("Message", "")
| order by TimeGenerated desc
```

**Diagnostic commands:**
```bash
az vm run-command invoke \
  --resource-group <rg> \
  --name <session-host-vm> \
  --command-id RunPowerShellScript \
  --scripts "Get-Service -Name RDAgentBootLoader,'Remote Desktop Agent Loader' | Select-Object Name, Status, StartType"
```

**Remediation:** restart the AVD agent services on the affected host.

```bash
az vm run-command invoke \
  --resource-group <rg> \
  --name <session-host-vm> \
  --command-id RunPowerShellScript \
  --scripts "Restart-Service -Name RDAgentBootLoader,'Remote Desktop Agent Loader' -Force; Get-Service -Name RDAgentBootLoader,'Remote Desktop Agent Loader'"
```

**Post-fix validation:**
1. Re-run the `WVDAgentHealthStatus` query.
2. Confirm the host returns to **Available**.
3. Retry a user connection.

---

## Step 2B: Network Connectivity (STA Blocked, NSG Rule, Gateway Path)

**Symptoms:**
- Connection starts but never completes
- User sees a long spinner or timeout
- AVD agent is healthy but users still fail to reach the desktop

**KQL:** look for connections that started but never reached a completed state.

```kql
let started =
    WVDConnections
    | where TimeGenerated > ago(1h)
    | where ConnectionType == "Connection" and State == "Started"
    | extend CorrelationId = tostring(column_ifexists("CorrelationId", column_ifexists("CorrelationID", "")))
    | project CorrelationId,
              UserName = column_ifexists("UserName", ""),
              SessionHostName = column_ifexists("SessionHostName", ""),
              HostPoolName = column_ifexists("HostPoolName", ""),
              StartedAt = TimeGenerated;
let completed =
    WVDConnections
    | where TimeGenerated > ago(1h)
    | where ConnectionType == "Connection" and State == "Completed"
    | extend CorrelationId = tostring(column_ifexists("CorrelationId", column_ifexists("CorrelationID", "")))
    | project CorrelationId,
              CompletedAt = TimeGenerated;
started
| join kind=leftouter completed on CorrelationId
| where isnull(CompletedAt)
| order by StartedAt desc
```

**Checks:**
1. Verify outbound TCP 443 to the `WindowsVirtualDesktop` service tag isn't blocked.
2. Review NSG rules on the AVD subnet and session host NICs.
3. Validate proxy, firewall, and DNS egress for AVD broker and gateway endpoints.

**Useful commands:**
```bash
az network nsg rule list --resource-group <rg> --nsg-name <nsg-name> --output table
az network watcher test-connectivity --source-resource <vm-id> --dest-address rdbroker.wvd.microsoft.com --dest-port 443
```

**Remediation:**
- Remove deny rules for `WindowsVirtualDesktop` on port 443.
- Restore required outbound access for broker, gateway, and diagnostics endpoints.
- If a single host is affected, compare NSG, route, and proxy settings with a healthy host.

---

## Step 2C: Logon Performance

**Symptoms:**
- Sign-in takes much longer than normal
- Users hit a black screen before Explorer loads
- Profile load or GPO processing dominates the timeline

**KQL:** break down profile load, GPO load, and shell initialization.

```kql
WVDCheckpoints
| where TimeGenerated > ago(1h)
| extend CheckpointName = tostring(column_ifexists("Name", column_ifexists("CheckPointName", "")))
| where CheckpointName has_any ("Profile", "Group Policy", "Shell")
| extend DurationMs = tolong(column_ifexists("DurationMs", column_ifexists("TimeTakenInMilliseconds", 0)))
| project TimeGenerated,
          UserName = column_ifexists("UserName", ""),
          SessionHostName = column_ifexists("SessionHostName", ""),
          Name = CheckpointName,
          DurationMs,
          Details = tostring(column_ifexists("Parameters", ""))
| order by DurationMs desc, TimeGenerated desc
```

**Interpretation guide:**
- **Profile** spikes usually point to FSLogix, SMB latency, or large profile containers.
- **Group Policy** spikes usually point to slow GPO processing, scripts, or DC reachability.
- **Shell** spikes usually point to logon scripts, shell extensions, or disk pressure.

**Remediation:**
- For profile delays, switch to `avd-fslogix-profiles.md`.
- For GPO delays, reduce synchronous GPOs or check domain controller latency.
- For shell delays, inspect startup tasks, antivirus scans, and free disk space.

---

## Step 2D: Capacity, Drain Mode, and Start-on-Connect

**Symptoms:**
- New users are rejected even though the host pool exists
- One host is overloaded while others are idle
- Healthy hosts are in drain mode or powered off

**Checks:**
```bash
az desktopvirtualization sessionhost list \
  --resource-group <rg> \
  --host-pool-name <host-pool> \
  --output table
```

Focus on:
- `allowNewSession == false` on too many hosts
- Hosts stuck in drain mode after maintenance
- No spare capacity when all healthy hosts are at or near the session limit
- Start-on-connect enabled but no host is able to boot quickly enough for demand

**Signals to review:**
- AVD Insights active sessions per host
- `WVDAgentHealthStatus` for healthy host count
- `WVDConnections` failure spikes during busy periods
- VM CPU, memory, and disk counters for session hosts

**Remediation:**
1. Re-enable new sessions on at least one healthy host:
   ```bash
   az desktopvirtualization sessionhost update \
     --resource-group <rg> \
     --host-pool-name <host-pool> \
     --name <session-host-resource-name> \
     --allow-new-session true
   ```
2. Add or start more hosts if demand is sustained.
3. Drain only the hosts you are actively patching or troubleshooting.
4. Validate start-on-connect and autoscale behavior if users arrive after hosts are deallocated.

---

## Recovery Checklist

Use this checklist after any fix:
1. Confirm the affected session host reports **Available**.
2. Confirm new connections move from `Started` to `Completed`.
3. Verify no profile attach failures remain.
4. Review drain mode and current session counts before closing the incident.
5. Notify the user and keep monitoring for 15-30 minutes.
