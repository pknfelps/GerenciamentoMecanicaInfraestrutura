#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('hom', 'prd')][string]$Environment,
    [ValidateSet('plan', 'apply', 'auto')][string]$Action = 'plan',
    [ValidateSet('provision', 'destroy')][string]$Operation = 'provision',
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
    $mode = if ($Operation -eq 'destroy') { 'destroy-pipeline' } else { 'pipeline' }
    $dir = Join-Path $repoRoot "artifacts/terraform/$Environment/$mode"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $plan = Join-Path $dir 'base.tfplan'
    $json = Join-Path $dir 'base.tfplan.json'
    $reportPath = Join-Path $dir 'review.json'
    # Plan/logs stay on the runner; no states, binary plans or values are uploaded.
    $planLog = Join-Path $dir 'plan.log'
    $planArguments = @('plan', '-input=false', '-no-color', '-detailed-exitcode', '-lock-timeout=60s', "-var-file=$($selection.Variables)", "-out=$plan")
    if ($Operation -eq 'destroy') { $planArguments += '-destroy' }
    & terraform "-chdir=$repoRoot/terraform" @planArguments *> $planLog
    if ($LASTEXITCODE -notin @(0, 2)) { Stop-TerraformFailure $planLog 'Plan' }
    & terraform "-chdir=$repoRoot/terraform" show -json $plan | Set-Content -LiteralPath $json -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao ler o plano salvo.' }
    $python = if (Get-Command python3 -ErrorAction SilentlyContinue) { 'python3' } else { 'python' }
    $reviewer = if ($Operation -eq 'destroy') { 'review_base_destroy.py' } else { 'review_base_plan.py' }
    $reviewArgs = @("$PSScriptRoot/$reviewer", $json, '--report', $reportPath)
    if ($Operation -eq 'destroy') { $reviewArgs += @('--environment', $Environment) }
    if ($ApprovedPlanSha256) { $reviewArgs += @('--expected-sha256', $ApprovedPlanSha256) }
    & $python @reviewArgs
    if ($LASTEXITCODE -ne 0) { throw 'Plano recusado pela revisão; nenhum apply executado.' }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    $summary = @(
        "### Base $Environment / $Operation / $Action", '', "Commit: $($env:GITHUB_SHA)",
        "Fingerprint SHA-256: $($report.sha256)", '', '| Recurso | Ação |', '|---|---|'
    )
    foreach ($change in $report.changes) { $summary += "| $($change.address) | $($change.actions -join '/') |" }
    if ($env:GITHUB_STEP_SUMMARY) { $summary | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }
    # Somente metadados seguros passam entre jobs; os planos/valores ficam no runner.
    if ($env:GITHUB_OUTPUT) {
        @(
            "commit=$($env:GITHUB_SHA)", "sha256=$($report.sha256)",
            "destructive=$($report.destructive.ToString().ToLowerInvariant())",
            "creates_cluster=$($report.creates_cluster.ToString().ToLowerInvariant())",
            "has_changes=$($report.has_changes.ToString().ToLowerInvariant())"
        ) | Add-Content -LiteralPath $env:GITHUB_OUTPUT
    }
    if ($Operation -eq 'provision' -and $report.destructive) { throw 'Exclusão/substituição detectada. Este workflow não aplica planos destrutivos.' }
    if ($Action -eq 'plan' -and $Operation -eq 'destroy') {
        $message = 'Plano de descarte gerado; nenhuma exclusão executada. Revise os recursos e aprove em Review deployments na ação destroy.'
        Write-Output $message
        if ($env:GITHUB_STEP_SUMMARY) { $message | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }
        if (!$report.has_changes) { & "$PSScriptRoot/Test-BaseDestroyed.ps1" -Environment $Environment }
        return
    }
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
    $metadataContext = Join-Path $dir 'metadata-context.json'
    $metadataScript = "$PSScriptRoot/base_metadata.py"
    $metadataArgs = @('--environment', $Environment, '--context', $metadataContext)
    $previousKubeconfig = $env:KUBECONFIG
    try {
        & $python $metadataScript begin @metadataArgs --input $json --operation $Operation
        if ($LASTEXITCODE -ne 0) { throw 'Falha no início dos metadados; nenhum apply executado.' }
        if (!$report.has_changes) { Write-Output 'Base sem alterações Terraform; reconciliando metadados.' } else {
            $applyLog = Join-Path $dir 'apply.log'
            & terraform "-chdir=$repoRoot/terraform" apply -input=false -no-color -lock-timeout=60s $plan *> $applyLog
            if ($LASTEXITCODE -ne 0) { Stop-TerraformFailure $applyLog 'Apply' }
        }
        if ($Operation -eq 'destroy') {
            & "$PSScriptRoot/Test-BaseDestroyed.ps1" -Environment $Environment
            & $python $metadataScript destroyed @metadataArgs
            if ($LASTEXITCODE -ne 0) { throw 'Recursos ausentes, mas limpeza SSM falhou.' }
        } else {
            & "$PSScriptRoot/Test-BaseCluster.ps1" -Environment $Environment
            $env:KUBECONFIG = Join-Path $env:RUNNER_TEMP "base-$Environment-kubeconfig"
            $outputs = Join-Path $dir 'metadata-outputs.json'
            & terraform "-chdir=$repoRoot/terraform" output -json | Set-Content -LiteralPath $outputs -Encoding utf8
            if ($LASTEXITCODE -ne 0) { throw 'Falha ao coletar outputs da base.' }
            & $python $metadataScript prepare @metadataArgs --input $outputs
            if ($LASTEXITCODE -ne 0) { throw 'Recursos da base não atendem ao perfil database.' }
            & $python $metadataScript publish @metadataArgs
            if ($LASTEXITCODE -eq 3) {
                $message = 'Dependência bloqueada: execute aws-oidc-check no repositório do banco com check_kubernetes=true; depois repita activate na mesma revisão. Nenhuma database-release publicada.'
                if ($env:GITHUB_STEP_SUMMARY) { $message | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }
                throw $message
            }
            if ($LASTEXITCODE -ne 0) { throw 'Falha na publicação SSM da base.' }
            $message = 'Perfil database pronto no SSM. Base completa (NLB/JWT) permanece pendente; API/função não estão liberadas.'
            Write-Output $message
            if ($env:GITHUB_STEP_SUMMARY) { $message | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }
        }
    } catch {
        $originalError = $_
        & $python $metadataScript failed @metadataArgs
        if ($LASTEXITCODE -ne 0) { Write-Warning 'Limpeza SSM não confirmada. Mantenha consumidores bloqueados e investigue esta execução.' }
        throw $originalError
    } finally {
        $env:KUBECONFIG = $previousKubeconfig
    }
} finally {
    foreach ($entry in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
}
