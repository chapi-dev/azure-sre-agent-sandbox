// =============================================================================
// Cost Workbook Module
// =============================================================================
// Deploys an Azure Workbook for illustrative SRE Agent token and AAU tracking.
// Queries use placeholder telemetry tables emitted by the SRE Agent demo lab.
// =============================================================================

@description('Workbook resource name')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('Log Analytics workspace resource ID used by workbook queries')
param logAnalyticsWorkspaceId string

var workbookDisplayName = 'SRE Agent — Token & AAU Consumption'
var workbookContent = {
  version: 'Notebook/1.0'
  items: [
    {
      type: 1
      content: {
        json: 'Illustrative workbook for SRE Agent token and AAU consumption. Queries reference placeholder tables `AgentTelemetry_CL` and `AgentTokenUsage_CL`; adjust the KQL if your workspace uses different names.'
        style: 'info'
      }
      name: 'text-intro'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: '''
AgentTokenUsage_CL
| where TimeGenerated > ago(7d)
| extend Aau = todouble(coalesce(column_ifexists('AAU_d', 0.0), column_ifexists('Aau_d', 0.0), column_ifexists('AAU', 0.0), 0.0))
| summarize TotalAAU = round(sum(Aau), 2)
'''
        size: 0
        title: 'Total AAU consumed last 7d'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        crossComponentResources: [
          logAnalyticsWorkspaceId
        ]
        timeContext: {
          durationMs: 604800000
        }
        visualization: 'tiles'
      }
      name: 'query-total-aau'
      styleSettings: {
        showBorder: true
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: '''
AgentTokenUsage_CL
| where TimeGenerated > ago(7d)
| extend Subagent = tostring(coalesce(column_ifexists('SubagentName_s', ''), column_ifexists('Subagent_s', ''), column_ifexists('AgentName_s', ''), column_ifexists('SubagentName', ''), 'unknown'))
| extend Aau = todouble(coalesce(column_ifexists('AAU_d', 0.0), column_ifexists('Aau_d', 0.0), column_ifexists('AAU', 0.0), 0.0))
| summarize TotalAAU = round(sum(Aau), 2) by bin(TimeGenerated, 1d), Subagent
| order by TimeGenerated asc
'''
        size: 1
        title: 'AAU by subagent'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        crossComponentResources: [
          logAnalyticsWorkspaceId
        ]
        timeContext: {
          durationMs: 604800000
        }
        visualization: 'areachart'
        chartSettings: {
          chartType: 'stackedArea'
        }
      }
      name: 'query-aau-by-subagent'
      styleSettings: {
        showBorder: true
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: '''
AgentTokenUsage_CL
| where TimeGenerated > ago(7d)
| extend ModelProvider = tostring(coalesce(column_ifexists('ModelProvider_s', ''), column_ifexists('Provider_s', ''), column_ifexists('ModelProvider', ''), 'unknown'))
| extend Aau = todouble(coalesce(column_ifexists('AAU_d', 0.0), column_ifexists('Aau_d', 0.0), column_ifexists('AAU', 0.0), 0.0))
| summarize TotalAAU = round(sum(Aau), 2) by ModelProvider
| order by TotalAAU desc
'''
        size: 1
        title: 'AAU by model provider'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        crossComponentResources: [
          logAnalyticsWorkspaceId
        ]
        timeContext: {
          durationMs: 604800000
        }
        visualization: 'piechart'
      }
      name: 'query-aau-by-model'
      styleSettings: {
        showBorder: true
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: '''
AgentTokenUsage_CL
| where TimeGenerated > ago(7d)
| extend ThreadId = tostring(coalesce(column_ifexists('ThreadId_g', ''), column_ifexists('ThreadId_s', ''), column_ifexists('threadId_s', ''), column_ifexists('ThreadId', '')))
| extend Incident = tostring(coalesce(column_ifexists('IncidentTitle_s', ''), column_ifexists('ThreadTitle_s', ''), column_ifexists('Incident_s', ''), ThreadId))
| extend TotalTokens = tolong(coalesce(column_ifexists('TotalTokens_d', 0), column_ifexists('TotalTokens', 0), 0))
| extend Aau = todouble(coalesce(column_ifexists('AAU_d', 0.0), column_ifexists('Aau_d', 0.0), column_ifexists('AAU', 0.0), 0.0))
| summarize TotalAAU = round(sum(Aau), 2), TotalTokens = sum(TotalTokens) by Incident, ThreadId
| top 10 by TotalAAU desc
'''
        size: 1
        title: 'Top 10 incidents by token cost'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        crossComponentResources: [
          logAnalyticsWorkspaceId
        ]
        timeContext: {
          durationMs: 604800000
        }
        visualization: 'table'
      }
      name: 'query-top-incidents'
      styleSettings: {
        showBorder: true
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: '''
let tokenUsage = AgentTokenUsage_CL
| where TimeGenerated > ago(7d)
| extend ThreadId = tostring(coalesce(column_ifexists('ThreadId_g', ''), column_ifexists('ThreadId_s', ''), column_ifexists('threadId_s', ''), column_ifexists('ThreadId', '')))
| extend Subagent = tostring(coalesce(column_ifexists('SubagentName_s', ''), column_ifexists('Subagent_s', ''), column_ifexists('AgentName_s', ''), column_ifexists('SubagentName', ''), 'unknown'))
| extend TotalTokens = tolong(coalesce(column_ifexists('TotalTokens_d', 0), column_ifexists('TotalTokens', 0), 0))
| extend Aau = todouble(coalesce(column_ifexists('AAU_d', 0.0), column_ifexists('Aau_d', 0.0), column_ifexists('AAU', 0.0), 0.0));
let telemetry = AgentTelemetry_CL
| where TimeGenerated > ago(7d)
| extend ThreadId = tostring(coalesce(column_ifexists('ThreadId_g', ''), column_ifexists('ThreadId_s', ''), column_ifexists('threadId_s', ''), column_ifexists('ThreadId', '')))
| extend Success = iif(tobool(coalesce(column_ifexists('RemediationSucceeded_b', false), column_ifexists('IsSuccess_b', false), column_ifexists('Succeeded_b', false))), 1, 0);
tokenUsage
| summarize TotalAAU = round(sum(Aau), 2), TotalTokens = sum(TotalTokens) by ThreadId, Subagent
| join kind=leftouter (telemetry | summarize RemediationSuccess = max(Success) by ThreadId) on ThreadId
| extend RemediationSuccess = toint(coalesce(RemediationSuccess, 0))
| project ThreadId, Subagent, TotalAAU, TotalTokens, RemediationSuccess
| order by TotalAAU desc
'''
        size: 1
        title: 'Token cost per remediation success'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        crossComponentResources: [
          logAnalyticsWorkspaceId
        ]
        timeContext: {
          durationMs: 604800000
        }
        visualization: 'scatterchart'
      }
      name: 'query-cost-vs-success'
      styleSettings: {
        showBorder: true
      }
    }
  ]
  isLocked: false
  fallbackResourceIds: [
    logAnalyticsWorkspaceId
  ]
}

resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: name
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    category: 'workbook'
    description: 'Illustrative workbook for SRE Agent token and AAU consumption.'
    displayName: workbookDisplayName
    serializedData: string(workbookContent)
    sourceId: logAnalyticsWorkspaceId
    version: 'Notebook/1.0'
  }
}

output workbookId string = workbook.id
output workbookName string = workbook.name

// Wire-up in main.bicep (guarded by deployGovernance):
// module costWorkbook 'modules/cost-workbook.bicep' = if (deployGovernance) {
//   name: 'cost-workbook'
//   params: {
//     name: '${namePrefix}-cost-workbook'
//     location: location
//     tags: tags
//     logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
//   }
// }
