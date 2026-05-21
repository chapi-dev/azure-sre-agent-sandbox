export default function createListDeliveryGroupsTool({ citrixClient }) {
  return {
    definition: {
      name: 'citrix_list_delivery_groups',
      description: 'List Citrix Delivery Groups with summarized capacity and session metadata.',
      inputSchema: {
        type: 'object',
        properties: {},
        additionalProperties: false,
      },
    },
    handler: async () => citrixClient.listDeliveryGroups(),
  };
}
