# Hooks for Module D

Hooks let the Azure SRE Agent intercept tool calls before or after execution. They are the governance layer for enforcing safe change rules, approval flows, and compliance logging.

## Hook types used here

| Type | When it runs | Example in this module |
|------|--------------|------------------------|
| `Stop` | Immediately before a risky action executes | Block deletes or require approval for critical restarts |
| `PreToolUse` | Before the target tool runs | Reject `--force`, require `--subscription`, block dangerous delete commands |
| `PostToolUse` | After the tool returns | Persist an immutable audit event to blob storage |

## Files in this folder

| Hook | Purpose |
|------|---------|
| `stop-prod-deletes.yaml` | Denies delete/remove operations outside business hours or against production-tagged resources |
| `pre-tool-validation.yaml` | Rejects unsafe Azure CLI write-command patterns before execution |
| `approval-required-restarts.yaml` | Requires portal approval for restart/redeploy/reboot operations on `criticality=high` resources |
| `post-tool-audit.yaml` | Emits JSON audit events to immutable blob storage with managed identity |

## Registration model

`configure-sre-agent.ps1` should register these files by calling:

```text
POST {agentEndpoint}/api/v2/extendedAgent/hooks
```

The companion script `scripts\upload-hooks.ps1` discovers the agent endpoint, acquires a bearer token, and posts every `*.yaml` file in this folder.

## Safe testing guidance

Use low-blast-radius commands when validating hooks:

1. **PreToolUse validation**
   - Example: `az group create --name rg-test --location eastus2 --force`
   - Expected: blocked because `--force` is disallowed
2. **Stop hook for deletes**
   - Example: `az group delete --name rg-test --subscription <sub-id>`
   - Expected: blocked outside Mon-Fri 08:00-18:00 UTC
3. **Approval workflow**
   - Example: `az vm restart --ids <critical-vm-id> --subscription <sub-id>` on a resource tagged `criticality=high`
   - Expected: portal approval required before execution
4. **PostToolUse audit**
   - Run any allowed command and confirm a blob lands under `agent-audit/<date>/`

Prefer test resource groups or disposable demo resources instead of shared production assets.