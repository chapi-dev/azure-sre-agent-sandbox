<#
.SYNOPSIS
    Lowers Cosmos DB throughput and optionally generates throttling load.

.DESCRIPTION
    Sets the plans-catalog container throughput to 100 RU/s for the multi-stack demo.
    If LoadRequests is greater than zero, the script fires concurrent upsert
    requests against a single hot partition to help provoke 429 responses.

.PARAMETER ResourceGroupName
    Resource group containing the Cosmos DB account.

.PARAMETER CosmosAccountName
    Name of the Cosmos DB account.

.PARAMETER LoadRequests
    Number of concurrent synthetic requests to send after lowering throughput.
    Default: 0

.EXAMPLE
    .\break-cosmos-throttle.ps1 -ResourceGroupName rg-srelab-eastus2 -CosmosAccountName cosmos-srelab-abc123

.EXAMPLE
    .\break-cosmos-throttle.ps1 -ResourceGroupName rg-srelab-eastus2 -CosmosAccountName cosmos-srelab-abc123 -LoadRequests 25
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$CosmosAccountName,

    [Parameter()]
    [ValidateRange(0, 500)]
    [int]$LoadRequests = 0
)

$ErrorActionPreference = 'Stop'

$databaseName = 'movistar-bss-db'
$containerName = 'plans-catalog'
$targetThroughput = 100

function Invoke-AzCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter()]
        [switch]$AsJson
    )

    $output = & az @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')`n$output"
    }

    if ($AsJson) {
        if ([string]::IsNullOrWhiteSpace($output)) {
            return $null
        }

        return $output | ConvertFrom-Json
    }

    return $output.Trim()
}

function Invoke-CosmosLoad {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter(Mandatory)]
        [string]$MasterKey,

        [Parameter(Mandatory)]
        [int]$Concurrency
    )

    $jobs = @()

    for ($index = 1; $index -le $Concurrency; $index++) {
        $jobs += Start-Job -Name "cosmos-hot-$index" -ArgumentList $Endpoint, $MasterKey, $databaseName, $containerName, $index -ScriptBlock {
            param($JobEndpoint, $JobMasterKey, $JobDatabaseName, $JobContainerName, $WorkerIndex)

            $ErrorActionPreference = 'Stop'

            function New-CosmosMasterKeyToken {
                param(
                    [string]$Verb,
                    [string]$ResourceType,
                    [string]$ResourceLink,
                    [string]$Date,
                    [string]$PrimaryKey
                )

                $payload = ($Verb.ToLowerInvariant() + "`n" + $ResourceType.ToLowerInvariant() + "`n" + $ResourceLink + "`n" + $Date.ToLowerInvariant() + "`n`n")
                $hmac = [System.Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($PrimaryKey))

                try {
                    $hash = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payload))
                }
                finally {
                    $hmac.Dispose()
                }

                $signature = [Convert]::ToBase64String($hash)
                return [System.Uri]::EscapeDataString("type=master&ver=1.0&sig=$signature")
            }

            $utcDate = [DateTime]::UtcNow.ToString('r')
            $resourceLink = "dbs/$JobDatabaseName/colls/$JobContainerName"
            $authorization = New-CosmosMasterKeyToken -Verb 'POST' -ResourceType 'docs' -ResourceLink $resourceLink -Date $utcDate -PrimaryKey $JobMasterKey
            $document = @{
                id = "throttle-$WorkerIndex-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
                sku = 'demo-load'
                category = 'hot-partition'
                updatedAt = [DateTime]::UtcNow.ToString('o')
                price = $WorkerIndex
            } | ConvertTo-Json -Compress

            $headers = @{
                'x-ms-date' = $utcDate
                'x-ms-version' = '2018-12-31'
                authorization = $authorization
                'x-ms-documentdb-is-upsert' = 'true'
                'x-ms-documentdb-partitionkey' = '["hot-partition"]'
            }

            $uri = "{0}/dbs/{1}/colls/{2}/docs" -f $JobEndpoint.TrimEnd('/'), $JobDatabaseName, $JobContainerName

            try {
                Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json' -Body $document -TimeoutSec 30 | Out-Null
                [pscustomobject]@{
                    Worker = $WorkerIndex
                    Status = 'Success'
                    StatusCode = 201
                }
            }
            catch {
                $statusCode = 0
                if ($_.Exception.PSObject.Properties.Name -contains 'Response' -and $null -ne $_.Exception.Response) {
                    try {
                        $statusCode = [int]$_.Exception.Response.StatusCode
                    }
                    catch {
                        $statusCode = 0
                    }
                }

                [pscustomobject]@{
                    Worker = $WorkerIndex
                    Status = if ($statusCode -eq 429) { 'Throttled' } else { 'Failed' }
                    StatusCode = $statusCode
                }
            }
        }
    }

    Wait-Job -Job $jobs | Out-Null
    $results = $jobs | Receive-Job
    $jobs | Remove-Job -Force | Out-Null
    return $results
}

if ($PSCmdlet.ShouldProcess("$CosmosAccountName/$databaseName/$containerName", "Set throughput to $targetThroughput RU/s")) {
    Invoke-AzCli -Arguments @(
        'cosmosdb', 'sql', 'container', 'throughput', 'update',
        '--resource-group', $ResourceGroupName,
        '--account-name', $CosmosAccountName,
        '--database-name', $databaseName,
        '--name', $containerName,
        '--throughput', $targetThroughput.ToString(),
        '--output', 'json'
    ) -AsJson | Out-Null
}

Write-Host "✅ Cosmos DB throughput lowered." -ForegroundColor Green
Write-Host "   Account    : $CosmosAccountName" -ForegroundColor Gray
Write-Host "   Container  : $databaseName/$containerName" -ForegroundColor Gray
Write-Host "   Throughput : $targetThroughput RU/s" -ForegroundColor Yellow

if ($LoadRequests -gt 0) {
    if ($PSCmdlet.ShouldProcess($CosmosAccountName, "Send $LoadRequests concurrent hot-partition requests")) {
        $endpoint = Invoke-AzCli -Arguments @(
            'cosmosdb', 'show',
            '--resource-group', $ResourceGroupName,
            '--name', $CosmosAccountName,
            '--query', 'documentEndpoint',
            '--output', 'tsv'
        )

        $primaryMasterKey = Invoke-AzCli -Arguments @(
            'cosmosdb', 'keys', 'list',
            '--resource-group', $ResourceGroupName,
            '--name', $CosmosAccountName,
            '--query', 'primaryMasterKey',
            '--output', 'tsv'
        )

        $results = Invoke-CosmosLoad -Endpoint $endpoint -MasterKey $primaryMasterKey -Concurrency $LoadRequests
        $throttled = @($results | Where-Object { $_.Status -eq 'Throttled' }).Count
        $failed = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
        $succeeded = @($results | Where-Object { $_.Status -eq 'Success' }).Count

        Write-Host "   Synthetic load summary:" -ForegroundColor Gray
        Write-Host "     Success   : $succeeded" -ForegroundColor Gray
        Write-Host "     Throttled : $throttled" -ForegroundColor Yellow
        Write-Host "     Failed    : $failed" -ForegroundColor Gray
    }
}

Write-Host "   Expected symptom: App Insights and AzureDiagnostics should begin showing Cosmos 429 pressure." -ForegroundColor Gray
