import { randomUUID } from 'node:crypto';
import express from 'express';
import { DefaultAzureCredential } from '@azure/identity';
import { SecretClient } from '@azure/keyvault-secrets';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { CallToolRequestSchema, ListToolsRequestSchema, isInitializeRequest } from '@modelcontextprotocol/sdk/types.js';
import CitrixClient from './citrix-client.js';
import createListMachinesTool from './tools/list-machines.js';
import createGetSessionInfoTool from './tools/get-session-info.js';
import createRestartMachineTool from './tools/restart-machine.js';
import createListDeliveryGroupsTool from './tools/list-delivery-groups.js';
import createGetMachineCatalogTool from './tools/get-machine-catalog.js';
import createDrainMachineTool from './tools/drain-machine.js';

const TOOL_FACTORIES = [
  createListMachinesTool,
  createGetSessionInfoTool,
  createRestartMachineTool,
  createListDeliveryGroupsTool,
  createGetMachineCatalogTool,
  createDrainMachineTool,
];

function readEnv(name) {
  const value = process.env[name];
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : undefined;
}

function parseSecretNameOverrides() {
  const fromJson = readEnv('KEYVAULT_SECRET_NAMES');
  let parsed = {};

  if (fromJson) {
    try {
      parsed = JSON.parse(fromJson);
    } catch (error) {
      console.warn('KEYVAULT_SECRET_NAMES is not valid JSON. Falling back to individual secret-name variables.');
    }
  }

  return {
    customerId: parsed.customerId ?? readEnv('CITRIX_CUSTOMER_ID_SECRET_NAME') ?? 'citrix-customer-id',
    clientId: parsed.clientId ?? readEnv('CITRIX_CLIENT_ID_SECRET_NAME') ?? 'citrix-client-id',
    clientSecret: parsed.clientSecret ?? readEnv('CITRIX_CLIENT_SECRET_SECRET_NAME') ?? 'citrix-client-secret',
    mcpBearerToken: parsed.mcpBearerToken ?? readEnv('MCP_BEARER_TOKEN_SECRET_NAME') ?? 'citrix-mcp-bearer-token',
  };
}

async function loadSecret(secretClient, secretName) {
  if (!secretName) {
    return undefined;
  }

  try {
    const response = await secretClient.getSecret(secretName);
    return response.value;
  } catch (error) {
    console.warn(`Unable to read secret "${secretName}" from Key Vault: ${error.message}`);
    return undefined;
  }
}

async function resolveRuntimeConfig() {
  const baseConfig = {
    citrixCustomerId: readEnv('CITRIX_CUSTOMER_ID'),
    citrixClientId: readEnv('CITRIX_CLIENT_ID'),
    citrixClientSecret: readEnv('CITRIX_CLIENT_SECRET'),
    mcpBearerToken: readEnv('MCP_BEARER_TOKEN'),
    keyVaultUrl: readEnv('KEYVAULT_URL'),
  };

  if (!baseConfig.keyVaultUrl) {
    return baseConfig;
  }

  try {
    const credential = new DefaultAzureCredential();
    const secretClient = new SecretClient(baseConfig.keyVaultUrl, credential);
    const secretNames = parseSecretNameOverrides();

    return {
      ...baseConfig,
      citrixCustomerId: baseConfig.citrixCustomerId ?? await loadSecret(secretClient, secretNames.customerId),
      citrixClientId: baseConfig.citrixClientId ?? await loadSecret(secretClient, secretNames.clientId),
      citrixClientSecret: baseConfig.citrixClientSecret ?? await loadSecret(secretClient, secretNames.clientSecret),
      mcpBearerToken: baseConfig.mcpBearerToken ?? await loadSecret(secretClient, secretNames.mcpBearerToken),
    };
  } catch (error) {
    console.warn(`Key Vault resolution failed. Continuing with direct environment variables only: ${error.message}`);
    return baseConfig;
  }
}

function toToolResult(payload) {
  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(payload, null, 2),
      },
    ],
  };
}

function createMcpServer(citrixClient) {
  const tools = TOOL_FACTORIES.map((factory) => factory({ citrixClient }));
  const toolMap = new Map(tools.map((tool) => [tool.definition.name, tool]));
  const server = new Server(
    {
      name: 'citrix-mcp',
      version: '0.1.0',
    },
    {
      capabilities: {
        tools: {},
      },
    },
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: tools.map((tool) => tool.definition),
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const tool = toolMap.get(request.params.name);

    if (!tool) {
      return {
        isError: true,
        content: [
          {
            type: 'text',
            text: `Unknown tool: ${request.params.name}`,
          },
        ],
      };
    }

    try {
      const result = await tool.handler(request.params.arguments ?? {});
      return toToolResult(result);
    } catch (error) {
      return {
        isError: true,
        content: [
          {
            type: 'text',
            text: error instanceof Error ? error.message : 'Unexpected tool error.',
          },
        ],
      };
    }
  });

  return server;
}

async function start() {
  const runtimeConfig = await resolveRuntimeConfig();
  const citrixClient = new CitrixClient({
    customerId: runtimeConfig.citrixCustomerId,
    clientId: runtimeConfig.citrixClientId,
    clientSecret: runtimeConfig.citrixClientSecret,
  });

  const sessions = new Map();
  const app = express();
  const port = Number.parseInt(process.env.PORT ?? '3000', 10);

  app.disable('x-powered-by');
  app.use(express.json({ limit: '1mb' }));

  app.get('/healthz', (_req, res) => {
    res.json({
      status: 'ok',
      toolCount: TOOL_FACTORIES.length,
      citrixConfigured: citrixClient.isConfigured(),
      keyVaultEnabled: Boolean(runtimeConfig.keyVaultUrl),
      mcpBearerTokenConfigured: Boolean(runtimeConfig.mcpBearerToken),
    });
  });

  app.use('/mcp', (req, res, next) => {
    if (!runtimeConfig.mcpBearerToken) {
      res.status(503).json({ error: 'MCP_BEARER_TOKEN is not configured.' });
      return;
    }

    const authorization = req.header('authorization');
    if (authorization !== `Bearer ${runtimeConfig.mcpBearerToken}`) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    next();
  });

  app.post('/mcp', async (req, res) => {
    const sessionId = req.header('mcp-session-id');
    let session = sessionId ? sessions.get(sessionId) : undefined;

    try {
      if (!session) {
        if (!isInitializeRequest(req.body)) {
          res.status(400).json({
            jsonrpc: '2.0',
            error: {
              code: -32000,
              message: 'Initialize the MCP session first.',
            },
            id: req.body?.id ?? null,
          });
          return;
        }

        const server = createMcpServer(citrixClient);
        let sessionRecord;
        const transport = new StreamableHTTPServerTransport({
          sessionIdGenerator: () => randomUUID(),
          enableJsonResponse: true,
          onsessioninitialized: (newSessionId) => {
            if (sessionRecord) {
              sessions.set(newSessionId, sessionRecord);
            }
          },
        });

        sessionRecord = { server, transport };
        session = sessionRecord;

        transport.onclose = () => {
          if (transport.sessionId) {
            sessions.delete(transport.sessionId);
          }

          void server.close().catch((error) => {
            console.error(`Failed to close MCP session ${transport.sessionId ?? '<pending>'}:`, error);
          });
        };

        await server.connect(transport);
      }

      await session.transport.handleRequest(req, res, req.body);
    } catch (error) {
      console.error('Failed to handle MCP request:', error);
      if (!res.headersSent) {
        res.status(500).json({
          jsonrpc: '2.0',
          error: {
            code: -32603,
            message: error instanceof Error ? error.message : 'Unexpected server error.',
          },
          id: req.body?.id ?? null,
        });
      }
    }
  });

  const handleSessionRoute = async (req, res) => {
    const sessionId = req.header('mcp-session-id');
    const session = sessionId ? sessions.get(sessionId) : undefined;

    if (!session) {
      res.status(400).send('Invalid or missing Mcp-Session-Id header.');
      return;
    }

    try {
      await session.transport.handleRequest(req, res, req.body);
    } catch (error) {
      console.error(`Failed to handle ${req.method} for MCP session ${sessionId}:`, error);
      if (!res.headersSent) {
        res.status(500).send(error instanceof Error ? error.message : 'Unexpected server error.');
      }
    }
  };

  app.get('/mcp', handleSessionRoute);
  app.delete('/mcp', handleSessionRoute);

  const httpServer = app.listen(port, '0.0.0.0', () => {
    console.log(`Citrix MCP server listening on port ${port}`);
    if (!citrixClient.isConfigured()) {
      console.warn('Citrix credentials are not fully configured yet. Tool calls will fail until secrets are provided.');
    }
  });

  const shutdown = async () => {
    const closeOperations = [];

    for (const [sessionId, session] of sessions.entries()) {
      sessions.delete(sessionId);
      closeOperations.push(session.server.close().catch(() => undefined));
    }

    await Promise.all(closeOperations);

    await new Promise((resolve) => {
      httpServer.close(() => resolve());
    });
  };

  process.on('SIGINT', async () => {
    await shutdown();
    process.exit(0);
  });

  process.on('SIGTERM', async () => {
    await shutdown();
    process.exit(0);
  });
}

start().catch((error) => {
  console.error('Citrix MCP server failed to start:', error);
  process.exit(1);
});
