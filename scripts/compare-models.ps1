<#
.SYNOPSIS
    Compares the same incident prompt across two SRE subagents.

.DESCRIPTION
    Uses Azure control-plane discovery plus the SRE Agent data-plane API to:
    - verify both subagents exist
    - create a temporary HTTP trigger per subagent
    - execute the same prompt against each subagent
    - capture response time, AAU consumed, and response text
    - save the raw response text to local .txt files

.PARAMETER ResourceGroupName
    Resource group that contains the Azure SRE Agent.

.PARAMETER Prompt
    Incident prompt to send to both subagents.

.PARAMETER SubagentA
    First subagent to compare.

.PARAMETER SubagentB
    Second subagent to compare.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$Prompt,

    [Parameter()]
    [string]$SubagentA = 'review-autonomy-handler-aoai',

    [Parameter()]
    [string]$SubagentB = 'review-autonomy-handler-claude',

    [Parameter()]
    [int]$PollIntervalSeconds = 10,

    [Parameter()]
    [int]$TimeoutSeconds = 300,

    [Parameter()]
    [string]$OutputDirectory = '.'
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

function Invoke-AgentApi {
    param(
        [Parameter(Mandatory)]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$Body
    )

    $url = '{0}{1}' -f $script:AgentEndpoint.TrimEnd('/'), $Path
    $curlArgs = @(
        '-sS',
        '-w', "`n%{http_code}",
        '-X', $Method,
        $url,
        '-H', "Authorization: Bearer $($script:AgentToken)"
    )

    if ($PSBoundParameters.ContainsKey('Body')) {
        $curlArgs += @('-H', 'Content-Type: application/json', '-d', $Body)
    }

    $output = & curl.exe @curlArgs 2>&1
    $lines = ($output -join "`n") -split "`n"
    $httpCode = $lines[-1].Trim()
    $responseBody = if ($lines.Count -gt 1) {
        ($lines[0..($lines.Count - 2)]) -join "`n"
    }
    else {
        ''
    }

    return [pscustomobject]@{
        StatusCode = [int]$httpCode
        Body       = $responseBody.Trim()
    }
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

function Get-AgentContext {
    $agentResource = Invoke-AzCliJson -Arguments @(
        'resource', 'list',
        '--resource-group', $ResourceGroupName,
        '--resource-type', 'Microsoft.App/agents',
        '--query', '[0]',
        '-o', 'json'
    )

    if (-not $agentResource -or [string]::IsNullOrWhiteSpace($agentResource.id)) {
        throw "No Microsoft.App/agents resource was found in resource group '$ResourceGroupName'."
    }

    $agentDetail = Invoke-AzCliJson -Arguments @(
        'rest', '--method', 'get',
        '--url', "https://management.azure.com$($agentResource.id)?api-version=2025-05-01-preview"
    )

    if ([string]::IsNullOrWhiteSpace($agentDetail.properties.agentEndpoint)) {
        throw 'The SRE Agent endpoint is missing. The agent might still be provisioning.'
    }

    return [pscustomobject]@{
        AgentName     = $agentDetail.name
        AgentId       = $agentDetail.id
        AgentEndpoint = $agentDetail.properties.agentEndpoint.TrimEnd('/')
    }
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
        try {
            $workspaceId = Invoke-AzCliText -Arguments @(
                'monitor', 'log-analytics', 'workspace', 'list',
                '--resource-group', $ResourceGroupName,
                '--query', '[0].id',
                '-o', 'tsv'
            )
        }
        catch {
            $workspaceId = ''
        }
    }

    if ([string]::IsNullOrWhiteSpace($workspaceId)) {
        return $null
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

function Assert-SubagentExists {
    param([string]$Name)

    $resp = Invoke-AgentApi -Method 'GET' -Path "/api/v2/extendedAgent/agents/$Name"
    if ($resp.StatusCode -ne 200) {
        throw "Subagent '$Name' was not found (HTTP $($resp.StatusCode)). Deploy it before running compare-models.ps1."
    }
}

function Get-ThreadMessages {
    param([string]$ThreadId)

    $resp = Invoke-AgentApi -Method 'GET' -Path "/api/v1/threads/$ThreadId/messages?skip=0&top=200&orderby=timestamp+asc"
    if ($resp.StatusCode -ne 200) {
        throw "Failed to read thread messages for '$ThreadId' (HTTP $($resp.StatusCode))."
    }

    if ([string]::IsNullOrWhiteSpace($resp.Body)) {
        return @()
    }

    $payload = $resp.Body | ConvertFrom-Json
    $messages = if ($payload.value) { $payload.value } else { $payload }
    return @($messages | Sort-Object { [datetime]$_.timeStamp })
}

function Wait-ForAgentResponse {
    param([string]$ThreadId)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastSignature = ''
    $stagnantPolls = 0

    while ((Get-Date) -lt $deadline) {
        $messages = Get-ThreadMessages -ThreadId $ThreadId
        $agentTextMessages = @(
            $messages | Where-Object {
                $_.author.role -eq 'SREAgent' -and -not [string]::IsNullOrWhiteSpace($_.text)
            }
        )

        $signature = if ($messages.Count -gt 0) {
            '{0}:{1}' -f $messages.Count, $messages[-1].id
        }
        else {
            'empty'
        }

        if ($signature -eq $lastSignature) {
            $stagnantPolls++
        }
        else {
            $lastSignature = $signature
            $stagnantPolls = 0
        }

        if ($agentTextMessages.Count -gt 0) {
            $lastAgentMessage = $agentTextMessages[-1]
            $hasCompletionFlag = $lastAgentMessage.PSObject.Properties.Name -contains 'isComplete'
            if (($hasCompletionFlag -and $lastAgentMessage.isComplete) -or $stagnantPolls -ge 2) {
                $responseText = ($agentTextMessages | ForEach-Object { $_.text.Trim() } | Where-Object { $_ }) -join "`r`n`r`n"
                return [pscustomobject]@{
                    Messages     = $messages
                    ResponseText = $responseText
                }
            }
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    throw "Timed out waiting for subagent response in thread '$ThreadId'."
}

function Get-ThreadUsage {
    param([string]$ThreadId)

    if (-not $script:WorkspaceContext) {
        return $null
    }

    $query = @"
AgentTokenUsage_CL
| where TimeGenerated > ago(2d)
| extend ThreadId = tostring(coalesce(column_ifexists('ThreadId_g', ''), column_ifexists('ThreadId_s', ''), column_ifexists('threadId_s', ''), column_ifexists('ThreadId', '')))
| extend AauValue = todouble(coalesce(column_ifexists('AAU_d', 0.0), column_ifexists('Aau_d', 0.0), column_ifexists('AAU', 0.0), 0.0))
| extend PromptTokensValue = tolong(coalesce(column_ifexists('PromptTokens_d', 0), column_ifexists('PromptTokens', 0), 0))
| extend CompletionTokensValue = tolong(coalesce(column_ifexists('CompletionTokens_d', 0), column_ifexists('CompletionTokens', 0), 0))
| extend TotalTokensValue = tolong(coalesce(column_ifexists('TotalTokens_d', 0), column_ifexists('TotalTokens', 0), PromptTokensValue + CompletionTokensValue))
| where ThreadId == '$ThreadId'
| summarize AAU = round(sum(AauValue), 4), PromptTokens = sum(PromptTokensValue), CompletionTokens = sum(CompletionTokensValue), TotalTokens = sum(TotalTokensValue)
"@

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $result = Invoke-AzCliJson -Arguments @(
                'monitor', 'log-analytics', 'query',
                '--workspace', $script:WorkspaceContext.CustomerId,
                '--analytics-query', $query,
                '-o', 'json'
            )

            $rows = Convert-LogAnalyticsResult -Result $result
            if ($rows.Count -gt 0) {
                return $rows[0]
            }
        }
        catch {
            if ($attempt -eq 3) {
                return $null
            }
        }

        Start-Sleep -Seconds 10
    }

    return $null
}

function Invoke-SubagentRun {
    param([string]$SubagentName)

    Assert-SubagentExists -Name $SubagentName

    $triggerId = $null
    try {
        $safeName = $SubagentName -replace '[^a-zA-Z0-9-]', '-'
        $triggerName = 'compare-{0}-{1}' -f $safeName, ([guid]::NewGuid().ToString('N').Substring(0, 8))
        $createBody = @{
            name        = $triggerName
            description = "Temporary trigger created by compare-models.ps1 for $SubagentName"
            agentPrompt = $Prompt
            agent       = $SubagentName
            agentMode   = 'autonomous'
        } | ConvertTo-Json -Depth 5 -Compress

        $createResp = Invoke-AgentApi -Method 'POST' -Path '/api/v1/httptriggers/create' -Body $createBody
        if ($createResp.StatusCode -notin @(200, 201, 202)) {
            throw "Failed to create HTTP trigger for '$SubagentName' (HTTP $($createResp.StatusCode))."
        }

        $trigger = $createResp.Body | ConvertFrom-Json
        $triggerId = $trigger.triggerId
        if ([string]::IsNullOrWhiteSpace($triggerId)) {
            throw "The trigger creation response for '$SubagentName' did not include a triggerId."
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $executeResp = Invoke-AgentApi -Method 'POST' -Path "/api/v1/httptriggers/$triggerId/execute" -Body '{}'
        if ($executeResp.StatusCode -notin @(200, 202)) {
            throw "Failed to execute trigger '$triggerId' for '$SubagentName' (HTTP $($executeResp.StatusCode))."
        }

        $execution = $executeResp.Body | ConvertFrom-Json
        $threadId = $execution.execution.threadId
        if ([string]::IsNullOrWhiteSpace($threadId)) {
            throw "Trigger '$triggerId' for '$SubagentName' did not return a threadId."
        }

        $response = Wait-ForAgentResponse -ThreadId $threadId
        $stopwatch.Stop()

        $usage = Get-ThreadUsage -ThreadId $threadId
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $outputPath = Join-Path $script:ResolvedOutputDirectory "$safeName-$stamp.txt"
        $rawOutput = @"
Subagent: $SubagentName
ThreadId: $threadId
ElapsedSeconds: $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 2))

Prompt:
$Prompt

Response:
$($response.ResponseText)
"@
        Set-Content -Path $outputPath -Value $rawOutput -Encoding UTF8

        return [pscustomobject]@{
            Subagent        = $SubagentName
            ThreadId        = $threadId
            ResponseTimeSec = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
            AAUConsumed     = if ($usage) { $usage.AAU } else { $null }
            TotalTokens     = if ($usage) { $usage.TotalTokens } else { $null }
            OutputFile      = $outputPath
        }
    }
    finally {
        if ($triggerId) {
            try {
                $null = Invoke-AgentApi -Method 'DELETE' -Path "/api/v1/httptriggers/$triggerId"
            }
            catch {
                Write-Warning "Failed to delete temporary trigger '$triggerId'."
            }
        }
    }
}

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    throw 'curl.exe is required but was not found on PATH.'
}

$outputBase = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory
}
else {
    Join-Path (Get-Location) $OutputDirectory
}
$script:ResolvedOutputDirectory = [System.IO.Path]::GetFullPath($outputBase)
if (-not (Test-Path $script:ResolvedOutputDirectory)) {
    New-Item -Path $script:ResolvedOutputDirectory -ItemType Directory | Out-Null
}

$agentContext = Get-AgentContext
$script:AgentEndpoint = $agentContext.AgentEndpoint
$script:AgentToken = Invoke-AzCliText -Arguments @(
    'account', 'get-access-token',
    '--resource', 'https://azuresre.dev',
    '--query', 'accessToken',
    '-o', 'tsv'
)
$script:WorkspaceContext = Get-WorkspaceContext

Write-Host "Comparing subagents '$SubagentA' and '$SubagentB' against agent '$($agentContext.AgentName)'..." -ForegroundColor Cyan
if (-not $script:WorkspaceContext) {
    Write-Warning 'No Log Analytics workspace was discovered. AAU fields will be reported as blank.'
}

$results = @(
    Invoke-SubagentRun -SubagentName $SubagentA
    Invoke-SubagentRun -SubagentName $SubagentB
)

$displayRows = $results | ForEach-Object {
    [pscustomobject]@{
        Subagent        = $_.Subagent
        ThreadId        = $_.ThreadId
        ResponseTimeSec = $_.ResponseTimeSec
        AAUConsumed     = if ($null -ne $_.AAUConsumed) { $_.AAUConsumed } else { 'n/a' }
        TotalTokens     = if ($null -ne $_.TotalTokens) { $_.TotalTokens } else { 'n/a' }
        OutputFile      = $_.OutputFile
    }
}

Write-Host ''
Write-Host 'Comparison summary' -ForegroundColor Green
$displayRows | Format-Table -AutoSize | Out-String | Write-Host
