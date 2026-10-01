#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path $PSScriptRoot -Parent) 'Assert-BaseApprovalEnvironment.ps1'
$names = @('GITHUB_REPOSITORY', 'GITHUB_REF', 'GH_TOKEN')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
if (Test-Path Function:Invoke-RestMethod) { throw 'Execute sem função Invoke-RestMethod prévia.' }
$global:mecanicaApprovalConfiguration = $null
$global:mecanicaApprovalHttpError = $false
$global:mecanicaApprovalRequests = @()
function Invoke-RestMethod {
    param($Method, $Uri, $TimeoutSec, $Headers)
    if ($Method -ne 'Get' -or $TimeoutSec -ne 30 -or $Headers.Authorization -ne 'Bearer fixture-token') { throw 'Requisição inesperada.' }
    $global:mecanicaApprovalRequests += $Uri
    if ($global:mecanicaApprovalHttpError) { throw 'HTTP 404 fixture-token must-never-appear' }
    return $global:mecanicaApprovalConfiguration
}
function Assert-Refused([scriptblock]$Action) {
    $failed = $false
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -like '*fixture-token*') { throw 'Erro expôs o token.' }
        $failed = $true
    }
    if (!$failed) { throw 'Configuração insegura foi aceita.' }
}
try {
    $env:GITHUB_REPOSITORY = 'pknfelps/GerenciamentoMecanicaInfraestrutura'
    $env:GH_TOKEN = 'fixture-token'
    $cases = 0
    foreach ($environment in @('hom', 'prd')) {
        $env:GITHUB_REF = if ($environment -eq 'hom') { 'refs/heads/develop' } else { 'refs/heads/main' }
        $global:mecanicaApprovalConfiguration = [pscustomobject]@{
            name = "$environment-approval"
            protection_rules = @([pscustomobject]@{type='required_reviewers';reviewers=@([pscustomobject]@{reviewer=[pscustomobject]@{id=123}})})
        }
        & $script -Environment $environment | Out-Null
        if ($global:mecanicaApprovalRequests[-1] -ne "https://api.github.com/repos/pknfelps/GerenciamentoMecanicaInfraestrutura/environments/$environment-approval") { throw 'Consulta de outro destino.' }
        $cases++
        $global:mecanicaApprovalConfiguration.protection_rules[0].reviewers = @()
        Assert-Refused { & $script -Environment $environment }
        $cases++
        $global:mecanicaApprovalConfiguration.protection_rules = @([pscustomobject]@{type='wait_timer';wait_timer=30})
        Assert-Refused { & $script -Environment $environment }
        $cases++
        $global:mecanicaApprovalConfiguration.protection_rules = @([pscustomobject]@{type='required_reviewers';reviewers=@([pscustomobject]@{reviewer=[pscustomobject]@{id=123}})})
        $global:mecanicaApprovalConfiguration.name = 'other-approval'
        Assert-Refused { & $script -Environment $environment }
        $cases++
    }
    $env:GITHUB_REF = 'refs/heads/develop'
    $global:mecanicaApprovalHttpError = $true
    Assert-Refused { & $script -Environment hom }
    $cases++
    $global:mecanicaApprovalHttpError = $false
    $env:GH_TOKEN = $null
    Assert-Refused { & $script -Environment hom }
    $cases++
    $env:GH_TOKEN = 'fixture-token'
    $env:GITHUB_REF = 'refs/heads/main'
    Assert-Refused { & $script -Environment hom }
    $cases++
    $env:GITHUB_REF = 'refs/heads/develop'
    $env:GITHUB_REPOSITORY = 'other/repo'
    Assert-Refused { & $script -Environment hom }
    $cases++
    Write-Output "$cases cenários de aprovação obrigatória aprovados, sem GitHub/AWS."
} finally {
    foreach ($entry in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
    Remove-Item Function:Invoke-RestMethod
}
