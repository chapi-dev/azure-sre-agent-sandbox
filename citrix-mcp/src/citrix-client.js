import axios from 'axios';

const TOKEN_CACHE_MS = 50 * 60 * 1000;
const DEFAULT_TIMEOUT_MS = 15000;
const CVAD_BASE_URL = 'https://api.cloud.com/cvad/manage';

function firstDefined(source, keys) {
  for (const key of keys) {
    const value = source?.[key];
    if (value !== undefined && value !== null && value !== '') {
      return value;
    }
  }

  return undefined;
}

function normalizeText(value) {
  return String(value ?? '').trim().toLowerCase();
}

function matchesFilter(value, expected) {
  if (!expected) {
    return true;
  }

  return normalizeText(value).includes(normalizeText(expected));
}

function clampLimit(limit, fallback = 25) {
  const parsed = Number.parseInt(String(limit ?? fallback), 10);

  if (Number.isNaN(parsed)) {
    return fallback;
  }

  return Math.max(1, Math.min(parsed, 100));
}

function toArray(payload) {
  if (Array.isArray(payload)) {
    return payload;
  }

  const candidates = [
    payload?.Items,
    payload?.items,
    payload?.value,
    payload?.Value,
    payload?.Machines,
    payload?.Sessions,
    payload?.DeliveryGroups,
    payload?.MachineCatalogs,
  ];

  for (const candidate of candidates) {
    if (Array.isArray(candidate)) {
      return candidate;
    }
  }

  return [];
}

function summarizeMachine(machine) {
  return {
    id: firstDefined(machine, ['Id', 'id', 'MachineId', 'Uid']),
    machineName: firstDefined(machine, ['MachineName', 'Name', 'HostedMachineName']),
    dnsName: firstDefined(machine, ['DnsName', 'DNSName', 'HostName']),
    accountName: firstDefined(machine, ['AccountName', 'ADAccountName', 'SamName']),
    deliveryGroup: firstDefined(machine, ['DeliveryGroupName', 'DesktopGroupName', 'DeliveryGroup']),
    catalog: firstDefined(machine, ['MachineCatalogName', 'CatalogName', 'MachineCatalog']),
    maintenanceMode: Boolean(firstDefined(machine, ['MaintenanceMode', 'InMaintenanceMode']) ?? false),
    powerState: firstDefined(machine, ['PowerState', 'PowerStatus']),
    registrationState: firstDefined(machine, ['RegistrationState', 'RegistrationStatus']),
    sessionCount: firstDefined(machine, ['SessionCount', 'Sessions']),
    zone: firstDefined(machine, ['ZoneName', 'Zone']),
  };
}

function summarizeSession(session) {
  return {
    sessionId: firstDefined(session, ['Id', 'id', 'SessionId', 'Uid']),
    user: firstDefined(session, ['UserName', 'Upn', 'UserPrincipalName', 'User']),
    machineId: firstDefined(session, ['MachineId', 'HostedMachineId']),
    machineName: firstDefined(session, ['MachineName', 'HostedMachineName']),
    deliveryGroup: firstDefined(session, ['DeliveryGroupName', 'DesktopGroupName']),
    catalog: firstDefined(session, ['MachineCatalogName', 'CatalogName']),
    state: firstDefined(session, ['SessionState', 'State']),
    protocol: firstDefined(session, ['Protocol', 'ProtocolName']),
    clientAddress: firstDefined(session, ['ClientAddress', 'ClientIP']),
    startTime: firstDefined(session, ['StartTime', 'LogonTime', 'CreatedDate']),
  };
}

function summarizeDeliveryGroup(group) {
  return {
    id: firstDefined(group, ['Id', 'id', 'Uid']),
    name: firstDefined(group, ['Name', 'DeliveryGroupName']),
    description: firstDefined(group, ['Description']),
    deliveryType: firstDefined(group, ['DeliveryType', 'DeliveryKind']),
    sessionSupport: firstDefined(group, ['SessionSupport', 'SessionType']),
    totalMachines: firstDefined(group, ['TotalMachines', 'MachineCount']),
    availableMachines: firstDefined(group, ['AvailableMachines', 'AvailableMachineCount']),
    enabled: firstDefined(group, ['Enabled', 'IsEnabled']),
  };
}

function summarizeMachineCatalog(catalog) {
  return {
    id: firstDefined(catalog, ['Id', 'id', 'Uid']),
    name: firstDefined(catalog, ['Name', 'CatalogName', 'MachineCatalogName']),
    allocationType: firstDefined(catalog, ['AllocationType']),
    provisioningType: firstDefined(catalog, ['ProvisioningType', 'ProvisioningMethod']),
    machineType: firstDefined(catalog, ['MachineType']),
    sessionSupport: firstDefined(catalog, ['SessionSupport', 'SessionType']),
    totalMachines: firstDefined(catalog, ['TotalMachines', 'MachineCount']),
    zone: firstDefined(catalog, ['ZoneName', 'Zone']),
  };
}

function summarizeAxiosError(error, fallbackMessage) {
  const status = error?.response?.status;
  const upstreamMessage =
    error?.response?.data?.error_description
    ?? error?.response?.data?.message
    ?? error?.response?.data?.Message;

  if (status && upstreamMessage) {
    return `${fallbackMessage} (HTTP ${status}: ${upstreamMessage})`;
  }

  if (status) {
    return `${fallbackMessage} (HTTP ${status})`;
  }

  if (error?.message) {
    return `${fallbackMessage} (${error.message})`;
  }

  return fallbackMessage;
}

export class CitrixClient {
  constructor({ customerId, clientId, clientSecret, timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
    this.customerId = customerId;
    this.clientId = clientId;
    this.clientSecret = clientSecret;
    this.token = undefined;
    this.tokenExpiresAt = 0;
    this.http = axios.create({
      timeout: timeoutMs,
      validateStatus: (status) => status >= 200 && status < 300,
    });
  }

  isConfigured() {
    return Boolean(this.customerId && this.clientId && this.clientSecret);
  }

  ensureConfigured() {
    if (!this.isConfigured()) {
      throw new Error('Citrix Cloud credentials are not configured. Set CITRIX_CUSTOMER_ID, CITRIX_CLIENT_ID, and CITRIX_CLIENT_SECRET or provide Key Vault settings.');
    }
  }

  async getToken(forceRefresh = false) {
    this.ensureConfigured();

    if (!forceRefresh && this.token && Date.now() < this.tokenExpiresAt) {
      return this.token;
    }

    const tokenUrl = `https://api.cloud.com/cctrustoauth2/${encodeURIComponent(this.customerId)}/tokens/clients`;
    const payload = new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: this.clientId,
      client_secret: this.clientSecret,
    });

    try {
      const response = await this.http.post(tokenUrl, payload.toString(), {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          Accept: 'application/json',
        },
      });

      const accessToken = response.data?.access_token;
      if (!accessToken) {
        throw new Error('Citrix token response did not include access_token.');
      }

      const expiresInSeconds = Number.parseInt(String(response.data?.expires_in ?? 3600), 10);
      const ttlMs = Math.min(TOKEN_CACHE_MS, Math.max(60, expiresInSeconds - 300) * 1000);

      this.token = accessToken;
      this.tokenExpiresAt = Date.now() + ttlMs;
      return this.token;
    } catch (error) {
      throw new Error(summarizeAxiosError(error, 'Failed to obtain Citrix Cloud access token'));
    }
  }

  async request(method, path, { params, data, retryOn401 = true } = {}) {
    const token = await this.getToken();

    try {
      return await this.http.request({
        method,
        url: `${CVAD_BASE_URL}${path}`,
        params,
        data,
        headers: {
          Accept: 'application/json',
          Authorization: `CWSAuth bearer=${token}`,
          'Citrix-CustomerId': this.customerId,
          'Content-Type': 'application/json',
        },
      });
    } catch (error) {
      if (error?.response?.status === 401 && retryOn401) {
        await this.getToken(true);
        return this.request(method, path, { params, data, retryOn401: false });
      }

      throw new Error(summarizeAxiosError(error, `Citrix API request failed for ${method.toUpperCase()} ${path}`));
    }
  }

  async getMachineRecords() {
    const response = await this.request('GET', '/Machines');
    return toArray(response.data);
  }

  resolveMachineFromRecord(record) {
    const resolvedId = firstDefined(record, ['Id', 'id', 'MachineId', 'Uid']);
    return {
      resolvedId,
      summary: summarizeMachine(record),
      record,
    };
  }

  machineMatches(record, machineId) {
    const candidates = [
      firstDefined(record, ['Id', 'id', 'MachineId', 'Uid']),
      firstDefined(record, ['MachineName', 'Name', 'HostedMachineName']),
      firstDefined(record, ['DnsName', 'DNSName', 'HostName']),
      firstDefined(record, ['AccountName', 'ADAccountName', 'SamName']),
    ];

    return candidates.some((candidate) => normalizeText(candidate) === normalizeText(machineId));
  }

  async resolveMachine(machineId) {
    if (!machineId) {
      throw new Error('machineId is required.');
    }

    const records = await this.getMachineRecords();
    const match = records.find((record) => this.machineMatches(record, machineId));

    if (!match) {
      throw new Error(`Machine "${machineId}" was not found in Citrix Cloud.`);
    }

    const resolved = this.resolveMachineFromRecord(match);
    if (!resolved.resolvedId) {
      throw new Error(`Machine "${machineId}" was found but did not include a Citrix machine identifier.`);
    }

    return resolved;
  }

  async listMachines({ deliveryGroup, catalog, limit } = {}) {
    const cappedLimit = clampLimit(limit, 25);
    const records = await this.getMachineRecords();
    const filtered = records.filter((machine) => {
      const machineSummary = summarizeMachine(machine);
      return matchesFilter(machineSummary.deliveryGroup, deliveryGroup)
        && matchesFilter(machineSummary.catalog, catalog);
    });

    return {
      filters: {
        deliveryGroup: deliveryGroup ?? null,
        catalog: catalog ?? null,
        limit: cappedLimit,
      },
      totalMatches: filtered.length,
      count: Math.min(filtered.length, cappedLimit),
      machines: filtered.slice(0, cappedLimit).map(summarizeMachine),
    };
  }

  async getSessionRecords() {
    const response = await this.request('GET', '/Sessions');
    return toArray(response.data);
  }

  sessionMatches(summary, sessionId) {
    const candidates = [summary.sessionId, summary.machineId, summary.machineName];
    return candidates.some((candidate) => normalizeText(candidate) === normalizeText(sessionId));
  }

  async findSessions({ user, machine, sessionId } = {}) {
    const records = await this.getSessionRecords();
    return records
      .map((session) => summarizeSession(session))
      .filter((summary) => matchesFilter(summary.user, user)
        && matchesFilter(summary.machineName ?? summary.machineId, machine)
        && (!sessionId || this.sessionMatches(summary, sessionId)));
  }

  async listSessions({ user, machine } = {}) {
    const filtered = await this.findSessions({ user, machine });

    return {
      filters: {
        user: user ?? null,
        machine: machine ?? null,
      },
      count: filtered.length,
      sessions: filtered.slice(0, 50),
    };
  }

  async listDeliveryGroups() {
    const response = await this.request('GET', '/DeliveryGroups');
    const records = toArray(response.data);

    return {
      count: records.length,
      deliveryGroups: records.slice(0, 100).map(summarizeDeliveryGroup),
    };
  }

  async listMachineCatalogs() {
    const response = await this.request('GET', '/MachineCatalogs');
    const records = toArray(response.data);

    return {
      count: records.length,
      machineCatalogs: records.slice(0, 100).map(summarizeMachineCatalog),
    };
  }

  async getMachine(machineId) {
    const resolved = await this.resolveMachine(machineId);
    return resolved.summary;
  }

  async restartMachine(machineId) {
    const resolved = await this.resolveMachine(machineId);
    const response = await this.request('POST', `/Machines/${encodeURIComponent(resolved.resolvedId)}/$reboot`, {
      data: {},
    });

    return {
      taskId:
        firstDefined(response.data, ['TaskId', 'Id', 'OperationId', 'operationId'])
        ?? response.headers?.['x-citrix-taskid']
        ?? `reboot-${resolved.resolvedId}`,
      status: firstDefined(response.data, ['Status', 'status']) ?? 'submitted',
      machine: resolved.summary,
    };
  }

  async setMaintenanceMode(machineId, enabled) {
    const resolved = await this.resolveMachine(machineId);
    const response = await this.request('PATCH', `/Machines/${encodeURIComponent(resolved.resolvedId)}`, {
      data: {
        MaintenanceMode: Boolean(enabled),
      },
    });

    return {
      taskId:
        firstDefined(response.data, ['TaskId', 'Id', 'OperationId', 'operationId'])
        ?? `maintenance-${resolved.resolvedId}`,
      status: firstDefined(response.data, ['Status', 'status']) ?? 'submitted',
      enabled: Boolean(enabled),
      machine: {
        ...resolved.summary,
        maintenanceMode: Boolean(enabled),
      },
    };
  }
}

export default CitrixClient;
