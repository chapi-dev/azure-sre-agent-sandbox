export default function createDrainMachineTool({ citrixClient }) {
  return {
    definition: {
      name: 'citrix_drain_machine',
      description: 'Enable or disable maintenance mode for a Citrix DaaS machine before remediation work.',
      inputSchema: {
        type: 'object',
        properties: {
          machineId: {
            type: 'string',
            description: 'Citrix machine identifier, DNS name, host name, or AD account name.',
          },
          enabled: {
            type: 'boolean',
            description: 'Set to true to drain the machine, false to return it to service.',
          },
        },
        required: ['machineId', 'enabled'],
        additionalProperties: false,
      },
    },
    handler: async (args = {}) => citrixClient.setMaintenanceMode(args.machineId, args.enabled),
  };
}
