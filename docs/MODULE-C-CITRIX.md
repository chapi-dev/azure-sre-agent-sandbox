# Module C - Citrix DaaS Integration via Custom MCP Server

Module C adds a demo-grade custom MCP server that wraps a subset of the Citrix Cloud DaaS REST API and exposes it to Azure SRE Agent as `citrix-mcp/*` tools.

## Prerequisites

- A Citrix Cloud tenant with DaaS enabled
- A Citrix Cloud API client created under **Identity and Access Management > API Access > Secure Clients > Create**
- Azure Container Registry to store the MCP image
- Azure Key Vault for secret storage (recommended)
- Azure Container Apps for the `citrix-mcp` service

Required Citrix values:

- `CitrixCustomerId`
- `CitrixClientId`
- `CitrixClientSecret`

## Build and push the MCP image

From the `citrix-mcp` directory:

```powershell
Set-Location .\citrix-mcp
docker build -t <acrLoginServer>/citrix-mcp:latest .
docker push <acrLoginServer>/citrix-mcp:latest
```

Equivalent single-line example:

```powershell
docker build -t <acrLoginServer>/citrix-mcp:latest . && docker push <acrLoginServer>/citrix-mcp:latest
```

## Intended deployment flag

The future deployment contract for this module is:

```powershell
.\scripts\deploy.ps1 -Location eastus2 -DeployCitrixMcp -CitrixCustomerId X -CitrixClientId Y -CitrixClientSecret $env:CITRIX_CLIENT_SECRET
```

This task intentionally **does not** modify `deploy.ps1`, `configure-sre-agent.ps1`, `main.bicep`, or `main.bicepparam`. The files added here define the Module C payload and the expected integration points for a later wire-up pass.

## Infrastructure pieces added

- `infra\bicep\modules\citrix-mcp-keyvault.bicep` - stores Citrix credentials and the shared MCP bearer token in Key Vault
- `infra\bicep\modules\citrix-mcp-container.bicep` - deploys Azure Container Apps environment + Container App for the MCP server
- `sre-config\connectors\citrix-mcp.yaml` - Streamable HTTP connector template
- `sre-config\agents\citrix-session-doctor.yaml` - specialized Citrix incident subagent

## How the MCP is registered with SRE Agent

`configure-sre-agent.ps1` is expected to substitute the FQDN returned by `citrix-mcp-container.bicep` into `sre-config\connectors\citrix-mcp.yaml` by replacing `CITRIX_MCP_URL_PLACEHOLDER`.

The resulting connector points SRE Agent to:

```text
https://<containerAppFqdn>/mcp
```

Authentication is bearer-token based. The same shared token configured in the Container App must be passed by the connector at runtime.

## Demo flow

Example story for the lab:

1. A user reports a frozen Citrix session.
2. `citrix-session-doctor` uses `citrix_get_session_info` to locate the user session.
3. It uses `citrix_list_machines` to identify the backing VDA and Delivery Group.
4. It correlates that machine with Azure VM diagnostics (CPU, disk latency, network errors, platform events).
5. If a single machine is unhealthy, it drains the host with `citrix_drain_machine`.
6. It submits `citrix_restart_machine` and verifies that the pool still has remaining capacity.
7. It documents findings and optional next steps.

## Security caveats

- Protect the MCP endpoint with `MCP_BEARER_TOKEN`; do not leave it unauthenticated.
- Prefer Key Vault-backed secrets over inline secret values.
- Restrict Container App ingress where possible.
- Do not store real Citrix credentials in source control.
- Treat this implementation as a demo integration, not production-ready hardening.

## Cost estimate

Expect roughly **$15-30/day** for the additional demo footprint, primarily from:

- Azure Container Apps environment + always-on replica
- Container App execution
- Azure Key Vault operations
- Minor supporting observability and network costs

Actual cost depends on region, replica count, and whether the environment is shared with other demo services.

## Demo-grade note

This module is intentionally scoped for demo realism rather than full production readiness. It is sufficient for showcasing SRE Agent extensibility with a custom MCP server, but it still needs final script wire-up, secret rotation policy, tighter network controls, and broader Citrix API coverage for production use.
