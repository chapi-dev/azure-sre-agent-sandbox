# Module B — Azure Virtual Desktop (AVD)

This module adds an Azure Virtual Desktop demo path focused on end-user connection troubleshooting.

## What Gets Deployed

When the integration agent wires `deployAvd` into `main.bicep`, Module B is intended to deploy:

- A pooled AVD host pool (`hp-${workloadName}`)
- A desktop application group (`avdag-${workloadName}`)
- An AVD workspace (`avdws-${workloadName}`)
- Two Windows 11 Enterprise multi-session session hosts (`vm-avd-${workloadName}-1..2`)
- AVD diagnostics to Log Analytics for host pool, workspace, and app group
- Knowledge base runbooks, an AVD-focused subagent, and scenario scripts

## Deployment Flag

```powershell
.\scripts\deploy.ps1 -Location eastus2 -DeployAvd
```

> `-DeployAvd` is part of the overall plan, but the actual `main.bicep` / `main.bicepparam` wiring is handled by another agent.

## How to Test a Connection

Use either:
- The Azure Virtual Desktop client, or
- The web client: https://client.wvd.microsoft.com

Recommended validation steps:
1. Assign a test user to the desktop application group.
2. Sign in with that user.
3. Launch the published desktop.
4. Confirm a session lands on one of the `vm-avd-*` hosts.

## Demo Prompts

Use prompts like these with Azure SRE Agent:

- "Users can't connect to the host pool, investigate"
- "A user says their AVD desktop never finishes loading"
- "Why are AVD sessions disconnecting before the desktop opens?"
- "Check whether FSLogix or the AVD agent is causing logon failures"
- "Review AVD capacity and tell me if drain mode is blocking users"

## Scenario Scripts

### 1. Agent stopped

Break it:
```powershell
.\scripts\scenarios-avd\break-avd-agent-stopped.ps1 -ResourceGroupName <rg>
```

Expected symptom:
- One host becomes unavailable or unhealthy
- Users routed to that host fail to connect

Expected investigation path:
- `WVDAgentHealthStatus`
- `WVDConnections`
- Session host service status for `RDAgentBootLoader`

### 2. NSG block

Break it:
```powershell
.\scripts\scenarios-avd\break-avd-nsg-block.ps1 -ResourceGroupName <rg> -NsgName <avd-nsg>
```

Expected symptom:
- Connections start but never complete
- Broker / STA path is blocked on outbound TCP 443

Expected investigation path:
- `WVDConnections` started-without-completed pattern
- NSG rule review for `WindowsVirtualDesktop`

### 3. Disk pressure

Break it:
```powershell
.\scripts\scenarios-avd\break-avd-disk-pressure.ps1 -ResourceGroupName <rg>
```

Expected symptom:
- Slow sign-in, shell delays, or host instability
- Session host free space drops sharply

Expected investigation path:
- `WVDCheckpoints`
- VM disk checks via Run Command

### 4. Profile lock

Break it:
```powershell
.\scripts\scenarios-avd\break-avd-profile-lock.ps1 -ResourceGroupName <rg>
```

Expected symptom:
- Profile attach errors
- User gets a temporary or broken profile experience

Expected investigation path:
- FSLogix Event Viewer logs
- Lock-file discovery and orphaned session review

> If a real FSLogix share isn't configured, this script simulates the symptom with a mock `.lock` file on the session host.

## Fix Commands

Reset everything with:

```powershell
.\scripts\scenarios-avd\fix-avd.ps1 -ResourceGroupName <rg>
```

Manual one-off fixes:

```powershell
# Restart the AVD agent services on a host
az vm run-command invoke --resource-group <rg> --name <vm> --command-id RunPowerShellScript --scripts "Restart-Service -Name RDAgentBootLoader,'Remote Desktop Agent Loader' -Force"

# Re-enable new sessions on a drained host
az desktopvirtualization sessionhost update --resource-group <rg> --host-pool-name <host-pool> --name <session-host> --allow-new-session true
```

## Suggested Demo Flow

1. Confirm the desktop opens normally.
2. Run one break script.
3. Ask Azure SRE Agent an open-ended investigation prompt.
4. Show the runbook-backed diagnosis.
5. Apply `fix-avd.ps1` or let the agent execute the remediation.
6. Re-test the connection in the AVD client or web client.

## Cost Estimate

Expect roughly **$5-8/day extra** for the two `Standard_D2s_v5` session hosts plus attached storage, depending on region and runtime hours.
