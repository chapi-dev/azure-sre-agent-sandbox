export default function createGetSessionInfoTool({ citrixClient }) {
  return {
    definition: {
      name: 'citrix_get_session_info',
      description: 'Look up Citrix session details by user principal name or session identifier.',
      inputSchema: {
        type: 'object',
        properties: {
          user: {
            type: 'string',
            description: 'Citrix user principal name (UPN) or username.',
          },
          sessionId: {
            type: 'string',
            description: 'Citrix session identifier.',
          },
        },
        oneOf: [
          { required: ['user'] },
          { required: ['sessionId'] },
        ],
        additionalProperties: false,
      },
    },
    handler: async (args = {}) => {
      if (!args.user && !args.sessionId) {
        throw new Error('Provide either user or sessionId.');
      }

      const sessions = await citrixClient.findSessions({
        user: args.user,
        sessionId: args.sessionId,
      });

      let machine = null;
      if (sessions.length === 1 && sessions[0].machineName) {
        try {
          machine = await citrixClient.getMachine(sessions[0].machineName);
        } catch (_error) {
          machine = null;
        }
      }

      return {
        filters: {
          user: args.user ?? null,
          sessionId: args.sessionId ?? null,
        },
        count: sessions.length,
        sessions,
        machine,
      };
    },
  };
}
