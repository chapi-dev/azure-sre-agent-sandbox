export default function createListMachinesTool({ citrixClient }) {
  return {
    definition: {
      name: 'citrix_list_machines',
      description: 'List Citrix DaaS machines with optional Delivery Group and Machine Catalog filters.',
      inputSchema: {
        type: 'object',
        properties: {
          deliveryGroup: {
            type: 'string',
            description: 'Optional Delivery Group name filter.',
          },
          catalog: {
            type: 'string',
            description: 'Optional Machine Catalog name filter.',
          },
          limit: {
            type: 'integer',
            description: 'Maximum number of machines to return. Defaults to 25.',
            minimum: 1,
            maximum: 100,
          },
        },
        additionalProperties: false,
      },
    },
    handler: async (args = {}) => citrixClient.listMachines({
      deliveryGroup: args.deliveryGroup,
      catalog: args.catalog,
      limit: args.limit,
    }),
  };
}
