#requires -Version 7.0
# Exercise the orchestration with fake aws/terraform and a fake cluster checker.
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('mecanica-base-pipeline-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path "$fixture/scripts", "$fixture/terraform/environments", "$fixture/terraform/backends" | Out-Null
foreach ($name in @('Assert-BasePipelineTarget.ps1', 'Invoke-BasePipeline.ps1', 'Invoke-TerraformEnvironment.ps1', 'review_base_plan.py')) {
    Copy-Item -LiteralPath "$repo/scripts/$name" -Destination "$fixture/scripts/$name"
}
Copy-Item "$repo/terraform/environments/*.tfvars" "$fixture/terraform/environments/"
Copy-Item "$repo/terraform/backends/*.hcl" "$fixture/terraform/backends/"
Set-Content -LiteralPath "$fixture/scripts/Test-BaseCluster.ps1" -Value 'param($Environment); $global:mecanicaClusterChecks++'
$pipeline = "$fixture/scripts/Invoke-BasePipeline.ps1"
$pythonCommand = Get-Command python3 -ErrorAction SilentlyContinue
if (!$pythonCommand) { $pythonCommand = Get-Command python -ErrorAction Stop }
$global:mecanicaTestPython = $pythonCommand.Source
$names = @('GITHUB_REPOSITORY', 'GITHUB_REF', 'GITHUB_SHA', 'GITHUB_EVENT_NAME', 'CONFIGURED_REGION', 'CONFIGURED_ROLE_ARN', 'CONFIGURED_STATE_BUCKET', 'TF_DATA_DIR', 'TF_WORKSPACE', 'TF_INPUT', 'TF_CLI_ARGS', 'GITHUB_STEP_SUMMARY')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
foreach ($name in @('aws','terraform','python3')) { if (Test-Path "Function:$name") { throw "Execute sem função $name prévia." } }
$global:mecanicaApplyCalls = 0
$global:mecanicaClusterChecks = 0
$global:mecanicaPlanExit = 2
$global:mecanicaApplyExit = 0
$global:mecanicaInitExit = 0
$global:mecanicaIdentityAccount = '121754142617'
$global:mecanicaPlan = @{
    format_version = '1.2'; terraform_version = '1.15.9'; complete = $true
    variables = @{environment = @{value = 'hom'}}
    resource_changes = @(@{address='aws_eks_access_entry.pipeline["base"]'; mode='managed'; type='aws_eks_access_entry'; change=@{actions=@('create'); before=$null; after=@{principal_arn='base-hom'}; after_unknown=@{id=$true}}})
}
function aws {
    if ($args[0] -ne 'sts' -or $args[1] -ne 'get-caller-identity') { throw 'Chamada AWS inesperada no teste.' }
    @{Account=$global:mecanicaIdentityAccount; Arn='arn:aws:sts::121754142617:assumed-role/mecanica-hom-base-github/test'} | ConvertTo-Json -Compress
    $global:LASTEXITCODE = 0
}
function terraform {
    switch ($args[1]) {
        'init' { $global:LASTEXITCODE = $global:mecanicaInitExit }
        'plan' {
            $destination = ($args | Where-Object { $_ -like '-out=*' }).Substring(5)
            Set-Content -LiteralPath $destination -Value 'fake-private-plan'
            $global:LASTEXITCODE = $global:mecanicaPlanExit
        }
        'show' { $global:mecanicaPlan | ConvertTo-Json -Depth 100; $global:LASTEXITCODE = 0 }
        'apply' {
            if (!(Test-Path -LiteralPath $args[-1]) -or $args -contains '-auto-approve') { throw 'Apply precisa do binário já revisado.' }
            $global:mecanicaApplyCalls++
            $global:LASTEXITCODE = $global:mecanicaApplyExit
        }
        default { throw 'Operação Terraform inesperada.' }
    }
}
function python3 { & $global:mecanicaTestPython @args; $global:LASTEXITCODE = $LASTEXITCODE }
function Assert-That([bool]$Condition, [string]$Message) { if (!$Condition) { throw $Message } }
function Assert-Refused([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        $failed = $true
    }
    Assert-That $failed "Era esperada recusa: $Message"
}
try {
    $env:GITHUB_REPOSITORY = 'pknfelps/GerenciamentoMecanicaInfraestrutura'
    $env:GITHUB_REF = 'refs/heads/develop'
    $env:GITHUB_SHA = 'a' * 40
    $env:GITHUB_EVENT_NAME = 'workflow_dispatch'
    $env:CONFIGURED_REGION = 'us-east-1'
    $env:CONFIGURED_ROLE_ARN = 'arn:aws:iam::121754142617:role/mecanica/pipelines/mecanica-hom-base-github'
    $env:CONFIGURED_STATE_BUCKET = 'mecanica-tfstate-121754142617-us-east-1'
    $env:TF_DATA_DIR = 'previous-directory'
    $env:TF_WORKSPACE = 'default'
    $env:TF_INPUT = 'true'
    $env:TF_CLI_ARGS = $null
    $env:GITHUB_STEP_SUMMARY = "$fixture/summary.md"
    & $pipeline -Environment hom -Action plan | Out-Null
    Assert-That ($global:mecanicaApplyCalls -eq 0) 'Plan não pode aplicar.'
    Assert-That ($env:TF_DATA_DIR -eq 'previous-directory' -and $env:TF_INPUT -eq 'true') 'Plan deve restaurar variáveis.'
    $fingerprint = (Get-Content "$fixture/artifacts/terraform/hom/pipeline/review.json" -Raw | ConvertFrom-Json).sha256
    & $pipeline -Environment hom -Action apply -ExpectedCommit ('a' * 40) -ApprovedPlanSha256 $fingerprint | Out-Null
    Assert-That ($global:mecanicaApplyCalls -eq 1 -and $global:mecanicaClusterChecks -eq 1) 'Apply aprovado deve executar e validar.'
    Assert-Refused { & $pipeline -Environment hom -Action apply -ExpectedCommit ('a' * 40) -ApprovedPlanSha256 ('b' * 64) } 'Plano recusado'
    Assert-That ($global:mecanicaApplyCalls -eq 1) 'Fingerprint divergente não pode aplicar.'
    $env:GITHUB_EVENT_NAME = 'push'
    & $pipeline -Environment hom -Action auto | Out-Null
    Assert-That ($global:mecanicaApplyCalls -eq 2 -and $global:mecanicaClusterChecks -eq 2) 'Auto deve atualizar base existente.'
    $global:mecanicaPlan.resource_changes[0].type = 'aws_eks_cluster'
    $global:mecanicaPlan.resource_changes[0].change.after = @{access_config=@(@{bootstrap_cluster_creator_admin_permissions=$false})}
    & $pipeline -Environment hom -Action auto | Out-Null
    Assert-That ($global:mecanicaApplyCalls -eq 2 -and $global:mecanicaClusterChecks -eq 2) 'Auto não pode ativar ambiente ausente.'
    $global:mecanicaPlan.resource_changes[0].type = 'aws_eks_access_entry'
    $global:mecanicaPlan.resource_changes[0].change.actions = @('delete','create')
    Assert-Refused { & $pipeline -Environment hom -Action auto } 'Exclusão/substituição'
    Assert-That ($global:mecanicaApplyCalls -eq 2) 'Auto não pode substituir recursos.'
    $global:mecanicaPlan.resource_changes[0].change.actions = @('create')
    $global:mecanicaPlanExit = 1
    Assert-Refused { & $pipeline -Environment hom -Action auto } 'Plan falhou'
    $global:mecanicaPlanExit = 2
    $global:mecanicaApplyExit = 1
    Assert-Refused { & $pipeline -Environment hom -Action auto } 'Apply falhou'
    Assert-That ($global:mecanicaApplyCalls -eq 3 -and $global:mecanicaClusterChecks -eq 2) 'Falha parcial não pode validar ou repetir apply.'
    $global:mecanicaApplyExit = 0
    $global:mecanicaInitExit = 1
    Assert-Refused { & $pipeline -Environment hom -Action auto } 'Terraform falhou'
    $global:mecanicaInitExit = 0
    $global:mecanicaIdentityAccount = '000000000000'
    Assert-Refused { & $pipeline -Environment hom -Action auto } 'Identidade STS inesperada'
    Assert-That ($global:mecanicaApplyCalls -eq 3) 'Identidade errada/init falho não podem aplicar.'
    Assert-That ($env:TF_DATA_DIR -eq 'previous-directory') 'Falhas devem restaurar seleção.'
    Assert-That ((Get-Content "$fixture/summary.md" -Raw) -notlike '*principal_arn*') 'Resumo não pode incluir valores do plano.'
    # A base não precisa existir: o apply manual cria e valida o cluster.
    $global:mecanicaIdentityAccount = '121754142617'
    $global:mecanicaPlan.resource_changes[0].type = 'aws_eks_cluster'
    $global:mecanicaPlan.resource_changes[0].change.after = @{access_config=@(@{bootstrap_cluster_creator_admin_permissions=$false})}
    $env:GITHUB_EVENT_NAME = 'workflow_dispatch'
    & $pipeline -Environment hom -Action plan | Out-Null
    $fingerprint = (Get-Content "$fixture/artifacts/terraform/hom/pipeline/review.json" -Raw | ConvertFrom-Json).sha256
    & $pipeline -Environment hom -Action apply -ExpectedCommit ('a' * 40) -ApprovedPlanSha256 $fingerprint | Out-Null
    Assert-That ($global:mecanicaApplyCalls -eq 4 -and $global:mecanicaClusterChecks -eq 3) 'Apply manual deve criar a base ausente e validar.'
    # Com a base ativa e sem alterações, apenas verificar sua saúde.
    $global:mecanicaPlan.resource_changes[0].change.before = $global:mecanicaPlan.resource_changes[0].change.after
    $global:mecanicaPlan.resource_changes[0].change.actions = @('no-op')
    $global:mecanicaPlanExit = 0
    $env:GITHUB_EVENT_NAME = 'push'
    & $pipeline -Environment hom -Action auto | Out-Null
    Assert-That ($global:mecanicaApplyCalls -eq 4 -and $global:mecanicaClusterChecks -eq 4) 'Base ativa sem alterações deve validar sem apply.'
    # Simula descarte externo: um novo plan/apply deve recriar, sem pré-provisionamento.
    $global:mecanicaPlan.resource_changes[0].change.before = $null
    $global:mecanicaPlan.resource_changes[0].change.actions = @('create')
    $global:mecanicaPlanExit = 2
    & $pipeline -Environment hom -Action auto | Out-Null
    Assert-That ($global:mecanicaApplyCalls -eq 4 -and $global:mecanicaClusterChecks -eq 4) 'Push após descarte deve manter a ativação pendente.'
    Assert-That ((Get-Content "$fixture/summary.md" -Raw) -like '*sem cluster prévio*action=plan*action=apply*') 'Resumo deve explicar como recriar pelo workflow.'
    $env:GITHUB_EVENT_NAME = 'workflow_dispatch'
    & $pipeline -Environment hom -Action plan | Out-Null
    $fingerprint = (Get-Content "$fixture/artifacts/terraform/hom/pipeline/review.json" -Raw | ConvertFrom-Json).sha256
    & $pipeline -Environment hom -Action apply -ExpectedCommit ('a' * 40) -ApprovedPlanSha256 $fingerprint | Out-Null
    Assert-That ($global:mecanicaApplyCalls -eq 5 -and $global:mecanicaClusterChecks -eq 5) 'Apply manual após descarte deve recriar e validar.'
    $global:mecanicaPlan.resource_changes[0].change.after.access_config[0].bootstrap_cluster_creator_admin_permissions = $true
    Assert-Refused { & $pipeline -Environment hom -Action apply -ExpectedCommit ('a' * 40) -ApprovedPlanSha256 $fingerprint } 'Plano recusado'
    Assert-That ($global:mecanicaApplyCalls -eq 5) 'Cluster novo com bootstrap implícito não pode ser aplicado.'
    Write-Output '14 cenários aprovados, incluindo criação, base ativa sem alterações e recriação após descarte, com bloqueio de bootstrap implícito.'
} finally {
    foreach ($entry in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
    foreach ($name in @('aws','terraform','python3')) { Remove-Item "Function:$name" }
    $global:LASTEXITCODE = 0
}
