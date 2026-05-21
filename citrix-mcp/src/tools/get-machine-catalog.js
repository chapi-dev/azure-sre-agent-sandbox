function matchesCatalog(catalog, catalogId) {
  const normalizedTarget = String(catalogId ?? '').trim().toLowerCase();
  const candidates = [catalog.id, catalog.name];
  return candidates.some((candidate) => String(candidate ?? '').trim().toLowerCase() === normalizedTarget);
}

export default function createGetMachineCatalogTool({ citrixClient }) {
  return {
    definition: {
      name: 'citrix_get_machine_catalog',
      description: 'List Citrix Machine Catalogs or return a single catalog by identifier or name.',
      inputSchema: {
        type: 'object',
        properties: {
          catalogId: {
            type: 'string',
            description: 'Optional catalog identifier or catalog name.',
          },
        },
        additionalProperties: false,
      },
    },
    handler: async (args = {}) => {
      const result = await citrixClient.listMachineCatalogs();

      if (!args.catalogId) {
        return result;
      }

      const matches = result.machineCatalogs.filter((catalog) => matchesCatalog(catalog, args.catalogId));
      return {
        requestedCatalogId: args.catalogId,
        count: matches.length,
        machineCatalogs: matches,
      };
    },
  };
}
