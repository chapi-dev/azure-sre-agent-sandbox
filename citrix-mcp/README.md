# Citrix MCP Server

This folder contains a demo-grade Model Context Protocol (MCP) server that wraps the Citrix Cloud DaaS REST API as MCP tools for Azure SRE Agent.

## What it does

The server exposes Citrix Cloud operations such as:

- List DaaS machines
- Look up session information
- List Delivery Groups and Machine Catalogs
- Place a machine in maintenance mode (drain)
- Reboot a machine

It is designed to run locally with Node.js or in Azure Container Apps behind a shared bearer token.

## Register a Citrix Cloud API client

1. Sign in to **Citrix Cloud**.
2. Go to **Identity and Access Management**.
3. Open **API Access** > **Secure Clients**.
4. Select **Create**.
5. Copy the generated values for:
   - `customer_id`
   - `client_id`
   - `client_secret`
6. Store those values in local environment variables or Azure Key Vault.

## Environment variables

### Direct environment mode

Set these variables when you want the server to read secrets directly from the process environment:

- `MCP_BEARER_TOKEN` - shared bearer token required on inbound MCP requests
- `CITRIX_CUSTOMER_ID`
- `CITRIX_CLIENT_ID`
- `CITRIX_CLIENT_SECRET`
- `PORT` - optional, defaults to `3000`

### Optional Azure Key Vault mode

If you prefer the server to fetch secrets at runtime with `DefaultAzureCredential`, set:

- `KEYVAULT_URL` - e.g. `https://my-vault.vault.azure.net/`
- `KEYVAULT_SECRET_NAMES` - optional JSON object such as:
  ```json
  {"customerId":"citrix-customer-id","clientId":"citrix-client-id","clientSecret":"citrix-client-secret","mcpBearerToken":"citrix-mcp-bearer-token"}
  ```

Instead of `KEYVAULT_SECRET_NAMES`, you can also use individual variables:

- `CITRIX_CUSTOMER_ID_SECRET_NAME`
- `CITRIX_CLIENT_ID_SECRET_NAME`
- `CITRIX_CLIENT_SECRET_SECRET_NAME`
- `MCP_BEARER_TOKEN_SECRET_NAME`

Direct environment variables take precedence over Key Vault lookups.

## Build and run locally

```powershell
Set-Location .\citrix-mcp
npm install
npm start
```

Example local configuration in PowerShell:

```powershell
$env:MCP_BEARER_TOKEN = 'replace-me'
$env:CITRIX_CUSTOMER_ID = 'customer-guid'
$env:CITRIX_CLIENT_ID = 'client-guid'
$env:CITRIX_CLIENT_SECRET = 'client-secret'
npm start
```

## Test the MCP endpoint with curl

Initialize a session:

```bash
curl -i -X POST http://localhost:3000/mcp \
  -H "Authorization: Bearer replace-me" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "init-1",
    "method": "initialize",
    "params": {
      "protocolVersion": "2024-11-05",
      "capabilities": {},
      "clientInfo": {
        "name": "curl",
        "version": "1.0.0"
      }
    }
  }'
```

Copy the `Mcp-Session-Id` response header value, then list tools:

```bash
curl -X POST http://localhost:3000/mcp \
  -H "Authorization: Bearer replace-me" \
  -H "Mcp-Session-Id: <session-id>" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "tools-1",
    "method": "tools/list",
    "params": {}
  }'
```

## Azure Container Apps deployment notes

The companion Bicep module in `infra\bicep\modules\citrix-mcp-container.bicep` is intended to:

- Create a dedicated Container Apps environment
- Deploy this image on port `3000`
- Expose an external HTTPS FQDN
- Pull the image from Azure Container Registry
- Inject Citrix and MCP secrets from Azure Key Vault references or inline secure parameters
- Keep `minReplicas = 1` and `maxReplicas = 3`

Recommended Container App settings for the demo:

- Image: `<acrLoginServer>/citrix-mcp:latest`
- Ingress target port: `3000`
- Restrict inbound network access where possible
- Rotate `MCP_BEARER_TOKEN` regularly
- Prefer Key Vault-backed secrets over inline values

## Notes

- This implementation is intentionally demo-grade.
- Do not store real Citrix credentials in source control.
- The server only wraps a small subset of the Citrix DaaS management API.
