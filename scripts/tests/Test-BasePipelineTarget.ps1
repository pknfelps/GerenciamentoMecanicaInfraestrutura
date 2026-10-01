#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path $PSScriptRoot -Parent) 'Assert-BasePipelineTarget.ps1'
$names = @('GITHUB_REPOSITORY', 'GITHUB_REF', 'GITHUB_SHA', 'GITHUB_EVENT_NAME', 'CONFIGURED_REGION', 'CONFIGURED_ROLE_ARN', 'CONFIGURED_STATE_BUCKET')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$cases = 0
function Assert-Refused([scriptblock]$Action) {
    $refused = $false
    try { & $Action } catch { $refused = $true }
    if (!$refused) { throw 'A configuração inválida foi aceita.' }
}
try {
    $env:GITHUB_REPOSITORY = 'pknfelps/GerenciamentoMecanicaInfraestrutura'
    $env:GITHUB_SHA = 'a' * 40
    $env:CONFIGURED_REGION = 'us-east-1'
    $env:CONFIGURED_STATE_BUCKET = 'mecanica-tfstate-121754142617-us-east-1'
    foreach ($environment in @('hom', 'prd')) {
        $env:GITHUB_REF = if ($environment -eq 'hom') { 'refs/heads/develop' } else { 'refs/heads/main' }
        $env:CONFIGURED_ROLE_ARN = "arn:aws:iam::121754142617:role/mecanica/pipelines/mecanica-$environment-base-github"
        $env:GITHUB_EVENT_NAME = 'workflow_dispatch'
        & $script -Environment $environment -Action plan
        & $script -Environment $environment -Action apply -ExpectedCommit ('a' * 40) -ApprovedPlanSha256 ('b' * 64)
        $cases += 2
        Assert-Refused { & $script -Environment $environment -Action apply -ExpectedCommit ('c' * 40) -ApprovedPlanSha256 ('b' * 64) }
        Assert-Refused { & $script -Environment $environment -Action apply -ExpectedCommit ('a' * 40) }
        Assert-Refused { & $script -Environment $environment -Action auto }
        $cases += 3
        $env:GITHUB_EVENT_NAME = 'push'
        & $script -Environment $environment -Action auto
        $cases++
        $env:GITHUB_REF = 'refs/pull/123/merge'
        Assert-Refused { & $script -Environment $environment }
        $cases++
    }
    $env:GITHUB_REF = 'refs/heads/develop'
    Assert-Refused { & $script -Environment hom }
    $cases++
    $env:CONFIGURED_ROLE_ARN = 'arn:aws:iam::121754142617:role/mecanica/pipelines/mecanica-hom-base-github'
    $env:CONFIGURED_STATE_BUCKET = 'wrong-bucket'
    Assert-Refused { & $script -Environment hom }
    $cases++
    Write-Output "$cases cenários de destino/aprovação aprovados, sem AWS."
} finally {
    foreach ($entry in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
}
