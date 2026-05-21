<#
.SYNOPSIS
    Starts a SQL query bomb to saturate the Movistar BSS Azure SQL database.

.DESCRIPTION
    Creates a helper firewall rule for the current client IP, writes a CPU-heavy
    SQL batch, and launches parallel sqlcmd processes that continuously execute
    the workload against the S0 Movistar BSS database. Process IDs are recorded so
    fix-multistack.ps1 can stop them later.

.PARAMETER ResourceGroupName
    Resource group containing the Azure SQL server.

.PARAMETER SqlServerFqdn
    Fully qualified domain name of the Azure SQL logical server.

.PARAMETER DatabaseName
    Name of the target database.

.PARAMETER AdminLogin
    SQL administrator login.

.PARAMETER AdminPassword
    SQL administrator password.

.PARAMETER ParallelQueries
    Number of long-running sqlcmd workers to start. Default: 5

.EXAMPLE
    .\break-sql-dtu.ps1 -ResourceGroupName rg-srelab-eastus2 -SqlServerFqdn sql-srelab-abc123.database.windows.net -DatabaseName movistar-bss-db -AdminLogin sqladmin -AdminPassword 'P@ssw0rd!' -ParallelQueries 5
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$SqlServerFqdn,

    [Parameter(Mandatory)]
    [string]$DatabaseName,

    [Parameter(Mandatory)]
    [string]$AdminLogin,

    [Parameter(Mandatory)]
    [string]$AdminPassword,

    [Parameter()]
    [ValidateRange(1, 20)]
    [int]$ParallelQueries = 5
)

$ErrorActionPreference = 'Stop'

$stateRoot = Join-Path $PSScriptRoot '.state'
$stateFile = Join-Path $stateRoot 'sql-dtu-processes.json'
$sqlFile = Join-Path $stateRoot 'sql-dtu-load.sql'
$serverName = ($SqlServerFqdn -split '\.')[0]
$firewallRuleName = 'AllowMultistackScenarioClient'

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

function Get-PublicIpAddress {
    [CmdletBinding()]
    param()

    $response = Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 20
    if ($null -eq $response -or [string]::IsNullOrWhiteSpace($response.ip)) {
        throw 'Unable to determine the current public IP address.'
    }

    return $response.ip
}

function Save-State {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Records
    )

    if (-not (Test-Path $stateRoot)) {
        New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    }

    $existing = @()
    if (Test-Path $stateFile) {
        $raw = Get-Content -Path $stateFile -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $existing = @($raw | ConvertFrom-Json)
        }
    }

    @($existing + $Records) | ConvertTo-Json -Depth 5 | Set-Content -Path $stateFile -Encoding UTF8
}

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw 'sqlcmd is required for this scenario. Install the SQL command-line tools and retry.'
}

if (-not (Test-Path $stateRoot)) {
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
}

Set-Content -Path $sqlFile -Encoding UTF8 -Value @"
SET NOCOUNT ON;
WHILE 1 = 1
BEGIN
    SELECT COUNT_BIG(*) AS ObjectJoinCount
    FROM sys.objects a
    CROSS JOIN sys.objects b
    CROSS JOIN sys.objects c
    OPTION (MAXDOP 1);
END
GO
"@

$publicIp = Get-PublicIpAddress

if ($PSCmdlet.ShouldProcess($serverName, "Create or update firewall rule $firewallRuleName for $publicIp")) {
    Invoke-AzCli -Arguments @(
        'sql', 'server', 'firewall-rule', 'create',
        '--resource-group', $ResourceGroupName,
        '--server', $serverName,
        '--name', $firewallRuleName,
        '--start-ip-address', $publicIp,
        '--end-ip-address', $publicIp,
        '--output', 'json'
    ) -AsJson | Out-Null
}

$records = @()
$previousSqlCmdPassword = $env:SQLCMDPASSWORD
$env:SQLCMDPASSWORD = $AdminPassword

try {
    for ($index = 1; $index -le $ParallelQueries; $index++) {
        if ($PSCmdlet.ShouldProcess($SqlServerFqdn, "Start SQL DTU load worker #$index")) {
            $process = Start-Process -FilePath 'sqlcmd' -ArgumentList @(
                '-S', $SqlServerFqdn,
                '-d', $DatabaseName,
                '-U', $AdminLogin,
                '-N',
                '-l', '0',
                '-i', $sqlFile
            ) -PassThru -WindowStyle Hidden

            $records += [pscustomobject]@{
                pid = $process.Id
                serverName = $serverName
                serverFqdn = $SqlServerFqdn
                databaseName = $DatabaseName
                firewallRuleName = $firewallRuleName
                publicIp = $publicIp
                startedAt = (Get-Date).ToString('o')
            }
        }
    }
}
finally {
    if ($null -ne $previousSqlCmdPassword) {
        $env:SQLCMDPASSWORD = $previousSqlCmdPassword
    }
    else {
        Remove-Item Env:SQLCMDPASSWORD -ErrorAction SilentlyContinue
    }
}

if ($records.Count -gt 0) {
    Save-State -Records $records

    Write-Host "✅ SQL DTU load workers started." -ForegroundColor Green
    Write-Host "   Server       : $SqlServerFqdn" -ForegroundColor Gray
    Write-Host "   Database     : $DatabaseName" -ForegroundColor Gray
    Write-Host "   Workers      : $ParallelQueries" -ForegroundColor Yellow
    Write-Host "   Firewall rule: $firewallRuleName ($publicIp)" -ForegroundColor Gray
    Write-Host "   Process IDs  : $(@($records.pid) -join ', ')" -ForegroundColor Gray
    Write-Host "   Recovery     : .\scripts\scenarios-multistack\fix-multistack.ps1 -ResourceGroupName $ResourceGroupName" -ForegroundColor Gray
}
elseif (-not $WhatIfPreference) {
    throw 'No SQL DTU load workers were started.'
}
