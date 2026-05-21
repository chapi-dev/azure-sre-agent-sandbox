<#
.SYNOPSIS
    Generates an HTML SRE Agent cost report from Log Analytics.

.DESCRIPTION
    Queries illustrative SRE Agent telemetry in Log Analytics and produces a
    simple HTML report that summarizes AAU consumption by subagent and model
    provider for the requested time window.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter()]
    [int]$Days = 7,

    [Parameter()]
    [string]$OutputPath = '.\cost-report.html'
)

$ErrorActionPreference = 'Stop'

function Invoke-AzCliJson {
    param([string[]]$Arguments)

    $raw = & az @Arguments --only-show-errors 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw ($raw.Trim())
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return $raw | ConvertFrom-Json
}

function Invoke-AzCliText {
    param([string[]]$Arguments)

    $raw = & az @Arguments --only-show-errors 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw ($raw.Trim())
    }

    return $raw.Trim()
}

function Convert-LogAnalyticsResult {
    param($Result)

    if (-not $Result -or -not $Result.tables -or $Result.tables.Count -eq 0) {
        return @()
    }

    $table = $Result.tables[0]
    $columns = @($table.columns | ForEach-Object { $_.name })
    $rows = @($table.rows)

    $objects = foreach ($row in $rows) {
        $item = [ordered]@{}
        for ($i = 0; $i -lt $columns.Count; $i++) {
            $item[$columns[$i]] = if ($row.Count -gt $i) { $row[$i] } else { $null }
        }
        [pscustomobject]$item
    }

    return @($objects)
}

function Get-WorkspaceContext {
    try {
        $workspaceId = Invoke-AzCliText -Arguments @(
            'monitor', 'app-insights', 'component', 'list',
            '--resource-group', $ResourceGroupName,
            '--query', '[0].workspaceResourceId',
            '-o', 'tsv'
        )
    }
    catch {
        $workspaceId = ''
    }

    if ([string]::IsNullOrWhiteSpace($workspaceId)) {
        $workspaceId = Invoke-AzCliText -Arguments @(
            'monitor', 'log-analytics', 'workspace', 'list',
            '--resource-group', $ResourceGroupName,
            '--query', '[0].id',
            '-o', 'tsv'
        )
    }

    if ([string]::IsNullOrWhiteSpace($workspaceId)) {
        throw "No Log Analytics workspace was found in resource group '$ResourceGroupName'."
    }

    $customerId = Invoke-AzCliText -Arguments @(
        'monitor', 'log-analytics', 'workspace', 'show',
        '--ids', $workspaceId,
        '--query', 'customerId',
        '-o', 'tsv'
    )

    return [pscustomobject]@{
        ResourceId = $workspaceId
        CustomerId = $customerId
    }
}

function Invoke-WorkspaceQuery {
    param([string]$Query)

    try {
        $result = Invoke-AzCliJson -Arguments @(
            'monitor', 'log-analytics', 'query',
            '--workspace', $script:WorkspaceContext.CustomerId,
            '--analytics-query', $Query,
            '-o', 'json'
        )
        return Convert-LogAnalyticsResult -Result $result
    }
    catch {
        Write-Warning "Log Analytics query failed: $($_.Exception.Message)"
        return @()
    }
}

function Convert-SectionToHtml {
    param(
        [string]$Title,
        [object[]]$Rows
    )

    if (-not $Rows -or $Rows.Count -eq 0) {
        return "<section><h2>$Title</h2><p>No telemetry rows were returned for this section.</p></section>"
    }

    $table = $Rows | ConvertTo-Html -Fragment
    return "<section><h2>$Title</h2>$table</section>"
}

$script:WorkspaceContext = Get-WorkspaceContext

$totalsQuery = @"
AgentTokenUsage_CL
| where TimeGenerated > ago(${Days}d)
| extend ThreadId = tostring(coalesce(column_ifexists('ThreadId_g', ''), column_ifexists('ThreadId_s', ''), column_ifexists('threadId_s', ''), column_ifexists('ThreadId', '')))
| extend Subagent = tostring(coalesce(column_ifexists('SubagentName_s', ''), column_ifexists('Subagent_s', ''), column_ifexists('AgentName_s', ''), column_ifexists('SubagentName', ''), 'unknown'))
| extend ModelProvider = tostring(coalesce(column_ifexists('ModelProvider_s', ''), column_ifexists('Provider_s', ''), column_ifexists('ModelProvider', ''), 'unknown'))
| extend AauValue = todouble(coalesce(column_ifexists('AAU_d', 0.0), column_ifexists('Aau_d', 0.0), column_ifexists('AAU', 0.0), 0.0))
| extend TotalTokensValue = tolong(coalesce(column_ifexists('TotalTokens_d', 0), column_ifexists('TotalTokens', 0), 0))
| summarize TotalAAU = round(sum(AauValue), 2), TotalTokens = sum(TotalTokensValue), Threads = dcount(ThreadId), Subagents = dcount(Subagent), ModelProviders = dcount(ModelProvider)
"@

$subagentQuery = @"
AgentTokenUsage_CL
| where TimeGenerated > ago(${Days}d)
| extend Subagent = tostring(coalesce(column_ifexists('SubagentName_s', ''), column_ifexists('Subagent_s', ''), column_ifexists('AgentName_s', ''), column_ifexists('SubagentName', ''), 'unknown'))
| extend ModelProvider = tostring(coalesce(column_ifexists('ModelProvider_s', ''), column_ifexists('Provider_s', ''), column_ifexists('ModelProvider', ''), 'unknown'))
| extend AauValue = todouble(coalesce(column_ifexists('AAU_d', 0.0), column_ifexists('Aau_d', 0.0), column_ifexists('AAU', 0.0), 0.0))
| extend TotalTokensValue = tolong(coalesce(column_ifexists('TotalTokens_d', 0), column_ifexists('TotalTokens', 0), 0))
| summarize TotalAAU = round(sum(AauValue), 2), TotalTokens = sum(TotalTokensValue), Calls = count() by Subagent, ModelProvider
| order by TotalAAU desc
"@

$modelQuery = @"
AgentTokenUsage_CL
| where TimeGenerated > ago(${Days}d)
| extend ModelProvider = tostring(coalesce(column_ifexists('ModelProvider_s', ''), column_ifexists('Provider_s', ''), column_ifexists('ModelProvider', ''), 'unknown'))
| extend AauValue = todouble(coalesce(column_ifexists('AAU_d', 0.0), column_ifexists('Aau_d', 0.0), column_ifexists('AAU', 0.0), 0.0))
| extend TotalTokensValue = tolong(coalesce(column_ifexists('TotalTokens_d', 0), column_ifexists('TotalTokens', 0), 0))
| summarize TotalAAU = round(sum(AauValue), 2), TotalTokens = sum(TotalTokensValue), Calls = count() by ModelProvider
| order by TotalAAU desc
"@

$dailyQuery = @"
AgentTokenUsage_CL
| where TimeGenerated > ago(${Days}d)
| extend ModelProvider = tostring(coalesce(column_ifexists('ModelProvider_s', ''), column_ifexists('Provider_s', ''), column_ifexists('ModelProvider', ''), 'unknown'))
| extend AauValue = todouble(coalesce(column_ifexists('AAU_d', 0.0), column_ifexists('Aau_d', 0.0), column_ifexists('AAU', 0.0), 0.0))
| summarize TotalAAU = round(sum(AauValue), 2), Calls = count() by Day = format_datetime(startofday(TimeGenerated), 'yyyy-MM-dd'), ModelProvider
| order by Day asc, ModelProvider asc
"@

$totals = Invoke-WorkspaceQuery -Query $totalsQuery
$bySubagent = Invoke-WorkspaceQuery -Query $subagentQuery
$byModel = Invoke-WorkspaceQuery -Query $modelQuery
$byDay = Invoke-WorkspaceQuery -Query $dailyQuery

$summary = if ($totals.Count -gt 0) {
    $totals[0]
}
else {
    [pscustomobject]@{
        TotalAAU      = 0
        TotalTokens   = 0
        Threads       = 0
        Subagents     = 0
        ModelProviders = 0
    }
}

$outputBase = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath
}
else {
    Join-Path (Get-Location) $OutputPath
}
$resolvedOutputPath = [System.IO.Path]::GetFullPath($outputBase)
$generatedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss UTC')

$summaryCards = @"
<div class='cards'>
  <div class='card'><div class='label'>Total AAU</div><div class='value'>$($summary.TotalAAU)</div></div>
  <div class='card'><div class='label'>Total tokens</div><div class='value'>$($summary.TotalTokens)</div></div>
  <div class='card'><div class='label'>Threads</div><div class='value'>$($summary.Threads)</div></div>
  <div class='card'><div class='label'>Subagents</div><div class='value'>$($summary.Subagents)</div></div>
  <div class='card'><div class='label'>Providers</div><div class='value'>$($summary.ModelProviders)</div></div>
</div>
"@

$html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
  <meta charset='utf-8' />
  <title>SRE Agent Cost Report</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #1f2937; }
    h1, h2 { color: #0f172a; }
    .meta { margin-bottom: 20px; color: #475569; }
    .note { padding: 12px 16px; border-left: 4px solid #2563eb; background: #eff6ff; margin-bottom: 20px; }
    .cards { display: flex; flex-wrap: wrap; gap: 16px; margin-bottom: 24px; }
    .card { min-width: 180px; padding: 16px; border: 1px solid #cbd5e1; border-radius: 10px; background: #f8fafc; }
    .label { font-size: 12px; text-transform: uppercase; color: #64748b; margin-bottom: 8px; }
    .value { font-size: 28px; font-weight: 600; color: #0f172a; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 24px; }
    th, td { border: 1px solid #cbd5e1; padding: 8px 10px; text-align: left; }
    th { background: #e2e8f0; }
    tr:nth-child(even) { background: #f8fafc; }
    section { margin-top: 24px; }
  </style>
</head>
<body>
  <h1>SRE Agent Weekly Cost Report</h1>
  <p class='meta'>Resource group: <strong>$ResourceGroupName</strong><br/>Workspace: <strong>$($script:WorkspaceContext.ResourceId)</strong><br/>Window: last <strong>$Days</strong> day(s)<br/>Generated: <strong>$generatedUtc</strong></p>
  <div class='note'>Queries in this report use the illustrative SRE Agent telemetry table <code>AgentTokenUsage_CL</code>. If your deployment emits different table or column names, update the KQL before using this report in a live demo.</div>
  $summaryCards
  $(Convert-SectionToHtml -Title 'AAU by subagent and model provider' -Rows $bySubagent)
  $(Convert-SectionToHtml -Title 'AAU by model provider' -Rows $byModel)
  $(Convert-SectionToHtml -Title 'Daily AAU trend' -Rows $byDay)
</body>
</html>
"@

Set-Content -Path $resolvedOutputPath -Value $html -Encoding UTF8
Start-Process $resolvedOutputPath | Out-Null

Write-Host "Weekly cost report written to $resolvedOutputPath" -ForegroundColor Green
