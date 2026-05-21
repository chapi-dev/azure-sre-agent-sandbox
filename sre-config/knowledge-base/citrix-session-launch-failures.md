# Citrix Session Launch Failures

Use this companion runbook when users report launch-time Citrix errors rather than an already-running frozen session.

---

## Key launch phases

1. **Authentication** - Azure AD or Active Directory validates the user.
2. **Entitlement** - Citrix confirms the user can access the Delivery Group.
3. **Brokering** - Citrix selects a registered, healthy VDA.
4. **Ticketing** - STA issues and validates the launch ticket.
5. **ICA / HDX session establishment** - Citrix ADC / gateway forwards the session to the VDA.
6. **Windows logon** - The VDA completes logon, profile load, and shell start.

A launch failure can happen at any of these stages. The goal is to identify the failing stage first.

---

## Error mapping table

> **Note:** Citrix DaaS surfaces different wording depending on Workspace app, browser launches, and gateway topology. Use the table below as a symptom-to-root-cause map for the demo lab.

| Error code / symptom | Likely root cause | Evidence to collect | Typical next step |
|----------------------|------------------|---------------------|-------------------|
| `Cannot start desktop` | No healthy registered VDA, machine in maintenance mode, or pool exhausted | Delivery Group capacity, machine registration, maintenance mode, power state | Check `citrix_list_machines`, drain or reboot only the bad host |
| `No available resources` | Delivery Group has no available machines or brokering policy mismatch | Delivery Group inventory, entitlement scope, powered-on count | Inspect Delivery Group and Catalog capacity |
| `STA ticket validation failed` | ADC / gateway cannot validate the STA ticket, URL mismatch, certificate issue, or clock skew | Gateway / ADC logs, STA configuration, certificates, time sync | Fix gateway / STA path before rebooting VDAs |
| `Broker forwarding failed` | Cloud Connector or broker cannot reach the target VDA | Connector health, VDA registration, network reachability, Windows firewall | Validate connector path and VDA registration |
| `AADSTS50058` or `AADSTS50076` | Azure AD sign-in issue, MFA requirement, token refresh failure | Entra sign-in logs, conditional access, user impact scope | Resolve identity flow before continuing Citrix checks |
| `0xC000006D` or `1326` | AD logon failure or bad credentials | Security logs, lockouts, domain controller reachability | Validate AD auth and account status |
| `1311` (`No logon servers available`) | Domain controller or DNS reachability issue from the VDA | DC connectivity, DNS queries, NSG / route path | Fix AD / DNS reachability |
| `Profile load timeout` / logon hangs | FSLogix, profile container, storage latency, or GPO delay | FSLogix logs, storage latency, disk queue, logon duration | Resolve profile path or storage latency |

---

## Focus areas by symptom

### 1. Generic "Cannot start desktop"

Most common causes:

- The target VDA is unregistered.
- The machine is already in maintenance mode.
- The Delivery Group has zero spare capacity.
- The VM is powered on but unhealthy from the Azure side.

Agent workflow:

1. `citrix_get_session_info` if the user already has a partial session.
2. `citrix_list_machines` for the target pool.
3. Query Azure diagnostics for CPU, disk, and network issues.
4. If only one host is bad, drain then reboot that host.

### 2. STA ticket validation failures

Symptoms usually indicate the brokering phase succeeded, but ICA launch could not be completed.

Check for:

- ADC / NetScaler configuration drift
- Wrong STA URLs or disabled STA servers
- Certificate mismatch or expiry
- Time skew between gateway, VDA, and control components

Do **not** start by rebooting VDAs if the failure is clearly at the gateway / STA layer.

### 3. Broker forwarding / VDA registration issues

Typical causes:

- VDA registration drift after image updates
- Cloud Connector cannot reach the VDA
- DNS or firewall changes between connectors and session hosts
- Machine catalog image problems affecting multiple hosts

If several machines in the same catalog are unregistered, treat the incident as a catalog or connector issue, not a single-host outage.

### 4. AAD / AD authentication failures

Identity indicators:

- The user never reaches the brokering stage.
- Citrix shows an auth or entitlement message instead of a host-specific error.
- Multiple launch attempts fail across otherwise healthy hosts.

Collect:

- Entra sign-in logs
- Conditional access decisions
- AD lockout and Kerberos events
- Domain controller reachability from the VDA or connector

---

## When to drain and reboot

Drain and reboot only when all of the following are true:

- A single host is implicated.
- Other machines in the same Delivery Group are healthy.
- Azure VM evidence points to guest or host degradation.
- The failure is not clearly caused by STA, ADC, Cloud Connector, or identity.

If those conditions are not met, continue investigating shared dependencies first.
