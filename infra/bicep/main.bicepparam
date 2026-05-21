// =============================================================================
// Bicep Parameters File - SRE Agent Sandbox
// =============================================================================
// Deploy with: az deployment sub create --location eastus2 --template-file main.bicep
// =============================================================================

using 'main.bicep'

// Core parameters are passed by scripts/deploy.ps1 via --parameters

// Observability stack (Grafana + Prometheus)
param deployObservability = true

// Baseline alert rules
param deployAlerts = false

// Deploy Azure SRE Agent (programmatic deployment now supported)
param deploySreAgent = true

// Default action group for incident routing (add webhook at deploy time)
param deployActionGroup = false

// Extended demo lab modules remain opt-in so the baseline lab still works unchanged.
param deployMultiStack = false
param deployAvd = false
param deployCitrixMcp = false
param deploySkillsAndHooks = false
param deployGovernance = false

param adminUsername = 'srelab-admin'

// Sensitive params should NOT be hard-coded. Leave them empty or inject them via environment variables.
// scripts/deploy.ps1 can also pass these with --parameters at deploy time.
param adminPassword = readEnvironmentVariable('SRELAB_ADMIN_PASSWORD', '')
param citrixCustomerId = readEnvironmentVariable('SRELAB_CITRIX_CUSTOMER_ID', '')
param citrixClientId = readEnvironmentVariable('SRELAB_CITRIX_CLIENT_ID', '')
param citrixClientSecret = readEnvironmentVariable('SRELAB_CITRIX_CLIENT_SECRET', '')
param mcpBearerToken = readEnvironmentVariable('SRELAB_MCP_BEARER_TOKEN', '')

// AKS Configuration - cost-optimized for demo
param systemNodeVmSize = 'Standard_D2s_v5'
param userNodeVmSize = 'Standard_D2s_v5'
param systemNodeCount = 2
param userNodeCount = 3

// Tags
param tags = {
  workload: 'sre-agent-demo'
  environment: 'sandbox'
  managedBy: 'bicep'
  purpose: 'demonstration'
  costCenter: 'demo-lab'
}
