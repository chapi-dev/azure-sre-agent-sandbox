// =============================================================================
// Cost Alerts Module
// =============================================================================
// Deploys an Azure Monitor scheduled query alert for illustrative SRE Agent AAU
// consumption tracking based on Log Analytics telemetry.
// =============================================================================

@description('Alert resource name')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('Log Analytics workspace resource ID used by the alert query')
param logAnalyticsWorkspaceId string

@description('Threshold for AAU consumed in the last 24 hours')
param dailyAauThreshold int = 50

@description('Optional action group resource IDs for notifications')
param actionGroupIds array = []

var alertActions = {
  actionGroups: actionGroupIds
  customProperties: {
    source: 'azure-sre-agent-sandbox'
    signal: 'daily-aau-threshold'
  }
}

resource dailyAauAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: name
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'SRE Agent - Daily AAU threshold breached'
    description: 'Fires when illustrative SRE Agent AAU consumption in the last 24 hours exceeds the configured threshold.'
    enabled: true
    severity: 2
    scopes: [
      logAnalyticsWorkspaceId
    ]
    evaluationFrequency: 'PT1H'
    windowSize: 'PT24H'
    autoMitigate: true
    skipQueryValidation: true
    criteria: {
      allOf: [
        {
          query: '''
AgentTokenUsage_CL
| where TimeGenerated > ago(24h)
| extend AauValue = todouble(coalesce(column_ifexists('AAU_d', 0.0), column_ifexists('Aau_d', 0.0), column_ifexists('AAU', 0.0), 0.0))
| project TimeGenerated, AauValue
'''
          metricMeasureColumn: 'AauValue'
          timeAggregation: 'Total'
          operator: 'GreaterThan'
          threshold: dailyAauThreshold
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: alertActions
  }
}

output alertId string = dailyAauAlert.id

// Wire-up in main.bicep (guarded by deployGovernance):
// module costAlerts 'modules/cost-alerts.bicep' = if (deployGovernance) {
//   name: 'cost-alerts'
//   params: {
//     name: '${namePrefix}-daily-aau-alert'
//     location: location
//     tags: tags
//     logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
//     dailyAauThreshold: 50
//     actionGroupIds: [
//       actionGroup.outputs.actionGroupId
//     ]
//   }
// }
