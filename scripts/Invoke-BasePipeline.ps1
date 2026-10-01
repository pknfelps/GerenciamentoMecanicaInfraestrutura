#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('hom', 'prd')][string]$Environment,
    [ValidateSet('plan', 'apply', 'auto')][string]$Action = 'plan',
    [string]$ExpectedCommit = '',
    [string]$ApprovedPlanSha256 = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Stop-TerraformFailure([string]$Log, [string]$Operation) {
    # Print only error headers; the full log can include planned values.
    Get-Content -LiteralPath $Log | Where-Object { $_ -match '^Error:' } | Select-Object -First 5 | Write-Output
    throw "$Operation falhou; preserve estado e investigue a execução. Sem retry/destroy automático."
}
& "$PSScriptRoot/Assert-BasePipelineTarget.ps1" @PSBoundParameters
$repoRoot = Split-Path $PSScriptRoot -Parent
$selection = & "$PSScriptRoot/Invoke-TerraformEnvironment.ps1" -Environment $Environment -Action Show
$identityText = & aws sts get-caller-identity --output json
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível consultar a identidade STS.' }
$identity = $identityText | ConvertFrom-Json
$expectedIdentity = "arn:aws:sts::121754142617:assumed-role/mecanica-$Environment-base-github/"
if ($identity.Account -ne '121754142617' -or !$identity.Arn.StartsWith($expectedIdentity)) { throw 'Identidade STS inesperada.' }
& "$PSScriptRoot/Invoke-TerraformEnvironment.ps1" -Environment $Environment -Action Init
$saved = @{}
foreach ($name in @('TF_DATA_DIR', 'TF_WORKSPACE', 'TF_INPUT')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:TF_DATA_DIR = $selection.DataDirectory
    $env:TF_WORKSPACE = 'default'
    $env:TF_INPUT = 'false'
    $dir = Join-Path $repoRoot "artifacts/terraform/$Environment/pipeline"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $plan = Join-Path $dir 'base.tfplan'
    $json = Join-Path $dir 'base.tfplan.json'
    $reportPath = Join-Path $dir 'review.json'
    # Plan/logs stay on the runner; no states, binary plans or values are uploaded.
    $planLog = Join-Path $dir 'plan.log'
    & terraform "-chdir=$repoRoot/terraform" plan -input=false -no-color -detailed-exitcode -lock-timeout=60s "-var-file=$($selection.Variables)" "-out=$plan" *> $planLog
    if ($LASTEXITCODE -notin @(0, 2)) { Stop-TerraformFailure $planLog 'Plan' }
    & terraform "-chdir=$repoRoot/terraform" show -json $plan | Set-Content -LiteralPath $json -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao ler o plano salvo.' }
    $python = if (Get-Command python3 -ErrorAction SilentlyContinue) { 'python3' } else { 'python' }
    $reviewArgs = @("$PSScriptRoot/review_base_plan.py", $json, '--report', $reportPath)
    if ($ApprovedPlanSha256) { $reviewArgs += @('--expected-sha256', $ApprovedPlanSha256) }
    & $python @reviewArgs
    if ($LASTEXITCODE -ne 0) { throw 'Plano recusado pela revisão; nenhum apply executado.' }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    $summary = @(
        "### Base $Environment / $Action", '', "Commit: $($env:GITHUB_SHA)",
        "Fingerprint SHA-256: $($report.sha256)", '', '| Recurso | Ação |', '|---|---|'
    )
    foreach ($change in $report.changes) { $summary += "| $($change.address) | $($change.actions -join '/') |" }
    if ($env:GITHUB_STEP_SUMMARY) { $summary | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }
    # Somente metadados seguros passam entre jobs; os planos/valores ficam no runner.
    if ($env:GITHUB_OUTPUT) {
        @(
            "commit=$($env:GITHUB_SHA)", "sha256=$($report.sha256)",
            "destructive=$($report.destructive.ToString().ToLowerInvariant())",
            "creates_cluster=$($report.creates_cluster.ToString().ToLowerInvariant())"
        ) | Add-Content -LiteralPath $env:GITHUB_OUTPUT
    }
    if ($report.destructive) { throw 'Exclusão/substituição detectada. Este workflow não aplica planos destrutivos.' }
    if ($Action -eq 'plan') {
        $message = if ($env:GITHUB_EVENT_NAME -eq 'push' -and $report.creates_cluster) {
            'Ambiente ausente: ativação pendente. Nenhum deploy realizado. Execute este workflow com action=activate; revise o resumo e aprove em Review deployments.'
        } else {
            'Plano gerado; nenhum apply realizado. Na ação activate, revise este resumo antes de aprovar em Review deployments. Na ação plan, a execução termina aqui.'
        }
        Write-Output $message
        if ($env:GITHUB_STEP_SUMMARY) { $message | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }
        return
    }
    if ($Action -eq 'auto' -and $report.creates_cluster) {
        $message = 'Ambiente ausente: criação/recriação pendente. Este workflow cria a base completa, sem cluster prévio. Execute action=activate e aprove o plano em Review deployments; commit/fingerprint são conferidos automaticamente. Nenhuma infraestrutura ativada por push.'
        Write-Output $message
        if ($env:GITHUB_STEP_SUMMARY) { $message | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }
        return
    }
    if (!$report.has_changes) { Write-Output 'Base sem alterações.' } else {
        $applyLog = Join-Path $dir 'apply.log'
        & terraform "-chdir=$repoRoot/terraform" apply -input=false -no-color -lock-timeout=60s $plan *> $applyLog
        if ($LASTEXITCODE -ne 0) { Stop-TerraformFailure $applyLog 'Apply' }
    }
    & "$PSScriptRoot/Test-BaseCluster.ps1" -Environment $Environment
} finally {
    foreach ($entry in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
}
