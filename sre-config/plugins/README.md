# Plugins for Module D

Plugins expose external HTTP APIs as agent tools. They are lighter-weight than MCP connectors and work well for simple request/response integrations such as CMDB lookups or incident-ticket updates.

## Plugin vs MCP

| Capability | Plugin | MCP |
|------------|--------|-----|
| Transport | Simple REST/HTTP wrapper | Dedicated bidirectional protocol |
| Best for | CRUD APIs, enrichment services, ticketing, CMDB lookups | Rich tool ecosystems, interactive servers, streaming workflows |
| Complexity | Lower | Higher |
| Example in this module | Mock CMDB and Jira | Existing `github-mcp` connector |

## Files in this folder

| Plugin | Purpose |
|--------|---------|
| `cmdb-http-plugin.yaml` | Calls a mock CMDB Function App for owner, criticality, dependency, and runbook data |
| `jira-http-plugin.yaml` | Calls Jira REST to create issues, add comments, and transition tickets |

## Registration model

`configure-sre-agent.ps1` should register these plugin definitions by calling:

```text
POST {agentEndpoint}/api/v2/extendedAgent/plugins
```

The companion script `scripts\upload-plugins.ps1` replaces the CMDB URL placeholder, optionally injects the Function key header value for the mock CMDB plugin, and posts each YAML definition.

## Security considerations

- Store plugin credentials in **Key Vault** or in the SRE Agent secret store instead of hardcoding them in source control
- Use **Managed Identity** when the target service supports it
- Scope Function keys and Jira API tokens to the minimum required permissions
- Keep audit hooks enabled so plugin usage is captured in immutable storage
- Review outbound connectivity and firewall rules before enabling plugins in a shared environment