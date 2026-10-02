#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('mecanica-destroy-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path "$fixture/scripts", "$fixture/terraform/environments", "$fixture/terraform/backends" | Out-Null
foreach ($name in @('Assert-BasePipelineTarget.ps1', 'Invoke-BasePipeline.ps1', 'Invoke-TerraformEnvironment.ps1', 'review_base_plan.py', 'review_base_destroy.py', 'Test-BaseDestroyed.ps1')) {
    Copy-Item -LiteralPath "$repo/scripts/$name" -Destination "$fixture/scripts/$name"
}
Copy-Item "$repo/terraform/environments/*.tfvars" "$fixture/terraform/environments/"
Copy-Item "$repo/terraform/backends/*.hcl" "$fixture/terraform/backends/"
$global:destroyPython = (Get-Command python -ErrorAction Stop).Source
$names = @('GITHUB_REPOSITORY','GITHUB_REF','GITHUB_SHA','GITHUB_EVENT_NAME','CONFIGURED_REGION','CONFIGURED_ROLE_ARN','CONFIGURED_STATE_BUCKET','TF_DATA_DIR','TF_WORKSPACE','TF_INPUT','TF_CLI_ARGS','GITHUB_STEP_SUMMARY','GITHUB_OUTPUT', 'RUNNER_TEMP')
$global:metadataCommands = @()
$global:metadataFailures = @{}
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
foreach ($name in @('aws','terraform','python3')) { if (Test-Path "Function:$name") { throw 'Função de teste já existe.' } }
$global:destroyApplies = 0
$global:destroyPlanExit = 2
$global:destroyApplyExit = 0
$global:destroyRemaining = $false
$global:destroyPlans = @()
$global:destroyEnvironment = 'hom'
function aws {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'sts') {
        @{Account='121754142617';Arn="arn:aws:sts::121754142617:assumed-role/mecanica-$global:destroyEnvironment-base-github/test"} | ConvertTo-Json -Compress
    } elseif ($args[0] -eq 'eks') {
        Write-Output 'An error occurred (ResourceNotFoundException) when calling the DescribeCluster operation'
        $global:LASTEXITCODE = 254
    } elseif ($args[0] -eq 'ec2') { '[]' } else { throw 'Chamada AWS inesperada.' }
}
function terraform {
    if (!$args[0].StartsWith('-chdir=') -or [IO.Path]::GetFullPath($args[0].Substring(7)) -ne [IO.Path]::GetFullPath("$fixture/terraform")) { throw 'Descarte tentou outra raiz.' }
    switch ($args[1]) {
        'init' {
            $backend = @($args | Where-Object { $_ -like '-backend-config=*' })
            if ($backend.Count -ne 1 -or [IO.Path]::GetFullPath($backend[0].Substring(16)) -ne [IO.Path]::GetFullPath("$fixture/terraform/backends/$global:destroyEnvironment.hcl")) { throw 'Backend de outro ambiente.' }
            $global:LASTEXITCODE = 0
        }
        'plan' {
            $global:destroyPlans += ,$args
            Set-Content -LiteralPath (($args | Where-Object { $_ -like '-out=*' }).Substring(5)) -Value 'private-plan'
            $global:LASTEXITCODE = $global:destroyPlanExit
        }
        'show' { $global:destroyPlan | ConvertTo-Json -Depth 40; $global:LASTEXITCODE = 0 }
        'apply' {
            if (!(Test-Path $args[-1]) -or $args -contains '-auto-approve' -or $args -contains '-destroy') { throw 'Apply exige somente o binário revisado.' }
            $global:destroyApplies++
            $global:LASTEXITCODE = $global:destroyApplyExit
        }
        'state' {
            if ($global:destroyRemaining) { 'aws_vpc.main' }
            $global:LASTEXITCODE = 0
        }
        default { throw 'Operação Terraform inesperada.' }
    }
}
function python3 {
    if ($args[0] -like '*base_metadata.py') {
        $global:metadataCommands += $args[1]
        $global:LASTEXITCODE = if ($global:metadataFailures.ContainsKey($args[1])) { $global:metadataFailures[$args[1]] } else { 0 }
        return
    }
    & $global:destroyPython @args; $global:LASTEXITCODE = $LASTEXITCODE
}
function Refused([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action | Out-Null } catch { if ($_.Exception.Message -notlike "*$Message*") { throw }; $failed=$true }
    if (!$failed) { throw "Esperada recusa: $Message" }
}
$pipeline = "$fixture/scripts/Invoke-BasePipeline.ps1"
try {
    $env:GITHUB_REPOSITORY = 'pknfelps/GerenciamentoMecanicaInfraestrutura'
    $env:GITHUB_SHA = 'a' * 40
    $env:GITHUB_EVENT_NAME = 'workflow_dispatch'
    $env:CONFIGURED_REGION = 'us-east-1'
    $env:CONFIGURED_STATE_BUCKET = 'mecanica-tfstate-121754142617-us-east-1'
    $env:TF_DATA_DIR = 'previous-data'
    $env:TF_WORKSPACE = 'default'
    $env:TF_CLI_ARGS = $null
    $env:GITHUB_STEP_SUMMARY = "$fixture/summary.md"
    $env:GITHUB_OUTPUT = "$fixture/outputs.txt"
    foreach ($environment in @('hom','prd')) {
        $global:destroyEnvironment = $environment
        $env:GITHUB_REF = if ($environment -eq 'hom') { 'refs/heads/develop' } else { 'refs/heads/main' }
        $env:CONFIGURED_ROLE_ARN = "arn:aws:iam::121754142617:role/mecanica/pipelines/mecanica-$environment-base-github"
        $global:destroyPlan = @{format_version='1.2';terraform_version='1.15.9';complete=$true;variables=@{environment=@{value=$environment}};resource_changes=@(
            @{address='aws_vpc.main';type='aws_vpc';mode='managed';change=@{actions=@('delete');before=@{id="vpc-$environment";tags_all=@{Project='mecanica';Environment=$environment;ManagedBy='Terraform'}};after=$null}}
        )}
        & $pipeline -Environment $environment -Operation destroy -Action plan | Out-Null
        if ($environment -eq 'hom' -and $global:metadataCommands.Count -ne 0) { throw 'Plan alterou SSM.' }
        if ($global:destroyApplies -ne $(if ($environment -eq 'hom') { 0 } else { 1 })) { throw 'Plan excluiu recursos.' }
        if ($global:destroyPlans[-1] -notcontains '-destroy') { throw 'Plano sem modo destroy.' }
        $hash = (Get-Content "$fixture/artifacts/terraform/$environment/destroy-pipeline/review.json" -Raw | ConvertFrom-Json).sha256
        & $pipeline -Environment $environment -Operation destroy -Action apply -ExpectedCommit ('a'*40) -ApprovedPlanSha256 $hash | Out-Null
    }
    Refused { & $pipeline -Environment prd -Operation destroy -Action apply -ExpectedCommit ('c'*40) -ApprovedPlanSha256 $hash } 'commit'
    Refused { & $pipeline -Environment prd -Operation destroy -Action apply -ExpectedCommit ('a'*40) -ApprovedPlanSha256 ('b'*64) } 'Plano recusado'
    $global:destroyPlan.resource_changes[0].change.before.id = 'changed-after-approval'
    Refused { & $pipeline -Environment prd -Operation destroy -Action apply -ExpectedCommit ('a'*40) -ApprovedPlanSha256 $hash } 'Plano recusado'
    $global:destroyPlan.resource_changes[0].change.actions = @('create')
    Refused { & $pipeline -Environment prd -Operation destroy -Action plan } 'Plano recusado'
    $global:destroyPlan.resource_changes[0].change.actions = @('delete')
    Refused { & $pipeline -Environment prd -Action plan } 'Exclusão/substituição'
    $env:GITHUB_EVENT_NAME = 'push'
    Refused { & $pipeline -Environment prd -Operation destroy -Action plan } 'Descarte é exclusivo'
    Refused { & $pipeline -Environment prd -Operation destroy -Action auto } 'Descarte é exclusivo'
    $env:GITHUB_EVENT_NAME = 'workflow_dispatch'
    $global:destroyPlanExit = 1
    Refused { & $pipeline -Environment prd -Operation destroy -Action plan } 'Plan falhou'
    $global:destroyPlanExit = 2
    & $pipeline -Environment prd -Operation destroy -Action plan | Out-Null
    $hash = (Get-Content "$fixture/artifacts/terraform/prd/destroy-pipeline/review.json" -Raw | ConvertFrom-Json).sha256
    $global:destroyApplyExit = 1
    Refused { & $pipeline -Environment prd -Operation destroy -Action apply -ExpectedCommit ('a'*40) -ApprovedPlanSha256 $hash } 'Apply falhou'
    if ($global:destroyApplies -ne 3) { throw 'Falha parcial repetiu o apply.' }
    $global:destroyApplyExit = 0
    $global:destroyPlan.resource_changes = @()
    $global:destroyPlanExit = 0
    & $pipeline -Environment prd -Operation destroy -Action plan | Out-Null
    if ($global:destroyApplies -ne 3) { throw 'Estado vazio executou apply.' }
    $global:destroyRemaining = $true
    Refused { & $pipeline -Environment prd -Operation destroy -Action plan } 'estado da base ainda'
    if ($env:TF_DATA_DIR -ne 'previous-data') { throw 'Descarte não restaurou seleção.' }
    if ((Get-Content "$fixture/outputs.txt" -Raw) -match 'vpc-|tags_all') { throw 'Metadados públicos vazaram valores.' }
    $global:destroyRemaining = $false
    $hash = (Get-Content "$fixture/artifacts/terraform/prd/destroy-pipeline/review.json" -Raw | ConvertFrom-Json).sha256
    $global:metadataCommands = @()
    & $pipeline -Environment prd -Operation destroy -Action apply -ExpectedCommit ('a'*40) -ApprovedPlanSha256 $hash | Out-Null
    if (($global:metadataCommands -join ',') -ne 'begin,destroyed' -or $global:destroyApplies -ne 3) { throw 'Estado vazio precisa limpar SSM sem apply Terraform.' }
    $global:metadataFailures = @{destroyed=1}
    Refused { & $pipeline -Environment prd -Operation destroy -Action apply -ExpectedCommit ('a'*40) -ApprovedPlanSha256 $hash } 'limpeza SSM falhou'
    if ($global:metadataCommands[-1] -ne 'failed') { throw 'Falha de limpeza precisa registrar falha.' }
    Write-Output '17 cenários de descarte aprovados, incluindo limpeza SSM com estado vazio e falha de limpeza.'
} finally {
    foreach ($entry in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
    foreach ($name in @('aws','terraform','python3')) { Remove-Item "Function:$name" }
    $global:LASTEXITCODE = 0
}
