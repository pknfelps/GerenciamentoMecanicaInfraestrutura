#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('mecanica-destroy-check-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path "$fixture/scripts" | Out-Null
Copy-Item "$repo/scripts/Test-BaseDestroyed.ps1" "$fixture/scripts/"
$global:absenceState = @()
$global:absenceStateExit = 0
$global:absenceCluster = 'absent'
$global:absenceEc2 = ''
$global:absenceAwsExit = 0
foreach ($name in @('aws','terraform')) { if (Test-Path "Function:$name") { throw 'Função de teste já existe.' } }
$savedSummary = $env:GITHUB_STEP_SUMMARY
$env:GITHUB_STEP_SUMMARY = "$fixture/summary.md"
function terraform { $global:absenceState; $global:LASTEXITCODE = $global:absenceStateExit }
function aws {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'eks') {
        switch ($global:absenceCluster) {
            'absent' { 'An error occurred (ResourceNotFoundException) when calling the DescribeCluster operation'; $global:LASTEXITCODE = 254 }
            'denied' { 'An error occurred (AccessDeniedException) when calling the DescribeCluster operation'; $global:LASTEXITCODE = 254 }
            default { '{"cluster":{}}' }
        }
    } else {
        foreach ($filter in @('Name=tag:Project,Values=mecanica','Name=tag:Environment,Values=hom','Name=tag:ManagedBy,Values=Terraform')) {
            if ($args -notcontains $filter) { throw 'Consulta não isolou tags do ambiente.' }
        }
        if ($args[1] -eq $global:absenceEc2) { '["remaining-resource"]' } else { '[]' }
        $global:LASTEXITCODE = $global:absenceAwsExit
    }
}
function Refused([string]$Message) {
    $failed = $false
    try { & "$fixture/scripts/Test-BaseDestroyed.ps1" -Environment hom | Out-Null } catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }; $failed=$true
    }
    if (!$failed) { throw "Esperada recusa: $Message" }
}
try {
    & "$fixture/scripts/Test-BaseDestroyed.ps1" -Environment hom | Out-Null
    $global:absenceState = @('aws_vpc.main')
    Refused 'estado da base ainda'
    $global:absenceState = @()
    $global:absenceStateExit = 1
    Refused 'Falha ao consultar'
    $global:absenceStateExit = 0
    $global:absenceCluster = 'active'
    Refused 'cluster ainda existe'
    $global:absenceCluster = 'denied'
    Refused 'comprovar ausência'
    $global:absenceCluster = 'absent'
    foreach ($operation in @('describe-vpcs','describe-nat-gateways','describe-addresses')) {
        $global:absenceEc2 = $operation
        Refused 'Ainda há recursos'
    }
    $global:absenceEc2 = ''
    $global:absenceAwsExit = 254
    Refused 'Falha ao conferir'
    Write-Output '9 cenários de verificação de descarte aprovados: ausência real, IAM negado, estado/cluster/VPC/NAT/EIP remanescentes e erro de consulta.'
} finally {
    $env:GITHUB_STEP_SUMMARY = $savedSummary
    foreach ($name in @('aws','terraform')) { Remove-Item "Function:$name" }
    $global:LASTEXITCODE = 0
}
