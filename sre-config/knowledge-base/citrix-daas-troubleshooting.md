# Citrix DaaS Troubleshooting Runbook

Use this runbook when Azure SRE Agent needs to diagnose Citrix DaaS user-session issues for workloads hosted on Azure.

---

## Citrix architecture on Azure

A typical Citrix DaaS deployment on Azure includes these layers:

- **Citrix Cloud control plane** - Brokering, policy, identity, and orchestration services.
- **Cloud Connectors** - Outbound trust bridge from the Azure landing zone into the Citrix Cloud control plane.
- **Delivery Controllers (logical broker plane)** - In Citrix DaaS this is mostly control-plane managed, but broker registration and VDA reachability still matter.
- **VDAs / session hosts** - The Windows VMs running user sessions and applications.
- **Machine Catalogs** - The provisioning boundary for sets of VDAs.
- **Delivery Groups** - The entitlement and brokering boundary presented to users.
- **STA (Secure Ticket Authority)** - Ticket validation used during session launch.
- **NetScaler / Citrix ADC** - ICA proxy, gateway, and HDX ingress when external access is involved.

When Citrix workloads run on Azure, SRE Agent should correlate Citrix state with Azure evidence such as VM health, NSGs, route tables, disk latency, boot diagnostics, guest agent status, and Log Analytics data.

---

## Common failure points

| Component | Symptom | Evidence to collect |
|-----------|---------|---------------------|
| Cloud Connector | Many launches fail at once | Connector health, outbound connectivity, broker registration drift |
| VDA / session host | Single machine causes frozen or failed sessions | CPU, memory, disk queue, packet loss, Windows event logs |
| Delivery Group | Users have no available desktops | Delivery Group capacity, maintenance mode, powered-on machine count |
| Machine Catalog | New machines never become usable | Provisioning state, registration failures, image drift |
| STA / ADC | Launch starts but ICA handoff fails | STA validation errors, gateway logs, clock skew, certificate issues |
| Azure networking | Intermittent registration or launch failures | NSG denies, DNS resolution, route changes, firewall policy |
| Identity | Logon or entitlement failures | AAD sign-in errors, AD lockouts, Kerberos / LDAP reachability |

---

## How the SRE agent should use citrix-mcp tools

1. **Start with memory** - Search for prior Citrix incidents and relevant runbooks.
2. **Find the session** - Use `citrix_get_session_info` with the user UPN or session identifier.
3. **Identify the machine** - Use `citrix_list_machines` to inspect registration state, maintenance mode, Delivery Group, and catalog placement.
4. **Check the blast radius** - Use `citrix_list_delivery_groups` and `citrix_get_machine_catalog` to determine whether the issue is isolated or systemic.
5. **Correlate with Azure** - Query Log Analytics and Azure VM diagnostics for CPU saturation, disk latency, network drops, guest agent failures, and recent platform actions.
6. **Contain first, then reboot** - If a single host is unhealthy, use `citrix_drain_machine` before `citrix_restart_machine`.
7. **Document the decision** - Record whether the symptom points to Citrix brokering, Azure infrastructure, or identity.

---

## Decision tree: session launch failure

### Symptom: "Session launch failed" or "Cannot start desktop"

1. **Is the issue affecting one user or many users?**
   - One user -> inspect the specific session and target machine.
   - Many users -> inspect Delivery Group capacity, connector health, STA, ADC, and identity services.
2. **Does Citrix return a session or machine candidate?**
   - Yes -> correlate with Azure VM health and machine registration.
   - No -> inspect entitlements, broker capacity, and authentication flow.
3. **Is the machine unhealthy but isolated?**
   - Yes -> drain the machine, reboot it, and verify new sessions are redirected elsewhere.
   - No -> do not reboot fleet-wide until control-plane, gateway, and identity dependencies are cleared.
4. **Does the failure happen before ICA launch?**
   - Yes -> suspect broker forwarding, entitlement, or identity issues.
   - No -> suspect STA validation, gateway proxy, or VDA host health.

---

## Investigation sequence

### Step 1: Scope the incident

- Determine affected users, Delivery Group, and Machine Catalog.
- Decide whether this is **single-host**, **single-pool**, or **environment-wide**.

### Step 2: Inspect Citrix state

Use MCP tools to answer:

- Is the session present?
- Which machine is assigned?
- Is the machine already in maintenance mode?
- Is the VDA registered and powered on?
- Are other machines in the same Delivery Group healthy?

### Step 3: Inspect Azure evidence

Correlate the Citrix machine with Azure diagnostics:

- VM CPU and memory pressure
- Disk queue length or high read/write latency
- NIC errors, packet drops, or NSG denies
- Recent restarts, host maintenance, or failed extensions
- Log Analytics events around the incident time window

### Step 4: Choose the least risky remediation

- **Single unhealthy host** -> drain, restart, validate, return to service.
- **Catalog-wide problem** -> stop and investigate image, registration, or provisioning.
- **Gateway / STA issue** -> do not reboot VDAs first; fix proxy or ticket validation path.
- **Identity issue** -> validate AAD / AD sign-in flow before touching hosts.

---

## Escalation guidance

Escalate to the Citrix platform owner when:

- More than one Delivery Group is failing simultaneously.
- Cloud Connector or ADC health is in doubt.
- STA ticket validation fails repeatedly.
- Machine reboots do not restore healthy launches.
- AAD or AD authentication is failing broadly.

Escalate to the Azure infrastructure owner when:

- Azure platform events align with the outage.
- NSG, routing, DNS, or VM extension failures are observed.
- Disk or host-level failures point to Azure infrastructure rather than Citrix brokering.
