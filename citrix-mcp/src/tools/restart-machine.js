export default function createRestartMachineTool({ citrixClient }) {
  return {
    definition: {
      name: 'citrix_restart_machine',
      description: 'Resolve a Citrix DaaS machine by DNS name, host name, or AD account name and submit a reboot request.',
      inputSchema: {
        type: 'object',
        properties: {
          machineId: {
            type: 'string',
            description: 'Citrix machine identifier, DNS name, host name, or AD account name.',
          },
        },
        required: ['machineId'],
        additionalProperties: false,
      },
    },
    handler: async (args = {}) => {
      const result = await citrixClient.restartMachine(args.machineId);
      return {
        taskId: result.taskId,
        status: result.status,
        machine: result.machine,
      };
    },
  };
}
