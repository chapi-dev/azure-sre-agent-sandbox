# Movistar BSS Application Architecture

This Telefonica/Movistar BSS demo lab simulates the lifecycle of plan activations, recharges, and provisioning on Azure Kubernetes Service (AKS). It models a Movistar self-service + provisioning platform in the `movistar` namespace, with subscriber journeys starting in digital channels and ending in OSS-style fulfillment workflows.

---

## Services

| Service | Language | Port | Description |
|---------|----------|------|-------------|
| customer-portal | Vue.js / Node.js | 8080 | Consumer self-service portal ("Mi Movistar") for browsing plans, activating lines, and recharges |
| csr-console | Vue.js / Node.js | 8081 | CSR console for assisted care, plan changes, and subscriber troubleshooting |
| activation-service | Go / Node.js | 3000 | BSS API for activations, plan changes, prepaid top-ups, and subscriber transactions |
| catalog-service | Go / Node.js | 3002 | Catalog API for plans, bundles, add-ons, and eligibility rules |
| provisioning-service | Go / Node.js | 3001 | OSS provisioning processor that simulates HLR/HSS and downstream network updates |
| traffic-simulator | Node.js | — | Simulates subscriber traffic through the self-service journey |
| network-worker | Node.js | — | Simulates operational workers completing provisioning tasks |

## Backing Services

| Service | Port | Persistence | Description |
|---------|------|-------------|-------------|
| subscriber-db | 27017 | PersistentVolumeClaim (Azure Managed Disk) | Subscriber, plan, and activation state store backed by MongoDB (`mongo:6`) |
| provisioning-queue | 5672 | In-memory | Queue used between activation and provisioning stages, backed by RabbitMQ (`rabbitmq:3.11-management-alpine`) |

## Dependencies

```
Internet
  │
  ├──→ customer-portal (8080) ──→ activation-service (3000) ──→ subscriber-db (27017)
  │         │                             │
  │         │                             └──→ provisioning-queue (5672)
  │         │
  │         └──→ catalog-service (3002) ──→ subscriber-db (27017)
  │
  ├──→ csr-console (8081) ──→ activation-service, catalog-service, provisioning-service
  │
  │    activation-service (3000) ──→ provisioning-queue (5672) ──→ provisioning-service (3001) ──→ subscriber-db (27017)
  │
  │    traffic-simulator ──→ customer-portal
  └──  network-worker ──→ provisioning-service
```

## Kubernetes Resources

All resources are deployed in the `movistar` namespace.

### Deployments
- `subscriber-db` — 1 replica, attached to `mongodb-data-pvc`
- `provisioning-queue` — 1 replica, in-memory
- `catalog-service` — 1 replica
- `activation-service` — 1 replica
- `provisioning-service` — 1 replica
- `customer-portal` — 1 replica, type LoadBalancer (external)
- `csr-console` — 1 replica
- `traffic-simulator` — 1 replica
- `network-worker` — 1 replica

### Services
- `subscriber-db` — ClusterIP on port 27017
- `provisioning-queue` — ClusterIP on port 5672 (AMQP) and 15672 (Management)
- `catalog-service` — ClusterIP on port 3002
- `activation-service` — ClusterIP on port 3000
- `provisioning-service` — ClusterIP on port 3001
- `customer-portal` — LoadBalancer on port 80 → 8080
- `csr-console` — ClusterIP on port 80 → 8081

### Storage
- `mongodb-data-pvc` — PersistentVolumeClaim using `managed-csi` StorageClass (Azure Managed Disk) for `subscriber-db`

## Azure Infrastructure

| Component | Azure Service | Purpose |
|-----------|--------------|---------|
| Compute | Azure Kubernetes Service (AKS) | Container orchestration for the Movistar BSS lab |
| Registry | Azure Container Registry | Container image storage |
| Secrets | Azure Key Vault | Secrets management |
| Logs | Log Analytics Workspace | Centralized log storage |
| Telemetry | Application Insights | APM and request tracing |
| Dashboards | Azure Managed Grafana | Visualization |
| Metrics | Azure Monitor Workspace | Prometheus metrics |
| SRE | Azure SRE Agent | AI-powered diagnostics |

## Common Failure Modes

| Failure | Impact | Detection |
|---------|--------|-----------|
| subscriber-db scaled to 0 | Subscriber and activation state lookups fail | catalog-service/activation-service/provisioning-service health checks fail |
| provisioning-queue down | Activations are accepted but provisioning never starts | provisioning-service has nothing to process |
| OOMKilled on activation-service | Pod restarts, activations and top-ups fail | Pod restart count increases, OOMKilled events |
| Network policy blocking activation-service | Activations fail, portal errors surface to subscribers | Connection timeout between customer-portal and activation-service |
| Service selector mismatch on activation-service | Silent failure, zero endpoints | Service has 0 endpoints despite healthy pods |
| Wrong image tag on provisioning-service | Pod stuck in ImagePullBackOff | Kubelet events show image pull errors |
| Missing ConfigMap on csr-console | CSR tooling will not start | CreateContainerConfigError |
| CPU stress workload | All BSS flows degrade | High CPU across nodes |
| Probe misconfiguration on customer-portal | Unnecessary restarts and false health alarms | Readiness/liveness probe events |
| Oversized resource requests | New pods stuck in Pending | Scheduler events show insufficient resources |

## Monitoring

### Log Analytics Queries

**Error logs across all services:**
```kql
ContainerLogV2
| where TimeGenerated > ago(1h)
| where PodNamespace == "movistar"
| where LogMessage contains "error" or LogMessage contains "Error"
| summarize ErrorCount = count() by PodName, bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

**Pod restart history:**
```kql
KubePodInventory
| where TimeGenerated > ago(24h)
| where Namespace == "movistar"
| where PodRestartCount > 0
| summarize MaxRestarts = max(PodRestartCount) by Name, bin(TimeGenerated, 1h)
| order by MaxRestarts desc
```

### Application Insights Queries

**Failed requests:**
```kql
requests
| where timestamp > ago(1h)
| where success == false
| summarize FailedCount = count() by name, resultCode, bin(timestamp, 5m)
| order by FailedCount desc
```
