# Azure Virtual Desktop FSLogix Profile Troubleshooting

Use this runbook when Azure Virtual Desktop users can authenticate but their profile fails to attach, is slow to load, or appears locked or corrupt.

---

## Typical Symptoms

- User lands on a temporary profile
- Sign-in hangs during profile attach
- FSLogix reports the VHD/VHDX is locked by another session
- Session host Event Viewer shows profile attach failures

If Azure Monitor Agent (AMA) forwards `Microsoft-FSLogix-Apps/Operational`, query Log Analytics before changing the profile container.

---

## Step 1: Query FSLogix Events

```kql
Event
| where TimeGenerated > ago(1h)
| where EventLog == "Microsoft-FSLogix-Apps/Operational"
   or Source == "Microsoft-FSLogix-Apps"
| where RenderedDescription has_any ("attach", "locked", "VHD", "VHDX", "failed")
| project TimeGenerated,
          Computer,
          EventID,
          Level = column_ifexists("EventLevelName", ""),
          RenderedDescription
| order by TimeGenerated desc
```

**Common error patterns:**
- **Profile attach failed** - storage path unavailable, ACL issue, or corrupt container
- **VHD locked by another session** - orphaned session or stale SMB handle
- **Container cannot be mounted** - underlying disk or file corruption

---

## Step 2: Confirm Active or Orphaned Sessions

Run on the affected session host:

```bash
az vm run-command invoke \
  --resource-group <rg> \
  --name <session-host-vm> \
  --command-id RunPowerShellScript \
  --scripts "quser"
```

If the same user has a stale disconnected session, log it off before touching the profile container.

```bash
az vm run-command invoke \
  --resource-group <rg> \
  --name <session-host-vm> \
  --command-id RunPowerShellScript \
  --scripts "logoff <session-id>"
```

---

## Step 3: Check for Lock Files or Open Handles

If you know the profile share path, inspect it for stale locks:

```powershell
Get-ChildItem \\<storage-or-fileserver>\profiles -Filter *.lock -Recurse -Force
Get-SmbOpenFile | Where-Object { $_.Path -like '*FSLogix*' }
```

If the lab is using the simulated profile-lock scenario instead of a real share, you might find a mock lock file such as:

```text
C:\FSLogix\Profiles\demo-user\Profile_demo.vhdx.lock
```

---

## Step 4: Remediation

Apply the least-destructive fix first:

1. **Force logoff orphan sessions** for the affected user.
2. **Delete stale `.lock` files** only after you confirm no active session owns the profile.
3. **Move the user to a fresh host** by draining the current host and reconnecting.
4. **If the container is corrupt**, rename the VHD/VHDX for offline analysis and allow FSLogix to recreate it.
5. **If storage latency is the root cause**, reduce concurrency on the share or scale the host pool while storage is repaired.

---

## Validation

After remediation:
1. Retry the user sign-in.
2. Confirm the Event Viewer no longer reports new attach failures.
3. Re-check `WVDCheckpoints` for profile stage duration.
4. If the issue repeats on the same host only, drain that host and investigate its SMB and disk health.
